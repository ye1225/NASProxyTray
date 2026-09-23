# ================================================================
#  src/00-boot.ps1 · 启动地基
#  原 ProxyTray.ps1 的头段，必须最先执行：
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
#    拆分到 src/ 后本模块是被 dot-source 的，$PSCommandPath 会指向 src\00-boot.ps1，
#    所以优先采用入口 ProxyTray.ps1 经 $script:LaunchScriptPath 传下来的真实入口路径。
$selfCandidates = @($script:LaunchScriptPath, $PSCommandPath)
foreach ($cand in $selfCandidates) {
    if ([string]::IsNullOrWhiteSpace($cand)) { continue }
    if (([System.IO.Path]::GetExtension($cand) -ieq '.ps1') -and (Test-Path -LiteralPath $cand)) {
        $script:appSelf = $cand
        break
    }
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
} elseif (-not [string]::IsNullOrWhiteSpace($script:LaunchRoot)) {
    $root = $script:LaunchRoot
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

# ---------------------------------------------------------------
# 5) DRYRUN 空转开关（测试用）
#    置 $env:PROXYTRAY_DRYRUN = '1' 后，任何会改动系统的动作都不执行：
#    不写注册表、不清系统代理、不动开机自启。仅在日志里留痕。
# ---------------------------------------------------------------
$script:DryRun = ($env:PROXYTRAY_DRYRUN -eq '1')

Write-Host ("[ProxyTray] mode={0} self={1}" -f $(if ($script:appIsExe) { 'EXE' } else { 'PS1' }), $script:appSelf)
Write-Host ("[ProxyTray] root={0}  data={1}" -f $root, $script:DataDir)
Write-Host ("[ProxyTray] apartment={0}" -f [System.Threading.Thread]::CurrentThread.GetApartmentState())

# ---------------------------------------------------------------
# 版本号：VERSION 文件是唯一来源；打包时 build.ps1 会把下面这行常量改写成 VERSION 的内容
# ---------------------------------------------------------------
$script:AppVersionBuiltin = '1.2.0'
$script:AppVersion = $script:AppVersionBuiltin
try {
    $verFile = Join-Path $root 'VERSION'
    if (Test-Path -LiteralPath $verFile) {
        $verText = (Get-Content -LiteralPath $verFile -Raw -Encoding UTF8).Trim()
        if ($verText) { $script:AppVersion = $verText }
    }
} catch { }
Write-Host ("[ProxyTray] version={0}" -f $script:AppVersion)

# ---------- 视觉样式：必须在创建任何控件之前调用 ----------
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    [System.Windows.Forms.Application]::EnableVisualStyles()
} catch {
    Write-Host "[ProxyTray] EnableVisualStyles failed: $_" -ForegroundColor Yellow
}


