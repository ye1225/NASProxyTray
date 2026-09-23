# ── src/90-main.ps1 · 主流程 ──
# Form Shown / Closing / Closed / 启动消息循环 / 兜底清理

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
