<#
.SYNOPSIS
    隐私检查的统一入口：优先调 tools\repo_hygiene.py，没有 Python 时退到内置正则。

.DESCRIPTION
    这个脚本是「上传前隐私审查」的**唯一入口**，三处调用它，规则集只有一份：

      · `.githooks\pre-push`          —— 推送时自动跑（硬拦）
      · `_工具\收工.ps1`             —— 离开机器前跑（因为还要往 NAS 传）
      · 手工：`powershell -File tools\privacy-scan.ps1 -Mode all`

    **规则集不在这里** —— 在 `tools\repo_hygiene.py`（与 skill `project-handoff`
    的上游副本逐字节相同）。本脚本只负责「找到 Python → 跑它 → 把退出码透出去」，
    免得同一套规则写两份、早晚跑偏。

    没有 Python 时退到内置的**最小正则**兜底，并明确告警「这次检查是降级的」——
    降级也不静默通过，这是刻意的。

.PARAMETER Root
    仓库根目录。默认取本脚本所在目录的上一级。

.PARAMETER Mode
    privacy / emails / stale / all（默认 all）。
    privacy、emails 不过 → 退出码 1；stale 只是提示，也返回 1 但调用方可以忽略。

.PARAMETER Quiet
    只输出结论行，不输出各段标题。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\privacy-scan.ps1
    powershell -ExecutionPolicy Bypass -File tools\privacy-scan.ps1 -Mode privacy
#>
[CmdletBinding()]
param(
    [string]$Root,
    [ValidateSet('privacy', 'emails', 'stale', 'all')]
    [string]$Mode = 'all',
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$Root = (Resolve-Path -LiteralPath $Root).Path
$checker = Join-Path $Root 'tools\repo_hygiene.py'

if (-not (Test-Path -LiteralPath $checker)) {
    Write-Host ('[隐私检查] 找不到检查器：' + $checker) -ForegroundColor Red
    Write-Host '           （应随仓库一起存在；缺了就是没做检查，请先把它补回来。）' -ForegroundColor Red
    exit 1
}

# ---------- 找 Python 3 ----------
function Find-Python {
    $candidates = New-Object System.Collections.Generic.List[object]

    if ($env:PROXYTRAY_PYTHON) {
        $candidates.Add([PSCustomObject]@{ Exe = $env:PROXYTRAY_PYTHON; Args = @() })
    }
    foreach ($n in @('python', 'python3')) {
        $c = Get-Command $n -ErrorAction SilentlyContinue
        if ($c) { $candidates.Add([PSCustomObject]@{ Exe = $c.Source; Args = @() }) }
    }
    # WorkBuddy 托管 Python（本机已知位置，PATH 里没有时也能用）
    $managed = 'C:\Users\Administrator\.workbuddy\binaries\python\versions\3.13.12\python.exe'
    if (Test-Path -LiteralPath $managed) {
        $candidates.Add([PSCustomObject]@{ Exe = $managed; Args = @() })
    }
    # py 启动器
    $py = Get-Command 'py' -ErrorAction SilentlyContinue
    if ($py) { $candidates.Add([PSCustomObject]@{ Exe = $py.Source; Args = @('-3') }) }

    foreach ($c in $candidates) {
        try {
            $null = & $c.Exe @($c.Args + @('-c', 'import sys')) 2>$null
            if ($LASTEXITCODE -eq 0) { return $c }
        } catch { }
    }
    return $null
}

$py = Find-Python

if ($py) {
    if (-not $Quiet) { Write-Host ('[隐私检查] 检查器：' + $checker) -ForegroundColor DarkGray }

    # 中文乱码防护：本机系统 ANSI 已是 UTF-8（Windows「Beta: 使用 Unicode UTF-8」开着），
    # 检查器（Python）吐的也是 UTF-8 字节；但控制台代码页可能仍是 936，字节到终端被按 GBK
    # 解释 → 乱码。跑检查器期间把代码页和 OutputEncoding 一起对齐成 UTF-8，跑完双双恢复。
    # （被 收工.ps1 调用时父进程已经切过，这里检测到 65001 会自动跳过。）
    $prevEnc = [Console]::OutputEncoding
    $chcpExe = (Get-Command chcp -ErrorAction SilentlyContinue).Source
    $prevCp = ''
    if ($chcpExe) { $prevCp = (((& $chcpExe) 2>&1) | Out-String) -replace '\D', '' }
    $cpSwitched = $false
    if ($chcpExe -and $prevCp -and $prevCp -ne '65001') {
        & $chcpExe 65001 > $null 2>&1
        $cpSwitched = $true
    }
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    try {
        & $py.Exe @($py.Args + @($checker, $Mode, '--repo', $Root))
        $exitCode = $LASTEXITCODE
    } finally {
        [Console]::OutputEncoding = $prevEnc
        if ($cpSwitched) { & $chcpExe $prevCp > $null 2>&1 }
    }
    exit $exitCode
}

# ---------- 降级：内置最小正则（**规则集以 repo_hygiene.py 为准，这里只做兜底**）----------
# 注意：**降级告警不受 -Quiet 影响** —— 检查能力变弱必须让人看见，不能静默通过。
Write-Host '[隐私检查] ⚠ 找不到 Python 3 —— 退到内置**最小**正则检查（能力弱于完整检查器）。' -ForegroundColor Yellow
Write-Host '           装上 Python 3 即可恢复完整检查（只用标准库）。' -ForegroundColor Yellow
Write-Host ''

$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) {
    Write-Host '[隐私检查] git 也不在 PATH 里，无法检查。' -ForegroundColor Red
    exit 1
}

# 私网地址 / 个人邮箱 / 绝对用户路径 / 令牌 / 机器名
$pattern = '192\.168\.[0-9]+\.[0-9]+|10\.[0-9]+\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]+\.[0-9]+|@(gmail|qq|163|126|outlook|hotmail|foxmail|icloud|yeah)\.com|[A-Za-z]:[\\/]+Users[\\/]+|/home/[a-z]|/(Users)/[a-z]|ghp_[A-Za-z0-9]|github_pat_|DESKTOP-[A-Z0-9]{6,}|LAPTOP-[A-Z0-9]{6,}'

# 示例值 / 占位符：出现这些的行不算问题
$allow = @('192.168.1.100', '7890', '%USERPROFILE%', '<用户目录>', '你的用户名', '<用户名>', 'example.com', 'users.noreply.github.com')

$raw = @(& git -C $Root grep -n -I -E $pattern -- . 2>$null)
$hits = New-Object System.Collections.Generic.List[string]
foreach ($line in $raw) {
    $isAllowed = $false
    foreach ($a in $allow) { if ($line -like ('*' + $a + '*')) { $isAllowed = $true; break } }
    if (-not $isAllowed) { $hits.Add($line) }
}

if ($hits.Count -eq 0) {
    Write-Host '[隐私检查] 被跟踪文件：未发现可疑内容 ✅（降级检查）' -ForegroundColor Green
    exit 0
}

Write-Host ('[隐私检查] ❌ 发现 ' + $hits.Count + ' 处可疑内容（降级检查）：') -ForegroundColor Red
foreach ($h in $hits) { Write-Host ('  ' + $h) -ForegroundColor Red }
Write-Host ''
Write-Host '  这些是会随仓库公开的内容。装个 Python 3 跑完整检查器看得更准。' -ForegroundColor Yellow
exit 1
