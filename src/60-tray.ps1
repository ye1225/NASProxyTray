# ── src/60-tray.ps1 · 托盘 ──
# NotifyIcon / 深色中文右键菜单 / 菜单与双击行为 / 窗口显隐

# ================================================================
#  托盘图标 + 深色中文菜单
# ================================================================
$script:iconGray  = New-BallIcon -Color ([System.Drawing.Color]::FromArgb(0x9E, 0x9E, 0x9E))
$script:iconGreen = New-BallIcon -Color ([System.Drawing.Color]::FromArgb(0x34, 0xC7, 0x59))

$tray         = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon    = $script:iconGray
$tray.Text    = 'NAS Proxy · 已关闭'
$tray.Visible = $true

function Update-TrayIcon {
    param([bool]$Enabled)
    try {
        if ($null -eq $script:iconGreen) { return }
        $tray.Icon = if ($Enabled) { $script:iconGreen } else { $script:iconGray }
        $tray.Text = if ($Enabled) { 'NAS Proxy · 已开启' } else { 'NAS Proxy · 已关闭' }
    } catch { }
}

$menu = New-Object System.Windows.Forms.ContextMenuStrip
if ($script:hasDarkRenderer) {
    try {
        $rt = 'DarkMenuRenderer' -as [type]
        if ($rt) { $menu.Renderer = [System.Activator]::CreateInstance($rt) }
    } catch { }
}
$menu.BackColor         = [System.Drawing.Color]::FromArgb(38, 38, 42)
$menu.ForeColor         = [System.Drawing.Color]::FromArgb(240, 240, 245)
$menu.ShowImageMargin   = $false
$menu.Padding           = New-Object System.Windows.Forms.Padding(2, 4, 2, 4)
$menu.DropShadowEnabled = $true
try { $menu.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9) } catch { }

$miShow  = [System.Windows.Forms.ToolStripMenuItem]::new('显示 / 隐藏窗口')
$miDev   = [System.Windows.Forms.ToolStripMenuItem]::new('打开开发者工具')
$miSep1  = [System.Windows.Forms.ToolStripSeparator]::new()
$miClean = [System.Windows.Forms.ToolStripMenuItem]::new('立即清除系统代理')
$miSize  = [System.Windows.Forms.ToolStripMenuItem]::new('复位窗口位置')
$miSep2  = [System.Windows.Forms.ToolStripSeparator]::new()
$miExit  = [System.Windows.Forms.ToolStripMenuItem]::new('退出')

foreach ($it in @($miShow,$miDev,$miClean,$miSize,$miExit)) {
    $it.Padding = New-Object System.Windows.Forms.Padding(10, 3, 10, 3)
}

[void]$menu.Items.Add($miShow)
[void]$menu.Items.Add($miDev)
[void]$menu.Items.Add($miSep1)
[void]$menu.Items.Add($miClean)
[void]$menu.Items.Add($miSize)
[void]$menu.Items.Add($miSep2)
[void]$menu.Items.Add($miExit)

$tray.ContextMenuStrip = $menu

$menu.add_Opened({
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

$miShow.add_Click({
    if ($form.Visible) { Hide-MainWindow } else { Show-MainWindow }
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

$tray.add_MouseDoubleClick({
    try {
        if ($form.IsDisposed) { return }
        if ($form.Visible) { Hide-MainWindow } else { Show-MainWindow }
    } catch {
        Write-Host "[ProxyTray] tray double-click failed: $_"
    }
})
