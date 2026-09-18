#Requires -Version 5.1
<#
    ProxyTray.ps1  —  NAS Proxy Tray
    全 ASCII，中文由 Unicode 码点拼接，避免编码乱码
    图标由 build.ps1 自动注入到 $IconBase64
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ========== 图标占位符（build.ps1 会替换这一行） ==========
$IconBase64 = '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'

# ============ 中文码点辅助 ============
function CN([string]$s) {
    -join ($s -split ',' | ForEach-Object { [char][Convert]::ToInt32($_, 16) })
}

$T = @{
    OpenProxy      = CN '5F00,542F,4EE3,7406'
    CloseProxy     = CN '5173,95ED,4EE3,7406'
    Settings       = (CN '8BBE,7F6E') + '...'
    WinProxySet    = (CN '6253,5F00') + ' Windows ' + (CN '4EE3,7406,8BBE,7F6E')
    Quit           = CN '9000,51FA'

    Title          = 'NAS ' + (CN '4EE3,7406,8BBE,7F6E')
    SrvLabel       = (CN '4EE3,7406,670D,52A1,5668,5730,5740') + ':'
    PortLabel      = (CN '7AEF,53E3') + ':'
    OvLabel        = (CN '4F8B,5916,5730,5740') + ' (' + (CN '5206,53F7,5206,9694') + ', ' + (CN '4E0D,7ECF,8FC7,4EE3,7406') + '):'
    ResetBtn       = CN '6062,590D,9ED8,8BA4'
    SaveBtn        = CN '4FDD,5B58'
    CancelBtn      = CN '53D6,6D88'

    TrayOn         = 'NAS ' + (CN '4EE3,7406') + ': ' + (CN '5DF2,5F00,542F') + "`n" + (CN '53CC,51FB,5173,95ED')
    TrayOff        = 'NAS ' + (CN '4EE3,7406') + ': ' + (CN '5DF2,5173,95ED') + "`n" + (CN '53CC,51FB,5F00,542F')

    BalloonOn      = CN '5DF2,5F00,542F,4EE3,7406'
    BalloonOff     = CN '5DF2,5173,95ED,4EE3,7406'
    BalloonSaved   = CN '8BBE,7F6E,5DF2,4FDD,5B58'
    BalloonApplied = CN '8BBE,7F6E,5DF2,4FDD,5B58,5E76,5DF2,5E94,7528,5230,5F53,524D,4EE3,7406'

    BalloonTitle   = 'NAS ' + (CN '4EE3,7406')
    AppTitle       = 'NAS ' + (CN '4EE3,7406,5F00,5173')
    InfoTitle      = CN '63D0,793A'

    MsgRunning     = (CN '4EE3,7406,5F00,5173,5DF2,7ECF,5728,8FD0,884C') + ', ' + (CN '8BF7,770B,4EFB,52A1,680F,53F3,4E0B,89D2,6258,76D8,56FE,6807') + '.'
    MsgEmptySrv    = (CN '4EE3,7406,670D,52A1,5668,5730,5740,4E0D,80FD,4E3A,7A7A') + '.'
    MsgBadPort     = (CN '7AEF,53E3,5FC5,987B,662F') + ' 1-65535 ' + (CN '4E4B,95F4,7684,6570,5B57') + '.'
    MsgFail        = (CN '64CD,4F5C,5931,8D25') + ':'
}

# ============ 配置 ============
$ConfigDir  = Join-Path $env:APPDATA 'NASProxyTray'
$ConfigFile = Join-Path $ConfigDir 'config.json'

function Get-DefaultConfig {
    [PSCustomObject]@{
        ProxyServer   = '192.168.31.126'
        ProxyPort     = '41634'
        ProxyOverride = 'localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.20.*;172.21.*;172.22.*;172.23.*;172.24.*;172.25.*;172.26.*;172.27.*;172.28.*;172.29.*;172.30.*;172.31.*;192.168.*'
    }
}

function Save-Config($cfg) {
    if (-not (Test-Path $ConfigDir)) {
        New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    }
    $cfg | ConvertTo-Json -Depth 3 | Set-Content -Path $ConfigFile -Encoding UTF8
}

function Load-Config {
    if (Test-Path $ConfigFile) {
        try {
            $json = Get-Content $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $def  = Get-DefaultConfig
            return [PSCustomObject]@{
                ProxyServer   = if ($json.ProxyServer) { [string]$json.ProxyServer } else { $def.ProxyServer }
                ProxyPort     = if ($json.ProxyPort)   { [string]$json.ProxyPort }   else { $def.ProxyPort }
                ProxyOverride = if ($null -ne $json.ProxyOverride) { [string]$json.ProxyOverride } else { $def.ProxyOverride }
            }
        } catch { }
    }
    $d = Get-DefaultConfig
    Save-Config $d
    return $d
}

$script:Config = Load-Config

# ============ 单实例 ============
$script:Mutex = New-Object System.Threading.Mutex($false, 'Local\NASProxyTray')
if (-not $script:Mutex.WaitOne(0)) {
    [System.Windows.Forms.MessageBox]::Show($T.MsgRunning, $T.AppTitle)
    exit
}

# ============ Win32 ============
Add-Type -Namespace Native -Name WinInet -MemberDefinition @'
[DllImport("wininet.dll", SetLastError = true)]
public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);
'@

Add-Type -Namespace Native -Name IconApi -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true)]
public static extern bool DestroyIcon(IntPtr hIcon);
'@

# ============ 注册表 ============
$script:RegPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'

function Set-RegValue {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowEmptyString()]$Value,
        [string]$Type = 'String'
    )
    New-ItemProperty -Path $script:RegPath -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

function Get-ProxyState {
    try {
        $item = Get-ItemProperty -Path $script:RegPath -ErrorAction Stop
        return ($item.ProxyEnable -eq 1)
    } catch { return $false }
}

function Invoke-SettingsRefresh {
    [void][Native.WinInet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0)
    [void][Native.WinInet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0)
    try { ipconfig /flushdns | Out-Null } catch { }
}

function Enable-Proxy {
    $server = '{0}:{1}' -f $script:Config.ProxyServer, $script:Config.ProxyPort
    Set-RegValue 'ProxyEnable'   1          'DWord'
    Set-RegValue 'ProxyServer'   $server    'String'
    Set-RegValue 'ProxyOverride' $script:Config.ProxyOverride 'String'
    Set-RegValue 'AutoDetect'    0          'DWord'
    Set-RegValue 'AutoConfigURL' ''         'String'
    Invoke-SettingsRefresh
}

function Disable-Proxy {
    Set-RegValue 'ProxyEnable'   0  'DWord'
    Set-RegValue 'ProxyServer'   '' 'String'
    Set-RegValue 'ProxyOverride' '' 'String'
    Set-RegValue 'AutoDetect'    0  'DWord'
    Set-RegValue 'AutoConfigURL' '' 'String'
    Invoke-SettingsRefresh
}

# ============ 图标 ============
$script:BaseIcon = $null

function Get-BaseIcon {
    if ($script:BaseIcon) { return $script:BaseIcon }
    if (-not $IconBase64 -or $IconBase64 -like '*__ICON*') { return $null }
    try {
        $bytes = [Convert]::FromBase64String($IconBase64)
        $ms = New-Object System.IO.MemoryStream -ArgumentList @(,$bytes)
        $ms.Position = 0
        $script:BaseIcon = New-Object System.Drawing.Icon -ArgumentList $ms
        return $script:BaseIcon
    } catch {
        return $null
    }
}

function New-StatusIcon {
    param([System.Drawing.Color]$Color)

    $size = 32
    $bmp  = New-Object System.Drawing.Bitmap $size, $size
    $g    = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode     = 'AntiAlias'
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.PixelOffsetMode   = 'HighQuality'
    $g.Clear([System.Drawing.Color]::Transparent)

    $base = Get-BaseIcon
    $drawn = $false
    if ($base) {
        try {
            $srcBmp = $base.ToBitmap()
            $rect   = New-Object System.Drawing.Rectangle 0, 0, $size, $size
            $g.DrawImage($srcBmp, $rect, 0, 0, $srcBmp.Width, $srcBmp.Height, [System.Drawing.GraphicsUnit]::Pixel)
            $srcBmp.Dispose()
            $drawn = $true
        } catch {
            $drawn = $false
        }
    }

    if (-not $drawn) {
        # 退化为纯色圆点
        $brush = New-Object System.Drawing.SolidBrush $Color
        $g.FillEllipse($brush, 2, 2, $size-4, $size-4)
        $brush.Dispose()
    } else {
        # 右下角状态小圆点
        $dot   = 13
        $x     = $size - $dot - 1
        $y     = $size - $dot - 1
        $pen   = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 2
        $brush = New-Object System.Drawing.SolidBrush $Color
        $g.FillEllipse($brush, $x, $y, $dot, $dot)
        $g.DrawEllipse($pen, $x, $y, $dot, $dot)
        $brush.Dispose(); $pen.Dispose()
    }

    $g.Dispose()
    $hIcon = $bmp.GetHicon()
    $tmp   = [System.Drawing.Icon]::FromHandle($hIcon)
    $icon  = New-Object System.Drawing.Icon -ArgumentList $tmp, 32, 32
    [void][Native.IconApi]::DestroyIcon($hIcon)
    $bmp.Dispose()
    return $icon
}

$script:IconOn  = New-StatusIcon ([System.Drawing.Color]::FromArgb(46, 204, 113))
$script:IconOff = New-StatusIcon ([System.Drawing.Color]::FromArgb(150, 160, 165))

# ============ 设置窗口 ============
function Show-SettingsDialog {
    $form = New-Object System.Windows.Forms.Form
    $form.Text            = $T.Title
    $form.Size            = New-Object System.Drawing.Size(500, 420)
    $form.StartPosition   = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox     = $false
    $form.MinimizeBox     = $false
    $form.Font            = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
    $form.BackColor       = [System.Drawing.Color]::White

    $lblServer = New-Object System.Windows.Forms.Label
    $lblServer.Text     = $T.SrvLabel
    $lblServer.Location = New-Object System.Drawing.Point(20, 25)
    $lblServer.Size     = New-Object System.Drawing.Size(130, 22)
    $form.Controls.Add($lblServer)

    $txtServer = New-Object System.Windows.Forms.TextBox
    $txtServer.Location = New-Object System.Drawing.Point(155, 22)
    $txtServer.Size     = New-Object System.Drawing.Size(310, 24)
    $txtServer.Text     = $script:Config.ProxyServer
    $form.Controls.Add($txtServer)

    $lblPort = New-Object System.Windows.Forms.Label
    $lblPort.Text     = $T.PortLabel
    $lblPort.Location = New-Object System.Drawing.Point(20, 60)
    $lblPort.Size     = New-Object System.Drawing.Size(130, 22)
    $form.Controls.Add($lblPort)

    $txtPort = New-Object System.Windows.Forms.TextBox
    $txtPort.Location = New-Object System.Drawing.Point(155, 57)
    $txtPort.Size     = New-Object System.Drawing.Size(120, 24)
    $txtPort.Text     = $script:Config.ProxyPort
    $form.Controls.Add($txtPort)

    $lblOv = New-Object System.Windows.Forms.Label
    $lblOv.Text     = $T.OvLabel
    $lblOv.Location = New-Object System.Drawing.Point(20, 95)
    $lblOv.Size     = New-Object System.Drawing.Size(450, 22)
    $form.Controls.Add($lblOv)

    $txtOv = New-Object System.Windows.Forms.TextBox
    $txtOv.Location   = New-Object System.Drawing.Point(20, 122)
    $txtOv.Size       = New-Object System.Drawing.Size(445, 190)
    $txtOv.Multiline  = $true
    $txtOv.ScrollBars = 'Vertical'
    $txtOv.Text       = $script:Config.ProxyOverride
    $form.Controls.Add($txtOv)

    $btnReset = New-Object System.Windows.Forms.Button
    $btnReset.Text     = $T.ResetBtn
    $btnReset.Location = New-Object System.Drawing.Point(20, 325)
    $btnReset.Size     = New-Object System.Drawing.Size(95, 32)
    $btnReset.Add_Click({
        $d = Get-DefaultConfig
        $txtServer.Text = $d.ProxyServer
        $txtPort.Text   = $d.ProxyPort
        $txtOv.Text     = $d.ProxyOverride
    })
    $form.Controls.Add($btnReset)

    $btnOK = New-Object System.Windows.Forms.Button
    $btnOK.Text         = $T.SaveBtn
    $btnOK.Location     = New-Object System.Drawing.Point(275, 325)
    $btnOK.Size         = New-Object System.Drawing.Size(90, 32)
    $btnOK.DialogResult = 'OK'
    $btnOK.BackColor    = [System.Drawing.Color]::FromArgb(46, 204, 113)
    $btnOK.ForeColor    = [System.Drawing.Color]::White
    $btnOK.FlatStyle    = 'Flat'
    $form.Controls.Add($btnOK)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text         = $T.CancelBtn
    $btnCancel.Location     = New-Object System.Drawing.Point(375, 325)
    $btnCancel.Size         = New-Object System.Drawing.Size(90, 32)
    $btnCancel.DialogResult = 'Cancel'
    $form.Controls.Add($btnCancel)

    $form.AcceptButton = $btnOK
    $form.CancelButton = $btnCancel

    while ($true) {
        $result = $form.ShowDialog()
        if ($result -ne [System.Windows.Forms.DialogResult]::OK) { return $false }

        $server = $txtServer.Text.Trim()
        $port   = $txtPort.Text.Trim()
        $ov     = $txtOv.Text.Trim()

        if ([string]::IsNullOrWhiteSpace($server)) {
            [System.Windows.Forms.MessageBox]::Show($T.MsgEmptySrv, $T.InfoTitle)
            continue
        }
        $p = 0
        if (-not [int]::TryParse($port, [ref]$p) -or $p -lt 1 -or $p -gt 65535) {
            [System.Windows.Forms.MessageBox]::Show($T.MsgBadPort, $T.InfoTitle)
            continue
        }

        $script:Config.ProxyServer   = $server
        $script:Config.ProxyPort     = $port
        $script:Config.ProxyOverride = $ov
        Save-Config $script:Config
        return $true
    }
}

# ============ 托盘 ============
$script:Tray = New-Object System.Windows.Forms.NotifyIcon
$script:Tray.Visible = $true

function Show-Balloon([string]$Text) {
    $script:Tray.BalloonTipTitle = $T.BalloonTitle
    $script:Tray.BalloonTipText  = $Text
    $script:Tray.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Info
    $script:Tray.ShowBalloonTip(1500)
}

function Update-Tray {
    if (Get-ProxyState) {
        $script:Tray.Icon = $script:IconOn
        $script:Tray.Text = $T.TrayOn
    } else {
        $script:Tray.Icon = $script:IconOff
        $script:Tray.Text = $T.TrayOff
    }
}

function Toggle-Proxy {
    try {
        if (Get-ProxyState) {
            Disable-Proxy
            Show-Balloon $T.BalloonOff
        } else {
            Enable-Proxy
            Show-Balloon ($T.BalloonOn + "`n" + "$($script:Config.ProxyServer):$($script:Config.ProxyPort)")
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("$($T.MsgFail)`n$($_.Exception.Message)", $T.AppTitle)
    }
    Update-Tray
}

# ============ 菜单 ============
$menu   = New-Object System.Windows.Forms.ContextMenuStrip
$miOn   = $menu.Items.Add($T.OpenProxy)
$miOff  = $menu.Items.Add($T.CloseProxy)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$miSet  = $menu.Items.Add($T.Settings)
$miSys  = $menu.Items.Add($T.WinProxySet)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$miQuit = $menu.Items.Add($T.Quit)

$script:Tray.ContextMenuStrip = $menu

$miOn.Add_Click({
    try { Enable-Proxy; Show-Balloon ($T.BalloonOn + "`n" + "$($script:Config.ProxyServer):$($script:Config.ProxyPort)") } catch { }
    Update-Tray
})

$miOff.Add_Click({
    try { Disable-Proxy; Show-Balloon $T.BalloonOff } catch { }
    Update-Tray
})

$miSet.Add_Click({
    if (Show-SettingsDialog) {
        if (Get-ProxyState) {
            try { Enable-Proxy } catch { }
            Show-Balloon $T.BalloonApplied
        } else {
            Show-Balloon $T.BalloonSaved
        }
        Update-Tray
    }
})

$miSys.Add_Click({ Start-Process 'ms-settings:network-proxy' })

$script:Tray.Add_DoubleClick({ Toggle-Proxy })

$script:Ctx = New-Object System.Windows.Forms.ApplicationContext

$miQuit.Add_Click({
    $script:Tray.Visible = $false
    $script:Tray.Dispose()
    try { $script:Mutex.ReleaseMutex() } catch { }
    $script:Ctx.ExitThread()
})

# ============ 启动 ============
Update-Tray
[System.Windows.Forms.Application]::Run($script:Ctx)