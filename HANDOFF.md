# NASProxyTray · 交接文档

> 交接给下一个接手的人（或 AI）。
> **当前状态：v1.2.6 已发布（修复自动保存无限循环）。**

---

## 项目简介

Windows 托盘工具，一键切换系统代理指向 NAS，支持全局代理与 PAC 智能分流。
技术栈：**PowerShell 5.1 + WinForms 承载 WebView2 控件**，界面是纯 HTML/CSS/JS。

| 项目 | 值 |
| --- | --- |
| 仓库 | https://github.com/ye1225/NASProxyTray |
| 本地路径 | `D:\Desktop\NASProxyTray` |
| 当前版本 | **v1.2.6**（唯一版本源：仓库根目录 `VERSION` 文件） |
| 主分支 | `main` |
| 运行环境 | Windows 10 1809+ / Windows 11 + WebView2 Runtime |
| 发布形态 | **单个 `NASProxyTray.exe`**（v1.2.0 起，不必再带 `lib\` 和 `ui\`） |

---

## 目录结构

```
D:\Desktop\NASProxyTray\
├── ProxyTray.ps1                     薄入口：定位 src\ 并按文件名顺序 dot-source
├── src\                              ← 真正的实现，10 个模块
│   ├── 00-boot.ps1                   启动地基（含 DPI 声明、资源释放）
│   ├── 10-native.ps1                 原生互操作（6 个 Add-Type 块）
│   ├── 20-config.ps1                 配置读写 + 刷新系统代理
│   ├── 30-proxy.ps1                  代理引擎（注册表 / PAC 服务 / 连通测试 / 自启）
│   ├── 40-icon.ps1                   托盘图标绘制
│   ├── 50-window.ps1                 窗口尺寸定位 / Form / WebView2 宿主 / DPI 换算
│   ├── 60-tray.ps1                   NotifyIcon / 深色中文右键菜单
│   ├── 70-message.ps1                WebView2 初始化 + 前端消息分发
│   ├── 80-update.ps1                 检查更新
│   └── 90-main.ps1                   Form 生命周期 / 消息循环 / 兜底清理
├── lib\                              WebView2 运行时依赖（3 个 DLL，仍入库）
├── ui\index.html                     WebView2 界面（420px 固定宽度设计）
├── build.ps1                         打包脚本 → dist\
├── VERSION                           版本号唯一来源
├── app.ico                           程序图标（build.ps1 依赖）
├── debug.bat                         带日志调试入口
├── LICENSE                           MIT
└── README.md

（运行时生成，不入库）

- `dist\` 构建产物：exe / zip / sha256
- `build\` 拼合后的中间脚本 `NASProxyTray.packed.ps1`
- 所有运行时数据都在 **`%LOCALAPPDATA%\NASProxy\`**（v1.2.1 起；exe 同级目录不再生成
  任何文件）：`ProxyTray.log` / `config.json` / `proxy.pac` / `proxy_remote.pac` /
  `update_check.json` / `runtime\<版本>\` / `.webview2\`
```

---

## 架构：加载顺序只有一个来源

`ProxyTray.ps1` 只做三件事：

1. 记下真实入口路径（`$script:LaunchScriptPath` / `$script:LaunchRoot`）
2. 找到 `src\`，按 `Sort-Object Name` 枚举 `*.ps1`
3. 逐个 dot-source

```powershell
Get-ChildItem -LiteralPath $srcPath -Filter '*.ps1' |
    Sort-Object Name |
    ForEach-Object { . $_.FullName }
```

**同一个顺序同时服务两种模式**：开发时直接 dot-source，打包时 `build.ps1` 按同一顺序拼合成单文件。所以两种模式行为一致，不存在"开发能跑、打包就崩"。

> ⚠️ dot-source 会让 `$PSCommandPath` / `$PSScriptRoot` 指向**模块自己**（`src\00-boot.ps1`），
> 所以真实入口路径必须由 `ProxyTray.ps1` 用 `$script:LaunchScriptPath` 传下去。
> 这是拆分后最容易踩的坑，已在 `00-boot.ps1` 处理。

---

## 各模块要点

### `00-boot.ps1` — 启动地基（约 300 行，最重的一个）

按执行顺序：

| # | 内容 | 备注 |
| --- | --- | --- |
| 0 | **DPI 感知声明** | 必须在建任何窗口之前；见下方「高 DPI」 |
| 1 | 自身路径探测 | 依次尝试 `$LaunchScriptPath` → `$PSCommandPath` → 命令行第 0 项 → 进程主模块 |
| 2 | STA 重开 | 非 STA 时用 `$env:PROXYTRAY_STA_RETRY=1` 防无限重开；exe 与 ps1 两种重启方式 |
| 3 | 单实例互斥 | `Local\NASProxyTray_SingleInstance`，抢不到就弹提示后 exit |
| 4 | 根目录 / 数据目录 | 数据目录写探针文件测试可写性，不可写退到 `%LOCALAPPDATA%\NASProxy` |
| 5 | 版本号 | `$script:AppVersionBuiltin` 常量 + 有 `VERSION` 文件则覆盖 |
| 6 | **内嵌资源释放** | 见下方「打包」 |
| 7 | 日志 | 覆写 `Write-Host`，同时写 `ProxyTray.log`，>512 KB 清空 |
| 8 | 控制台探测 | `$script:HasConsole`；无控制台时**提前 return**，不当无用的转发（曾因此卡 13 秒启动） |
| 9 | DRYRUN | `$env:PROXYTRAY_DRYRUN=1` → `$script:DryRun` |
| 10 | `EnableVisualStyles()` | 建控件之前调用 |

导出的关键变量：`$script:appSelf`、`$script:appIsExe`、`$script:DataDir`、`$script:AppVersion`、
`$script:RuntimeDir`、`$script:UsingPacked`、`$script:DpiAwareMode`、`$script:DpiScale`、
`$script:HasConsole`、`$script:DryRun`，以及 `$lib` / `$html` / `$udd` 三个路径。

### `10-native.ps1`

6 个 `Add-Type` 编译的 C# 类，按顺序：

| 类 | 用途 |
| --- | --- |
| `NativeLoader` | `SetDllDirectory`（WebView2Loader.dll 靠它找到） |
| `NativeDrag` | `ReleaseCapture` + `SendMessage`，实现无边框窗口拖动 |
| `NativeRound` | 圆角：`SetWindowCornerPreference`（Win11 DWM）+ `CreateRoundRectRgn` 兜底 |
| `WinINet` | `InternetSetOption` 刷新系统代理设置，让注册表改动立刻生效 |
| `IconNative` | `DestroyIcon` 销毁动态生成的图标句柄 |
| `DarkMenuRenderer` | 深色右键菜单渲染器，编译失败则 `$script:hasDarkRenderer = $false` 回退默认 |

### `20-config.ps1`

共享状态与配置路径：`$script:ConfigFile`、`$script:PacFile`、`$script:PacListener = $null`。
`Update-InternetSettings`（带 DRYRUN 保护）、`Get-DefaultProxyConfig`、`Get-ProxyConfig`、`Save-ProxyConfig`。

配置项：`server / port / override / mode / pacSource / pacDomains / localPacPath / remotePacUrl / pacRewrite / autoStart / enabled`

| 配置项 | 取值 | 说明 |
| --- | --- | --- |
| `mode` | `global` / `smart` | `smart` 才看 `pacSource`；**`global` 下 PAC 相关设置全部被忽略** |
| `pacSource` | `builtin` / `local` / `remote` | 内置域名表 / 本地 `.pac` / 远程 URL（失败回退 `proxy_remote.pac` 缓存） |
| `builtinPolicy` | `direct-list` / `proxy-list` | **仅对 `pacSource=builtin` 生效**，见下一节；缺省按 `direct-list` |
| `pacRewrite` | `true` / `false` | 缺省视为 `true`。仅对外部 PAC 生效，见下下节 |

### `30-proxy.ps1` — 代理引擎

| 函数 | 作用 |
| --- | --- |
| `Set-GlobalProxy` | 注册表 `ProxyEnable=1` + `ProxyServer` + `ProxyOverride` |
| `Set-PacProxy` | 起本地 PAC HTTP 服务，写 `AutoConfigURL` |
| `Clear-SystemProxy` | 清空注册表代理项 |
| `Start-PacServer` | `TcpListener` 服务 `http://127.0.0.1:<随机端口>/proxy.pac` |
| `Stop-PacServer` | 停 listener 让阻塞的 `AcceptTcpClient` 醒来 → 优雅退出 |
| `Build-BuiltinPac` | 按 `-Policy` 生成内置 PAC（两种策略，见下） |
| `Convert-PacProxyEndpoint` | **把外部 PAC 里写死的代理地址换成本应用配置的地址**（见下） |
| `Apply-ProxyConfig` | 按 config 应用（全局 / PAC / 关闭），外部 PAC 会先过一遍地址替换 |
| `Test-ProxyConn` | `TcpClient` 连接测试，返回延迟 ms |
| `Set-AutoStart` / `Get-AutoStart` | 写 `Startup\NASProxy.lnk`（不是注册表 Run 键） |

> `Set-GlobalProxy` / `Set-PacProxy` / `Clear-SystemProxy` / `Set-AutoStart` 四个都会改系统，
> 全部做了 DRYRUN 短路。

#### 内置分流：两种策略（v1.2.3）

`Build-BuiltinPac -Policy` 有两个取值：

| 策略 | PAC 行为 | 用到的数据 |
| --- | --- | --- |
| `direct-list`（默认） | 命中清单 → `DIRECT`；否则 → `PROXY <你的地址>` | `src/35-china-direct.ps1` 里的 703 条清单 + `.cn` 后缀 |
| `proxy-list`（旧行为） | 命中清单 → `PROXY`；否则 → `DIRECT` | 配置里的 `pacDomains`（用户可编辑） |

`direct-list` 生成的 PAC 结构（约 13 KB）：

```js
var CHINA_DIRECT = { "baidu.com":1, "qq.com":1, ... };   // 703 条

function FindProxyForURL(url, host) {
  host = host.toLowerCase();
  if (host.length > 3 && host.slice(-3) === ".cn") return "DIRECT";
  var parts = host.split("."), i, cand;
  for (i = 0; i < parts.length - 1; i++) {
    cand = parts.slice(i).join(".");
    if (CHINA_DIRECT[cand] === 1) return "DIRECT";   // 哈希查找，O(1)
  }
  return "PROXY <server>:<port>; DIRECT";
}
```

设计要点：

- **清单只需覆盖常见站**。用户自己的代理通常还有一层分流规则，清单漏掉的国内域名
  会走代理由代理再判断，不会出错；清单的作用是让流量少绕路，不是当唯一裁判。
- **后缀逐级查找 + 哈希表**，单次判定 O(1)，清单规模不影响 PAC 性能。
  （别写成逐个 `dnsDomainIs` 的线性扫描 —— 700 条就是 700 次比较。）
- `direct-list` 下 **`pacDomains` 不参与**。否则默认那 33 条里含 `*.google.com`，
  会被当成"额外直连"从而把 Google 也直连掉。
- 用对象字面量而不是 `Set`，兼容老 PAC 引擎。
- 判定用 `CHINA_DIRECT[cand] === 1`（严格等于 1）而不是真值判断，
  避免 `constructor` / `toString` 这类原型链 key 命中。

**清单怎么来的**：`tools/gen-china-list.py` 从三个公开源交叉生成 ——
`felixonmars/dnsmasq-china-list`、`blackmatrix7/ios_rule_script`（ChinaMax）、
`ACL4SSR`（ChinaDomain）。规则是：

1. 骨架 = ACL4SSR 精选里被前两个源确认过的域名（约 570 条）
2. 补充 = 按品牌关键词（约 115 个，按域名**段精确匹配**）从「两源交集」里捞
3. 附加 = 手工列的十几个漏网站点
4. 自检 = 被墙站（google/github/... ）若被收录则剔除

> 重新生成：`python tools/gen-china-list.py`（原始清单缓存在 `build/list-cache/`）。
> 注意直连 GitHub raw 在本机不通，脚本走 jsDelivr CDN。
>
> **踩过的坑**：手工重打品牌词表时漏了 `xhscdn`（小红书图片 CDN），
> 导致清单少一条且 `diff` 只在一处报差异 —— 改词表后务必重新比对生成结果。

#### 外部 PAC 的代理地址替换（v1.2.2）

**问题**：第三方 PAC 里写死的是作者本机的代理地址。gfw-pac 第一行就是
`var proxy = "PROXY 127.0.0.1:3128";` —— 拿来直接用，命中规则的流量全被丢到
一个本机不存在的端口上，现象是「Google 全打不开、国内站正常」。

**做法**：`Convert-PacProxyEndpoint` 用一条正则只换「地址:端口」，代理方案关键字原样保留：

```powershell
$pattern = '(?<scheme>\b(?:PROXY|HTTPS|SOCKS5|SOCKS4|SOCKS)\s+)(?<endpoint>[A-Za-z0-9][A-Za-z0-9\.\-]*:\d{1,5})'
```

几个容易踩的点：
- 替换串里的 `$` 必须转义成 `$$`，否则 `192.168.31.126:41634` 会被当成正则反向引用
  （实际上没有 `$`，但 `server` 里可能有；统一 `.Replace('$','$$')` 最省心）。
- 正则要求「方案关键字 + 空白 + 主机:端口」，所以 `DIRECT`、`http://host:port`
  这类不会被误改。
- 只用 .NET 静态 `[regex]::Replace`，**不要用 `-replace`**（后者对 `$` 的处理更绕）。
- 不猜协议：PAC 写 `SOCKS5` 就还是 `SOCKS5`，只换地址。发现的方案会写进日志。
- 关掉开关（`pacRewrite=false`）就完全保留原文件。

实测（v1.2.2，DRYRUN + 用户真实的 `D:\Downloads\gfw.pac`）：

```
开关开 → var proxy = "PROXY 192.168.31.126:41634";   残留 127.0.0.1:3128 = 0 处
开关关 → var proxy = "PROXY 127.0.0.1:3128";         残留 127.0.0.1:3128 = 1 处
日志   → [ProxyTray] PAC 代理地址替换 1 处: 127.0.0.1:3128 -> 192.168.31.126:41634  方案: PROXY
```


### `40-icon.ps1`
`New-BallIcon -Color <Color>` 动态画圆点图标（灰 = 关闭，绿 = 开启）。

### `50-window.ps1`
工作区与尺寸基准 / Form / WebView2 宿主 / 圆角 / **尺寸防抖（120ms Timer）** / 失焦延迟隐藏（150ms）/ `DpiChanged` 处理。
详见下方「高 DPI」。

### `60-tray.ps1`
NotifyIcon + 深色中文右键菜单。菜单项顺序：

```
[发现新版本 vX.Y.Z · 点击下载]   ← 默认隐藏，仅 80-update 发现新版时显示
显示 / 隐藏窗口
打开开发者工具
──────────
立即清除系统代理
复位窗口位置
检查更新
──────────
v1.2.0                          ← 灰色禁用，仅展示版本
退出
```

菜单的 Padding 按 `$script:DpiScale` 缩放（物理像素，WinForms 不代缩）。
**字体固定 9pt，绝不能手工乘 DpiScale** —— GDI+ 渲染 point 字体会随设备 DPI
自动放大，再手工乘一遍就是双重放大（v1.2.0 在 200% 屏上菜单文字特别大就是这个原因）。

### `70-message.ps1`
注入 JS（禁动画、隐藏滚动条、`.title-bar` 拖拽、Escape 隐藏、上报尺寸）+ WebView2 初始化 + 消息分发。
另注册 `NewWindowRequested`，让界面里的外链走默认浏览器打开。

### `80-update.ps1`
见下方「检查更新」。

### `90-main.ps1`
Form 生命周期、`Application.Run`、退出清理（含更新检查的 Timer 与 runspace 释放）。

---

## 前后端通信协议

**前端 → 宿主**（`window.chrome.webview.postMessage`，JSON 字符串）：

| action | 参数 | 作用 |
| --- | --- | --- |
| `startDrag` | — | 拖动窗口（点 `.title-bar`） |
| `hide` | — | 隐藏窗口（Escape） |
| `size` | `w, h` | 上报界面实际宽高（**CSS 像素**，宿主乘 DpiScale） |
| `theme` | `dark` | 通知系统深色模式 |
| `getConfig` | — | 请求配置 |
| `saveConfig` | `config, quiet?` | 保存配置（`quiet=true` 时成功不弹 toast，自动保存用） |
| `toggleProxy` | `enabled, config?` | 开关代理 |
| `setAutoStart` | `enabled` | 切换自启动 |
| `browseFile` | — | 弹文件选择框（选 PAC） |
| `testConnection` | `server, port` | TCP 连接测试 |
| `resetConfig` | — | 恢复默认 |
| `uiError` | `msg, src, line` | 前端 JS 异常，宿主写 `[UI-ERROR]` 进日志 |

**宿主 → 前端**（`PostWebMessageAsString`）：

| action | 数据 | 触发时机 |
| --- | --- | --- |
| `config` | `config, version` | getConfig / setAutoStart / resetConfig 后 |
| `saved` | `ok, msg, config` | saveConfig 后 |
| `state` | `enabled, ok, msg, mode, server, port` | toggleProxy 后 |
| `filePicked` | `path` | 用户选完 PAC 文件 |
| `connResult` | `ok, latency` | 连接测试返回 |

> `config` 载荷里的 **`version` 是 v1.2.0 新增的**：界面页脚的版本号由宿主下发，
> 不再在 HTML 里写死。新增/修改协议时记得同步 `ui/index.html`。

### 自动保存（v1.2.5 起，界面不再有「保存设置」按钮）

- 任何改动走 600 ms 防抖，到点自动发 `saveConfig`；窗口失焦 / 隐藏 / 卸载前立即补发
- **生死攸关的不变量（v1.2.6 修复的无限循环）**：`flushSave()` 发出请求的瞬间必须
  `dirty = false`。否则 `saved` 回执到达时 `dirty` 仍为 true，会被当成「期间又有改动」
  再次 `flushSave()` → 回执 → 再补 → 无限循环（v1.2.5 界面永远卡在「保存中…」、
  后端每秒被灌几十次 saveConfig 就是这个原因）。
  「保存期间用户又改了」的检测靠的是发出后、回执前 `markDirty()` 重新置位 dirty。
- 另有 5 秒看门狗：回执丢失则解除 `saveInFlight` 占位，避免此后永远无法保存
- **校验在前**：`validateConfig()` 不过（地址空 / 端口越界 / 智能分流缺 PAC 文件）
  就**不发请求**，配置文件保留上次有效值，底部状态条转红
- 相关元素：`#autosaveBar`（三态 `.pending / .ok / .err`）、`#autosaveText`；
  原 `.save-btn` 样式与「未保存的更改」弹窗已删除（弹窗代码此前从未被触发过）

---

## 打包成单文件 exe

```powershell
.\build.ps1                 # 完整流程
.\build.ps1 -SkipZip        # 只要 exe，不打 zip
```

产物（`dist\`）：

| 文件 | 说明 |
| --- | --- |
| `NASProxyTray.exe` | 单文件，约 **422 KB**（不是早期猜测的 10–15 MB，因为 DLL 先压成 ZIP 再 Base64） |
| `NASProxyTray-v<版本>.zip` | 只含上面那个 exe |
| `NASProxyTray.exe.sha256` | 校验值 |

`build.ps1` 六步：

1. 读 `VERSION` → 校验格式 → 换算成四段式程序集版本
2. **按文件名顺序拼合 `src\*.ps1`**，逐条剥掉 BOM，只保留一份
3. `lib\*.dll` + `ui\index.html` → ZIP → Base64，内嵌为 `$script:PackedResources`
4. 拼上文件头，把 `$script:AppVersionBuiltin` 改写成 `VERSION` 的值（**要求恰好命中 1 处**，否则报错）
5. `Invoke-ps2exe -noConsole -STA -x64`，带图标与版本信息
6. 算 SHA256，`Compress-Archive` 打 zip

> **`build.ps1` 绝不修改任何源文件。** 旧版会把图标 Base64 写回 `ProxyTray.ps1`，现在不会了。

**为什么必须 `-x64`**：`lib\WebView2Loader.dll` 是原生 64 位，32 位进程加载不了。

**为什么不用 `-DPIAware` / `-winFormsDPIAware`**：那会把 DPI 感知写进 exe 清单，
运行时反而无法升级到 Per-Monitor V2。DPI 由 `00-boot.ps1` 在运行时声明。

### 运行时资源释放

exe 启动时若 `$script:PackedResources` 存在且同级目录下没有 `lib\`，就：

1. 解到 `<数据目录>\runtime\.tmp-<guid>\`
2. 逐条写字节（**不走 `Expand-Archive`**，避免给 DLL 打上「来自 Internet」标记）
3. 写 `.ok` 标记（内容是版本号）
4. 整体 `Move-Item` 改名成 `<数据目录>\runtime\<版本>\`

下次启动看到 `.ok` 直接复用。**先临时目录再改名**，避免中途失败留下半个残缺目录。
失败时 `$script:RuntimeDir` 回退到根目录。

---

## 高 DPI（4K 清晰渲染）

三层改动，缺一不可：

**1. 进程级 DPI 感知**（`00-boot.ps1`，建窗口之前）

```powershell
SetProcessDpiAwarenessContext(-4)   # PER_MONITOR_AWARE_V2
  ↓ 失败
SetProcessDpiAwareness(2)           # Per-Monitor
  ↓ 失败
SetProcessDPIAware()                # System
```

不声明的话进程是 DPI-unaware 的，Windows 会先把整个界面按 96 DPI 光栅化成位图，
再整体拉伸到物理像素 —— 4K 上看着就是糊的。声明之后由本进程按真实 DPI 自己渲染。

**2. 窗口几何按 DpiScale 换算**（`50-window.ps1`）

```powershell
$null = $form.Handle                       # ★ 关键
$dpi = [int]$form.DeviceDpi
if ($dpi -le 96) { $dpi = [NativeDpi.Api]::GetDpiForSystem() }
$script:DpiScale = [Math]::Round(($dpi / 96.0) * 4) / 4   # 归到 0.25 的倍数
```

> ★ **句柄没建出来之前 `Form.DeviceDpi` 恒为 96**。不先 `$null = $form.Handle` 强制建句柄，
> 在 200% 缩放的机器上会算出 `scale=1`，界面瞬间缩成一半。这是本轮调试花时间最多的坑。
> 另加 `GetDpiForSystem()` 兜底。

`Update-DpiMetrics()` 把 `margin(12)` / `initW(420)` / `initH(500)` / `cornerRadius(24)` 都乘上 scale。
尺寸防抖的 `slack` 也乘 scale。另外注册了 `DpiChanged`，拖到另一块显示器或改缩放时重新计算并复位。

**3. 前端给的是 CSS 像素，宿主给的是设备像素**

`size` 消息上来的是 CSS px，宿主乘 `$script:DpiScale` 后再 `SetBounds`。两边基准必须分清。

**实测**：本机 3200×2000 @200% → `dpiScale=2`，初始化窗口 `840x1000` 设备像素，
日志 `dpiAware=PerMonitorV2`，界面清晰。

---

## 检查更新

设计取向是**只做「发现 + 提示 + 用默认浏览器打开下载页」，不自动替换自己**：
未签名 exe 自替换容易被 SmartScreen 和杀软拦住，得不偿失。

| 项 | 值 |
| --- | --- |
| 数据源 | `https://api.github.com/repos/ye1225/NASProxyTray/releases/latest` |
| 触发 | 启动后延迟 5 秒静默检查 + 托盘菜单「检查更新」手动触发 |
| 节流 | 24 小时（记录在 `update_check.json`） |
| 超时 | 10 秒 |
| 实现 | 独立 runspace（MTA）跑网络请求，主线程 400ms Timer 轮询 `IsCompleted` |
| 提示 | 托盘气泡 + 菜单浮现「发现新版本 vX.Y.Z · 点击下载」 |
| 点击 | `Start-Process` 打开 Release 页 |

TLS 强制 1.2（PS 5.1 默认可能还是 1.0/1.1）。

调过版本比较：`Compare-AppVersion` 用 `[version]` 解析，容忍 `v` 前缀，异常时返回 0（视为相同）。

---

## 环境事实与踩过的坑

**本机环境**（这些都影响命令怎么写）：

| 项 | 值 |
| --- | --- |
| 系统 | Windows 11 Build 26200 |
| 屏幕 | **3200×2000 @ 200% 缩放**（有效 1600×1000） |
| PowerShell | **5.1.19041.6456**，没有 `pwsh` |
| WebView2 Runtime | 已装，运行时上报浏览器版本 **145.0.3800.97** |
| ps2exe | 1.0.18（`build.ps1` 会自动装到 CurrentUser） |
| git | 2.55.0.windows.5 |
| `gh` CLI | ❌ **没装**（影响发布流程，见下） |

**坑清单**：

1. **`.ps1` 必须带 UTF-8 BOM**。PS 5.1 读无 BOM 的 `.ps1` 会按 GBK 解码，中文全乱、语法直接报错。
   仓库里的 `src\*.ps1` 与 `ProxyTray.ps1` 都是带 BOM 的，新建文件时注意。
2. **本仓库文件是 CRLF**。判断行尾别用 `grep -c $'\r'`（会误报 0），用 Python `re.split(r'(?<=\n)')` 更可靠。
3. **git 分支名不能带 `/`**。本环境写不了嵌套的 `refs/heads/refactor/` 目录，
   `git checkout -b refactor/v1.2.0` 会得到一个 unborn branch。用扁平名（`refactor-1.2.0`）。
4. **别用 `Remove-Item` 删构建产物**。本机有「安全删除（移到回收站）」包装器会接管 `Remove-Item`，
   回收站不可用时直接失败。改用 `[System.IO.File]::Delete()`。
5. **exe 里 `$PSCommandPath` 为空**，路径探测必须多路兜底。
6. **dot-source 后 `$PSScriptRoot` 指向模块自身**，真实入口靠 `$script:LaunchScriptPath` 传。
7. **`-noConsole` 后 `Write-Host` 转发会拖慢启动**（曾出现 13 秒启动）。用 `[Console]::WindowWidth` 探测有无控制台。
8. **从 Bash 调 `powershell` 会被安全策略拦截**，本地执行 PowerShell 请走 PowerShell 工具或直接双击脚本。
9. 本环境的 Git Bash 缺 `dirname` / `ls`，纯 shell 命令前先 `export PATH="/usr/bin:/bin:$PATH"`。

---

## 测试与调试

**DRYRUN 空转开关（跑测试必开）**

```powershell
$env:PROXYTRAY_DRYRUN = '1'
.\ProxyTray.ps1
```

所有会改动系统的动作（写注册表 / 清系统代理 / 动开机自启）都只写日志、不真执行。
跑完记得检查 `HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings` 没被动过。

**语法自检**（不运行，只解析）：

```powershell
$errs = $null
[System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errs)
```

**日志**：`ProxyTray.log`（数据目录下），超过 512 KB 自动清空。
正常启动的日志长这样：

```
[ProxyTray] mode=PS1 self=...\ProxyTray.ps1
[ProxyTray] root=...  data=...
[ProxyTray] apartment=STA
[ProxyTray] version=1.2.0  packed=False  console=True
[ProxyTray] content=...          ← packed=True 时这里是 runtime\<版本>\
[ProxyTray] dpiAware=PerMonitorV2
[ProxyTray] load 10-native.ps1   ← 依次 load 到 90-main.ps1
[ProxyTray] dpiScale=2  initSize=840x1000
[ProxyTray] ready. window @ (2336,896) size 840x1000
[ProxyTray] INIT OK, browser = 145.0.3800.97
[ProxyTray] 已是最新版本 v1.2.0
```

**单文件 exe 干净目录验证**：把 exe 单独拷到一个空目录再跑，
确认日志里出现 `packed=True`、`content=<数据目录>\runtime\1.2.0`、`INIT OK`，
且 `runtime\1.2.0\.ok` 已生成。

---

## 发布

Release 用于分发 exe。**当前卡在工具上：本机没装 `gh` CLI。**三条路：

| 方案 | 说明 |
| --- | --- |
| A. 装 `gh` + 授权 | 一次性 `winget install GitHub.cli` 然后 `gh auth login`，之后都可命令行发 |
| B. 用户给 PAT | 带 `repo` 权限的 Personal Access Token，走 GitHub REST API 上传 |
| C. 手动发 | 我产出 exe + zip + Release 文案，用户在网页上点一下 |

远程仓库已有 v1.1.0 的 Release。v1.2.0 的 Release 尚未发布。

---

## 工作流

```bash
git pull --rebase origin main                 # 开工前
git add . && git commit -m "..." && git push  # 收工
```

`.gitignore` 已排除：`dist/`、`build/`、`*.exe`、`*.log`、`config.json`、`.webview2/`、
`update_check.json`、`.workbuddy/`。

**注意 `lib/` 下的 3 个 DLL 是入库的**（`.gitignore` 刻意没写 `*.dll`）。
`app.ico` 也保留，`build.ps1` 依赖它。

---

## 四个目标的完成情况

| 目标 | 状态 | 落点 |
| --- | --- | --- |
| 1. 优化应用逻辑（拆模块） | ✅ | `src\` 下 10 个模块 + 薄入口，原 1366 行单文件已拆完 |
| 2. 打包成单 exe | ✅ | `build.ps1` 重写；内嵌资源运行时释放；422 KB 单文件 |
| 3. 4K 显示优化 | ✅ | Per-Monitor V2 + DpiScale 几何换算，本机 200% 缩放下清晰 |
| 4. 可升级架构 | ✅ | `80-update.ps1`：静默检查 + 气泡提示 + 菜单项，不自动替换 |

### 后续可做（未排期）

- **发 v1.2.0 Release**（等上面发布方案定下来）
- 更新检查目前只比版本号，可以考虑读 Release 的 body 做更新说明展示
- `ui/index.html` 是 420px 固定宽度设计，若要做真·响应式需另开工作量
- 界面目前仍是深色单一主题（`theme` 消息已有，但没接亮色实现）

---

## 给接手者的第一句话

结构已经理清、四个目标都落地了。上手建议顺序：

1. 读 `README.md`（面向用户） + 本文件（面向开发者）
2. 读 `ProxyTray.ps1`（45 行，一眼看完） → 再按 `src\` 文件名顺序读下去
3. 想改代码：**新文件记得带 UTF-8 BOM**，改完跑一遍 DRYRUN 验证
4. 改完提交，若要出包就跑 `build.ps1`，然后按「单文件 exe 干净目录验证」测一遍

> 主要改动集中在 `00-boot.ps1`（DPI + 资源释放）、`80-update.ps1`（新增）、
> `build.ps1`（重写）、`50-window.ps1`（DPI 换算）。
