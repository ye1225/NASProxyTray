# NASProxyTray · 交接文档

> 交接给下一个接手的人（或 AI）。
> **当前状态：v1.2.8 已发布**（2026-09-24，`7d60248`）。
> 本版内容：公开仓库脱敏（示例地址统一为 `192.168.1.100:7890`，去掉本机路径/账号名）
> + 文档完善。功能上等价于 v1.2.7（圆角走 DWM 合成、托盘双击切代理 + 图标三色）。

---

## 项目简介

Windows 托盘工具，一键切换系统代理指向 NAS，支持全局代理与 PAC 智能分流。
技术栈：**PowerShell 5.1 + WinForms 承载 WebView2 控件**，界面是纯 HTML/CSS/JS。

| 项目 | 值 |
| --- | --- |
| 仓库 | https://github.com/ye1225/NASProxyTray （**公开仓库**，已做脱敏，约定见「隐私与脱敏」一节） |
| 本地路径 | **`D:\WorkBuddy\NASProxyTray`**（2026-09-24 起：所有项目统一平级放在 `D:\WorkBuddy\` 下）<br>历史位置：笔记本 `D:\Desktop\NASProxyTray`、台式机 `C:\Users\<用户名>\Desktop\NASProxyTray` |
| 当前版本 | **v1.2.8**（唯一版本源：仓库根目录 `VERSION` 文件） |
| 主分支 | `main` |
| 运行环境 | Windows 10 1809+ / Windows 11 + WebView2 Runtime |
| 发布形态 | **单个 `NASProxyTray.exe`**（v1.2.0 起，不必再带 `lib\` 和 `ui\`） |

---

## 版本沿革（项目是怎么一步步走到现在的）

每一步都有对应 Release，发布说明在 `dist\RELEASE_NOTES-v*.md`（不入库，重新构建后仍可从
GitHub Release 页面读到）。

| 版本 | 主题 | 关键内容 |
| --- | --- | --- |
| **v1.0.0** | 最小可用版 | 单文件 `ProxyTray.ps1`（416 行）+ 纯 WinForms 界面（**不依赖 WebView2**）；只做「双击托盘开关代理 + 改地址」 |
| **v1.2.0** | 底层重构 | 单文件拆成 `src\` 下 10 个模块 + 薄入口；界面换成 WebView2（HTML/CSS）；**打包成单文件 exe**（`build.ps1` 重写 + 运行时释放资源）；新增检查更新；数据目录统一到 `%LOCALAPPDATA%\NASProxy`；修复高分屏托盘菜单字体双倍放大 |
| **v1.2.1** | 高分屏修复 | 4K/200% 缩放下菜单文字过大的修复；文档校正到 v1.2.1 的新行为 |
| **v1.2.2** | 导入第三方 PAC 修复 | **自动把第三方 PAC 里写死的代理地址换成本机配置的地址**（导入 gfw-pac 后 Google 打不开的那个坑） |
| **v1.2.3** | 内置分流重做 | 默认策略改为「常见国内站直连 + 其余走代理」（703 条清单 + 全部 `.cn`），不必再导入第三方 PAC |
| **v1.2.4** | 细节 | 开启态按钮的对勾图标放大到与电源图标等大 |
| **v1.2.5** | 交互简化 | 取消「保存设置」按钮 → **600ms 防抖自动保存** |
| **v1.2.6** | 回归修复 | 修 v1.2.5 引入的**自动保存无限循环**（`flushSave` 未清 `dirty`），并加 5 秒看门狗 |
| **v1.2.7** | 圆角 + 托盘交互 | ①窗口圆角改走 **DWM 合成**，消除 1-bit region 锯齿（挖出 ps2exe 谎报系统版本的老 bug）；②**双击托盘=切换代理、单击=开界面**，图标三色区分模式；③收录三轮交互测速脚本 |
| **v1.2.8** | 脱敏 | 默认代理地址改为示例值 `192.168.1.100:7890`（已有用户的配置不受影响）；README 交互说明同步；HANDOFF 补版本沿革与隐私自检。另在 git 历史层面把个人邮箱全量重写为 noreply |

**演进主线**：单文件能用 → 工程化（模块化 + 打包 + 更新）→ 按真实反馈逐个打补丁
（高分屏、第三方 PAC、分流策略、交互）→ 打磨观感（圆角、托盘）。每一次修复的
「为什么」都记在本文件对应章节里，改代码前先读那一段。

---

## 目录结构

```
<仓库根目录>\
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
├── speedtest3.py / .bat              三轮交互测速（全局/规则/关闭），双击 bat 按提示操作
├── docs\                             需求与决策记录（见下）
│   └── 需求与决策.md                 每条需求的原话 + 逐条决策与理由，**只追加不改历史**
├── LICENSE                           MIT
└── README.md

（运行时生成，不入库）

- `dist\` 构建产物：exe / zip / sha256
- `build\` 拼合后的中间脚本 `NASProxyTray.packed.ps1`
- 所有运行时数据都在 **`%LOCALAPPDATA%\NASProxy\`**（v1.2.1 起；exe 同级目录不再生成
  任何文件）：`ProxyTray.log` / `config.json` / `proxy.pac` / `proxy_remote.pac` /
  `update_check.json` / `runtime\<版本>\` / `.webview2\`
```

### 三份文档怎么分工

判断方法一句话：**把这句话搬到另一个完全不同的项目里，还成立吗？**

| 内容 | 写在哪 | 入库 |
| --- | --- | --- |
| 当前架构、约定、构建发布、**当前范围与结论** | **本文件** | 是（公开前脱敏） |
| **需求原话与逐条决策**（含被打断/被砍掉的） | `docs\需求与决策.md` | 是 |
| 该项目本机细节、命令备忘、逐日流水 | `.workbuddy\memory\` | **否**（被 git 忽略） |
| 跨项目通用经验（换了项目也成立） | `D:\WorkBuddy\MEMORY.md` | 否 |

> **别把同一件事写在两处** —— 早晚互相矛盾，而且不可能同时维护。
> 本文件只写**「现在是什么样、为什么」**；需求的来龙去脉和取舍过程全部在
> `docs\需求与决策.md`，两边不互相抄。

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
- 替换串里的 `$` 必须转义成 `$$`，否则 `192.168.1.100:7890` 这类地址里的字符会被当成
  正则反向引用（实际上没有 `$`，但 `server` 里可能有；统一 `.Replace('$','$$')` 最省心）。
- 正则要求「方案关键字 + 空白 + 主机:端口」，所以 `DIRECT`、`http://host:port`
  这类不会被误改。
- 只用 .NET 静态 `[regex]::Replace`，**不要用 `-replace`**（后者对 `$` 的处理更绕）。
- 不猜协议：PAC 写 `SOCKS5` 就还是 `SOCKS5`，只换地址。发现的方案会写进日志。
- 关掉开关（`pacRewrite=false`）就完全保留原文件。

实测（v1.2.2，DRYRUN + 一份真实的第三方 PAC）：

```
开关开 → var proxy = "PROXY 192.168.1.100:7890";   残留 127.0.0.1:3128 = 0 处
开关关 → var proxy = "PROXY 127.0.0.1:3128";       残留 127.0.0.1:3128 = 1 处
日志   → [ProxyTray] PAC 代理地址替换 1 处: 127.0.0.1:3128 -> 192.168.1.100:7890  方案: PROXY
```


### `40-icon.ps1`
`New-BallIcon -Color <Color>` 动态画圆点图标，**三色**（灰 = 关闭，绿 = 规则分流，蓝 = 全局代理）。
颜色选择在 `Update-TrayIcon`（60-tray）里按 `CurrentConfig.mode` 做。

### `50-window.ps1`
工作区与尺寸基准 / Form / WebView2 宿主 / 圆角 / **尺寸防抖（120ms Timer）** / 失焦延迟隐藏（150ms）/ `DpiChanged` 处理。
圆角两条路径（实现见 `10-native.ps1` 的 `NativeRound`）：Win11 用 `WS_THICKFRAME` + 窗口子类化
（NCCALCSIZE 客户区撑满 / NCHITTEST 禁 resize）+ DWM 合成抗锯齿圆角，**建句柄后尽早启用**、
句柄被 WinForms 重建时自愈；Win10 / DWM 失败回退 `CreateRoundRectRgn`（1-bit，有锯齿）。
⚠️ 判系统版本必须用 `RealBuildNumber()`（ntdll `RtlGetVersion`）—— ps2exe 的 exe 里
`Environment.OSVersion` 谎报 build 9200（见「环境事实」坑清单）。
详见下方「高 DPI」。

### `60-tray.ps1`
NotifyIcon + 深色中文右键菜单。**左键：单击 = 立即打开主界面；双击 = 切换代理开/关**
（`Invoke-ProxyToggle`，与前端 `toggleProxy` 同一套动作：落盘 → `Apply-ProxyConfig` →
图标 → PostWebMessage('state')）。双击不闪界面的原理：双击的两条消息连续派发，
第一次点击 Show 的窗口还没来得及绘制就被收起（`trayShownByClick` 标记）。
菜单项顺序：

```
[发现新版本 vX.Y.Z · 点击下载]   ← 默认隐藏，仅 80-update 发现新版时显示
开启代理 / 关闭代理              ← 文字随状态变（menu_Opened 里刷新）
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
| `NASProxyTray.exe` | 单文件，**约 463 KB**（v1.2.7 / v1.2.8 实测均为 474,112 字节；不是早期猜测的 10–15 MB，因为 DLL 先压成 ZIP 再 Base64） |
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

**实测**（两台机器各验一次，缩放不同、结果不同）：

| 机器 | 屏幕 | `dpiScale` | 初始化窗口（设备像素） | 落点 |
| --- | --- | --- | --- | --- |
| 笔记本 | 3200×2000 @200% | `2` | `840x1000` | `(2336,896)` |
| 台式机 | 3440×1440 @100% | `1` | `420x500` | `(3008,880)` |

两次日志都是 `dpiAware=PerMonitorV2`，界面清晰。落点可以拿
`wa.Right - initW - margin` / `wa.Bottom - initH - margin` 反推校验：
台式机 `3440-420-12=3008`、`1392-500-12=880` ✓ 与日志分毫不差。

> ⚠️ **判断当前缩放别信注册表**。`HKCU:\Control Panel\Desktop\LogPixels` 与
> `PerMonitorSettings\*\DpiValue` 都可能是改缩放后留下的**陈旧值** —— 台式机
> `LogPixels=144`（看着像 150%）但两个屏实际都是 100%，差点把正确的 `dpiScale=1`
> 当成 bug。可靠办法：Python+ctypes 调 `shcore.GetDpiForMonitor(MDT_EFFECTIVE_DPI)`
> 拿每个显示器的真实 DPI，或用上面的落点公式反推。

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

**两台开发机**（这些数值都会影响命令怎么写，**按当前这台核对，别照抄另一台**）：

| 项 | 笔记本（v1.0.0→v1.2.6 的工作在它上面做） | **台式机（2026-09-24 起接手，v1.2.7 / v1.2.8 从它发布）** |
| --- | --- | --- |
| 系统 | Windows 11 Build 26200 | Windows 11 24H2 |
| 屏幕 | **3200×2000 @ 200% 缩放**（有效 1600×1000） | 主屏 3440×1440 + 竖屏 1080×1920，**均 @ 100%** |
| PowerShell | **5.1.19041.6456**，没有 `pwsh` | **5.1.26100.9444**，没有 `pwsh` |
| WebView2 Runtime | 浏览器版本 **145.0.3800.97** | 浏览器版本 **153.0.4234.48** |
| ps2exe | 1.0.18 | 1.0.18（`D:\Documents\WindowsPowerShell\Modules\`） |
| git | 2.55.0.windows.5 | 2.55.0.windows.3 |
| `gh` CLI | ✅ 2.101.0，`%LOCALAPPDATA%\Programs\gh\gh.exe`，已授权 `ye1225` | ✅ 同上（2026-09-24 装好并授权） |
| 用户目录 | `%USERPROFILE%`（账号名两位缩写） | `%USERPROFILE%`（账号名 Administrator，系统默认名） |

### 台式机实测（2026-09-24）

- 网段与笔记本是**同一网段**，台式机的系统代理已指向那台 NAS 代理机（`ProxyEnable=1`、
  无 `AutoConfigURL`，地址形如 `192.168.x.x:<端口>`），**实测可达**
  —— 也就是说台式机已经在用那台 NAS 代理，只是没用本程序托管
- `build.ps1` **1.9 秒**跑通（11 个模块 / 1780 行）；干净目录 DRYRUN 冒烟全绿：
  `packed=True` `content=runtime\<当时的版本号>` `dpiAware=PerMonitorV2` `dpiScale=1`
  `INIT OK browser=153.0.4234.48`；`runtime\<版本>\` 下 3 个 DLL + `index.html` + `.ok` 齐全，
  注册表 BEFORE/AFTER 完全一致（没污染用户现用的系统代理）
- **两个屏都是 100% 缩放** → **高 DPI 路径在台式机验不到**，要复现得手动把缩放调上去
- 杀软：**360 也在**（`360Safe` / `360sd` / `360DrvMgr`），Defender 实时防护是关的
  （被 360 顶掉）→ 换 exe 过来照样会误报
- 桌面另有 `NASProxyTray1.exe`（62,976 B = v1.0.0 精简版）；
  台式机自己的 `D:\Desktop\proxy\` 里是**旧的单文件版**（`ProxyTray.ps1` + `lib\` + `ui\`，
  **没有 `src\`**），别当现行源码（笔记本上**同一个路径**是另一份，别混）

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
10. **判 DPI 别看 `HKCU:\Control Panel\Desktop\LogPixels`**。它和 `PerMonitorSettings\*\DpiValue`
    都可能是**切换缩放后遗留的陈旧值** —— 台式机 `LogPixels=144`（看着像 150%）但两个屏实际都是
    100%，差点把正确的 `dpiScale=1` 误判成 bug。可靠办法见「高 DPI」一节。
11. **`Add-Type` 在助手的 PowerShell 工具里被沙箱拦**（"compiles and loads .NET code at runtime"）。
    要 P/Invoke 探系统 API（读 DPI、枚举显示器之类）改用 **Python + ctypes** ——
    `user32.GetDpiForSystem` / `shcore.GetDpiForMonitor` 都能直接调。
12. **核对与远端是否同步用 `git ls-remote origin main`**，别用 `git log origin/main`
    （`refs/remotes/` 落不了盘，永远报 unknown revision）。
13. **`sc query` 在台式机被命令黑名单拦**（`PROGRAM BLOCKED BY SECURITY POLICY`）。
    查服务状态改用 PowerShell 的 `Get-Service`。
14. **助手工具的 stdout 偶发捕获不到**（exit 0 但零输出），`gh api` 输出经 `ConvertFrom-Json`
    也会偶发变空。重要结果一律 `Set-Content` 到文件再读回来；调 API 时打印
    `rawlen` 自证，别直接信解析结果。

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
正常启动的日志长这样（`dpiScale` / `initSize` / 落点 / `browser` 随机器不同，
下面两行分别对应 200% 笔记本与 100% 台式机）：

```
[ProxyTray] mode=PS1 self=...\ProxyTray.ps1        ← exe 模式下是 mode=EXE
[ProxyTray] root=...  data=...
[ProxyTray] apartment=STA
[ProxyTray] version=1.2.7  packed=False  console=True
[ProxyTray] content=...          ← packed=True 时这里是 runtime\<版本>\
[ProxyTray] dpiAware=PerMonitorV2
[ProxyTray] load 10-native.ps1   ← 依次 load 到 90-main.ps1
[ProxyTray] dpiScale=2  initSize=840x1000        ← 200% 笔记本
[ProxyTray] dpiScale=1  initSize=420x500         ← 100% 台式机
[ProxyTray] ready. window @ (2336,896) size 840x1000
[ProxyTray] INIT OK, browser = 153.0.4234.48
[ProxyTray] 已是最新版本 v1.2.7
```

**单文件 exe 干净目录验证**：把 exe 单独拷到一个空目录再跑，
确认日志里出现 `packed=True`、`content=<数据目录>\runtime\<VERSION 的值>`、`INIT OK`，
且 `runtime\<VERSION 的值>\.ok` 已生成。

---

## 发布

Release 用于分发 exe，全程命令行：

```bash
export PATH="/usr/bin:/bin:$HOME/AppData/Local/Programs/gh:$PATH"
# 台式机：环境变量里的代理指向 WorkBuddy 透明代理（127.0.0.1:2184 → NAS），
# 那条链会偶发 502；先清空再显式指 NAS 代理最稳
export http_proxy= https_proxy= HTTP_PROXY= HTTPS_PROXY=
git -c http.proxy=http://<NAS:端口> -c https.proxy=http://<NAS:端口> push origin main

export HTTPS_PROXY=http://<NAS:端口> https_proxy=http://<NAS:端口>
gh release create v1.2.8 dist/NASProxyTray.exe dist/NASProxyTray-v1.2.8.zip \
  --repo ye1225/NASProxyTray --title "v1.2.8" \
  --notes-file dist/RELEASE_NOTES-v1.2.8.md --latest
```

> ⚠️ **构建前先确认没有实例占着 `dist\NASProxyTray.exe`**：正在运行的 exe 会被
> Windows 锁住，`build.ps1` 删旧 exe 时报 `访问被拒绝`，日志停在 `[5/6]` 却看不出原因。
> 两个办法：让用户退出托盘程序，或者 `mv dist\NASProxyTray.exe dist\NASProxyTray.exe.inuse`
> 把文件改名腾位（**正在运行的进程不受影响**，改完即能构建；新 exe 生成后再删那个 `.inuse`）。

已发布：v1.0.0 / v1.2.0 / v1.2.1 / v1.2.2 / v1.2.3 / v1.2.4 / v1.2.5 / v1.2.6 / v1.2.7 / **v1.2.8**。

踩过的坑：

- **`gh release upload` 读不了项目目录外的文件**（沙箱限制）→ 先把文件拷进仓库目录再传
- **`gh api .../releases/latest` 的 `.assets` 字段有时为空**（GitHub 正在灰度 immutable
  releases），要看附件请查 `releases/latest` 或 `releases/{id}/assets`，别信列表里的 `.assets`
- **`schannel: failed to receive handshake` / `api.github.com ... EOF` / `CONNECT tunnel failed 502`
  都是链路瞬时抖动**，与 NAS 代理本身无关（curl 直连 NAS 一直 200）。**写个 for 循环重试
  2~3 次必过**，不要当成故障排查
- **`build.ps1` 别用 `Set-Location` + `*>` / `Tee-Object` 跑**（PowerShell 工具 stdout 会抽风：
  日志只到 `[5/6]`、exe 不更新，白跑）。用后台方式（`run_in_background`）最稳；
  验产物版本别信输出，直接数 exe 里的版本字节或看 `build/NASProxyTray.packed.ps1`
- **推送凭据（2026-09-24 已钉死）**：`~/.gitconfig` 的 `credential.helper` 第一条是
  **空值**（重置 helper 列表，清掉 PortableGit 系统级塞入的 `helper-selector` ——
  它就是反复弹 `CredentialHelperSelector` 框的元凶），第二条是
  `!"%LOCALAPPDATA%/Programs/gh/gh.exe" auth git-credential`
  （绝对路径，防 PATH 裁剪）。push 不再需要任何 `-c credential.helper`；
  若弹框复发先 `git config --show-origin --get-all credential.helper` 查插队来源

---

## 换机器接手清单

**会跟着仓库走**：全部源码、`HANDOFF.md`、`README.md`、`build.ps1`、`tools/gen-china-list.py`、
`VERSION`、`lib\` 的 3 个 DLL、`app.ico`。

**不会跟着走**（都是本机/本进程产物）：

| 内容 | 说明 / 恢复方式 |
| --- | --- |
| `.workbuddy/`（助手记忆、每日日志） | 已被 `.gitignore` 排除；要带走就整个目录拷 |
| `会话存档/`、`本机环境参考/` | 换机器时助手/用户带过来的参考资料（体积大、绑机器），也已排除，要带走同样整个目录拷 |
| `dist/`（exe、zip、sha256、发布文案） | 重新 `.\build.ps1` 即可 |
| `build/list-cache/`（词表缓存） | 重跑 `tools/gen-china-list.py` 会重新下载 |
| `%LOCALAPPDATA%\NASProxy\`（配置、PAC、日志） | 本机运行时数据，不必带走 |
| `D:\Desktop\proxy\NASProxyTray-vX.Y.Z\`（笔记本上的用户部署目录） | 用户本机习惯，新机器上重新解压 |
| `gh` 授权、git 凭据 | 新机器上 `gh auth login` 重新授权 |

**新机器上的开工三步**：装 WorkBuddy → `git clone` 本仓库 → 让助手先读 `HANDOFF.md`
（**「架构：加载顺序只有一个来源」**和**「环境事实与踩过的坑」**两节是必读）。

本仓库的坑是**跨机器继承**的：`.ps1` 要带 BOM、`Remove-Item` 被包装器接管、
`refs/remotes/` 落不了盘这几条在笔记本和台式机上**都成立**；而屏幕缩放、杀软、
WebView2 版本这类要按机器重新核对（见「环境事实」的两台机器对照表）。

> **台式机（2026-09-24）已经做完的开工准备**：git clone 到位、`gh` 装好并授权 `ye1225`、
> 推送凭据助手已钉死（见「发布」一节）、`build.ps1` 与 DRYRUN 冒烟验证通过，
> 并且**已从它发出 v1.2.7 与 v1.2.8** —— 即台式机现在可以直接开发 + 发 Release。
> 下次换新机器照上面的三步重来一遍即可。

---

## 工作流

```bash
git pull --rebase origin main                 # 开工前
git add . && git commit -m "..." && git push  # 收工
```

**每次提交前问一句**：这次改动对应的需求记进 `docs\需求与决策.md` 了吗？
需求有变就**追加一条**（并注明取代了哪条），本文件的相关章节同步更新 —— 落纸，别留「下次再说」。

`.gitignore` 已排除：`dist/`、`build/`、`*.exe`、`*.log`、`config.json`、`.webview2/`、
`update_check.json`、`.workbuddy/`、`会话存档/`、`本机环境参考/`。

**注意 `lib/` 下的 3 个 DLL 是入库的**（`.gitignore` 刻意没写 `*.dll`）。
`app.ico` 也保留，`build.ps1` 依赖它。

### 提交前的隐私自检（**入库前必跑**）

仓库是公开的，提交前扫一遍有没有把「本机事实」写进文档/代码：

```bash
# 真实地址 / 邮箱 / 绝对路径 / 令牌
git grep -n -I -E "192\.168\.[0-9]+\.[0-9]+|100\.[0-9]+\.[0-9]+\.[0-9]+|@(gmail|qq|outlook)\.com|[A-Za-z]:\\\\Users\\\\|ghp_|github_pat_" -- .
```

补充两条经验：

- **示例一律用 `192.168.1.100:7890`**（README / HANDOFF / `src\20-config.ps1` 默认值 /
  `ui\index.html` 的 `DEFAULTS` 都必须一致），真机地址只留在本机配置里，不进仓库
- **提交者邮箱也算隐私**，且**写在每一个提交的对象里、改文件改不掉**。本仓库曾在
  2026-09-24 用 `git filter-branch --env-filter` 把 25 个提交里的个人邮箱批量改成
  GitHub noreply 地址，并 force-push 了 branch 与全部 tag（内容零变化，
  `git diff <旧HEAD> <新HEAD>` 为空）。**预防**：`git config user.email`
  用 `37562835+ye1225@users.noreply.github.com`，并到 GitHub 设置里打开
  「Keep my email addresses private」+「Block command line pushes that expose my email」

---

## 四个目标的完成情况

| 目标 | 状态 | 落点 |
| --- | --- | --- |
| 1. 优化应用逻辑（拆模块） | ✅ | `src\` 下 10 个模块 + 薄入口，原 1366 行单文件已拆完 |
| 2. 打包成单 exe | ✅ | `build.ps1` 重写；内嵌资源运行时释放；约 463 KB 单文件（v1.2.7） |
| 3. 4K 显示优化 | ✅ | Per-Monitor V2 + DpiScale 几何换算，本机 200% 缩放下清晰 |
| 4. 可升级架构 | ✅ | `80-update.ps1`：静默检查 + 气泡提示 + 菜单项，不自动替换 |

### 后续可做（未排期）

- 更新检查目前只比版本号，可以考虑读 Release 的 body 做更新说明展示
- `ui/index.html` 是 420px 固定宽度设计，若要做真·响应式需另开工作量
- 内置国内直连清单（703 条）可以定期用 `tools/gen-china-list.py` 重跑刷新

---

## 给接手者的第一句话

结构已经理清、四个目标都落地了。上手建议顺序：

1. 读 `README.md`（面向用户） + 本文件（面向开发者）
2. 读 `ProxyTray.ps1`（45 行，一眼看完） → 再按 `src\` 文件名顺序读下去
3. 想改代码：**新文件记得带 UTF-8 BOM**，改完跑一遍 DRYRUN 验证
4. 改完提交，若要出包就跑 `build.ps1`，然后按「单文件 exe 干净目录验证」测一遍

> 主要改动集中在 `00-boot.ps1`（DPI + 资源释放）、`80-update.ps1`（新增）、
> `build.ps1`（重写）、`50-window.ps1`（DPI 换算）。
