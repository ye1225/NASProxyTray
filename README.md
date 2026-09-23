# NASProxyTray
一个常驻托盘的 Windows 系统代理切换工具，可一键开启/关闭系统代理。双击状态栏图标启动主界面。
内置 WebView2 界面用于配置规则、切换皮肤。


<img width="442" height="524" alt="image" src="https://github.com/user-attachments/assets/3f37f62f-542f-4326-9784-a318891cea6e" />



---

## ✨ 功能

- 🔄 **一键切换系统代理**：左键双击启动主界面
- 🎨 **WebView2 界面**：配置面板 / 皮肤切换
- 📋 **PAC 规则支持**：按域名分流，不是无脑全局代理
- 🖥️ **高 DPI 清晰**：声明 Per-Monitor V2，4K / 200% 缩放下界面不再发虚
- 🔔 **检查更新**：启动后静默检查新版本，托盘菜单里也能手动检查
- 📦 **单文件**：v1.2.0 起依赖全部打进 exe，不必再带 `lib\` 与 `ui\`
- 🪶 **轻量常驻**：托盘运行，占用低
- 🚀 **免安装**：绿色版，解压即用

---

## 📋 系统要求

| 项目 | 要求 |
|---|---|
| 操作系统 | Windows 10 1809 及以上 / Windows 11 |
| 运行时 | **Microsoft Edge WebView2 Runtime**（见下方说明） |
| 从源码运行 | PowerShell 5.1（系统自带） |

### ⚠️ 关于 WebView2 Runtime

本程序的界面依赖 WebView2 运行时。**大多数 Win11 和已安装新版 Edge 的 Win10 已经自带**。
如果没有，界面会白屏或报错，请安装一次（装完永久有效）：

👉 **下载地址**：<https://go.microsoft.com/fwlink/p/?LinkId=2124703>

> 装完不需要重启，直接再打开程序即可。

---

## 🚀 快速开始（普通用户）

### 方式一：下载免安装版（推荐）

1. 到 [Releases](../../releases/latest) 下载 `NASProxyTray-v1.2.1.zip`
2. 解压到任意目录（**不要放在需要管理员权限的目录**，比如 `C:\Program Files`）
3. 双击 `NASProxyTray.exe`
4. 托盘出现图标 → 左键双击 = 打开界面

> **v1.2.0 起是单文件**：`lib\` 与 `ui\` 已经打进 exe 内部，首次运行会释放到
> `%LOCALAPPDATA%\NASProxy\runtime\<版本>\`，之后启动直接复用。
> 所以 exe 可以随便移动、随便改名，不必再和目录一起带着走。
>
> **v1.2.1 起所有运行时数据都放在 `%LOCALAPPDATA%\NASProxy\`**（日志、配置、
> WebView2 缓存、更新检查记录），exe 同级目录不再生成任何文件。从旧版本
> 升级时，程序会自动迁移配置并清理 exe 目录里的遗留杂物。

## 🖱️ 使用方法

| 操作 | 效果 |
|---|---|
| **左键双击**托盘图标 | 打开配置界面（图标变色 = 已开启） |
| **右键单击**托盘图标 | 打开菜单（设置 / 查看日志 / 退出） |


### 首次使用建议

1. 左键双击图标
2. 填写你的代理服务器地址和端口
3. 保存后左键点击顶部图标即可生效

> 开启后可在「Windows 设置 → 网络和 Internet → 代理」里看到自动配置已写入。

---

## 🛠 开发

### 从源码运行

```powershell
git clone https://github.com/ye1225/NASProxyTray.git
cd NASProxyTray
.\ProxyTray.ps1
```

`ProxyTray.ps1` 只是一个薄入口，真正的实现按**文件名顺序**放在 `src\` 下：

| 模块 | 职责 |
|---|---|
| `00-boot` | 路径探测 / STA / 单实例 / 数据目录 / 日志 / DPI 感知 / 内嵌资源释放 |
| `10-native` | 原生互操作（DLL 目录、窗口拖动、圆角、WinINet、图标、深色菜单渲染器） |
| `20-config` | 共享状态与配置路径 / 刷新系统代理设置 / 默认值 / 读取 / 保存 |
| `30-proxy` | 注册表写入、本地 PAC 服务、内置 PAC 生成、连通测试、开机自启 |
| `40-icon` | 托盘图标绘制 |
| `50-window` | 窗口尺寸与定位 / Form / WebView2 宿主 / 圆角 / 尺寸防抖 |
| `60-tray` | NotifyIcon / 深色中文右键菜单 / 窗口显隐 |
| `70-message` | 注入脚本 / WebView2 初始化 / 前端消息分发 |
| `80-update` | 检查更新 |
| `90-main` | Form 生命周期 / 消息循环 / 兜底清理 |

> 加载顺序只有一个来源：`src\` 里 `*.ps1` 的文件名排序。
> 开发时 dot-source，打包时按同一顺序拼合成单文件，两种模式行为一致。

### 打包成单文件 exe

```powershell
.\build.ps1
```

产物在 `dist\`：`NASProxyTray.exe`（含全部依赖）、`NASProxyTray-v<版本>.zip`、`NASProxyTray.exe.sha256`。

**版本号只有一个来源**：仓库根目录的 `VERSION` 文件。构建时会把它注入到脚本内置常量里
（单文件运行时读不到 `VERSION`），界面页脚也由宿主下发，不再各处写死。

### 调试与测试

- `debug.bat`：带日志运行，输出同时写进 `run.log`
- **空转开关**：设置环境变量 `PROXYTRAY_DRYRUN=1` 后再运行，所有会改动系统的动作
  都会空转——不写注册表、不清系统代理、不动开机自启，只在日志里留痕。
  跑测试时请务必打开，避免污染真实系统设置。

### 运行时数据

默认放在 exe 同级目录；目录不可写时自动退到 `%LOCALAPPDATA%\NASProxy`。

| 文件 | 说明 |
|---|---|
| `config.json` | 用户配置 |
| `proxy.pac` / `proxy_remote.pac` | PAC 内容与远端缓存 |
| `ProxyTray.log` | 运行日志（超过 512 KB 自动清空） |
| `update_check.json` | 检查更新的节流记录 |
| `runtime\<版本>\` | 单文件 exe 释放出来的 `lib\` 与 `ui\` |
| `.webview2\` | WebView2 用户数据 |
