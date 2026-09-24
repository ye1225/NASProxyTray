# ── src/10-native.ps1 · 原生互操作 ──
# SetDllDirectory / 窗口拖动 / 圆角 / WinINet 刷新 / 图标释放 / 深色菜单渲染器
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
# 两条路径：
#   Win11 (build>=22000)：WS_THICKFRAME + 子类化(WM_NCCALCSIZE 客户区撑满 /
#   WM_NCHITTEST 禁 resize 热区) + DwmSetWindowAttribute(ROUND) —— DWM 合成
#   的 GPU 抗锯齿圆角；无边框窗口必须带 WS_THICKFRAME，DWM 才肯画圆角。
#   Win10 / DWM 失败：回退 CreateRoundRectRgn（1-bit 区域，天生有锯齿）。
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

    private const int GWL_STYLE   = -16;
    private const int GWL_WNDPROC = -4;
    private const long WS_THICKFRAME = 0x00040000;
    private const uint SWP_NOSIZE = 0x0001;
    private const uint SWP_NOMOVE = 0x0002;
    private const uint SWP_NOZORDER = 0x0004;
    private const uint SWP_FRAMECHANGED = 0x0020;
    private const uint WM_NCCALCSIZE = 0x0083;
    private const uint WM_NCHITTEST  = 0x0084;

    private delegate IntPtr WndProcDelegate(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern IntPtr GetWindowLongPtrW(IntPtr hWnd, int nIndex);
    public static long GetStyle(IntPtr hwnd) {
        try { return GetWindowLongPtrW(hwnd, GWL_STYLE).ToInt64(); } catch { return 0; }
    }

    // 真实系统 build 号。Environment.OSVersion 受 exe 清单 supportedOS 声明影响：
    // ps2exe 生成的 exe 没有该声明，会谎报 build 9200 (Win8)，导致永远进不了 Win11 分支。
    [StructLayout(LayoutKind.Sequential)]
    private struct OSVERSIONINFOEXW {
        public uint dwOSVersionInfoSize;
        public uint dwMajorVersion;
        public uint dwMinorVersion;
        public uint dwBuildNumber;
        public uint dwPlatformId;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string szCSDVersion;
    }
    [DllImport("ntdll.dll")]
    private static extern int RtlGetVersion(ref OSVERSIONINFOEXW v);
    public static int RealBuildNumber() {
        try {
            OSVERSIONINFOEXW v = new OSVERSIONINFOEXW();
            v.dwOSVersionInfoSize = (uint)Marshal.SizeOf(typeof(OSVERSIONINFOEXW));
            if (RtlGetVersion(ref v) == 0) { return (int)v.dwBuildNumber; }
        } catch { }
        return 0;
    }
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    private static extern IntPtr SetWindowLongPtrW(IntPtr hWnd, int nIndex, IntPtr dwNewLong);
    [DllImport("user32.dll")]
    private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")]
    private static extern IntPtr CallWindowProcW(IntPtr lpPrevWndFunc, IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    private static IntPtr _oldProc = IntPtr.Zero;
    private static WndProcDelegate _hook;   // 引用保活，防止被 GC 回收后崩溃

    // NCCALCSIZE 返回 0 → 客户区铺满整个窗口（抵消 THICKFRAME 的 7px 框架）；
    // NCHITTEST 恒返 HTCLIENT → 边缘不出现系统 resize 热区（拖动仍走 StartDrag）。
    private static IntPtr BorderlessProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam) {
        if (msg == WM_NCCALCSIZE && wParam != IntPtr.Zero) { return IntPtr.Zero; }
        if (msg == WM_NCHITTEST) { return (IntPtr)1; }
        return CallWindowProcW(_oldProc, hWnd, msg, wParam, lParam);
    }

    // 返回诊断字符串："OK" 或失败原因；失败时回滚 hook 与样式
    public static string EnableDwmRound(IntPtr hwnd) {
        if (_oldProc != IntPtr.Zero) { return "OK"; }
        IntPtr saved = IntPtr.Zero;
        try {
            saved = GetWindowLongPtrW(hwnd, GWL_WNDPROC);
            if (saved == IntPtr.Zero) { return "getproc=0"; }
            _hook = BorderlessProc;
            IntPtr fp;
            try { fp = Marshal.GetFunctionPointerForDelegate(_hook); }
            catch (Exception e) { _hook = null; return "delegate:" + e.GetType().Name; }
            SetWindowLongPtrW(hwnd, GWL_WNDPROC, fp);
            _oldProc = saved;
            long st = GetWindowLongPtrW(hwnd, GWL_STYLE).ToInt64();
            SetWindowLongPtrW(hwnd, GWL_STYLE, (IntPtr)(st | WS_THICKFRAME));
            SetWindowPos(hwnd, IntPtr.Zero, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
            int hr = SetWindowCornerPreference(hwnd, 2);
            SetWindowRgn(hwnd, IntPtr.Zero, true);
            if (hr != 0) {
                // 回滚：卸 hook、去 THICKFRAME
                SetWindowLongPtrW(hwnd, GWL_WNDPROC, _oldProc);
                _oldProc = IntPtr.Zero; _hook = null;
                SetWindowLongPtrW(hwnd, GWL_STYLE, (IntPtr)st);
                SetWindowPos(hwnd, IntPtr.Zero, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
                return "dwm=0x" + hr.ToString("X8");
            }
            return "OK";
        } catch (Exception e) {
            if (_oldProc != IntPtr.Zero) { try { SetWindowLongPtrW(hwnd, GWL_WNDPROC, _oldProc); } catch { } }
            _oldProc = IntPtr.Zero; _hook = null;
            return "exc:" + e.GetType().Name;
        }
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

