# ── src/30-proxy.ps1 · 代理引擎 ──
# 全局代理与 PAC 写入 / 本地 PAC 服务 / 内置 PAC 生成 / 连通测试 / 开机自启

function Set-GlobalProxy {
    param([string]$Server, [string]$Port, [string]$Override)
    if ($script:DryRun) { Write-Host "[DRYRUN] 跳过写注册表：全局代理 $Server`:$Port"; return }
    $proxy = "$Server`:$Port"
    if ($Override) {
        Set-ItemProperty -Path $script:RegPath -Name 'ProxyOverride' -Value $Override -ErrorAction SilentlyContinue
    }
    Set-ItemProperty -Path $script:RegPath -Name 'ProxyServer' -Value $proxy
    Set-ItemProperty -Path $script:RegPath -Name 'ProxyEnable' -Value 1 -Type DWord
    Remove-ItemProperty -Path $script:RegPath -Name 'AutoConfigURL' -ErrorAction SilentlyContinue
    Update-InternetSettings
}

function Set-PacProxy {
    param([string]$PacContent)
    $PacContent | Set-Content -Path $script:ServedPac -Encoding ASCII
    $port = Start-PacServer
    $url  = "http://127.0.0.1:$port/proxy.pac"
    if ($script:DryRun) { Write-Host "[DRYRUN] 跳过写注册表：PAC 模式 $url"; return $url }
    Set-ItemProperty -Path $script:RegPath -Name 'AutoConfigURL' -Value $url
    Set-ItemProperty -Path $script:RegPath -Name 'ProxyEnable'    -Value 0 -Type DWord
    Remove-ItemProperty -Path $script:RegPath -Name 'ProxyServer' -ErrorAction SilentlyContinue
    Update-InternetSettings
    return $url
}

function Clear-SystemProxy {
    try {
        if ($script:DryRun) { Write-Host "[DRYRUN] 跳过清除系统代理（不改注册表）"; return }
        Set-ItemProperty     -Path $script:RegPath -Name 'ProxyEnable'   -Value 0 -Type DWord
        Remove-ItemProperty  -Path $script:RegPath -Name 'ProxyServer'   -ErrorAction SilentlyContinue
        Remove-ItemProperty  -Path $script:RegPath -Name 'AutoConfigURL' -ErrorAction SilentlyContinue
        Update-InternetSettings
    } catch {
        Write-Host "[ProxyTray] Clear-SystemProxy failed: $_"
    }
}

# ---------- 本地 PAC 服务 ----------
# 监听器在主线程创建并持有引用，Stop-PacServer 直接关掉它，
# 阻塞中的 AcceptTcpClient 会立刻抛错退出 —— 旧实现在抛出后仍不停循环，会空转占满一核。
function Start-PacServer {
    if ($script:PacPs) { return $script:PacPort }

    $listener = $null
    for ($attempt = 0; $attempt -lt 20 -and -not $listener; $attempt++) {
        $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $probe.Start()
        $port = ([System.Net.IPEndPoint]$probe.LocalEndpoint).Port
        $probe.Stop()
        try {
            $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
            $listener.Start()
            $script:PacPort = $port
        } catch {
            $listener = $null
        }
    }
    if (-not $listener) { throw 'PAC 服务无法绑定本地端口' }
    $script:PacListener = $listener

    $pacPath = $script:ServedPac

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'MTA'
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
        param($listener, $pacPath)
        while ($true) {
            try {
                $client = $listener.AcceptTcpClient()
            } catch {
                break          # 监听器已被关闭 → 服务线程优雅退出
            }
            try {
                $stream = $client.GetStream()
                $reader = New-Object System.IO.StreamReader($stream)
                while (-not [string]::IsNullOrEmpty($reader.ReadLine())) { }
                $body = if (Test-Path $pacPath) { Get-Content $pacPath -Raw } else { 'function FindProxyForURL(url, host) { return "DIRECT"; }' }
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
                $header = "HTTP/1.1 200 OK`r`nContent-Type: application/x-ns-proxy-autoconfig`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n"
                $hb = [System.Text.Encoding]::ASCII.GetBytes($header)
                $stream.Write($hb, 0, $hb.Length)
                $stream.Write($bytes, 0, $bytes.Length)
                $stream.Flush()
            } catch { } finally { $client.Close() }
        }
    }).AddArgument($listener).AddArgument($pacPath)
    $ps.BeginInvoke() | Out-Null

    $script:PacPs = $ps
    $script:PacRunspace = $rs
    return $script:PacPort
}

function Stop-PacServer {
    try {
        # 先关监听器唤醒阻塞的 Accept，服务线程随即自行结束
        if ($script:PacListener) {
            try { $script:PacListener.Stop() } catch { }
            $script:PacListener = $null
        }
        if ($script:PacPs) {
            try { $script:PacPs.Stop() }    catch { }
            try { $script:PacPs.Dispose() } catch { }
            $script:PacPs = $null
        }
        if ($script:PacRunspace) {
            try { $script:PacRunspace.Close() }     catch { }
            try { $script:PacRunspace.Dispose() }   catch { }
            $script:PacRunspace = $null
        }
    } catch { }
}


function Build-BuiltinPac {
    param([string]$DomainsText, [string]$ProxyAddr)
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($DomainsText -split "`r?`n")) {
        $d = $line.Trim().ToLower()
        if (-not $d -or $d.StartsWith('#')) { continue }
        if ($d.StartsWith('*.')) {
            $base = $d.Substring(2)
            $lines.Add("  if (host === `"$base`" || dnsDomainIs(host, `".$base`")) return `"$ProxyAddr`";")
        } elseif ($d.Contains('*')) {
            $lines.Add("  if (shExpMatch(host, `"$d`")) return `"$ProxyAddr`";")
        } else {
            $lines.Add("  if (host === `"$d`" || dnsDomainIs(host, `".$d`")) return `"$ProxyAddr`";")
        }
    }
    $rules = ($lines -join "`n")
    return @"
function FindProxyForURL(url, host) {
  host = host.toLowerCase();
$rules
  return "DIRECT";
}
"@
}

function Apply-ProxyConfig {
    param($Config)
    if (-not $Config.enabled) {
        Clear-SystemProxy
        return @{ ok = $true; msg = '已关闭系统代理' }
    }

    if ($Config.mode -eq 'global') {
        try {
            Set-GlobalProxy -Server $Config.server -Port $Config.port -Override $Config.override
            return @{ ok = $true; msg = "全局代理已开启 ($($Config.server):$($Config.port))" }
        } catch {
            return @{ ok = $false; msg = "设置全局代理失败：$_" }
        }
    }

    $pacContent = $null
    try {
        switch ($Config.pacSource) {
            'local' {
                if ([string]::IsNullOrWhiteSpace($Config.localPacPath)) { return @{ ok = $false; msg = '未指定 PAC 文件' } }
                if (-not (Test-Path $Config.localPacPath))             { return @{ ok = $false; msg = 'PAC 文件不存在' } }
                $pacContent = Get-Content $Config.localPacPath -Raw -Encoding UTF8
            }
            'remote' {
                if ([string]::IsNullOrWhiteSpace($Config.remotePacUrl)) { return @{ ok = $false; msg = '未填写 PAC 订阅地址' } }
                try {
                    $old = [Net.ServicePointManager]::SecurityProtocol
                    try {
                        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                        $resp = Invoke-WebRequest -Uri $Config.remotePacUrl -UseBasicParsing -TimeoutSec 20
                    } finally {
                        [Net.ServicePointManager]::SecurityProtocol = $old
                    }
                    $pacContent = $resp.Content
                    if ($pacContent) { $pacContent | Set-Content -Path $script:RemotePacCache -Encoding UTF8 }
                } catch {
                    if (Test-Path $script:RemotePacCache) {
                        $pacContent = Get-Content $script:RemotePacCache -Raw -Encoding UTF8
                        Write-Host "[ProxyTray] Remote PAC fetch failed, fallback to cache"
                    } else { throw }
                }
            }
            default {
                $proxyAddr  = "PROXY $($Config.server):$($Config.port); DIRECT"
                $pacContent = Build-BuiltinPac -DomainsText $Config.pacDomains -ProxyAddr $proxyAddr
            }
        }
    } catch {
        return @{ ok = $false; msg = "获取 PAC 失败：$_" }
    }

    if ([string]::IsNullOrWhiteSpace($pacContent)) { return @{ ok = $false; msg = 'PAC 内容为空' } }

    try {
        [void](Set-PacProxy -PacContent $pacContent)
        return @{ ok = $true; msg = '智能分流已开启' }
    } catch {
        return @{ ok = $false; msg = "设置 PAC 失败：$_" }
    }
}

function Test-ProxyConn {
    param([string]$Server, [int]$Port, [int]$TimeoutMs = 900)
    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $iar = $client.BeginConnect($Server, $Port, $null, $null)
        $ok  = $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        $sw.Stop()
        if ($ok -and $client.Connected) {
            try { $client.EndConnect($iar) } catch { }
            return @{ ok = $true; latency = [int]$sw.ElapsedMilliseconds }
        }
        return @{ ok = $false; latency = 0 }
    } catch {
        return @{ ok = $false; latency = 0 }
    } finally {
        if ($client) { try { $client.Close() } catch { } }
    }
}

# ---------- 开机自启：兼容 .ps1 / .exe ----------
function Set-AutoStart {
    param([bool]$Enabled)
    if ($script:DryRun) { Write-Host ("[DRYRUN] 跳过开机自启设置：Enabled={0}" -f $Enabled); return $true }
    $startupDir = [Environment]::GetFolderPath('Startup')
    if (-not $startupDir) { return $false }
    $lnk = Join-Path $startupDir 'NASProxy.lnk'
    try {
        if ($Enabled) {
            $ws = New-Object -ComObject WScript.Shell
            $sc = $ws.CreateShortcut($lnk)
            if ($script:appIsExe) {
                # 打包成 exe：快捷方式直接指向自己
                $sc.TargetPath       = $script:appSelf
                $sc.Arguments        = ''
                $sc.WorkingDirectory = $root
                $sc.WindowStyle      = 7
                $sc.IconLocation     = "$($script:appSelf),0"
            } else {
                $psExe = Join-Path $PSHOME 'powershell.exe'
                if (-not (Test-Path -LiteralPath $psExe)) { $psExe = 'powershell.exe' }
                $sc.TargetPath       = $psExe
                $sc.Arguments        = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($script:appSelf)`""
                $sc.WorkingDirectory = $root
                $sc.WindowStyle      = 7
            }
            $sc.Save()
        } else {
            if (Test-Path $lnk) { Remove-Item $lnk -Force -ErrorAction SilentlyContinue }
        }
        return $true
    } catch {
        Write-Host "[ProxyTray] Set-AutoStart failed: $_"
        return $false
    }
}

function Get-AutoStart {
    $startupDir = [Environment]::GetFolderPath('Startup')
    if (-not $startupDir) { return $false }
    return (Test-Path (Join-Path $startupDir 'NASProxy.lnk'))
}
