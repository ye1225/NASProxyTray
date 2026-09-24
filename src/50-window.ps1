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

# ---------- DPI 换算基准 ----------
# 声明 DPI 感知之后，SetBounds / 边距 / 圆角用的都是物理像素，
# 而前端给的是 CSS 像素，两者相差一个 DpiScale。
# 关键：句柄没建出来之前 Form.DeviceDpi 恒为 96，必须先建句柄再读，
# 否则在 200% 缩放的机器上会算出 scale=1，界面瞬间缩成一半。
$null = $form.Handle
$script:DpiScale = 1.0
$dpi = 0
try { $dpi = [int]$form.DeviceDpi } catch { }
if ($dpi -le 96) {
    try { $dpi = [int][NativeDpi.Api]::GetDpiForSystem() } catch { }
}
if ($dpi -gt 0) { $script:DpiScale = $dpi / 96.0 }
if ($script:DpiScale -lt 1) { $script:DpiScale = 1 }
$script:DpiScale = [Math]::Round($script:DpiScale * 4) / 4        # 归到 0.25 的整数倍，避免半像素抖动

function Update-DpiMetrics {
    $script:margin       = [int][Math]::Round(12  * $script:DpiScale)
    $script:initW        = [int][Math]::Round(420 * $script:DpiScale)
    $script:initH        = [int][Math]::Round(500 * $script:DpiScale)
    $script:cornerRadius = [Math]::Max(1, [int][Math]::Round(24 * $script:DpiScale))
}
Update-DpiMetrics

$script:initLeft = $script:wa.Right  - $script:initW - $script:margin
$script:initTop  = $script:wa.Bottom - $script:initH - $script:margin
$form.SetBounds($script:initLeft, $script:initTop, $script:initW, $script:initH)
$script:baseRight  = $script:initLeft + $script:initW
$script:baseBottom = $script:initTop  + $script:initH
Write-Host ("[ProxyTray] dpiScale={0}  initSize={1}x{2}" -f $script:DpiScale, $script:initW, $script:initH)

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
# Win11：DWM 合成圆角（抗锯齿）；Win10 / DWM 失败：回退 1-bit region（有锯齿）
function Set-FormRoundCorners {
    param([int]$Radius = $script:cornerRadius)
    try {
        if ($script:useDwmRound) {
            # 句柄可能被 WinForms 重建（如 Opacity 动画改样式）——核对 THICKFRAME 还在不在
            $still = $false
            try { $still = (([NativeRound]::GetStyle($form.Handle) -band 0x40000) -ne 0) } catch { }
            if ($still) {
                try { [void][NativeRound]::SetWindowCornerPreference($form.Handle, 2) } catch { }
                return
            }
            Write-Host "[ProxyTray] DWM round lost (handle rebuilt) -> re-enabling" -ForegroundColor DarkGray
            $script:useDwmRound = $false
        }
        # Environment.OSVersion 在 ps2exe exe 里谎报 build 9200，必须用 RtlGetVersion
        $osBuild = [NativeRound]::RealBuildNumber()
        if ($osBuild -le 0) { $osBuild = [System.Environment]::OSVersion.Version.Build }
        if ($osBuild -ge 22000) {
            $diag = ''
            try { $diag = [NativeRound]::EnableDwmRound($form.Handle) } catch { $diag = "ps:" + $_.Exception.GetType().Name }
            if ($diag -eq 'OK') {
                $script:useDwmRound = $true
                return
            }
            Write-Host "[ProxyTray] DWM round failed: $diag -> fallback region" -ForegroundColor DarkGray
        }
        $w = $form.Width; $h = $form.Height
        if ($w -lt 10 -or $h -lt 10) { return }
        $rgn = [NativeRound]::CreateRoundRectRgn(0, 0, $w + 1, $h + 1, $Radius, $Radius)
        [void][NativeRound]::SetWindowRgn($form.Handle, $rgn, $true)
    } catch {
        Write-Host "[ProxyTray] roundcorners exc: $($_.Exception.GetType().Name) $($_.Exception.Message)" -ForegroundColor DarkGray
    }
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

# 尽早启用 DWM 圆角：句柄已建（本文件 38 行），窗口 Opacity=0 期间改样式不闪
try { Set-FormRoundCorners } catch { Write-Host "[ProxyTray] early roundcorners failed: $_" -ForegroundColor DarkGray }

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

    $slack = [Math]::Max(2, [int][Math]::Round(8 * $script:DpiScale))
    if ($form.Width -eq $targetW -and [Math]::Abs($form.Height - $targetH) -le $slack) { return }

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

# ---------- DPI 变化：拖到另一块显示器 / 改系统缩放 ----------
try {
    $form.add_DpiChanged({
        param($sender, $e)
        try { $script:DpiScale = $form.DeviceDpi / 96.0 } catch { }
        if ($script:DpiScale -lt 1) { $script:DpiScale = 1 }
        $script:DpiScale = [Math]::Round($script:DpiScale * 4) / 4
        Update-DpiMetrics
        try { $script:wa = [System.Windows.Forms.Screen]::FromHandle($form.Handle).WorkingArea } catch { }
        $script:lockedWidth = 0          # 让前端按新比例重新上报尺寸
        $script:useDwmRound = $false
        Reset-ToBottomRight
        Write-Host ("[ProxyTray] DPI 变化 -> scale={0}" -f $script:DpiScale)
    })
} catch {
    Write-Host "[ProxyTray] 注册 DpiChanged 失败: $_"
}
