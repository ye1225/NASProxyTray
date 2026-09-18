# NASProxyTray

Windows 10 / 11 系统托盘小工具，一键开启 / 关闭系统代理，指向你的 NAS（或任意 HTTP 代理）。双击图标即切换，右键可进入图形设置界面。


## 环境要求

- Windows 10 (1709+) / Windows 11
- PowerShell 5.1（系统自带）
- 从源码构建需安装 `ps2exe`（`build.ps1` 会自动安装）

  
## 功能

- 双击托盘图标切换代理
- 右键图形配置 IP / 端口 / 例外
- 配置保存在 %APPDATA%\NASProxyTray\config.json
<img width="450" height="298" alt="1" src="https://github.com/user-attachments/assets/ddaf490a-fb17-4274-8571-33a1a7d720a3" />


## 构建

powershell -ExecutionPolicy Bypass -File .\build.ps1

## 许可证

MIT
