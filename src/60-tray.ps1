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
$menu.BackColor         = [System.Drawing.Color]::FromArgb(38, 38, 42)
$menu.ForeColor         = [System.Drawing.Color]::FromArgb(240, 240, 245)
$menu.ShowImageMargin   = $false
$padX = [Math]::Max(2, [int][Math]::Round(2 * $script:DpiScale))
$padY = [Math]::Max(4, [int][Math]::Round(4 * $script:DpiScale))
$menu.Padding           = New-Object System.Windows.Forms.Padding($padX, $padY, $padX, $padY)
$menu.DropShadowEnabled = $true
try { $menu.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9) } catch { }

# 有新版本时才显示的一项（默认隐藏，由 80-update 控制）
$miNewVer = [System.Windows.Forms.ToolStripMenuItem]::new('发现新版本')
$miNewVer.Visible = $false
$miToggle = [System.Windows.Forms.ToolStripMenuItem]::new('开启代理')
$miShow  = [System.Windows.Forms.ToolStripMenuItem]::new('显示 / 隐藏窗口')
$miDev   = [System.Windows.Forms.ToolStripMenuItem]::new('打开开发者工具')
$miSep1  = [System.Windows.Forms.ToolStripSeparator]::new()
$miClean = [System.Windows.Forms.ToolStripMenuItem]::new('立即清除系统代理')
$miSize  = [System.Windows.Forms.ToolStripMenuItem]::new('复位窗口位置')
$miUpdate = [System.Windows.Forms.ToolStripMenuItem]::new('检查更新')
$miSep2  = [System.Windows.Forms.ToolStripSeparator]::new()
$miExit  = [System.Windows.Forms.ToolStripMenuItem]::new('退出')

foreach ($it in @($miNewVer,$miToggle,$miShow,$miDev,$miClean,$miSize,$miUpdate,$miExit)) {
    $itemPadX = [Math]::Max(10, [int][Math]::Round(10 * $script:DpiScale))
    $itemPadY = [Math]::Max(3,  [int][Math]::Round(3  * $script:DpiScale))
    $it.Padding = New-Object System.Windows.Forms.Padding($itemPadX, $itemPadY, $itemPadX, $itemPadY)
}

[void]$menu.Items.Add($miNewVer)
[void]$menu.Items.Add($miToggle)
[void]$menu.Items.Add($miShow)
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
        # 菜单文字跟随当前状态
        $cfg = $script:CurrentConfig
        if ($null -eq $cfg) { $cfg = Get-ProxyConfig }
        $miToggle.Text = if ([bool]$cfg.enabled) { '关闭代理' } else { '开启代理' }
    } catch { }
    try {
        $w = $menu.Width; $h = $menu.Height
        if ($w -lt 10 -or $h -lt 10) { return }
        $rad = 8
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

$miToggle.add_Click({ Invoke-ProxyToggle -Source 'menu' })

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

