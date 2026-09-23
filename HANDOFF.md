# NASProxyTray · 交接文档

> 交给 WorkBuddy 的完整上下文。请先读 README.md、本文件、ProxyTray.ps1，再动手。

---

## 项目简介

Windows 托盘工具，一键切换系统代理指向 NAS，支持全局代理和智能分流（PAC）。
技术栈：PowerShell 5.1 + WinForms 承载 WebView2 控件，UI 是纯 HTML/CSS/JS。

- **仓库**：https://github.com/ye1225/NASProxyTray
- **本地路径**：D:\Desktop\NASProxyTray
- **当前版本**：v1.1.0（HEAD: 53f77be）
- **运行环境**：Windows 10 1803+ / Windows 11，需要 WebView2 Runtime（系统一般自带）

---

## 目录结构

```
D:\Desktop\NASProxyTray\
├── lib/                              WebView2 运行时依赖（3 个 DLL）
│   ├── Microsoft.Web.WebView2.Core.dll
│   ├── Microsoft.Web.WebView2.WinForms.dll
│   └── WebView2Loader.dll
├── ui/
│   └── index.html                    WebView2 界面（420px 固定宽度设计）
├── .gitignore
├── app.ico                           程序图标
├── build.ps1                         构建脚本（注入 icon + ps2exe 打包）
├── debug.bat                         调试入口
├── LICENSE                           MIT
├── ProxyTray.ps1                     主脚本（约 1000 行）
└── README.md
```

---

## 主脚本 ProxyTray.ps1 结构详解

脚本按"先环境，后业务"的顺序组织。以下按代码顺序列出主要段落。

### 启动阶段（1–200 行左右）

1. **自身路径探测**：兼容 `.ps1` 直跑和 `ps2exe` 打包 exe 两种模式，分别从 `$PSCommandPath`、命令行第 0 项、进程主模块三处探测
2. **STA 线程重开**：WinForms + OpenFileDialog 需要 STA，非 STA 时自动重启自己（用 `$env:PROXYTRAY_STA_RETRY` 防无限重启）
3. **单实例互斥锁**：`Local\NASProxyTray_SingleInstance`，防双击开两个托盘
4. **根目录 / 数据目录**：
   - `$root` = exe 所在目录（只读内容：lib、ui、app.ico）
   - `$script:DataDir` = 探测可写性，不可写则退到 `%LOCALAPPDATA%\NASProxy`
   - **这是单 exe 打包后资源释放目录的天然位置，可复用**
5. **日志**：遮蔽 `Write-Host`，同时写 `ProxyTray.log`，限制 512KB 自动清空
6. **加载 DLL**：`SetDllDirectory($lib)` + `$env:PATH` 前置，然后 `Add-Type -Path` 加载两个托管 DLL，WebView2Loader.dll 靠 SetDllDirectory 找到
7. **Win32 API**：NativeLoader（SetDllDirectory）/ NativeDrag（窗口拖动）/ NativeRound（圆角 + DWM）/ WinINet（刷新代理）/ IconNative（销毁图标）
8. **深色菜单渲染器**：编译 C# 类 `DarkMenuRenderer`，失败则回退默认

### 代理引擎（约 400–700 行）

| 函数 | 作用 |
| --- | --- |
| `Get-DefaultProxyConfig` | 返回默认配置对象（server / port / override / mode / pacSource / pacDomains / localPacPath / remotePacUrl / autoStart / enabled） |
| `Get-ProxyConfig` | 从 `%DataDir%\config.json` 读配置，合并默认值 |
| `Save-ProxyConfig` | 写 `config.json` |
| `Set-GlobalProxy` | 注册表写 ProxyEnable=1 + ProxyServer + ProxyOverride |
| `Set-PacProxy` | 启动本地 PAC HTTP 服务，注册表写 AutoConfigURL |
| `Clear-SystemProxy` | 清空注册表代理项 |
| `Start-PacServer` | 后台 runspace 启 TcpListener，服务 `http://127.0.0.1:<随机端口>/proxy.pac` |
| `Stop-PacServer` | 停服务 |
| `Build-BuiltinPac` | 根据域名列表生成 PAC 内容 |
| `Apply-ProxyConfig` | 根据 config 应用代理（全局 / PAC / 关闭） |
| `Test-ProxyConn` | TcpClient 连接测试，返回延迟毫秒 |
| `Set-AutoStart` / `Get-AutoStart` | 写 `Startup\NASProxy.lnk` 快捷方式（不是注册表 Run） |

### 托盘 + 窗口（约 700–900 行）

- `$tray`：NotifyIcon，图标用 `New-BallIcon` 动态画圆点（灰 / 绿）
- `$menu`：右键菜单（显示/隐藏、开发者工具、立即清除代理、复位窗口位置、退出）
- `$form`：WinForms 无边框窗口，初始位置右下角，尺寸随 HTML 内容变化
- **尺寸防抖**：前端上报 size 后，Timer 120ms 合并多次变化
- **Deactivate 隐藏**：失焦 150ms 后隐藏
- **圆角**：优先 DWM（Win11），失败退 `SetWindowRgn`

### WebView2 初始化 + 消息（约 900–末尾）

初始化成功后：
- 关闭默认右键菜单和状态栏
- 注入 `$injectJs`（阻止所有 CSS 动画、隐藏滚动条、`.title-bar` 拖拽、Escape 隐藏、上报尺寸）
- 注册 `WebMessageReceived` 处理前端消息

---

## 前后端通信协议

**前端 → 宿主**（通过 `window.chrome.webview.postMessage`，JSON 字符串）：

| action | 参数 | 作用 |
| --- | --- | --- |
| `startDrag` | 无 | 拖动窗口（点 `.title-bar` 触发） |
| `hide` | 无 | 隐藏窗口（Escape 键） |
| `size` | `w, h` | 上报界面实际宽高 |
| `theme` | `dark` | 通知系统深色模式 |
| `getConfig` | 无 | 请求配置 |
| `saveConfig` | `config` | 保存配置 |
| `toggleProxy` | `enabled, config?` | 开关代理 |
| `setAutoStart` | `enabled` | 切换自启动 |
| `browseFile` | 无 | 弹文件选择框（选 PAC） |
| `testConnection` | `server, port` | TCP 连接测试 |
| `resetConfig` | 无 | 恢复默认 |

**宿主 → 前端**：

| type | 数据 | 触发时机 |
| --- | --- | --- |
| `config` | `config` | getConfig / setAutoStart / resetConfig 后 |
| `saved` | `ok, msg, config` | saveConfig 后 |
| `state` | `enabled, ok, msg, mode, server, port` | toggleProxy 后 |
| `filePicked` | `path` | 用户选完 PAC 文件 |
| `connResult` | `ok, latency` | 连接测试返回 |

---

## 当前问题清单（用户已确认）

1. **无法打包成单个 exe**：`build.ps1` 目前只把 `app.ico` 转 Base64 注入，**没处理 `lib/` 和 `ui/`**。发布形态是 `exe + lib/ + ui/` 三个并列，体验差
2. **4K 显示效果待优化**：用户未描述具体现象（模糊/太小/错位），需要 WorkBuddy 先问清楚再动手
3. **逻辑可优化**：主脚本 1000 行，可按职责拆分
4. **缺可升级架构**：目前无"检查更新"能力

---

## 四个目标详细说明

### 目标 1：优化应用逻辑

主脚本已经超过 1000 行，建议按职责拆分：
- `core.ps1`：配置 + 代理引擎 + PAC 服务
- `tray.ps1`：托盘 + 菜单 + 图标
- `webview.ps1`：WebView2 宿主 + 消息处理
- `ProxyTray.ps1`：入口，dot-source 上面三个

**注意**：拆分后 `build.ps1` 的 ps2exe 打包要调整（ps2exe 只打包单个 .ps1，需要把其他文件也用 dot-source 引进来，或者全部内嵌）。

### 目标 2：打包成单 exe

**当前 build.ps1 逻辑**：
1. 读 `app.ico` → Base64 → 替换 `ProxyTray.ps1` 里的 `$IconBase64`
2. `Invoke-ps2exe` 打包

**需要改成**：
1. 读 `app.ico` + `lib/*.dll` + `ui/index.html` → 全部 Base64 放进一个 JSON
2. 替换 `ProxyTray.ps1` 里的 `$ResourcesJson` 占位符
3. `ProxyTray.ps1` 启动时把资源释放到 `$script:DataDir\runtime\`（脚本已有 DataDir 探测逻辑，直接复用）
4. 用版本号做缓存标记，改资源时更新版本号触发重新释放
5. DLL 加载路径从 `$root\lib` 改成 `$script:DataDir\runtime\lib`
6. HTML 路径同理改成 runtime 下的

**关键坑**：
- WebView2Loader.dll 是非托管 DLL，要 `SetDllDirectory`，脚本里已有
- exe 会膨胀到 10–15 MB（Base64 有 33% 膨胀）
- 首次启动慢几百毫秒（解码 + 写文件），之后靠标记跳过
- 如果用户把 exe 放到只读目录，释放目录自动退到 `%LOCALAPPDATA%`（脚本已做）

### 目标 3：4K 分辨率显示优化

**需要先问用户具体现象**：
- 界面糊 / 模糊？
- 界面元素太小？
- 界面错位 / 显示不全？

**可能的方向**：
- WinForms 启用 Per-Monitor V2 DPI 感知：`Application.SetHighDpiMode([HighDpiMode]::PerMonitorV2)`，要在创建任何窗口前调用
- 或用 app.manifest 声明 DPI aware
- UI 侧用相对单位或 `clamp()` 响应系统缩放
- WebView2 控件本身的 DPI 行为：`CoreWebView2Controller.RasterizationScale`

### 目标 4：可升级架构

**两种理解，需先跟用户对齐**：
- A. 应用自身能自动升级（检查 GitHub Releases，下载新版，替换自己）
- B. 代码结构可演进（也就是目标 1 的延伸）

如果是 A，先做"检查更新 + 提示"这一层，不做静默替换。

---

## 建议执行顺序

```
1. 优化应用逻辑（拆模块）
   ↓ 结构清楚后
2. 打包成单 exe
   ↓ 打包流程变了，需要重新测
3. 4K 显示优化
   ↓ 视觉调完
4. 可升级架构
   ↓ 依赖"当前版本稳定"
```

理由：
- 先拆模块，后面所有改动在新结构上做，不返工
- 打包会改 ProxyTray.ps1（注入资源），在拆完模块后做更顺
- 4K 调整不涉及逻辑
- 升级架构需要稳定基线

---

## 测试环境

- Windows 11 Build 26200
- PowerShell 5.1（没有 pwsh）
- WebView2 Runtime 已装 153.0.4234.32
- ps2exe 未装，`build.ps1` 会自动装
- 首次跑前需：`Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force`

---

## 工作流

- 主分支 `main`（曾叫 master，已改名）
- `.gitignore` 已排除：`*.exe`、`.vscode/`、`.idea/`、`*.tmp`、`*.log`、`config.json`
- `app.ico` **保留**（build.ps1 依赖它）
- Release 已发 v1.1.0，exe 通过 GitHub Release 分发
- 日常命令：
  ```
  git pull --rebase origin main   # 开工前
  git add . && git commit -m "..." && git push   # 收工
  ```

---

## 运行调试

**启动**：
```powershell
powershell -ExecutionPolicy Bypass -File .\ProxyTray.ps1
```
或双击 `debug.bat`。

**日志位置**（脚本用 Write-Host 覆写，输出到文件）：
- 优先：`D:\Desktop\NASProxyTray\ProxyTray.log`
- 兜底：`%LOCALAPPDATA%\NASProxy\ProxyTray.log`

**构建 exe**：
```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```
产物：`NASProxyTray.exe`（当前形态还需要 `lib/` 和 `ui/` 在旁边）

---

## 第一句话

请先读以下文件理解现状，然后给一个执行计划，确认后再动手：

1. `README.md`
2. `HANDOFF.md`（本文件）
3. `ProxyTray.ps1`
4. `build.ps1`
5. `ui/index.html`

确认计划后再改代码。改代码时优先小步验证，每完成一个子目标就提交一次。