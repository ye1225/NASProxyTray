# ProxyTray

一个常驻托盘的 Windows 系统代理切换工具。左键托盘图标即可一键开启/关闭系统代理，
内置 WebView2 界面用于配置规则、切换皮肤。

![界面截图](docs/screenshot.png)

---

## ✨ 功能

- 🔄 **一键切换系统代理**：托盘图标左键点击即可开关，状态实时显示
- 🎨 **WebView2 界面**：配置面板 / 皮肤切换
- 📋 **PAC 规则支持**：按域名分流，不是无脑全局代理
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

1. 到 [Releases](../../releases/latest) 下载 `ProxyTray-v1.1.0.zip`
2. 解压到任意目录（**不要放在需要管理员权限的目录**，比如 `C:\Program Files`）
3. 双击 `ProxyTray.exe`
4. 托盘出现图标 → 左键点击 = 开关代理

> 解压后**不要单独移动 exe**，`lib\` 和 `ui\` 目录要跟它在一起。

### 方式二：从源码运行

```powershell
git clone https://github.com/你的用户名/ProxyTray.git
cd ProxyTray
.\debug.bat
```

`debug.bat` 会把所有输出同时写到 `run.log`，方便排查问题。

---

## 🖱️ 使用方法

| 操作 | 效果 |
|---|---|
| **左键单击**托盘图标 | 开启 / 关闭系统代理（图标变色 = 已开启） |
| **右键单击**托盘图标 | 打开菜单（设置 / 查看日志 / 退出） |
| 双击托盘图标 | 打开配置界面 |

### 首次使用建议

1. 右键托盘图标 → **设置**
2. 填写你的代理服务器地址和端口
3. 保存后左键点击图标即可生效

> 开启后可在「Windows 设置 → 网络和 Internet → 代理」里看到自动配置已写入。

---

## 🛠️ 开发者：如何打包成 exe

### 环境准备

```powershell
# 安装 ps2exe（只需一次）
Install-Module ps2exe -Scope CurrentUser -Force
```

### 一键打包

```powershell
.\build.ps1
```

产物在 `dist\ProxyTray.exe`，把它和 `lib\`、`ui\` 一起分发。

### 目录结构

```
ProxyTray/
├── ProxyTray.ps1          # 主程序（源码）
├── build.ps1              # 一键打包脚本
├── debug.bat           # 开发调试入口
├── ui/                    # WebView2 界面资源（HTML/CSS/JS）
├── lib/                   # WebView2 运行时 DLL（随程序分发）
├── assets/                # 图标等静态资源
├── dist/                  # 打包产物（不提交 git）
└── .gitignore
```

---

## ❓ 常见问题

<details>
<summary><b>双击没反应 / 托盘没图标</b></summary>

先看目录里有没有 `run.log`，或者右键托盘前先跑一次 `debug.bat` 看报警。
最常见原因是 **缺少 WebView2 Runtime**，见上方说明。
</details>

<details>
<summary><b>界面白屏</b></summary>

同样先确认 WebView2 Runtime 已安装。若已安装仍白屏，删除 `%LOCALAPPDATA%\ProxyTray\WebView2`
目录（清缓存）后重试。
</details>

<details>
<summary><b>报错 "找不到 WebView2Loader.dll"</b></summary>

说明 `lib\` 目录没跟 exe 放在一起，或者放在了一起但被你单独挪走了 exe。
**exe、lib\、ui\ 必须保持同目录。**
</details>

<details>
<summary><b>代理开关点了没效果</b></summary>

1. 确认程序以当前用户权限运行（不要用管理员，系统代理是按用户存的）
2. 检查被杀毒软件/公司组策略拦截了注册表写入
</details>

<details>
<summary><b>想彻底卸载</b></summary>

程序本身免安装，删除文件夹即可。另外删除残留配置：
`%LOCALAPPDATA%\ProxyTray\`
</details>

---

## 📄 许可证

[MIT](LICENSE) © 2026 [你的名字]