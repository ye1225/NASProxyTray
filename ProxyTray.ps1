# ================================================================
#  NASProxyTray · 入口
#
#  真正的实现全部位于 src/ 下，按文件名前缀顺序加载（00 → 90）。
#  加载顺序只有一个来源：src/ 目录里 *.ps1 的文件名排序。
#    · 开发时：直接运行本文件（dot-source src/ 下各模块）
#    · 打包时：build.ps1 按同样的顺序把 src/*.ps1 拼成单文件喂给 ps2exe
#  两种模式因此必然一致，不存在两套加载顺序。
#
#  注意：拆分之后，模块内的 $PSScriptRoot / $PSCommandPath 会指向 src\ 下的
#  模块文件本身，而不是程序根目录。所以这里先把入口的真实路径与目录记下来，
#  以 $script:LaunchScriptPath / $script:LaunchRoot 交给 00-boot 使用。
# ================================================================
$ErrorActionPreference = 'Stop'

$script:LaunchScriptPath = $PSCommandPath
if ([string]::IsNullOrWhiteSpace($script:LaunchScriptPath)) {
    try { $script:LaunchScriptPath = $MyInvocation.MyCommand.Path } catch { }
}

$script:LaunchRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($script:LaunchRoot)) {
    $script:LaunchRoot = (Get-Location).Path
}

# 定位 src 目录：优先入口同级，其次当前工作目录
$srcDir = Join-Path $script:LaunchRoot 'src'
if (-not (Test-Path -LiteralPath $srcDir)) {
    $alt = Join-Path (Get-Location).Path 'src'
    if (Test-Path -LiteralPath $alt) { $srcDir = $alt }
}
if (-not (Test-Path -LiteralPath $srcDir)) {
    Write-Host "[ProxyTray] 找不到 src 目录：$srcDir" -ForegroundColor Red
    exit 1
}

Get-ChildItem -LiteralPath $srcDir -Filter '*.ps1' |
    Sort-Object Name |
    ForEach-Object {
        Write-Host ("[ProxyTray] load {0}" -f $_.Name) -ForegroundColor DarkGray
        . $_.FullName
    }
