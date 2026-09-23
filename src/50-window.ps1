# ── src/50-window.ps1 · 窗口 ──
# 工作区与尺寸基准 / Form 与 WebView2 宿主 / 圆角 / 尺寸防抖 / 失焦延迟隐藏

# ================================================================
#  屏幕工作区 / 定位
# ================================================================
$script:margin      = 12
$script:wa          = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$script:lockedWidth = 0
$script:baseRight   = $null
$script:baseBottom  = $null

$script:initW = 420
$script:initH = 500
$script:initLeft = $script:wa.Right  - $script:initW - $script:margin
$script:initTop  = $script:wa.Bottom - $script:initH - $script:margin

$script:cornerRadius  = 24
$script:dwmCornerType = 2
$script:useDwmRound   = $false

# ---------- form ----------
$form                 = New-Object System.Windows.Forms.Form
$form.Text            = 'NAS Proxy'
$form.StartPosition   = 'Manual'
$form.FormBorderStyle = 'None'
$form.MaximizeBox     = $false
$form.MinimizeBox     = $false
$form.ShowInTaskbar   = $false
$form.BackColor       = [System.Drawing.Color]::FromArgb(24,24,27)
$form.Opacity         = 0

$form.SetBounds($script:initLeft, $script:initTop, $script:initW, $script:initH)
$script:baseRight  = $script:initLeft + $script:initW
$script:baseBottom = $script:initTop  + $script:initH

# ---------- webview ----------
$webView = New-Object Microsoft.Web.WebView2.WinForms.WebView2
$webView.CreationProperties = New-Object Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties
$webView.CreationProperties.UserDataFolder = $udd
$webView.Dock = 'Fill'
$webView.DefaultBackgroundColor = [System.Drawing.Color]::FromArgb(24,24,27)
$form.Controls.Add($webView)

# ---------- 状态标志 ----------
$script:ready      = $false
$script:hiding     = $false
$script:reallyExit = $false
$script:showTimer  = $null

# ---------- 圆角工具 ----------
function Set-FormRoundCorners {
    param([int]$Radius = $script:cornerRadius)
    if ($script:useDwmRound) { return }
    try {
        $osBuild = [System.Environment]::OSVersion.Version.Build
        if ($osBuild -ge 22000) {
            try {
                $hr = [NativeRound]::SetWindowCornerPreference($form.Handle, $script:dwmCornerType)
                if ($hr -eq 0) {
                    $script:useDwmRound = $true
                    [void][NativeRound]::SetWindowRgn($form.Handle, [IntPtr]::Zero, $true)
                    return
                }
            } catch { }
        }
        $w = $form.Width; $h = $form.Height
        if ($w -lt 10 -or $h -lt 10) { return }
        $rgn = [NativeRound]::CreateRoundRectRgn(0, 0, $w + 1, $h + 1, $Radius, $Radius)
        [void][NativeRound]::SetWindowRgn($form.Handle, $rgn, $true)
    } catch { }
}

function Reset-ToBottomRight {
    $w = if ($form.Width  -gt 0) { $form.Width  } else { $script:initW }
    $h = if ($form.Height -gt 0) { $form.Height } else { $script:initH }
    $L = $script:wa.Right  - $w - $script:margin
    $T = $script:wa.Bottom - $h - $script:margin
    $form.SetBounds($L, $T, $w, $h)
    $script:baseRight  = $L + $w
    $script:baseBottom = $T + $h
    Set-FormRoundCorners
}

# ---------- 尺寸防抖 Timer ----------
$script:pendingW = 0
$script:pendingH = 0
$script:sizeTimer = New-Object System.Windows.Forms.Timer
$script:sizeTimer.Interval = 120
$script:sizeTimer.add_Tick({
    $script:sizeTimer.Stop()
    $w = $script:pendingW
    $h = $script:pendingH
    $script:pendingW = 0
    $script:pendingH = 0
    if ($w -lt 200 -or $h -lt 200) { return }
    if ($form.IsDisposed) { return }

    if ($script:lockedWidth -eq 0) { $script:lockedWidth = $w }
    $targetW = $script:lockedWidth
    $maxH    = $script:wa.Height - 2 * $script:margin
    $targetH = [Math]::Min($h, $maxH)

    if ($form.Width -eq $targetW -and [Math]::Abs($form.Height - $targetH) -le 8) { return }

    $newLeft = $script:baseRight  - $targetW
    $newTop  = $script:baseBottom - $targetH
    if ($newTop  -lt $script:wa.Top)  { $newTop  = $script:wa.Top }
    if ($newLeft -lt $script:wa.Left) { $newLeft = $script:wa.Left }
    $form.SetBounds($newLeft, $newTop, $targetW, $targetH)
    Set-FormRoundCorners
})

# ---------- Deactivate 延迟隐藏 ----------
$script:hideTimer = New-Object System.Windows.Forms.Timer
$script:hideTimer.Interval = 150
$script:hideTimer.add_Tick({
    $script:hideTimer.Stop()
    if (-not $script:ready)   { return }
    if ($form.IsDisposed)     { return }
    if (-not $form.Visible)   { return }
    try {
        $fg = [System.Windows.Forms.Form]::ActiveForm
        if ($fg -eq $form) { return }
    } catch { }

    $script:hiding = $true
    try { $form.Hide() } catch { }
    $script:hiding = $false
})

$form.add_Deactivate({
    if (-not $script:ready) { return }
    if ($script:hiding)     { return }
    if (-not $form.Visible) { return }
    $script:hideTimer.Stop()
    $script:hideTimer.Start()
})
