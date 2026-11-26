# ── src/36-direct-update.ps1 · 直连规则联网更新 ──
# 托盘菜单「更新直连规则（联网）」→ 后台 runspace 下载上游清单 →
# 归并成 %LOCALAPPDATA%\NASProxy\china-direct.auto.txt → 重建 PAC。
# 网络请求在独立 runspace，主线程用 500ms Timer 轮询，不冻界面。
#
# 源的选择（按质量优先，逐个尝试）：
#   1) ACL4SSR ChinaDomain.list —— 人工精选的国内域名，几千条，条条是真站（首选）
#   2) felixonmars/dnsmasq-china-list —— 全量国内域名，10 万级，含大量长尾与垃圾短域，
#                                        仅作备选，靠基域归并 + 封顶 + 首段含字母 过滤
# 体积控制：PAC 按后缀逐段匹配（a.b.com 命中 b.com），所以只留「父域不在源表中」的基域，
# 并剔掉 .cn（后缀规则已全覆盖）。

$script:DirectUpdatePending = $false
$script:DirectUpdateHandle = $null

function Start-DirectRulesUpdateAsync {
    if ($script:DirectUpdatePending) {
        Write-Host '[ProxyTray] 直连规则更新已在进行中，忽略本次请求'
        return
    }
    $script:DirectUpdatePending = $true

    $path = Join-Path $script:DataDir 'china-direct.auto.txt'
    $ua   = "NASProxyTray/$($script:AppVersion)"

    try {
        $rs = [runspacefactory]::CreateRunspace()
        $rs.ApartmentState = 'MTA'
        $rs.Open()
        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddScript({
            param($path, $ua)

            function Out-Json($o) { $o | ConvertTo-Json -Compress }

            # ---------- 1) 选源 + 解析 + 清洗（一个源不达标就换下一个） ----------
            $sources = @(
                @{ url  = 'https://cdn.jsdelivr.net/gh/ACL4SSR/ACL4SSR@master/Clash/ChinaDomain.list'
                   name = 'ACL4SSR ChinaDomain' },
                @{ url  = 'https://cdn.jsdelivr.net/gh/felixonmars/dnsmasq-china-list@master/accelerated-domains.china.conf'
                   name = 'dnsmasq-china-list' }
            )
            $walled = @('google','youtube','github','twitter','facebook','wikipedia','reddit',
                        'telegram','whatsapp','instagram','openai','chatgpt','claude','anthropic',
                        'netflix','twitch','discord','pixiv','dropbox','slack','cloudflare','bbc','nytimes')

            $set = $null; $kept = $null; $srcName = ''
            foreach ($s in $sources) {
                try {
                    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                    $body = (Invoke-WebRequest -Uri $s.url -TimeoutSec 60 -UseBasicParsing `
                                -Headers @{ 'User-Agent' = $ua }).Content
                } catch { $body = $null }
                if (-not $body) { continue }

                # 解析：兼容 Surge/Clash 的 DOMAIN-SUFFIX,DOMAIN 与 dnsmasq 的 server=/d/
                $s1 = New-Object 'System.Collections.Generic.HashSet[string]'
                foreach ($ln in ($body -split "`r?`n")) {
                    $d = ''
                    if ($ln -match '^\s*DOMAIN-SUFFIX\s*,\s*([^\s,]+)') { $d = $matches[1] }
                    elseif ($ln -match '^\s*DOMAIN\s*,\s*([^\s,]+)') { $d = $matches[1] }
                    elseif ($ln -match '^\s*server=/([^/]+)/') { $d = $matches[1] }
                    if (-not $d) { continue }
                    $d = $d.Trim().TrimStart('.').ToLower()
                    if ($d -and $d.Contains('.') -and $d -match '^[a-z0-9][a-z0-9\.\-]*$') { [void]$s1.Add($d) }
                }
                if ($s1.Count -lt 100) { continue }

                # 清洗：剔被墙站 / .cn（后缀规则已覆盖）/ 首段无两个字母的垃圾域
                $k1 = New-Object 'System.Collections.Generic.List[string]'
                foreach ($d in $s1) {
                    $segs = $d.Split('.')
                    $bad = $false
                    foreach ($w in $walled) { if ($segs -contains $w) { $bad = $true; break } }
                    if ($bad) { continue }
                    if ($d.EndsWith('.cn') -or $d -eq 'cn') { continue }
                    if ($segs[0] -notmatch '[a-z].*[a-z]') { continue }
                    $k1.Add($d)
                }
                if ($k1.Count -lt 50) { continue }

                $set = $s1; $kept = $k1; $srcName = $s.name
                break
            }
            if (-not $kept) { return Out-Json @{ ok = $false; err = '清单源全部不可用（网络异常或格式变更）' } }

            # ---------- 4) 只留基域：父域已在源表里 → 本条冗余（PAC 后缀匹配已覆盖） ----------
            #    用 $set（HashSet）判父域，O(1)；List.Contains 是线性扫描，几万条会退化
            $final = New-Object 'System.Collections.Generic.List[string]'
            foreach ($d in $kept) {
                $i = $d.IndexOf('.')
                if ($i -lt 0) { continue }
                $parent = $d.Substring($i + 1)
                if ($set.Contains($parent)) { continue }
                $final.Add($d)
            }
            # 防呆线：基域远超正常规模（>50 万）说明上游数据异常，中止
            if ($final.Count -gt 500000) { return Out-Json @{ ok = $false; err = "结果异常（$($final.Count) 条），已中止" } }
            $final.Sort([StringComparer]::Ordinal)

            # ---------- 5) 兜底封顶（只有全量源会触发，精选源远小于此） ----------
            $cap = 30000
            $baseCount = $final.Count
            if ($baseCount -gt $cap) {
                $ranked = @($final | Sort-Object @{Expression = { $_.Length }; Ascending = $true },
                                                @{Expression = { $_ }; Ascending = $true} |
                            Select-Object -First $cap)
                $final = New-Object 'System.Collections.Generic.List[string]'
                foreach ($d in $ranked) { $final.Add($d) }
                $final.Sort([StringComparer]::Ordinal)
            }

            # ---------- 6) 落盘 ----------
            $sb = New-Object System.Text.StringBuilder
            [void]$sb.AppendLine('# NAS Proxy · 自动更新的国内直连清单')
            [void]$sb.AppendLine(("# 生成时间: {0}   来源: {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $srcName))
            [void]$sb.AppendLine(("# 上游基域 {0} 条，本次收录 {1} 条；手工补充请写 my-direct.txt" -f $baseCount, $final.Count))
            foreach ($d in $final) { [void]$sb.AppendLine($d) }
            try {
                Set-Content -LiteralPath $path -Value $sb.ToString() -Encoding UTF8
            } catch {
                return Out-Json @{ ok = $false; err = "写入失败：$_" }
            }

            return Out-Json @{ ok = $true; count = $final.Count; base = $baseCount; raw = $set.Count; src = $srcName }
        }).AddArgument($path).AddArgument($ua)

        $script:DirectUpdateHandle = $ps.BeginInvoke()
        $script:DirectUpdatePs     = $ps
        $script:DirectUpdateRs     = $rs
        Write-Host '[ProxyTray] 开始更新直连规则（精选源优先）'
    } catch {
        $script:DirectUpdatePending = $false
        Write-Host "[ProxyTray] 启动规则更新失败: $_"
    }
}

function Complete-DirectRulesUpdate {
    if (-not $script:DirectUpdateHandle) { return $false }
    if (-not $script:DirectUpdateHandle.IsCompleted) { return $false }
    $script:DirectUpdatePending = $false

    $json = $null
    try {
        $out = $script:DirectUpdatePs.EndInvoke($script:DirectUpdateHandle)
        if ($out -and $out.Count -gt 0) { $json = [string]$out[0] }
    } catch {
        Write-Host "[ProxyTray] 读取规则更新结果失败: $_"
    }
    try { $script:DirectUpdatePs.Dispose() } catch { }
    try { $script:DirectUpdateRs.Close() }   catch { }
    try { $script:DirectUpdateRs.Dispose() } catch { }
    $script:DirectUpdatePs = $null; $script:DirectUpdateRs = $null; $script:DirectUpdateHandle = $null

    if ([string]::IsNullOrWhiteSpace($json)) {
        Write-Host '[ProxyTray] 规则更新没有得到结果'
        return $true
    }
    $r = $null
    try { $r = $json | ConvertFrom-Json } catch {
        Write-Host "[ProxyTray] 规则更新结果无法解析: $json"
        return $true
    }

    if (-not $r.ok) {
        Write-Host "[ProxyTray] 规则更新失败: $($r.err)"
        try { $tray.ShowBalloonTip(6000, 'NAS Proxy', "直连规则更新失败：$($r.err)`n（原有规则继续生效）", [System.Windows.Forms.ToolTipIcon]::Warning) } catch { }
        return $true
    }

    Write-Host ("[ProxyTray] 直连规则已更新：来源 {0}，上游 {1} 条 → 基域 {2} 条 → 收录 {3} 条" -f $r.src, $r.raw, $r.base, $r.count)
    try {
        $cfg = Get-ProxyConfig
        if ([bool]$cfg.enabled) {
            $rr = Apply-ProxyConfig -Config $cfg
            Write-Host "[ProxyTray] 规则更新后重新应用: $($rr.msg)"
        }
        $tray.ShowBalloonTip(6000, 'NAS Proxy', "直连规则已更新：收录 $($r.count) 条`n（来源 $($r.src)，已生效）", [System.Windows.Forms.ToolTipIcon]::Info)
    } catch {
        Write-Host "[ProxyTray] 规则更新后应用失败: $_"
    }
    return $true
}

$script:directUpdatePollTimer = New-Object System.Windows.Forms.Timer
$script:directUpdatePollTimer.Interval = 500
$script:directUpdatePollTimer.add_Tick({
    if (Complete-DirectRulesUpdate) { $script:directUpdatePollTimer.Stop() }
})
