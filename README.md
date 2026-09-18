# WiFi 密码查询工具 / WiFi Password Query Tool

一个用于查看 Windows 已保存 WiFi 密码的实用工具。提供 **三种实现**，功能一致，按需选用。

A Windows utility for viewing saved WiFi passwords. Ships in **three implementations** with identical features — pick the one that fits your workflow.

## 三种实现 / Three Implementations

| | BAT 版 / BAT edition | Go 版 / Go edition | Rust 版 / Rust edition |
|---|---|---|---|
| 目录 / Folder | [`bat-wifi-view/`](bat-wifi-view/) | [`go-wifi-view/`](go-wifi-view/) | [`rust-wifi-view/`](rust-wifi-view/) |
| 入口文件 / Entry | `wifi_password_tool_auto.bat` | `wifi_password_tool.exe` (编译后) | `wifi_password_tool.exe` (编译后) |
| 运行依赖 / Runtime deps | Windows 自带 / Windows built-in | 无（单 exe）/ none (single exe) | 无（单 exe）/ none (single exe) |
| 分发 / Distribution | 拷 `.bat` 即可 / copy `.bat` | 拷 `wifi_password_tool.exe` / copy the exe | 拷 `wifi_password_tool.exe` / copy the exe |
| 编译需要 / Build needs | 无 / none | Go 1.21+ | Rust stable + Python 3（首次） |
| 文件大小 / Size | ~36 KB | ~3 MB（`-s -w`）/ ~1.5 MB（+ UPX） | **~307 KB**（无 UPX） |
| 二维码图片 / QR image | ❌ | ✅ PNG / PNG | ✅ SVG（矢量）/ SVG (vector) |
| `-h` / `-v` 开关 / CLI flags | ❌ | ❌ | ✅ |
| 文档 / Docs | 见子目录 / see subfolder | [go-wifi-view/README.md](go-wifi-view/README.md) | [rust-wifi-view/README.md](rust-wifi-view/README.md) |

三者菜单、快捷键、提示、ANSI 颜色完全一致，互不冲突。

All three share the same menus, shortcuts, prompts and ANSI colors — switch freely between them.

## 快速开始 / Quick Start

### BAT 版 / BAT edition（最快上手 / fastest to try）

1. 进入 [`bat-wifi-view/`](bat-wifi-view/) 目录 / Enter the folder
2. 右键 `wifi_password_tool_auto.bat` → **以管理员身份运行** / Right-click → **Run as administrator**
3. 详细说明见 [`WiFi密码查询工具使用说明.md`](bat-wifi-view/WiFi密码查询工具使用说明.md) 或英文版 [`WiFi_Password_Query_Tool_Manual.md`](bat-wifi-view/WiFi_Password_Query_Tool_Manual.md)

### Go 版 / Go edition

```powershell
cd go-wifi-view
go mod tidy
go build -o wifi_password_tool.exe
# 右键以管理员身份运行 / Run as administrator
```

完整文档：[go-wifi-view/README.md](go-wifi-view/README.md)

### Rust 版 / Rust edition（最小体积 / smallest binary）

```powershell
cd rust-wifi-view
python gen_libs.py          # 首次运行：生成导入库 / first time only: generate import libs
cargo build --release
# 产物 / output: target/release/wifi_password_tool.exe
# 右键以管理员身份运行 / Run as administrator
```

完整文档：[rust-wifi-view/README.md](rust-wifi-view/README.md)

## 通用功能 / Common Features

- 🔍 查看所有已保存的 WiFi 配置（带序号）/ View all saved WiFi configurations (with index)
- 🔢 按序号或名称快速查询 / Quick query by index or name
- 🔎 **模糊搜索**（`/关键词`，多 token AND，大小写无关）/ Fuzzy search (`/keyword`, multi-token AND, case-insensitive)
- 🔐 自动复制密码到剪贴板 / Auto-copy password to clipboard
- 📊 **密码强度评分**（0-5 分，含黑名单/连续/重复字符检测）/ Password strength meter (0-5, with blacklist/sequential/repeat detection)
- 🤖 自动识别系统语言（zh/en/ja/ko/de/fr/ru/es/it/pt/pl/nl/tr/ar/he/cs/hu/sv/fi/da/no，共 21 种 UI；21 种 netsh 输出解析）
- 📤 批量导出 TXT / CSV（含 UTF-8 BOM，Excel 直接打开）/ Batch export TXT / CSV (UTF-8 BOM, Excel-compatible)
- 📱 复制 WiFi 连接字符串（手机相机扫码即可连接）/ Copy WiFi connect string (scan to connect)
- 📊 实时进度条 / Real-time progress bar
- 🔁 密码显示/隐藏切换 / Password show/hide toggle
- 📖 查询历史（最近 10 条）/ Query history (last 10)
- 🎨 ANSI 颜色高亮 / ANSI color highlighting

## 系统要求 / System Requirements

- Windows 10/11（推荐，依赖 ANSI/VT）/ Windows 10+ (recommended, uses ANSI/VT)
- Windows 7/8：基本功能可用，颜色可能不显示 / Windows 7/8: basic functions, colors may not render
- 管理员权限（必需）/ Administrator privileges (required)
- 已保存的 WiFi 配置 / Saved WiFi configurations

## 选哪个？/ Which one to choose?

- **临时在别人电脑上跑一下** → BAT 版，零安装 / Temporary use on someone else's PC → BAT, zero install
- **想塞进 U 盘随身带 / 给同事分发** → Rust 版，307 KB 最小 / Carry on USB / distribute → Rust, 307 KB is smallest
- **想用脚本/自动化调用** → Go 版或 Rust 版，可重命名入口参数稳定 / Want scripting/automation → Go or Rust, predictable CLI args
- **想加自定义功能** → Go 版，单文件易改易编译 / Want custom modifications → Go, easy to edit and rebuild
- **追求极致体积 / 启动速度** → Rust 版，307 KB，无 runtime / Want smallest size / fastest startup → Rust, 307 KB, no runtime

## 项目结构 / Project Layout

```
wifi_passwd_view/
├── README.md                              ← 本文件 / this file
├── CHANGELOG.md                           ← 变更日志 / changelog
├── LICENSE                                ← MIT
├── bat-wifi-view/                         ← BAT 实现 / BAT edition
│   ├── wifi_password_tool_auto.bat        ← 唯一入口（v3.1，统一版+模糊搜索+密码强度）/ sole entry (v3.1 unified + fuzzy + strength)
│   ├── WiFi密码查询工具使用说明.md
│   ├── WiFi_Password_Query_Tool_Manual.md
│   └── Language_Support.md                ← 语言支持总览（21 种 UI / netsh）/ Language overview (21 UI / netsh)
├── go-wifi-view/                          ← Go 实现 / Go edition
│   ├── main.go
│   ├── main_test.go
│   ├── go.mod
│   ├── go.sum
│   ├── README.md                          ← Go 版使用说明 / Go edition docs
│   └── Language_Support.md                ← 语言支持总览（同上）/ Language overview (same)
└── rust-wifi-view/                        ← Rust 实现 / Rust edition
    ├── Cargo.toml                         ← 项目配置 + release profile
    ├── .cargo/
    │   └── config.toml                   ← lld-link 链接器配置 / linker config
    ├── gen_libs.py                        ← 从系统 DLL 生成导入库（一次性）/ generate import libs (once)
    ├── src/
    │   └── main.rs                        ← 单文件实现（~2000 行）/ single-file impl
    └── README.md                          ← Rust 版使用说明 / Rust edition docs
```

## 常见问题 / FAQ

| 问题 / Issue | 解决方案 / Solution |
|-------------|---------------------|
| 权限不足 / Insufficient privileges | 以管理员身份运行 / Run as administrator |
| 找不到 WiFi / WiFi not found | 检查序号范围或名称拼写 / Check index range or spelling |
| 密码为空 / Empty password | 该 WiFi 可能没保存密码 / WiFi may not have saved password |
| 颜色不显示 / Colors don't show | 使用 Windows 10+ 终端 / Use Windows 10+ terminal |
| Go 版 `missing GOSUMDB` | `go env -w GONOSUMDB=off` 或 `GONOSUMDB=sum.golang.org` |
| Rust 版启动崩溃 `0xc0000005` | 重跑 `python gen_libs.py` 后重新 `cargo build --release` |
| 中文乱码 / Chinese garbled | 终端设为 UTF-8（`chcp 65001`）/ set terminal to UTF-8 |

## 开源协议 / License

[MIT License](LICENSE)

---

**免责声明 / Disclaimer**: 本工具仅供合法用途使用，请遵守当地法律法规。
For legal use only. Comply with local laws and regulations.
