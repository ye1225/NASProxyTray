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
# 高 DPI：必须在创建任何窗口/控件之前声明。
# 不声明的话进程是 DPI-unaware 的，Windows 会先把整个界面按 96 DPI
# 光栅化成位图、再整体拉伸到物理像素 —— 4K 上看着就是糊的。
# 声明 Per-Monitor V2 后由本进程按真实 DPI 自己渲染，界面才清晰。
# ---------------------------------------------------------------
$script:DpiAwareMode = 'none'
try {
    Add-Type -Namespace 'NativeDpi' -Name 'Api' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetProcessDpiAwarenessContext(System.IntPtr value);
[System.Runtime.InteropServices.DllImport("shcore.dll")]
public static extern int SetProcessDpiAwareness(int value);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetProcessDPIAware();
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern uint GetDpiForSystem();
'@
    # DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 == (HANDLE)-4
    if ([NativeDpi.Api]::SetProcessDpiAwarenessContext([System.IntPtr]::new(-4))) {
        $script:DpiAwareMode = 'PerMonitorV2'
    } elseif ([NativeDpi.Api]::SetProcessDpiAwareness(2) -eq 0) {
        $script:DpiAwareMode = 'PerMonitor'
    } elseif ([NativeDpi.Api]::SetProcessDPIAware()) {
        $script:DpiAwareMode = 'System'
    }
} catch { }

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
#    v1.2.1 起 exe 模式的数据（runtime 释放、.webview2、日志、配置、
#    更新检查缓存）一律放 %LOCALAPPDATA%\NASProxy，不再在 exe 同级
#    目录生成一堆杂物。源码直跑仍用仓库目录，方便开发与清理。
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

if ($script:appIsExe) {
    # exe 模式：固定用 %LOCALAPPDATA%\NASProxy（用户级，任何位置可写）
    $script:DataDir = Join-Path $env:LOCALAPPDATA 'NASProxy'
    try {
        if (-not (Test-Path -LiteralPath $script:DataDir)) {
            New-Item -ItemType Directory -Force -Path $script:DataDir | Out-Null
        }
    } catch { }
} else {
    # 源码直跑：优先仓库目录；不可写（少见）才退到 LOCALAPPDATA
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
}

# v1.2.0 及之前曾把数据写在 exe 同级目录：
# 配置类文件迁到新数据目录（保留用户设置），可再生成的杂物直接清掉。
if ($script:appIsExe -and ($script:DataDir -ine $root)) {
    $script:MigratedFrom = $root
} else {
    $script:MigratedFrom = $null
}

# ---------------------------------------------------------------
# 版本号：VERSION 文件是唯一来源。
# 单文件 exe 里没有 VERSION 文件，build.ps1 会把下面这行常量改写成 VERSION 的内容。
# ---------------------------------------------------------------
$script:AppVersionBuiltin = '1.2.5'
$script:AppVersion = $script:AppVersionBuiltin
try {
    $verFile = Join-Path $root 'VERSION'
    if (Test-Path -LiteralPath $verFile) {
        $verText = (Get-Content -LiteralPath $verFile -Raw -Encoding UTF8).Trim()
        if ($verText) { $script:AppVersion = $verText }
    }
} catch { }

# ---------------------------------------------------------------
# 内容目录：源码直跑时直接用仓库里的 lib\ 与 ui\；
# 单文件 exe 时把内嵌资源释放到 <数据目录>\runtime\<版本>\，写 .ok 标记后复用。
# 先释放到临时目录再整体改名，避免中途失败留下半个残缺目录。
# ---------------------------------------------------------------
$script:RuntimeDir  = $root
$script:UsingPacked = $false

$packed = $null
if (Test-Path variable:script:PackedResources) { $packed = $script:PackedResources }

if ($packed -and -not (Test-Path -LiteralPath (Join-Path $root 'lib'))) {
    $script:UsingPacked = $true
    $rtBase  = Join-Path $script:DataDir 'runtime'
    $rtFinal = Join-Path $rtBase $script:AppVersion

    if (Test-Path -LiteralPath (Join-Path $rtFinal '.ok')) {
        $script:RuntimeDir = $rtFinal
    } else {
        $rtTmp = Join-Path $rtBase ('.tmp-' + [Guid]::NewGuid().ToString('N'))
        try {
            Add-Type -AssemblyName System.IO.Compression | Out-Null
            Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
            if (-not (Test-Path -LiteralPath $rtBase)) {
                New-Item -ItemType Directory -Force -Path $rtBase | Out-Null
            }
            if (Test-Path -LiteralPath $rtTmp) { Remove-Item -LiteralPath $rtTmp -Recurse -Force }
            New-Item -ItemType Directory -Force -Path $rtTmp | Out-Null

            $ms  = [System.IO.MemoryStream]::new([Convert]::FromBase64String($packed))
            $zip = [System.IO.Compression.ZipArchive]::new(
                       $ms, [System.IO.Compression.ZipArchiveMode]::Read, $true)

            # 逐条写字节，不走 Expand-Archive：避免给 DLL 打上「来自 Internet」的标记
            foreach ($entry in $zip.Entries) {
                if ([string]::IsNullOrEmpty($entry.Name)) { continue }
                $dst = Join-Path $rtTmp ($entry.FullName -replace '/', '\')
                $dstDir = Split-Path -Parent $dst
                if (-not (Test-Path -LiteralPath $dstDir)) {
                    New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
                }
                $es = $entry.Open()
                $os = [System.IO.File]::Create($dst)
                try { $es.CopyTo($os) } finally { $os.Dispose(); $es.Dispose() }
            }
            $zip.Dispose()
            $ms.Dispose()

            Set-Content -LiteralPath (Join-Path $rtTmp '.ok') -Value $script:AppVersion -Encoding ASCII
            if (Test-Path -LiteralPath $rtFinal) { Remove-Item -LiteralPath $rtFinal -Recurse -Force }
            Move-Item -LiteralPath $rtTmp -Destination $rtFinal
            $script:RuntimeDir = $rtFinal
        } catch {
            if (Test-Path -LiteralPath $rtTmp) {
                Remove-Item -LiteralPath $rtTmp -Recurse -Force -ErrorAction SilentlyContinue
            }
            $script:RuntimeDir = $root
        }
    }
}


# 内容目录一律以 $script:RuntimeDir 为准：源码直跑时它就是根目录，
# 单文件 exe 时是释放出来的 runtime\<版本>\，两者对下游完全一致。
$lib  = Join-Path $script:RuntimeDir 'lib'
$html = Join-Path $script:RuntimeDir 'ui\index.html'
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

# 有没有真实控制台？-noConsole 打包出来的 exe 没有。
# 此时一律不再把日志转发给宿主：没人看得到，反而会拖慢启动。
$script:HasConsole = $false
try { $null = [Console]::WindowWidth; $script:HasConsole = $true } catch { }

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
        if (-not $script:HasConsole) { return }
        if ($ForegroundColor) {
            Microsoft.PowerShell.Utility\Write-Host $text -ForegroundColor $ForegroundColor
        } else {
            Microsoft.PowerShell.Utility\Write-Host $text
        }
    }
}

# ---------------------------------------------------------------
# 4.5) 旧版数据迁移（放在 Write-Host 重定向之后，日志才记录得到）
#     v1.2.0 及之前 exe 把数据写在 exe 同级目录：
#     配置类文件迁到新数据目录（保留用户设置），可再生成的杂物清掉。
# ---------------------------------------------------------------
if ($script:MigratedFrom) {
    foreach ($mig in @('config.json', 'proxy.pac', 'proxy_remote.pac', 'update_check.json')) {
        try {
            $migSrc = Join-Path $script:MigratedFrom $mig
            $migDst = Join-Path $script:DataDir $mig
            if ((Test-Path -LiteralPath $migSrc) -and -not (Test-Path -LiteralPath $migDst)) {
                Move-Item -LiteralPath $migSrc -Destination $migDst -Force
                Write-Host "[ProxyTray] 迁移旧数据: $mig"
            }
        } catch {
            Write-Host "[ProxyTray] 迁移失败 $mig : $_" -ForegroundColor Yellow
        }
    }
    foreach ($junk in @('runtime', '.webview2', 'ProxyTray.log')) {
        try {
            $junkPath = Join-Path $script:MigratedFrom $junk
            if (-not (Test-Path -LiteralPath $junkPath)) { continue }
            # 清掉只读/隐藏属性，再用 .NET 直接删：PS5.1 的 Remove-Item -Recurse
            # 在 ps2exe 环境里实测会静默失败
            Get-ChildItem -LiteralPath $junkPath -Recurse -Force -ErrorAction SilentlyContinue |
                ForEach-Object { try { $_.Attributes = 'Normal' } catch { } }
            if (Test-Path -LiteralPath $junkPath -PathType Container) {
                [System.IO.Directory]::Delete($junkPath, $true)
            } else {
                [System.IO.File]::Delete($junkPath)
            }
            Write-Host "[ProxyTray] 清理 exe 目录遗留: $junk"
        } catch {
            Write-Host "[ProxyTray] 清理失败 $junk : $_" -ForegroundColor Yellow
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
Write-Host ("[ProxyTray] version={0}  packed={1}  console={2}" -f $script:AppVersion, $script:UsingPacked, $script:HasConsole)
Write-Host ("[ProxyTray] content={0}" -f $script:RuntimeDir)
Write-Host ("[ProxyTray] dpiAware={0}" -f $script:DpiAwareMode)


# ---------- 视觉样式：必须在创建任何控件之前调用 ----------
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    [System.Windows.Forms.Application]::EnableVisualStyles()
} catch {
    Write-Host "[ProxyTray] EnableVisualStyles failed: $_" -ForegroundColor Yellow
}
