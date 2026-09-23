#Requires -Version 5.1
<#
==========================================================================
 build.ps1 · 打包成单文件 exe

 产出（dist\）：
   NASProxyTray.exe             单文件，自带 lib\ 与 ui\ 资源
   NASProxyTray-v<版本>.zip     仅含上面那个 exe
   NASProxyTray.exe.sha256      校验值

 做法：
   1. 读 VERSION 作为唯一版本源
   2. 按文件名顺序拼合 src\*.ps1，剥掉各模块的 BOM，只保留一份
   3. 把 lib\*.dll 与 ui\index.html 打成 ZIP 再 Base64，内嵌为 $script:PackedResources
   4. 把 $script:AppVersionBuiltin 常量改写成 VERSION 的值（单文件没有 VERSION 文件可读）
   5. 交给 ps2exe 编译，带图标与版本号

 注意：本脚本绝不修改任何源文件（旧版会把图标 Base64 写回 ProxyTray.ps1）。
==========================================================================
#>
[CmdletBinding()]
param(
    [switch]$SkipZip,          # 只产出 exe，不打包 zip
    [string]$Ps2exeModulePath  # 手动指定 ps2exe 模块路径（自动定位失败时用）
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Step($n, $msg) { Write-Host ("[{0}/6] {1}" -f $n, $msg) -ForegroundColor Cyan }
function Ok($msg)       { Write-Host ("      {0}" -f $msg) -ForegroundColor Green }
function Warn($msg)     { Write-Host ("      {0}" -f $msg) -ForegroundColor Yellow }

$t0 = Get-Date
$root   = Split-Path -Parent $MyInvocation.MyCommand.Path
$srcDir = Join-Path $root 'src'
$libDir = Join-Path $root 'lib'
$uiFile = Join-Path $root 'ui\index.html'
$verFile = Join-Path $root 'VERSION'
$iconPath = Join-Path $root 'app.ico'
$distDir  = Join-Path $root 'dist'
$buildDir = Join-Path $root 'build'

Write-Host ''
Write-Host 'NASProxyTray 打包' -ForegroundColor White
Write-Host ("根目录: {0}" -f $root) -ForegroundColor DarkGray

# ---------------------------------------------------------------- 1 版本
Step 1 '读取版本号'
foreach ($p in @($srcDir, $libDir, $uiFile, $verFile, $iconPath)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "缺少必需文件/目录: $p" }
}
$version = (Get-Content -LiteralPath $verFile -Raw -Encoding UTF8).Trim()
if ($version -notmatch '^\d+\.\d+(\.\d+)?$') { throw "VERSION 内容不合法: '$version'" }

# 程序集版本必须是四段式
$fileVersion = switch ($version) {
    { $_ -match '^\d+\.\d+$' }        { "$_.0.0" }
    { $_ -match '^\d+\.\d+\.\d+$' }   { "$_.0" }
    default                           { $_ }
}
Ok ("版本 {0}（程序集版本 {1}）" -f $version, $fileVersion)

# -------------------------------------------------------- 2 拼合 src 模块
Step 2 '拼合 src\*.ps1'
$modules = Get-ChildItem -LiteralPath $srcDir -Filter '*.ps1' | Sort-Object Name
if ($modules.Count -eq 0) { throw "src 目录下没有 .ps1 模块" }
$utf8 = New-Object System.Text.UTF8Encoding($false)

$sb = New-Object System.Text.StringBuilder
foreach ($m in $modules) {
    $text = [System.IO.File]::ReadAllText($m.FullName, [System.Text.Encoding]::UTF8)
    $text = $text.TrimStart([char]0xFEFF)          # 剥掉模块自带的 BOM
    [void]$sb.Append($text.TrimEnd("`r", "`n"))
    [void]$sb.Append("`r`n")
}
$body = $sb.ToString()
Ok ("{0} 个模块，{1} 行" -f $modules.Count, ($body -split "`r`n").Count)

# --------------------------------------------------- 3 资源打包为 Base64
Step 3 '压缩内嵌资源（lib\*.dll + ui\index.html）'
Add-Type -AssemblyName System.IO.Compression | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null

$payload = New-Object System.Collections.Generic.List[object]
foreach ($f in (Get-ChildItem -LiteralPath $libDir -Filter '*.dll' | Sort-Object Name)) {
    $payload.Add([pscustomobject]@{ File = $f; Rel = 'lib/' + $f.Name })
}
$uiItem = Get-Item -LiteralPath $uiFile
$payload.Add([pscustomobject]@{ File = $uiItem; Rel = 'ui/index.html' })

$ms = New-Object System.IO.MemoryStream
$zip = New-Object System.IO.Compression.ZipArchive(
    $ms, [System.IO.Compression.ZipArchiveMode]::Create, $true)
foreach ($item in $payload) {
    $entry = $zip.CreateEntry($item.Rel, [System.IO.Compression.CompressionLevel]::Optimal)
    $es = $entry.Open()
    $bytes = [System.IO.File]::ReadAllBytes($item.File.FullName)
    $es.Write($bytes, 0, $bytes.Length)
    $es.Dispose()
    Ok ("{0}  {1,8:N1} KB" -f $item.Rel, ($bytes.Length / 1KB))
}
$zip.Dispose()
$rawSize = $ms.Length
$blob = [Convert]::ToBase64String($ms.ToArray())
$ms.Dispose()
Ok ("原始 {0:N1} KB -> ZIP {1:N1} KB -> Base64 {2:N1} KB" -f `
    (($payload | ForEach-Object { $_.File.Length } | Measure-Object -Sum).Sum / 1KB), `
    ($rawSize / 1KB), ($blob.Length / 1KB))

# ------------------------------------------------------------ 4 组装脚本
Step 4 '组装单文件脚本'
$header = @"
# ================================================================
#  NASProxyTray · 单文件版
#  由 build.ps1 生成于 $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))，请勿手改。
#  版本 $version
#
#  下面是内嵌资源（lib\*.dll 与 ui\index.html 打成的 ZIP 再 Base64）。
#  首次运行会释放到 <数据目录>\runtime\<版本>\ 并写 .ok 标记，之后直接复用。
# ================================================================
`$script:PackedResources = @'
$blob
'@

"@
$assembled = $header + $body

# 把内置版本常量改成 VERSION 的值（单文件里读不到 VERSION 文件）
$pattern = '\$script:AppVersionBuiltin\s*=\s*''[^'']*'''
$replacement = "`$script:AppVersionBuiltin = '$version'"
$hits = ([regex]::Matches($assembled, $pattern)).Count
if ($hits -ne 1) { throw "在拼合结果里找到 $hits 处 AppVersionBuiltin 常量（预期 1 处）" }
$assembled = [regex]::Replace($assembled, $pattern, $replacement)
Ok ("已注入版本常量，脚本总长 {0:N0} 字符" -f $assembled.Length)

if (-not (Test-Path -LiteralPath $buildDir)) { New-Item -ItemType Directory -Force -Path $buildDir | Out-Null }
if (-not (Test-Path -LiteralPath $distDir))  { New-Item -ItemType Directory -Force -Path $distDir  | Out-Null }
$stagePath = Join-Path $buildDir 'NASProxyTray.packed.ps1'
[System.IO.File]::WriteAllText($stagePath, $assembled, (New-Object System.Text.UTF8Encoding $true))
Ok ("已写出 $stagePath")

# ------------------------------------------------------------- 5 编译 exe
Step 5 '编译 exe'
$mod = $null
if ($Ps2exeModulePath) {
    $mod = Get-Module -ListAvailable ps2exe |
           Where-Object { $_.Path -like "*$Ps2exeModulePath*" } | Select-Object -First 1
}
if (-not $mod) { $mod = Get-Module -ListAvailable ps2exe | Sort-Object Version -Descending | Select-Object -First 1 }
if (-not $mod) {
    Warn '本机没有 ps2exe，尝试安装到 CurrentUser ...'
    Install-Module ps2exe -Scope CurrentUser -Force
    $mod = Get-Module -ListAvailable ps2exe | Sort-Object Version -Descending | Select-Object -First 1
}
if (-not $mod) { throw 'ps2exe 不可用' }
Import-Module $mod.Path -Force
Ok ("ps2exe {0}" -f $mod.Version)

$exePath = Join-Path $distDir 'NASProxyTray.exe'
# 用 .NET 的文件接口删除旧产物，不走 Remove-Item：
# 后者在某些环境里被「安全删除（移入回收站）」包装器接管，会因回收站不可用而失败
if ([System.IO.File]::Exists($exePath)) { [System.IO.File]::Delete($exePath) }

# -x64 是硬要求：lib\WebView2Loader.dll 是原生 64 位，32 位进程加载不了
# 不用 -DPIAware / -winFormsDPIAware：那会把 DPI 感知写进清单，
# 反而让运行时无法再升级到 Per-Monitor V2（见 src\00-boot.ps1）
Invoke-ps2exe -InputFile $stagePath -OutputFile $exePath -noConsole -STA -x64 `
    -title 'NAS Proxy' `
    -product 'NASProxyTray' `
    -description 'NAS 代理托盘工具（内置 WebView2 配置界面）' `
    -company 'ye1225' `
    -version $fileVersion `
    -iconFile $iconPath | Out-Null

if (-not (Test-Path -LiteralPath $exePath)) { throw "编译后没有生成 $exePath" }
$exeLen = (Get-Item -LiteralPath $exePath).Length
Ok ("NASProxyTray.exe  {0:N0} 字节 ({1:N2} MB)" -f $exeLen, ($exeLen / 1MB))

# --------------------------------------------------------- 6 校验与打包
Step 6 '校验与打包'
$sha = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
$shaPath = Join-Path $distDir 'NASProxyTray.exe.sha256'
[System.IO.File]::WriteAllText($shaPath, ("{0}  NASProxyTray.exe`r`n" -f $sha), $utf8)
Ok ("SHA256 {0}" -f $sha)

if (-not $SkipZip) {
    $zipPath = Join-Path $distDir ("NASProxyTray-v{0}.zip" -f $version)
    if ([System.IO.File]::Exists($zipPath)) { [System.IO.File]::Delete($zipPath) }
    Compress-Archive -LiteralPath $exePath -DestinationPath $zipPath -CompressionLevel Optimal
    Ok ("{0}  {1:N2} MB" -f (Split-Path -Leaf $zipPath), ((Get-Item $zipPath).Length / 1MB))
}

$span = (Get-Date) - $t0
Write-Host ''
Write-Host ("打包完成，耗时 {0:N1} 秒" -f $span.TotalSeconds) -ForegroundColor Green
Get-ChildItem -LiteralPath $distDir | ForEach-Object {
    Write-Host ("  {0,-32} {1,10:N0} 字节" -f $_.Name, $_.Length) -ForegroundColor Gray
}
Write-Host ''
