# ── src/20-config.ps1 · 配置 ──
# 共享状态与配置文件路径 / 刷新系统代理设置 / 默认值 / 读取 / 保存
# ================================================================
#  代理引擎
# ================================================================
$script:ConfigFile     = Join-Path $script:DataDir 'config.json'
$script:ServedPac      = Join-Path $script:DataDir 'proxy.pac'
$script:RemotePacCache = Join-Path $script:DataDir 'proxy_remote.pac'
$script:RegPath        = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$script:PacPort        = 0
$script:PacPs          = $null
$script:PacListener    = $null
$script:PacRunspace    = $null
$script:CurrentConfig  = $null

function Update-InternetSettings {
    if ($script:DryRun) { Write-Host "[DRYRUN] 跳过刷新系统代理设置"; return }
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
        # ⚠️ 下面是**示例默认值**，首次使用请在界面里改成你自己代理机的地址与端口
        server        = '192.168.1.100'
        port          = '7890'
        override      = 'localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.20.*;172.21.*;172.22.*;172.23.*;172.24.*;172.25.*;172.26.*;172.27.*;172.28.*;172.29.*;172.30.*;172.31.*;192.168.*'
        mode          = 'smart'
        pacSource     = 'builtin'
        builtinPolicy = 'direct-list'
        pacDomains    = $domains
        localPacPath  = ''
        remotePacUrl  = ''
        pacRewrite    = $true
        autoStart     = $false
        enabled       = $false
    }
}

function Get-ProxyConfig {
    $cfg = Get-DefaultProxyConfig
    if (Test-Path $script:ConfigFile) {
        try {
            $raw = Get-Content $script:ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($k in @('server','port','override','mode','pacSource','builtinPolicy','pacDomains','localPacPath','remotePacUrl','pacRewrite','autoStart','enabled')) {
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
