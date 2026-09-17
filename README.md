# WiFi密码查询工具 / WiFi Password Query Tool

## 文件说明 / File Description

| 文件名 / Filename | 说明 / Description |
|------------------|-------------------|
| `wifi_password_tool_auto.bat` | **统一版（推荐）** 自动识别系统语言，动态匹配 netsh 关键词 / **Unified (Recommended)** Auto-detect language, dynamic netsh matching |
| `wifi_password_tool.bat` | 中文版WiFi密码查询工具 / Chinese version |
| `select_wifi_passwd_optimized.bat` | 英文版WiFi密码查询工具 / English version |
| `WiFi密码查询工具使用说明.md` | 中文详细使用说明 / Chinese detailed manual |
| `WiFi_Password_Query_Tool_Manual.md` | 英文详细使用说明 / English detailed manual |
| `LICENSE` | MIT 开源协议 / MIT License |

## 快速开始 / Quick Start

### 推荐方式（自动识别语言）/ Recommended (Auto Language Detection)
1. 右键点击 `wifi_password_tool_auto.bat` / Right-click on `wifi_password_tool_auto.bat`
2. 选择"以管理员身份运行" / Select "Run as administrator"
3. 脚本自动识别系统语言并显示对应界面 / Auto-detects system language and shows corresponding interface
4. 也可强制指定语言：`wifi_password_tool_auto.bat zh` 或 `en` / Or force language: `wifi_password_tool_auto.bat zh` or `en`

### 中文用户 / For Chinese Users
1. 右键点击 `wifi_password_tool.bat`
2. 选择"以管理员身份运行"
3. 按照提示操作

### English Users
1. Right-click on `select_wifi_passwd_optimized.bat`
2. Select "Run as administrator"
3. Follow the prompts

## 多语言适配说明 / Multi-language Adaptation

### 自动语言检测 / Auto Language Detection
`wifi_password_tool_auto.bat` 按以下顺序检测系统语言 / detects system language in this order:
1. 命令行参数（`zh`/`en`/`ja`/`ko`/`de`/`fr` 等）/ Command line argument
2. 注册表 `HKCU\Control Panel\International\LocaleName` / Registry LocaleName
3. `wmic os get oslanguage` LCID 映射 / wmic OSLanguage LCID mapping
4. `LANG` 环境变量 / LANG environment variable
5. 默认英文 / Default to English

### 动态 netsh 关键词匹配 / Dynamic netsh Keyword Matching
- **配置文件解析**：中英文类型关键词精确匹配 + 通用模式后备（提取最后一个 `:` 后内容），支持所有语言的 netsh 输出
- **密码提取**：18 种语言关键词匹配（中/英/日/韩/德/法/俄/西/意/葡/波/荷/土/匈/瑞/芬/丹/挪）+ 通用后备（行同时包含 `key` 和 `content`）
- **界面语言**：中文系统显示中文界面，其他语言系统显示英文界面（netsh 解析仍支持多语言）

## 功能特点 / Features

### 基础功能 / Basic Features
- 🔍 查看所有已保存的WiFi配置（带序号）/ View all saved WiFi configurations (with index numbers)
- 🔢 支持按序号快速选择WiFi / Support quick WiFi selection by index
- ⌨️ 支持直接输入WiFi名称 / Support direct WiFi name input
- 🔑 查询指定WiFi的密码 / Query password for specified WiFi
- 📋 自动复制密码到剪贴板 / Auto-copy password to clipboard
- 🌐 支持中文和英文界面 / Support Chinese and English interfaces
- 🤖 自动识别系统语言（v3.0）/ Auto-detect system language (v3.0)
- 🔧 动态匹配 netsh 多语言输出关键词 / Dynamic multi-language netsh keyword matching

### 导出功能 / Export Features
- 📤 批量导出WiFi密码：支持自选导出范围（全部/指定编号）和格式（TXT/CSV）/ Batch export: pick scope (all/selected indices) and format (TXT/CSV)
- 📱 复制WiFi连接字符串（手机相机扫码即可连接）/ Copy WiFi connect string, scanable by phone camera
- 📊 导出进度条实时显示（`█░` 10段 + 百分比）/ Real-time progress bar during export

### 界面优化 / UI Enhancements
- 🔐 密码显示/隐藏切换（主菜单选项 4）/ Password show/hide toggle (menu option 4)
- 📖 查询历史记录（最多 10 条，支持序号快速重查）/ Query history (up to 10 entries, quick re-query by index)
- ⌨️ 快捷键提示栏（`[e]导出 [h]历史 [q]退出`）/ Quick key hint bar
- 🎨 ANSI 颜色高亮（标题青色、WiFi名称黄色、密码亮白、错误红色、成功绿色）/ ANSI color highlighting
- ✨ Unicode 分隔线（`─`）替代 `====`，视觉更清爽 / Unicode separator lines

## 系统要求 / System Requirements

- Windows 10/11（推荐，ANSI 颜色需要 VT 支持）/ Windows 10/11 (recommended, ANSI colors need VT support)
- Windows 7/8（基本功能可用，颜色可能不显示）/ Windows 7/8 (basic features work, colors may not show)
- 管理员权限 / Administrator privileges
- 已保存的WiFi配置 / Saved WiFi configurations

## 使用步骤 / Usage Steps

1. **以管理员身份运行脚本** / **Run script as administrator**
2. **查看WiFi列表（带序号）** / **View WiFi list (with index numbers)**
3. **输入序号/名称查询，或按快捷键** / **Enter index/name to query, or use quick keys**
   - `e` = 批量导出 / batch export
   - `h` = 查看查询历史 / view query history
   - `q` = 退出程序 / quit
4. **查看密码结果** / **View password result**
   - 密码自动复制到剪贴板 / Password auto-copied to clipboard
   - 主菜单可选：继续/导出/QR字符串/显示隐藏密码/历史/退出 / Menu: continue/export/QR/toggle/history/exit
5. **导出时可选范围和格式** / **Choose scope and format when exporting**
   - 范围：全部 / 指定编号（逗号分隔，如 1,3,5）/ Scope: all / selected indices (comma separated)
   - 格式：TXT 文本 / CSV 表格 / Format: TXT / CSV

## 常见问题 / Common Issues

| 问题 / Issue | 解决方案 / Solution |
|-------------|-------------------|
| 权限不足 / Insufficient privileges | 以管理员身份运行 / Run as administrator |
| 找不到WiFi / WiFi not found | 检查序号是否在范围内，或WiFi名称是否正确 / Check if index is in range, or WiFi name is correct |
| 密码为空 / Password is empty | 该WiFi可能没有保存密码 / WiFi may not have saved password |
| ANSI 颜色不显示 / ANSI colors not showing | 使用 Windows 10+ 终端，确保支持 VT 处理 / Use Windows 10+ terminal with VT support |
| Unicode 字符乱码 / Unicode chars garbled | 确保终端使用 UTF-8 编码（chcp 65001）/ Ensure terminal uses UTF-8 (chcp 65001) |

## 技术支持 / Technical Support

如有问题，请查看详细使用说明文档。
For issues, please refer to the detailed user manual.

## 开源协议 / License

本项目基于 [MIT License](LICENSE) 开源。
This project is open-sourced under the [MIT License](LICENSE).

---

**免责声明 / Disclaimer**: 本工具仅供合法用途使用，请遵守当地法律法规。
This tool is for legal use only, please comply with local laws and regulations.
