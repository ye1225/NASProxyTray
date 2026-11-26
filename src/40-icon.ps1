# ── src/40-icon.ps1 · 托盘图标绘制 ──
# 按颜色生成圆形图标位图（灰=已关闭 / 绿=规则分流已开启 / 蓝=全局代理已开启）
# 画布固定 96px 高分辨率：托盘缩到 16~32px 显示时边缘仍然锐利（v1.3.0 按
# SmallIconSize 直接画，200% DPI 下被放大后发虚）。
# 留白从 8% 收到 2%：满幅圆在托盘里和 360 等方形 Logo 视觉大小一致（v1.3.1）。

function New-BallIcon {
    param([System.Drawing.Color]$Color)
    $px = 96

    $bmp = New-Object System.Drawing.Bitmap($px, $px, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.Clear([System.Drawing.Color]::Transparent)

    $pad = [int]($px * 0.02)
    $d   = $px - 2 * $pad

    # 主色球（满幅，不再画深色描边圈 —— 描边在 16px 下会把球"吃"掉一圈，显小）
    $main = New-Object System.Drawing.SolidBrush ($Color)
    $g.FillEllipse($main, $pad, $pad, $d, $d)

    # 左上高光，保留一点球面质感
    $hw = [int]($d * 0.46); $hh = [int]($d * 0.38)
    $hx = $pad + [int]($d * 0.13); $hy = $pad + [int]($d * 0.09)
    $hl = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(110, 255, 255, 255))
    $g.FillEllipse($hl, $hx, $hy, $hw, $hh)

    $g.Dispose(); $main.Dispose(); $hl.Dispose()

    $hIcon = $bmp.GetHicon()
    $icon  = [System.Drawing.Icon]([System.Drawing.Icon]::FromHandle($hIcon).Clone())
    [void][IconNative]::DestroyIcon($hIcon)
    $bmp.Dispose()
    return $icon
}
