# WiFi密码查询工具 / WiFi Password Query Tool

## 文件说明 / File Description

| 文件名 / Filename | 说明 / Description |
|------------------|-------------------|
| `wifi_password_tool_auto.bat` | **统一版（推荐）** 自动识别系统语言，动态匹配 netsh 关键词 / **Unified (Recommended)** Auto-detect language, dynamic netsh matching |
| `wifi_password_tool.bat` | 中文版WiFi密码查询工具 / Chinese version |
| `select_wifi_passwd_optimized.bat` | 英文版WiFi密码查询工具 / English version |
| `WiFi密码查询工具使用说明.md` | 中文详细使用说明 / Chinese detailed manual |
| `WiFi_Password_Query_Tool_Manual.md` | 英文详细使用说明 / English detailed manual |

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

## 重要提醒 / Important Notes

⚠️ **必须以管理员身份运行！** / **Must run as Administrator!**

⚠️ **仅用于查询自己的WiFi密码** / **Only for querying your own WiFi passwords**

## 功能特点 / Features

- 🔍 查看所有已保存的WiFi配置（带序号）/ View all saved WiFi configurations (with index numbers)
- 🔢 支持按序号快速选择WiFi / Support quick WiFi selection by index
- ⌨️ 支持直接输入WiFi名称 / Support direct WiFi name input
- 🔑 查询指定WiFi的密码 / Query password for specified WiFi
- 📤 一键批量导出所有WiFi密码为TXT / One-click batch export all WiFi passwords to TXT
- 📋 自动复制密码到剪贴板 / Auto-copy password to clipboard
- 🌐 支持中文和英文界面 / Support Chinese and English interfaces
- 🤖 自动识别系统语言（v3.0）/ Auto-detect system language (v3.0)
- 🔧 动态匹配 netsh 多语言输出关键词 / Dynamic multi-language netsh keyword matching
- 🛡️ 安全的本地运行 / Secure local execution

## 系统要求 / System Requirements

- Windows 7/8/10/11
- 管理员权限 / Administrator privileges
- 已保存的WiFi配置 / Saved WiFi configurations

## 使用步骤 / Usage Steps

1. **以管理员身份运行脚本** / **Run script as administrator**
2. **查看WiFi列表（带序号）** / **View WiFi list (with index numbers)**
3. **输入序号/名称查询，或输入e批量导出为TXT** / **Enter index/name to query, or enter e for batch TXT export**
4. **查看密码结果或导出文件** / **View password result or export file**
5. **选择继续、导出或退出** / **Choose to continue, export or exit**

## 常见问题 / Common Issues

| 问题 / Issue | 解决方案 / Solution |
|-------------|-------------------|
| 权限不足 / Insufficient privileges | 以管理员身份运行 / Run as administrator |
| 找不到WiFi / WiFi not found | 检查序号是否在范围内，或WiFi名称是否正确 / Check if index is in range, or WiFi name is correct |
| 密码为空 / Password is empty | 该WiFi可能没有保存密码 / WiFi may not have saved password |

## 技术支持 / Technical Support

如有问题，请查看详细使用说明文档。
For issues, please refer to the detailed user manual.

---

**免责声明 / Disclaimer**: 本工具仅供合法用途使用，请遵守当地法律法规。
This tool is for legal use only, please comply with local laws and regulations.
