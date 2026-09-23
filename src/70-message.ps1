# ── src/70-message.ps1 · 前端协议 ──
# 注入脚本（拖动 / ESC / 尺寸上报）/ WebView2 初始化 / 11 个 action 分发

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

        # 界面里的外链（GitHub 等）交给系统默认浏览器打开，
        # 否则 WebView2 会把配置界面自身导航到外站，回不来
        $core.add_NewWindowRequested({
            param($s3, $e3)
            try {
                $e3.Handled = $true
                Start-Process $e3.Uri
            } catch {
                Write-Host "[ProxyTray] 打开外部链接失败: $_"
            }
        })

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
                    $payload = @{ action = 'config'; config = $cfg; version = $script:AppVersion } | ConvertTo-Json -Depth 6 -Compress
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
                    $payload = @{ action = 'config'; config = $cfg; version = $script:AppVersion } | ConvertTo-Json -Depth 6 -Compress
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
                    $payload = @{ action = 'config'; config = $cfg; version = $script:AppVersion } | ConvertTo-Json -Depth 6 -Compress
                    $s2.PostWebMessageAsString($payload)
                }
            }
        })
    } catch {
        Write-Host "[ProxyTray] EXCEPTION in init: $_" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    }
})
