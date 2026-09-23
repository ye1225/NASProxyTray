# ── src/80-update.ps1 · 检查更新 ──
# 读 GitHub Releases 的最新 tag 与当前版本比较。
# 只做「发现 + 提示 + 用默认浏览器打开下载页」，不自动替换自己：
# 未签名的 exe 自替换容易被 SmartScreen 与杀软拦住，得不偿失。
#
# 网络请求跑在独立 runspace 里，主线程用 400ms 的 Timer 轮询结果，
# 避免网络不通时把界面卡死（最长超时 10 秒）。

$script:UpdateRepo          = 'ye1225/NASProxyTray'
$script:UpdateTimeoutSec    = 10
$script:UpdateThrottleHours = 24
$script:UpdateStateFile     = Join-Path $script:DataDir 'update_check.json'
$script:UpdateInfo          = $null      # @{ Version = '1.3.0'; Url = '...' }

$script:UpdatePs      = $null
$script:UpdateRs      = $null
$script:UpdateHandle  = $null
$script:UpdatePending = $false

# ---------------------------------------------------------------- 辅助
function Compare-AppVersion {
    param([string]$A, [string]$B)
    try {
        $va = [version]($A -replace '^[vV]', '')
        $vb = [version]($B -replace '^[vV]', '')
        return $va.CompareTo($vb)
    } catch {
        return 0
    }
}

function Get-UpdateLastCheck {
    try {
        if (Test-Path -LiteralPath $script:UpdateStateFile) {
            $raw = Get-Content -LiteralPath $script:UpdateStateFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($raw.checkedAt) { return [datetime]$raw.checkedAt }
        }
    } catch { }
    return [datetime]::MinValue
}

function Set-UpdateLastCheck {
    param([string]$Latest)
    try {
        [pscustomobject]@{
            checkedAt = (Get-Date).ToString('o')
            version   = $script:AppVersion
            latest    = $Latest
        } | ConvertTo-Json -Compress | Set-Content -LiteralPath $script:UpdateStateFile -Encoding UTF8
    } catch { }
}

function Test-UpdateThrottle {
    $last = Get-UpdateLastCheck
    return ((((Get-Date) - $last).TotalHours) -ge $script:UpdateThrottleHours)
}

function Set-UpdateMenuState {
    try {
        if ($null -eq $script:UpdateInfo) {
            $miNewVer.Visible = $false
            return
        }
        $miNewVer.Text    = ('发现新版本 v{0} · 点击下载' -f $script:UpdateInfo.Version)
        $miNewVer.Visible = $true
    } catch { }
}

function Show-UpdateBalloon {
    param([string]$Text)
    try {
        $tray.ShowBalloonTip(6000, 'NAS Proxy', $Text, [System.Windows.Forms.ToolTipIcon]::Info)
    } catch { }
}

function Open-UpdatePage {
    try {
        $url = if ($script:UpdateInfo) { $script:UpdateInfo.Url }
               else { "https://github.com/$($script:UpdateRepo)/releases/latest" }
        Start-Process $url
    } catch {
        Write-Host "[ProxyTray] 打开下载页失败: $_"
    }
}

# ------------------------------------------------------ 异步发起检查
function Start-UpdateCheckAsync {
    if ($script:UpdatePending) {
        Write-Host '[ProxyTray] 已有一次检查在进行中，忽略本次请求'
        return
    }
    $script:UpdatePending = $true

    $uri = "https://api.github.com/repos/$($script:UpdateRepo)/releases/latest"
    $ua  = "NASProxyTray/$($script:AppVersion)"
    $to  = $script:UpdateTimeoutSec

    try {
        $rs = [runspacefactory]::CreateRunspace()
        $rs.ApartmentState = 'MTA'
        $rs.Open()
        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddScript({
            param($uri, $ua, $to)
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $r = Invoke-RestMethod -Uri $uri -TimeoutSec $to -UseBasicParsing `
                        -Headers @{ 'User-Agent' = $ua; 'Accept' = 'application/vnd.github+json' }
                [pscustomobject]@{ ok = $true; tag = [string]$r.tag_name; url = [string]$r.html_url } |
                    ConvertTo-Json -Compress
            } catch {
                [pscustomobject]@{ ok = $false; err = [string]$_ } | ConvertTo-Json -Compress
            }
        }).AddArgument($uri).AddArgument($ua).AddArgument($to)

        $script:UpdateHandle = $ps.BeginInvoke()
        $script:UpdatePs     = $ps
        $script:UpdateRs     = $rs
        Write-Host ("[ProxyTray] 开始检查更新（超时 {0} 秒）" -f $to)
    } catch {
        $script:UpdatePending = $false
        Write-Host "[ProxyTray] 启动更新检查失败: $_"
    }
}

# ------------------------------------------------------ 收取检查结果
function Complete-UpdateCheck {
    if (-not $script:UpdateHandle) { return $false }
    if (-not $script:UpdateHandle.IsCompleted) { return $false }
    $script:UpdatePending = $false

    $json = $null
    try {
        $out = $script:UpdatePs.EndInvoke($script:UpdateHandle)
        if ($out -and $out.Count -gt 0) { $json = [string]$out[0] }
    } catch {
        Write-Host "[ProxyTray] 读取检查结果失败: $_"
    }
    try { $script:UpdatePs.Dispose() }        catch { }
    try { $script:UpdateRs.Close() }          catch { }
    try { $script:UpdateRs.Dispose() }        catch { }
    $script:UpdatePs = $null; $script:UpdateRs = $null; $script:UpdateHandle = $null

    if ([string]::IsNullOrWhiteSpace($json)) {
        Write-Host '[ProxyTray] 检查更新没有得到结果'
        return $true
    }

    $r = $null
    try { $r = $json | ConvertFrom-Json } catch {
        Write-Host "[ProxyTray] 检查结果无法解析: $json"
        return $true
    }
    if (-not $r.ok) {
        Write-Host "[ProxyTray] 检查更新失败: $($r.err)"
        return $true
    }

    Set-UpdateLastCheck -Latest ([string]$r.tag)

    $latest = ([string]$r.tag).TrimStart('v', 'V')
    if ((Compare-AppVersion $latest $script:AppVersion) -gt 0) {
        $url = if ($r.url) { [string]$r.url } else { "https://github.com/$($script:UpdateRepo)/releases/latest" }
        $script:UpdateInfo = @{ Version = $latest; Url = $url }
        Set-UpdateMenuState -Info $script:UpdateInfo
        Write-Host ("[ProxyTray] 发现新版本 v{0}（当前 v{1}）" -f $latest, $script:AppVersion)
        Show-UpdateBalloon -Text ("发现新版本 v{0}`n右键托盘图标可打开下载页" -f $latest)
    } else {
        Write-Host ("[ProxyTray] 已是最新版本 v{0}" -f $script:AppVersion)
    }
    return $true
}

# ------------------------------------------------------ 轮询与触发
$script:updatePollTimer = New-Object System.Windows.Forms.Timer
$script:updatePollTimer.Interval = 400
$script:updatePollTimer.add_Tick({
    if (Complete-UpdateCheck) { $script:updatePollTimer.Stop() }
})

$script:updateStartTimer = New-Object System.Windows.Forms.Timer
$script:updateStartTimer.Interval = 5000
$script:updateStartTimer.add_Tick({
    $script:updateStartTimer.Stop()
    try { $script:updateStartTimer.Dispose() } catch { }
    $script:updateStartTimer = $null

    if (Test-UpdateThrottle) {
        Start-UpdateCheckAsync
        $script:updatePollTimer.Start()
    } else {
        Write-Host ("[ProxyTray] 距上次检查不满 {0} 小时，启动时跳过" -f $script:UpdateThrottleHours)
    }
})
$script:updateStartTimer.Start()

# 菜单项由 60-tray 创建，这里挂行为（80 在 60 之后加载，变量已存在）
$miUpdate.add_Click({
    Write-Host '[ProxyTray] 手动检查更新'
    Start-UpdateCheckAsync
    $script:updatePollTimer.Start()
})

$miNewVer.add_Click({ Open-UpdatePage })
