# ── src/40-icon.ps1 · 托盘图标绘制 ──
# 按颜色生成圆形图标位图（灰=已关闭 / 绿=已开启）

function New-BallIcon {
    param([System.Drawing.Color]$Color)
    $size = [System.Windows.Forms.SystemInformation]::SmallIconSize.Width
    if ($size -lt 16) { $size = 16 }

    $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.Clear([System.Drawing.Color]::Transparent)

    $pad = [Math]::Max(1, [int]($size * 0.08))
    $d   = $size - 2 * $pad

    $edge = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(70, 0, 0, 0))
    $g.FillEllipse($edge, $pad, $pad, $d, $d)

    $main = New-Object System.Drawing.SolidBrush ($Color)
    $g.FillEllipse($main, $pad + 1, $pad + 1, $d - 2, $d - 2)

    $hw = [int](($d - 2) * 0.50); $hh = [int](($d - 2) * 0.42)
    $hx = $pad + 1 + [int](($d - 2) * 0.14); $hy = $pad + 1 + [int](($d - 2) * 0.10)
    $hl = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(130, 255, 255, 255))
    $g.FillEllipse($hl, $hx, $hy, $hw, $hh)

    $g.Dispose(); $edge.Dispose(); $main.Dispose(); $hl.Dispose()

    $hIcon = $bmp.GetHicon()
    $icon  = [System.Drawing.Icon]([System.Drawing.Icon]::FromHandle($hIcon).Clone())
    [void][IconNative]::DestroyIcon($hIcon)
    $bmp.Dispose()
    return $icon
}
