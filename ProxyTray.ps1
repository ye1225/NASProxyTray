# ================================================================
#  ProxyTray.ps1  (v23 - EXE 打包适配版)
#  相对 v22 只改「打包成 exe 所必需」的部分，业务逻辑一行未动：
#   1. 自身路径探测（exe 内 $PSCommandPath/$PSScriptRoot 为空）
#   2. STA 重开兼容 exe（带防无限重开保护）
#   3. 单实例互斥，防止双击两次出现两个托盘
#   4. 数据目录可写性探测，exe 放只读目录也能跑
#   5. 全量日志落盘，-noConsole 后仍可排查
# ================================================================
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------
# 0) 自身路径探测（.ps1 直跑 / ps2exe 打包 exe 通用）
# ---------------------------------------------------------------
$script:appSelf  = $null
$script:appIsExe = $false

# a) 直跑 .ps1：$PSCommandPath 有效
if (-not [string]::IsNullOrWhiteSpace($PSCommandPath) -and
    ([System.IO.Path]::GetExtension($PSCommandPath) -ieq '.ps1') -and
    (Test-Path -LiteralPath $PSCommandPath)) {
    $script:appSelf = $PSCommandPath
}

# b) 打包 exe：$PSCommandPath 为空，取命令行第 0 项
if (-not $script:appSelf) {
    try {
        $c0 = [Environment]::GetCommandLineArgs()[0]
        if ($c0) {
            $c0 = [System.IO.Path]::GetFullPath($c0)
            $nm = [System.IO.Path]::GetFileNameWithoutExtension($c0).ToLower()
            if ($nm -ne 'powershell' -and $nm -ne 'pwsh' -and (Test-Path -LiteralPath $c0)) {
                $script:appSelf = $c0
            }
        }
    } catch { }
}

# c) 兜底：进程主模块
if (-not $script:appSelf) {
    try {
        $mm = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ($mm) { $script:appSelf = $mm }
    } catch { }
}

if ($script:appSelf) {
    $script:appIsExe = ([System.IO.Path]::GetExtension($script:appSelf) -ieq '.exe')
}

# ---------------------------------------------------------------
# 1) 必须 STA（WinForms + OpenFileDialog 需要）
# ---------------------------------------------------------------
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne [System.Threading.ApartmentState]::STA) {
    if ($env:PROXYTRAY_STA_RETRY -eq '1') {
        Write-Host "[ProxyTray] WARN: 宿主仍为 MTA，继续运行（选择文件对话框可能不可用）" -ForegroundColor Yellow
    } else {
        $env:PROXYTRAY_STA_RETRY = '1'
        try {
            if ($script:appIsExe) {
                Start-Process -FilePath $script:appSelf
            } else {
                $psExe = Join-Path $PSHOME 'powershell.exe'
                if (-not (Test-Path -LiteralPath $psExe)) { $psExe = 'powershell.exe' }
                Start-Process -FilePath $psExe -ArgumentList @(
                    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$($script:appSelf)`""
                )
            }
        } catch { }
        exit
    }
}

# ---------------------------------------------------------------
# 2) 单实例（防止双击两次 → 两个托盘 / 两个 PAC 端口）
# ---------------------------------------------------------------
$script:mutex      = $null
$script:hasMutex   = $false
try {
    Add-Type -AssemblyName System.Windows.Forms
    $script:mutex = New-Object System.Threading.Mutex($false, 'Local\NASProxyTray_SingleInstance')
    $script:hasMutex = $script:mutex.WaitOne(0, $false)
    if (-not $script:hasMutex) {
        try {
            [System.Windows.Forms.MessageBox]::Show(
                'NAS Proxy 已经在运行了，请查看右下角托盘图标。',
                'NAS Proxy', 'OK', 'Information') | Out-Null
        } catch { }
        exit 0
    }
} catch { }

# ---------------------------------------------------------------
# 3) 根目录（只读内容）/ 数据目录（可写内容）
# ---------------------------------------------------------------
$root = $null
if ($script:appIsExe) {
    $root = Split-Path -Parent $script:appSelf
} elseif (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $root = $PSScriptRoot
} elseif ($script:appSelf) {
    $root = Split-Path -Parent $script:appSelf
} else {
    $root = (Get-Location).Path
}

# 数据目录可写性探测：exe 放在 Program Files 等只读位置时自动退到 LOCALAPPDATA
$script:DataDir = $root
try {
    $probeFile = Join-Path $root ('.wtest_' + [Guid]::NewGuid().ToString('N'))
    Set-Content -LiteralPath $probeFile -Value '1' -Encoding ASCII -ErrorAction Stop
    Remove-Item -LiteralPath $probeFile -Force -ErrorAction SilentlyContinue
} catch {
    $script:DataDir = Join-Path $env:LOCALAPPDATA 'NASProxy'
    if (-not (Test-Path -LiteralPath $script:DataDir)) {
        New-Item -ItemType Directory -Force -Path $script:DataDir | Out-Null
    }
}

$lib  = Join-Path $root 'lib'
$html = Join-Path $root 'ui\index.html'
$udd  = Join-Path $script:DataDir '.webview2'

# ---------------------------------------------------------------
# 4) 日志：遮蔽 Write-Host，把输出同时写进 ProxyTray.log
#    （-noConsole 打包后看不到控制台，就靠这个排查）
#    不想要日志的话，删掉下面这一段即可
# ---------------------------------------------------------------
$script:LogFile = Join-Path $script:DataDir 'ProxyTray.log'
try {
    if (Test-Path -LiteralPath $script:LogFile) {
        if ((Get-Item -LiteralPath $script:LogFile).Length -gt 512KB) {
            Remove-Item -LiteralPath $script:LogFile -Force -ErrorAction SilentlyContinue
        }
    }
} catch { }

function Write-Host {
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [object]$Object,
        [string]$ForegroundColor
    )
    process {
        $text = if ($null -eq $Object) { '' } else { [string]$Object }
        if ($script:LogFile) {
            try {
                Add-Content -LiteralPath $script:LogFile -Encoding UTF8 -ErrorAction SilentlyContinue `
                    -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $text)
            } catch { }
        }
        if ($ForegroundColor) {
            Microsoft.PowerShell.Utility\Write-Host $text -ForegroundColor $ForegroundColor
        } else {
            Microsoft.PowerShell.Utility\Write-Host $text
        }
    }
}

Write-Host ("[ProxyTray] mode={0} self={1}" -f $(if ($script:appIsExe) { 'EXE' } else { 'PS1' }), $script:appSelf)
Write-Host ("[ProxyTray] root={0}  data={1}" -f $root, $script:DataDir)
Write-Host ("[ProxyTray] apartment={0}" -f [System.Threading.Thread]::CurrentThread.GetApartmentState())

# ---------- DLL 加载目录 ----------
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class NativeLoader {
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern bool SetDllDirectory(string lpPathName);
}
'@
[void][NativeLoader]::SetDllDirectory($lib)
$env:PATH = "$lib;$env:PATH"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# 关键依赖缺失时给出可见提示（打包后没有控制台，必须弹窗）
$needCore  = Join-Path $lib 'Microsoft.Web.WebView2.Core.dll'
$needWin   = Join-Path $lib 'Microsoft.Web.WebView2.WinForms.dll'
$miss = @()
if (-not (Test-Path -LiteralPath $needCore)) { $miss += $needCore }
if (-not (Test-Path -LiteralPath $needWin))  { $miss += $needWin }
if ($miss.Count -gt 0) {
    [System.Windows.Forms.MessageBox]::Show(
        ("缺少 WebView2 依赖库：`n`n{0}`n`n请确认 lib 目录与程序在同一文件夹下。" -f ($miss -join "`n")),
        'NAS Proxy · 依赖缺失', 'OK', 'Error') | Out-Null
    exit 1
}

Add-Type -Path $needCore
Add-Type -Path $needWin

# ---------- 窗口拖动 ----------
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class NativeDrag {
    [DllImport("user32.dll")] public static extern bool ReleaseCapture();
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int msg, int wParam, int lParam);
    public static void StartDrag(IntPtr hWnd) { ReleaseCapture(); SendMessage(hWnd, 0xA1, 0x2, 0); }
}
'@

# ---------- 圆角 ----------
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class NativeRound {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern int SetWindowRgn(IntPtr hWnd, IntPtr hRgn, bool bRedraw);
    [DllImport("gdi32.dll")]
    public static extern IntPtr CreateRoundRectRgn(int nLeftRect, int nTopRect, int nRightRect, int nBottomRect, int nWidthEllipse, int nHeightEllipse);
    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
    public const int DWMWA_WINDOW_CORNER_PREFERENCE = 33;
    public static int SetWindowCornerPreference(IntPtr hwnd, int preference) {
        int val = preference;
        return DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, ref val, sizeof(int));
    }
}
'@

# ---------- WinINet（刷新系统代理设置） ----------
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class WinINet {
    [DllImport("wininet.dll", SetLastError = true)]
    public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);
    public const int INTERNET_OPTION_SETTINGS_CHANGED = 39;
    public const int INTERNET_OPTION_REFRESH = 37;
}
'@

# ---------- Icon 释放 ----------
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class IconNative {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool DestroyIcon(IntPtr hIcon);
}
'@

# ---------- 深色圆角中文菜单渲染器 ----------
$script:hasDarkRenderer = $false
try {
    Add-Type -ReferencedAssemblies @('System.Windows.Forms','System.Drawing') -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

public class DarkColorTable : ProfessionalColorTable {
    public override Color MenuBorder                    { get { return Color.FromArgb(58, 58, 64); } }
    public override Color MenuItemBorder                { get { return Color.Transparent; } }
    public override Color MenuItemSelected              { get { return Color.Transparent; } }
    public override Color MenuItemSelectedGradientBegin { get { return Color.Transparent; } }
    public override Color MenuItemSelectedGradientEnd   { get { return Color.Transparent; } }
    public override Color ToolStripDropDownBackground   { get { return Color.FromArgb(38, 38, 42); } }
    public override Color ImageMarginGradientBegin      { get { return Color.FromArgb(38, 38, 42); } }
    public override Color ImageMarginGradientMiddle     { get { return Color.FromArgb(38, 38, 42); } }
    public override Color ImageMarginGradientEnd        { get { return Color.FromArgb(38, 38, 42); } }
    public override Color SeparatorDark                 { get { return Color.FromArgb(58, 58, 64); } }
    public override Color SeparatorLight                { get { return Color.FromArgb(58, 58, 64); } }
}

public class DarkMenuRenderer : ToolStripProfessionalRenderer {
    public Color Bg      = Color.FromArgb(38, 38, 42);
    public Color Fg      = Color.FromArgb(240, 240, 245);
    public Color HoverBg = Color.FromArgb(10, 132, 255);
    public Color HoverFg = Color.White;
    public Color LineCol = Color.FromArgb(58, 58, 64);
    public Color EdgeCol = Color.FromArgb(62, 62, 68);

    public DarkMenuRenderer() : base(new DarkColorTable()) {
        this.RoundedEdges = false;
    }

    protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e) {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using (SolidBrush b = new SolidBrush(Bg)) {
            e.Graphics.FillRectangle(b, e.AffectedBounds);
        }
    }

    protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e) {
        using (Pen p = new Pen(EdgeCol, 1)) {
            int w = e.ToolStrip.Width;
            int h = e.ToolStrip.Height;
            e.Graphics.DrawRectangle(p, 0, 0, w - 1, h - 1);
        }
    }

    protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e) {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        if (e.Item.Selected && e.Item.Enabled && (e.Item is ToolStripMenuItem)) {
            Rectangle r = new Rectangle(3, 1, e.Item.Width - 6, e.Item.Height - 2);
            using (GraphicsPath path = RoundRect(r, 6))
            using (SolidBrush b = new SolidBrush(HoverBg)) {
                g.FillPath(b, path);
            }
        }
    }

    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e) {
        if (!e.Item.Enabled) {
            e.TextColor = Color.FromArgb(110, 110, 118);
        } else if (e.Item.Selected) {
            e.TextColor = HoverFg;
        } else {
            e.TextColor = Fg;
        }
        base.OnRenderItemText(e);
    }

    protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e) {
        using (Pen p = new Pen(LineCol, 1)) {
            int y = e.Item.Height / 2;
            e.Graphics.DrawLine(p, 10, y, e.Item.Width - 10, y);
        }
    }

    static GraphicsPath RoundRect(Rectangle r, int radius) {
        GraphicsPath path = new GraphicsPath();
        int d = radius * 2;
        if (d <= 0 || r.Width <= d || r.Height <= d) {
            path.AddRectangle(r);
            return path;
        }
        path.AddArc(r.X, r.Y, d, d, 180, 90);
        path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }
}
'@
    $script:hasDarkRenderer = $true
    Write-Host "[ProxyTray] 深色菜单渲染器编译成功" -ForegroundColor DarkGray
} catch {
    Write-Host "[ProxyTray] 深色菜单渲染器编译失败，已回退：$_" -ForegroundColor Yellow
}

# ================================================================
#  代理引擎
# ================================================================
$script:ConfigFile     = Join-Path $script:DataDir 'config.json'
$script:ServedPac      = Join-Path $script:DataDir 'proxy.pac'
$script:RemotePacCache = Join-Path $script:DataDir 'proxy_remote.pac'
$script:RegPath        = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$script:PacPort        = 0
$script:PacPs          = $null
$script:PacRunspace    = $null
$script:CurrentConfig  = $null

function Update-InternetSettings {
    [void][WinINet]::InternetSetOption([IntPtr]::Zero, [WinINet]::INTERNET_OPTION_SETTINGS_CHANGED, [IntPtr]::Zero, 0)
    [void][WinINet]::InternetSetOption([IntPtr]::Zero, [WinINet]::INTERNET_OPTION_REFRESH,          [IntPtr]::Zero, 0)
}

function Get-DefaultProxyConfig {
    $domains = @(
        '*.google.com','*.googleapis.com','*.youtube.com','*.googlevideo.com','*.ytimg.com',
        '*.github.com','*.githubusercontent.com','*.openai.com','*.chatgpt.com','*.anthropic.com',
        '*.claude.ai','*.twitter.com','*.x.com','*.facebook.com','*.instagram.com','*.telegram.org',
        '*.wikipedia.org','*.reddit.com','*.medium.com','*.discord.com','*.notion.so','*.docker.com',
        '*.npmjs.com','*.stackoverflow.com','*.cloudflare.com','*.amazonaws.com','*.gstatic.com',
        '*.ggpht.com','*.t.me','*.whatsapp.com','*.signal.org','*.protonmail.com'
    ) -join "`n"

    [PSCustomObject]@{
        server       = '192.168.31.126'
        port         = '41634'
        override     = 'localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.20.*;172.21.*;172.22.*;172.23.*;172.24.*;172.25.*;172.26.*;172.27.*;172.28.*;172.29.*;172.30.*;172.31.*;192.168.*'
        mode         = 'global'
        pacSource    = 'builtin'
        pacDomains   = $domains
        localPacPath = ''
        remotePacUrl = ''
        autoStart    = $false
        enabled      = $false
    }
}

function Get-ProxyConfig {
    $cfg = Get-DefaultProxyConfig
    if (Test-Path $script:ConfigFile) {
        try {
            $raw = Get-Content $script:ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($k in @('server','port','override','mode','pacSource','pacDomains','localPacPath','remotePacUrl','autoStart','enabled')) {
                if ($raw.PSObject.Properties.Name -contains $k) {
                    $cfg.PSObject.Properties[$k].Value = $raw.$k
                }
            }
        } catch {
            Write-Host "[ProxyTray] Config load failed: $_"
        }
    }
    $cfg
}

function Save-ProxyConfig {
    param($Config)
    try {
        $Config | ConvertTo-Json -Depth 6 | Set-Content -Path $script:ConfigFile -Encoding UTF8
    } catch {
        Write-Host "[ProxyTray] Config save failed: $_"
    }
}

function Set-GlobalProxy {
    param([string]$Server, [string]$Port, [string]$Override)
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
    Set-ItemProperty -Path $script:RegPath -Name 'AutoConfigURL' -Value $url
    Set-ItemProperty -Path $script:RegPath -Name 'ProxyEnable'    -Value 0 -Type DWord
    Remove-ItemProperty -Path $script:RegPath -Name 'ProxyServer' -ErrorAction SilentlyContinue
    Update-InternetSettings
    return $url
}

function Clear-SystemProxy {
    try {
        Set-ItemProperty     -Path $script:RegPath -Name 'ProxyEnable'   -Value 0 -Type DWord
        Remove-ItemProperty  -Path $script:RegPath -Name 'ProxyServer'   -ErrorAction SilentlyContinue
        Remove-ItemProperty  -Path $script:RegPath -Name 'AutoConfigURL' -ErrorAction SilentlyContinue
        Update-InternetSettings
    } catch {
        Write-Host "[ProxyTray] Clear-SystemProxy failed: $_"
    }
}

function Start-PacServer {
    if ($script:PacPs) { return $script:PacPort }

    $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $probe.Start()
    $script:PacPort = ([System.Net.IPEndPoint]$probe.LocalEndpoint).Port
    $probe.Stop()

    $port    = $script:PacPort
    $pacPath = $script:ServedPac

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'MTA'
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
        param($port, $pacPath)
        try {
            $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
            $listener.Start()
        } catch { return }
        while ($true) {
            try {
                $client = $listener.AcceptTcpClient()
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
                } finally { $client.Close() }
            } catch { }
        }
    }).AddArgument($port).AddArgument($pacPath)
    $ps.BeginInvoke() | Out-Null

    $script:PacPs = $ps
    $script:PacRunspace = $rs
    return $port
}

function Stop-PacServer {
    try {
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

# ================================================================
#  注入脚本
# ================================================================
$injectJs = @'
(function () {
    'use strict';

    try {
        var killer = document.createElement('style');
        killer.textContent = [
            '*,*::before,*::after{transition:none !important;animation:none !important;}',
            '.collapse-panel-inner{transition:opacity 0.18s ease-out, transform 0.18s ease-out !important;}',
            'html,body{scrollbar-width:none !important;-ms-overflow-style:none !important;}',
            '::-webkit-scrollbar{display:none !important;width:0 !important;height:0 !important;}',
            '.pac-panel.active{min-height:116px !important;}',
            '.toast,.toast-container,.notification,.alert,.message,[class*="toast"],[class*="notification"],[class*="alert"],[class*="message"],[role="alert"]{display:none !important;}'
        ].join('\n');
        (document.head || document.documentElement).appendChild(killer);
    } catch (e) {}

    try {
        document.documentElement.style.margin  = '0';
        document.documentElement.style.padding = '0';
        if (document.body) {
            document.body.style.overflowX = 'hidden';
            document.body.style.overflowY = 'auto';
        }
    } catch (e) {}

    try {
        var tb = document.querySelector('.title-bar');
        if (tb && !tb.__dragBound) {
            tb.__dragBound = true;
            tb.style.cursor = 'move';
            tb.addEventListener('mousedown', function (e) {
                if (e.button !== 0) return;
                var t = e.target;
                if (t && t.closest && t.closest('button, a, input, select, textarea, label, [data-nodrag]')) return;
                window.chrome.webview.postMessage(JSON.stringify({ action: 'startDrag' }));
            });
        }
    } catch (e) {}

    try {
        document.addEventListener('keydown', function (e) {
            if (e.key === 'Escape') {
                try { window.chrome.webview.postMessage(JSON.stringify({ action: 'hide' })); } catch (err) {}
            }
        });
    } catch (e) {}

    try {
        var lastReportedW = -1, lastReportedH = -1;
        var FREEZE_MS = 500;
        var frozenUntil = 0;
        var freezeTimer = null;

        function publish() {
            if (!document.body) return;
            if (Date.now() < frozenUntil) return;
            var r = document.body.getBoundingClientRect();
            var w = Math.ceil(r.width), h = Math.ceil(r.height);
            if (w === lastReportedW && h === lastReportedH) return;
            lastReportedW = w; lastReportedH = h;
            window.chrome.webview.postMessage(JSON.stringify({ action: 'size', w: w, h: h }));
        }
        function onResize() { publish(); }

        document.addEventListener('click', function (e) {
            var hit = false;
            try {
                var t = e.target;
                if (t && t.closest) {
                    hit = !!t.closest(
                        'button, [type=submit], [type=button], [type=reset], [role=button], ' +
                        '.btn, .button, [id*="save"], [id*="Save"], ' +
                        '[class*="save"], [class*="Save"], [class*="SaveBtn"], [class*="save-btn"]'
                    );
                }
            } catch (err) { }
            if (!hit) return;

            frozenUntil = Date.now() + FREEZE_MS;
            if (freezeTimer) clearTimeout(freezeTimer);
            freezeTimer = setTimeout(function () {
                lastReportedW = -1; lastReportedH = -1;
                publish();
            }, FREEZE_MS + 30);
        }, true);

        if (window.ResizeObserver) new ResizeObserver(onResize).observe(document.body);
        document.addEventListener('DOMContentLoaded', onResize, { once: true });
        window.addEventListener('load', onResize, { once: true });
        onResize();
        setTimeout(publish, 0);
        setTimeout(publish, 400);
        setTimeout(publish, 1000);
    } catch (e) {}
})();
'@

# ================================================================
#  WebView2 初始化 + 消息处理
# ================================================================
$webView.add_CoreWebView2InitializationCompleted([System.EventHandler[Microsoft.Web.WebView2.Core.CoreWebView2InitializationCompletedEventArgs]]{
    param($sender, $evt)
    try {
        if (-not $evt.IsSuccess) {
            Write-Host "[ProxyTray] INIT FAILED:" -ForegroundColor Red
            Write-Host $evt.InitializationException
            $form.Opacity = 1; $form.Show()
            return
        }
        $core = $sender.CoreWebView2
        Write-Host "[ProxyTray] INIT OK, browser = $($core.Environment.BrowserVersionString)" -ForegroundColor Green
        $core.Settings.AreDefaultContextMenusEnabled = $false
        $core.Settings.IsStatusBarEnabled            = $false

        $core.add_NavigationCompleted({
            param($s2, $e2)
            if (-not $e2.IsSuccess) { Show-ReadyForm; return }
            $s2.ExecuteScriptAsync($injectJs) | Out-Null

            if ($script:showTimer) {
                try { $script:showTimer.Stop(); $script:showTimer.Dispose() } catch { }
                $script:showTimer = $null
            }
            $script:showTimer = New-Object System.Windows.Forms.Timer
            $script:showTimer.Interval = 90
            $script:showTimer.add_Tick({
                try { $script:showTimer.Stop(); $script:showTimer.Dispose() } catch { }
                $script:showTimer = $null
                Show-ReadyForm
            })
            $script:showTimer.Start()
        })

        $core.add_WebMessageReceived({
            param($s2, $e2)
            $raw = $null
            try { $raw = $e2.TryGetWebMessageAsString() } catch { }
            if ([string]::IsNullOrWhiteSpace($raw)) { return }

            $obj = $null
            try { $obj = $raw | ConvertFrom-Json } catch { return }

            switch ($obj.action) {
                'startDrag' { [NativeDrag]::StartDrag($form.Handle) }

                'hide' { Hide-MainWindow }

                'size' {
                    $w = [int]$obj.w; $h = [int]$obj.h
                    if ($w -lt 200 -or $h -lt 200) { return }
                    $script:pendingW = $w
                    $script:pendingH = $h
                    $script:sizeTimer.Stop()
                    $script:sizeTimer.Start()
                }

                'theme' {
                    try {
                        $dark = [bool]$obj.dark
                        $c = if ($dark) { [System.Drawing.Color]::FromArgb(28,28,30) }
                             else       { [System.Drawing.Color]::FromArgb(245,245,247) }
                        $form.BackColor = $c
                        $webView.DefaultBackgroundColor = $c
                    } catch { }
                }

                'getConfig' {
                    $cfg = Get-ProxyConfig
                    $script:CurrentConfig = $cfg
                    Update-TrayIcon -Enabled ([bool]$cfg.enabled)
                    $payload = @{ action = 'config'; config = $cfg } | ConvertTo-Json -Depth 6 -Compress
                    $s2.PostWebMessageAsString($payload)
                }

                'saveConfig' {
                    $ui = $obj.config
                    if ($null -eq $ui) { return }
                    $cfg = Get-ProxyConfig
                    foreach ($k in @('server','port','override','mode','pacSource','pacDomains','localPacPath','remotePacUrl')) {
                        if ($ui.PSObject.Properties.Name -contains $k) {
                            $cfg.PSObject.Properties[$k].Value = $ui.$k
                        }
                    }
                    if ($ui.PSObject.Properties.Name -contains 'autoStart') {
                        $want = [bool]$ui.autoStart
                        if ($want -ne [bool]$cfg.autoStart) {
                            Set-AutoStart -Enabled $want | Out-Null
                            $cfg.autoStart = $want
                        }
                    }
                    Save-ProxyConfig -Config $cfg
                    $script:CurrentConfig = $cfg
                    Update-TrayIcon -Enabled ([bool]$cfg.enabled)

                    $msgText = '设置已保存'
                    $ok = $true
                    if ($cfg.enabled) {
                        $r = Apply-ProxyConfig -Config $cfg
                        $msgText = $r.msg; $ok = $r.ok
                    }
                    $payload = @{ action = 'saved'; ok = $ok; msg = $msgText; config = $cfg } | ConvertTo-Json -Depth 6 -Compress
                    $s2.PostWebMessageAsString($payload)
                }

                'toggleProxy' {
                    $wantOn = [bool]$obj.enabled
                    $cfg = Get-ProxyConfig
                    if ($obj.config) {
                        foreach ($k in @('server','port','override','mode','pacSource','pacDomains','localPacPath','remotePacUrl','autoStart')) {
                            if ($obj.config.PSObject.Properties.Name -contains $k) {
                                $cfg.PSObject.Properties[$k].Value = $obj.config.$k
                            }
                        }
                    }
                    $cfg.enabled = $wantOn
                    Save-ProxyConfig -Config $cfg
                    $script:CurrentConfig = $cfg

                    $r = Apply-ProxyConfig -Config $cfg
                    Update-TrayIcon -Enabled ([bool]$cfg.enabled)

                    $state = @{
                        action  = 'state'
                        enabled = [bool]$cfg.enabled
                        ok      = [bool]$r.ok
                        msg     = $r.msg
                        mode    = $cfg.mode
                        server  = $cfg.server
                        port    = $cfg.port
                    } | ConvertTo-Json -Compress
                    $s2.PostWebMessageAsString($state)
                }

                'setAutoStart' {
                    $want = [bool]$obj.enabled
                    Set-AutoStart -Enabled $want | Out-Null
                    $cfg = Get-ProxyConfig
                    $cfg.autoStart = $want
                    Save-ProxyConfig -Config $cfg
                    $script:CurrentConfig = $cfg
                    $payload = @{ action = 'config'; config = $cfg } | ConvertTo-Json -Depth 6 -Compress
                    $s2.PostWebMessageAsString($payload)
                }

                'browseFile' {
                    $dlg = New-Object System.Windows.Forms.OpenFileDialog
                    $dlg.Title = '选择 PAC 文件'
                    $dlg.Filter = 'PAC 文件 (*.pac)|*.pac|所有文件 (*.*)|*.*'
                    $dlg.CheckFileExists = $true
                    $path = ''
                    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                        $path = $dlg.FileName
                    }
                    $payload = @{ action = 'filePicked'; path = $path } | ConvertTo-Json -Compress
                    $s2.PostWebMessageAsString($payload)
                }

                'testConnection' {
                    $server  = [string]$obj.server
                    $portStr = [string]$obj.port
                    $port    = 0
                    [void][int]::TryParse($portStr, [ref]$port)
                    if ($server -and $port -gt 0) {
                        $r = Test-ProxyConn -Server $server -Port $port
                        $payload = @{ action = 'connResult'; ok = $r.ok; latency = $r.latency } | ConvertTo-Json -Compress
                    } else {
                        $payload = @{ action = 'connResult'; ok = $false; latency = 0 } | ConvertTo-Json -Compress
                    }
                    $s2.PostWebMessageAsString($payload)
                }

                'resetConfig' {
                    $cfg = Get-DefaultProxyConfig
                    Save-ProxyConfig -Config $cfg
                    $script:CurrentConfig = $cfg
                    try { Set-AutoStart -Enabled $false | Out-Null } catch { }
                    try { Clear-SystemProxy } catch { }
                    Update-TrayIcon -Enabled $false
                    $payload = @{ action = 'config'; config = $cfg } | ConvertTo-Json -Depth 6 -Compress
                    $s2.PostWebMessageAsString($payload)
                }
            }
        })
    } catch {
        Write-Host "[ProxyTray] EXCEPTION in init: $_" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    }
})

# ================================================================
#  Form Shown / Closing / Closed
# ================================================================
$form.add_Shown({
    Write-Host "[ProxyTray] Shown fired" -ForegroundColor Cyan
    try { $script:hideTimer.Stop() } catch { }

    try { Set-FormRoundCorners } catch { Write-Host "[ProxyTray] roundcorners failed: $_" }

    try {
        $cfg = Get-ProxyConfig
        $script:CurrentConfig = $cfg

        $wantAuto = [bool]$cfg.autoStart
        $haveAuto = Get-AutoStart
        if ($wantAuto -ne $haveAuto) { Set-AutoStart -Enabled $wantAuto | Out-Null }

        if ($cfg.enabled) {
            $r = Apply-ProxyConfig -Config $cfg
            Write-Host "[ProxyTray] Auto-apply: $($r.msg)" -ForegroundColor Cyan
        }

        Update-TrayIcon -Enabled ([bool]$cfg.enabled)
    } catch {
        Write-Host "[ProxyTray] Auto-apply failed: $_"
    }

    if (-not (Test-Path -LiteralPath $html)) {
        Write-Host "[ProxyTray] UI 文件不存在：$html" -ForegroundColor Red
        [System.Windows.Forms.MessageBox]::Show(
            ("找不到界面文件：`n$html`n`n请确认 ui\index.html 与程序在同一文件夹下。"),
            'NAS Proxy · 界面缺失', 'OK', 'Error') | Out-Null
        return
    }
    $webView.Source = [Uri]('file:///' + ($html -replace '\\','/'))
})

$form.add_FormClosing({
    param($sender, $evt)
    Write-Host ("[ProxyTray] FormClosing CloseReason={0} reallyExit={1}" -f $evt.CloseReason, $script:reallyExit) -ForegroundColor Yellow
    if (-not $script:reallyExit) {
        $evt.Cancel = $true
        Hide-MainWindow
    }
})

$form.add_FormClosed({
    param($sender, $evt)
    Write-Host "[ProxyTray] ** FormClosed **" -ForegroundColor Red
})

# ================================================================
#  主消息循环
# ================================================================
Write-Host "[ProxyTray] ready. window @ ($($form.Left),$($form.Top)) size $($form.Width)x$($form.Height)"

$script:appContext          = New-Object System.Windows.Forms.ApplicationContext
$script:appContext.MainForm = $form

try {
    $form.Show()
} catch {
    Write-Host "[ProxyTray] form.Show() EXCEPTION:" -ForegroundColor Red
    Write-Host $_
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
}

try {
    [System.Windows.Forms.Application]::Run($script:appContext)
} catch {
    Write-Host "[ProxyTray] Application.Run EXCEPTION:" -ForegroundColor Red
    Write-Host $_
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
}

Write-Host "[ProxyTray] bye."

# ---------- 兜底清理 ----------
try { Stop-PacServer } catch { }
try { if ($script:showTimer) { $script:showTimer.Dispose() } } catch { }
try { if ($script:sizeTimer) { $script:sizeTimer.Dispose() } } catch { }
try { $script:hideTimer.Dispose() } catch { }
try { $tray.Visible = $false; $tray.Dispose() } catch { }
try { $menu.Dispose() } catch { }
try { if ($script:mutex) { if ($script:hasMutex) { $script:mutex.ReleaseMutex() }; $script:mutex.Dispose() } } catch { }
[System.Environment]::Exit(0)