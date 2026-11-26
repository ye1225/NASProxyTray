# ── src/60-tray.ps1 · 托盘 ──
# NotifyIcon / 深色中文右键菜单 / 菜单与双击行为 / 窗口显隐

# ================================================================
#  托盘图标 + 深色中文菜单
# ================================================================
$script:iconGray  = New-BallIcon -Color ([System.Drawing.Color]::FromArgb(0x9E, 0x9E, 0x9E))
$script:iconGreen = New-BallIcon -Color ([System.Drawing.Color]::FromArgb(0x34, 0xC7, 0x59))
$script:iconBlue  = New-BallIcon -Color ([System.Drawing.Color]::FromArgb(0x0A, 0x84, 0xFF))

$tray         = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon    = $script:iconGray
$tray.Text    = 'NAS Proxy · 已关闭'
$tray.Visible = $true

# 三态图标：灰=关闭 / 绿=规则分流 / 蓝=全局代理。
# mode 从 CurrentConfig 读，所以既有调用点（70-message / 90-main / miClean）不用改。
function Update-TrayIcon {
    param([bool]$Enabled)
    try {
        if ($null -eq $script:iconGreen) { return }
        $mode = ''
        try { $mode = [string]$script:CurrentConfig.mode } catch { }
        if ($Enabled -and $mode -eq 'global') {
            $tray.Icon = $script:iconBlue
            $tray.Text = 'NAS Proxy · 全局代理已开启'
        } elseif ($Enabled) {
            $tray.Icon = $script:iconGreen
            $tray.Text = 'NAS Proxy · 规则分流已开启'
        } else {
            $tray.Icon = $script:iconGray
            $tray.Text = 'NAS Proxy · 已关闭'
        }
    } catch { }
}

$menu = New-Object System.Windows.Forms.ContextMenuStrip
if ($script:hasDarkRenderer) {
    try {
        $rt = 'DarkMenuRenderer' -as [type]
        if ($rt) { $menu.Renderer = [System.Activator]::CreateInstance($rt) }
    } catch { }
}
# 字体：固定 9pt，不按 DpiScale 手工放大。
# GDI+ 渲染 point 字体时会随设备 DPI（200% 屏 = 192）自动放大，
# 再手工乘一遍就是双重放大 —— v1.2.0 在 4K 上菜单文字特别大就是这个原因。
# Padding 是物理像素，WinForms 不会代缩，这里保留手工乘 DpiScale。
$menu.BackColor         = [System.Drawing.Color]::FromArgb(40, 40, 43)
$menu.ForeColor         = [System.Drawing.Color]::FromArgb(236, 236, 239)
# 左侧留出勾选槽（勾由 DarkMenuRenderer 自绘，比默认那枚小灰勾清楚得多）
$menu.ShowCheckMargin   = $true
$menu.ShowImageMargin   = $false
$padX = [Math]::Max(4, [int][Math]::Round(4 * $script:DpiScale))
$padY = [Math]::Max(6, [int][Math]::Round(6 * $script:DpiScale))
$menu.Padding           = New-Object System.Windows.Forms.Padding($padX, $padY, $padX, $padY)
$menu.DropShadowEnabled = $true
try { $menu.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9) } catch { }

# 有新版本时才显示的一项（默认隐藏，由 80-update 控制）
$miNewVer = [System.Windows.Forms.ToolStripMenuItem]::new('发现新版本')
$miNewVer.Visible = $false
$miToggle = [System.Windows.Forms.ToolStripMenuItem]::new('开启代理')
$miModeGlobal = [System.Windows.Forms.ToolStripMenuItem]::new('全部走代理')
$miModeSmart  = [System.Windows.Forms.ToolStripMenuItem]::new('国内直连（国外走代理）')
$miSepMode = [System.Windows.Forms.ToolStripSeparator]::new()
$miShow  = [System.Windows.Forms.ToolStripMenuItem]::new('显示 / 隐藏窗口')
$miRules = [System.Windows.Forms.ToolStripMenuItem]::new('编辑国内直连规则')
$miRulesUpdate = [System.Windows.Forms.ToolStripMenuItem]::new('更新直连规则（联网）')
$miAuto  = [System.Windows.Forms.ToolStripMenuItem]::new('开机自启动')
$miDev   = [System.Windows.Forms.ToolStripMenuItem]::new('打开开发者工具')
$miSep1  = [System.Windows.Forms.ToolStripSeparator]::new()
$miClean = [System.Windows.Forms.ToolStripMenuItem]::new('立即清除系统代理')
$miSize  = [System.Windows.Forms.ToolStripMenuItem]::new('复位窗口位置')
$miUpdate = [System.Windows.Forms.ToolStripMenuItem]::new('检查更新')
$miSep2  = [System.Windows.Forms.ToolStripSeparator]::new()
$miExit  = [System.Windows.Forms.ToolStripMenuItem]::new('退出')

foreach ($it in @($miNewVer,$miToggle,$miShow,$miRules,$miRulesUpdate,$miDev,$miClean,$miSize,$miUpdate,$miExit)) {
    $itemPadX = [Math]::Max(12, [int][Math]::Round(12 * $script:DpiScale))
    $itemPadY = [Math]::Max(5,  [int][Math]::Round(5  * $script:DpiScale))
    $it.Padding = New-Object System.Windows.Forms.Padding($itemPadX, $itemPadY, $itemPadX, $itemPadY)
}

[void]$menu.Items.Add($miNewVer)
[void]$menu.Items.Add($miToggle)
[void]$menu.Items.Add($miModeGlobal)
[void]$menu.Items.Add($miModeSmart)
[void]$menu.Items.Add($miSepMode)
[void]$menu.Items.Add($miShow)
[void]$menu.Items.Add($miRules)
[void]$menu.Items.Add($miRulesUpdate)
[void]$menu.Items.Add($miAuto)
[void]$menu.Items.Add($miDev)
[void]$menu.Items.Add($miSep1)
[void]$menu.Items.Add($miClean)
[void]$menu.Items.Add($miSize)
[void]$menu.Items.Add($miUpdate)
[void]$menu.Items.Add($miSep2)
$miVersion = [System.Windows.Forms.ToolStripMenuItem]::new(('v{0}' -f $script:AppVersion))
$miVersion.Enabled = $false
[void]$menu.Items.Add($miVersion)
[void]$menu.Items.Add($miExit)

$tray.ContextMenuStrip = $menu

$menu.add_Opened({
    try {
        # 菜单文字与勾选跟随当前状态
        $cfg = $script:CurrentConfig
        if ($null -eq $cfg) { $cfg = Get-ProxyConfig }
        $miToggle.Text = if ([bool]$cfg.enabled) { '关闭代理' } else { '开启代理' }
        $miModeGlobal.Checked = ([string]$cfg.mode -eq 'global')
        $miModeSmart.Checked  = (-not $miModeGlobal.Checked)
        $miAuto.Checked       = [bool]$cfg.autoStart
    } catch { }
    try {
        $w = $menu.Width; $h = $menu.Height
        if ($w -lt 10 -or $h -lt 10) { return }
        $rad = [Math]::Max(6, [int][Math]::Round(5 * $script:DpiScale))
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $path.AddArc(0, 0, $rad * 2, $rad * 2, 180, 90)
        $path.AddArc($w - $rad * 2 - 1, 0, $rad * 2, $rad * 2, 270, 90)
        $path.AddArc($w - $rad * 2 - 1, $h - $rad * 2 - 1, $rad * 2, $rad * 2, 0, 90)
        $path.AddArc(0, $h - $rad * 2 - 1, $rad * 2, $rad * 2, 90, 90)
        $path.CloseFigure()
        $menu.Region = New-Object System.Drawing.Region($path)
        $path.Dispose()
        $menu.Invalidate()
    } catch { }
})

function Show-ReadyForm {
    if ($script:ready) { return }
    $script:ready = $true
    try { $script:hideTimer.Stop() } catch { }

    if ($script:SilentStart) {
        # 开机自启（--silent）：只留托盘图标，不弹面板打扰。
        # WebView2 在隐藏窗口里继续运行，配置照常加载、尺寸照常上报。
        $form.Opacity = 1
        try { if ($form.Visible) { $form.Hide() } } catch { }
        Write-Host '[ProxyTray] 静默启动：面板不弹出，仅托盘图标'
        return
    }

    $form.Opacity = 1
    try {
        if (-not $form.Visible) { $form.Show() }
        $form.BringToFront()
        $form.Activate()
    } catch {
        Write-Host "[ProxyTray] Show-ReadyForm failed: $_"
    }
}

function Show-MainWindow {
    try {
        if ($form.IsDisposed) { return }
        try { $script:hideTimer.Stop() } catch { }
        if (-not $form.Visible) { $form.Show() }
        $form.BringToFront()
        $form.Activate()
        # 静默启动后窗口一直藏着，可能没收到尺寸消息 —— 补一次上报
        if ($null -ne $webView.CoreWebView2) {
            try { [void]$webView.CoreWebView2.ExecuteScriptAsync('window.__ptPublish&&window.__ptPublish()') } catch { }
        }
    } catch {
        Write-Host "[ProxyTray] show failed: $_"
    }
}

function Hide-MainWindow {
    try {
        if ($form.IsDisposed) { return }
        try { $script:hideTimer.Stop() } catch { }
        if ($form.Visible) { $form.Hide() }
    } catch { }
}

# 切换代理开/关（托盘双击 / 菜单项共用）。
# 与前端 toggleProxy 动作同一套动作：落盘配置 → Apply → 图标 → 通知界面刷新。
function Invoke-ProxyToggle {
    param([string]$Source = 'tray')
    try {
        $cfg = Get-ProxyConfig
        $cfg.enabled = -not [bool]$cfg.enabled
        Save-ProxyConfig -Config $cfg
        $script:CurrentConfig = $cfg

        $r = Apply-ProxyConfig -Config $cfg
        Update-TrayIcon -Enabled ([bool]$cfg.enabled)

        if ($null -ne $webView.CoreWebView2) {
            $state = @{
                action  = 'state'
                enabled = [bool]$cfg.enabled
                ok      = [bool]$r.ok
                msg     = $r.msg
                mode    = $cfg.mode
                server  = $cfg.server
                port    = $cfg.port
            } | ConvertTo-Json -Compress
            try { $webView.CoreWebView2.PostWebMessageAsString($state) } catch { }
        }
        Write-Host ("[ProxyTray] toggle({0}) -> enabled={1} ok={2} msg={3}" -f $Source, $cfg.enabled, $r.ok, $r.msg)
    } catch {
        Write-Host "[ProxyTray] toggle($Source) failed: $_"
    }
}

$miShow.add_Click({
    if ($form.Visible) { Hide-MainWindow } else { Show-MainWindow }
})

# 编辑国内直连规则：打开（必要时先建模板）my-direct.txt，
# 记事本关闭后自动重新应用配置（重建 PAC），改完即生效。
$miRules.add_Click({
    try {
        $rulesFile = Join-Path $script:DataDir 'my-direct.txt'
        if (-not (Test-Path -LiteralPath $rulesFile)) {
            New-DirectRulesTemplate -Path $rulesFile
        }
        $script:rulesProc = Start-Process notepad.exe -ArgumentList ('"' + $rulesFile + '"') -PassThru
        if (-not $script:rulesWatchTimer) {
            $script:rulesWatchTimer = New-Object System.Windows.Forms.Timer
            $script:rulesWatchTimer.Interval = 800
            $script:rulesWatchTimer.add_Tick({
                try {
                    if ($script:rulesProc -and $script:rulesProc.HasExited) {
                        $script:rulesWatchTimer.Stop()
                        $script:rulesProc = $null
                        $cfg = Get-ProxyConfig
                        if ([bool]$cfg.enabled) {
                            $r = Apply-ProxyConfig -Config $cfg
                            Write-Host "[ProxyTray] 直连规则已更新并重新应用: $($r.msg)"
                        } else {
                            Write-Host '[ProxyTray] 直连规则已保存（代理未开启，下次开启时生效）'
                        }
                    }
                } catch {
                    Write-Host "[ProxyTray] rules re-apply failed: $_"
                }
            })
        }
        $script:rulesWatchTimer.Stop()
        $script:rulesWatchTimer.Start()
    } catch {
        Write-Host "[ProxyTray] open rules editor failed: $_"
    }
})

# 更新直连规则（联网）：后台下载上游清单 → 归并落盘 → 重建 PAC。
# 下载在 runspace 里跑，完成由 36-direct-update 的 Timer 轮询后自动应用。
$miRulesUpdate.add_Click({
    try {
        if (-not $script:DirectUpdatePending) {
            Start-DirectRulesUpdateAsync
            try { $script:directUpdatePollTimer.Start() } catch { }
            try { $tray.ShowBalloonTip(4000, 'NAS Proxy', '正在更新直连规则，完成后会提示…', [System.Windows.Forms.ToolTipIcon]::Info) } catch { }
        }
    } catch {
        Write-Host "[ProxyTray] update direct rules failed: $_"
    }
})

$miToggle.add_Click({ Invoke-ProxyToggle -Source 'menu' })

# 托盘菜单直接切模式（不开面板）：落盘 → 已开启则重应用 → 图标 → 通知界面刷新
function Set-ProxyMode {
    param([ValidateSet('global','smart')][string]$Mode, [string]$Source = 'menu')
    try {
        $cfg = Get-ProxyConfig
        if ([string]$cfg.mode -eq $Mode) { return }   # 重复点同一个模式，什么都不做
        $cfg.mode = $Mode
        Save-ProxyConfig -Config $cfg
        $script:CurrentConfig = $cfg

        if ($cfg.enabled) {
            $r = Apply-ProxyConfig -Config $cfg
            Write-Host ("[ProxyTray] mode({0}) -> {1} ok={2} msg={3}" -f $Source, $Mode, $r.ok, $r.msg)
        } else {
            Write-Host ("[ProxyTray] mode({0}) -> {1} (未开启，仅保存)" -f $Source, $Mode)
        }

        Update-TrayIcon -Enabled ([bool]$cfg.enabled)

        if ($null -ne $webView.CoreWebView2) {
            $payload = @{
                action     = 'config'
                config     = $cfg
                version    = $script:AppVersion
                chinaCount = @($script:ChinaDirectDomains).Count
            } | ConvertTo-Json -Depth 6 -Compress
            try { $webView.CoreWebView2.PostWebMessageAsString($payload) } catch { }
        }
    } catch {
        Write-Host "[ProxyTray] mode($Source) failed: $_"
    }
}

$miModeGlobal.add_Click({ Set-ProxyMode -Mode 'global' -Source 'menu' })
$miModeSmart.add_Click({ Set-ProxyMode -Mode 'smart' -Source 'menu' })

$miAuto.add_Click({
    try {
        $want = $miAuto.Checked
        Set-AutoStart -Enabled $want | Out-Null
        $cfg = Get-ProxyConfig
        $cfg.autoStart = $want
        Save-ProxyConfig -Config $cfg
        $script:CurrentConfig = $cfg
        Write-Host "[ProxyTray] autostart -> $want"
    } catch {
        Write-Host "[ProxyTray] autostart failed: $_"
    }
})

$miDev.add_Click({
    if ($null -ne $webView.CoreWebView2) { $webView.CoreWebView2.OpenDevToolsWindow() }
})

$miClean.add_Click({
    try {
        Clear-SystemProxy
        $cfg = Get-ProxyConfig
        $cfg.enabled = $false
        Save-ProxyConfig -Config $cfg
        $script:CurrentConfig = $cfg
        Update-TrayIcon -Enabled $false
        if ($null -ne $webView.CoreWebView2) {
            $payload = @{ action = 'state'; enabled = $false; ok = $true; msg = '系统代理已清除' } | ConvertTo-Json -Compress
            try { $webView.CoreWebView2.PostWebMessageAsString($payload) } catch { }
        }
    } catch {
        Write-Host "[ProxyTray] clean failed: $_"
    }
})

$miSize.add_Click({ $script:lockedWidth = 0; Reset-ToBottomRight })

$miExit.add_Click({
    $script:reallyExit = $true
    try { $script:hideTimer.Stop() } catch { }
    try { $script:sizeTimer.Stop() } catch { }
    try { Clear-SystemProxy } catch { }
    try { Stop-PacServer }   catch { }
    try { $tray.Visible = $false; $tray.Dispose() } catch { }
    try { $menu.Dispose() } catch { }
    try { $form.Close() } catch { }
    try { [System.Windows.Forms.Application]::ExitThread() } catch { }
})

# ---------- 托盘左键：单击=开界面（立即），双击=切换代理 ----------
# WinForms 的双击必然先触发两次 MouseClick。利用「WM_PAINT 是低优先级消息」：
# 双击的两条消息连续派发，第一次点击 Show 的窗口还没被绘制，DoubleClick 里
# 立刻 Hide —— 窗口一次都不会画到屏幕上，既不闪也不需要给单击加延迟。
# 只有当窗口是「被这次点击序列打开的」时才顺手收起；窗口本来就开着则保持。
$script:trayShownByClick = $false

$tray.add_MouseClick({
    param($s, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    try {
        if ($form.IsDisposed) { return }
        $script:trayShownByClick = $false
        if (-not $form.Visible) {
            Show-MainWindow
            $script:trayShownByClick = $true
        } else {
            $form.BringToFront()
            $form.Activate()
        }
    } catch {
        Write-Host "[ProxyTray] tray click failed: $_"
    }
})

$tray.add_MouseDoubleClick({
    param($s, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    try {
        if ($form.IsDisposed) { return }
        Invoke-ProxyToggle -Source 'tray-dbl'
        if ($script:trayShownByClick -and $form.Visible) { Hide-MainWindow }
        $script:trayShownByClick = $false
    } catch {
        Write-Host "[ProxyTray] tray double-click failed: $_"
    }
})

