# WiFi Password Query Tool (Go Edition) / WiFi 密码查询工具（Go 版）

## 简介 / Overview

`main.go` 是 `bat-wifi-view/wifi_password_tool_auto.bat` 的 Go 单文件重写版。功能与 BAT 版完全对齐，同时额外提供带 WiFi 名称标注的二维码图片导出。

This is a single-file Go reimplementation of the BAT tool in `bat-wifi-view/`. Feature-compatible with the BAT version, plus an additional QR code image with the SSID labeled below.

## 与 BAT 版的差异 / Differences from BAT

- **单可执行文件**：`go build` 后得到一个 `wifi_password_tool.exe`，分发更简单。
- **二维码图片**：在菜单 4 生成 PNG，二维码下方显示 WiFi 名称（自动按宽度缩字号，不截断）。
- **界面一致**：菜单顺序、快捷键、提示文本、ANSI 颜色与 BAT 版相同，迁移零成本。
- **导出文件位置**：与 BAT 版一致，输出到 `exe` 所在目录。

## 系统要求 / Requirements

- Windows 10/11（推荐，依赖 ANSI/VT）/ Windows 10+ recommended (uses ANSI/VT)
- 管理员权限（必需）/ Administrator privileges (required)
- Go 1.21+（仅编译时需要）/ Go 1.21+ (build-time only)

## 编译 / Build

普通构建：

```powershell
cd go-wifi-view
go mod tidy
go build -o wifi_password_tool.exe
```

带版本信息的构建（推荐，版本号会显示在主界面抬头）：

```powershell
$VERSION="v3.1.0"
$COMMIT=(git rev-parse --short HEAD 2>$null)
if (-not $COMMIT) { $COMMIT="local" }
$BUILD_DATE=(Get-Date -Format "yyyy-MM-dd")
go build -ldflags "-X main.Version=$VERSION -X main.Commit=$COMMIT -X main.BuildDate=$BUILD_DATE -s -w" -o wifi_password_tool.exe
```

`-s -w` 去掉符号表与调试信息，二进制从 ~6MB 缩到 ~3MB。

首次 `go mod tidy` 会下载：

- `github.com/skip2/go-qrcode` — 二维码生成 / QR generation
- `golang.org/x/image` — 字体渲染（内嵌 Go Regular TTF，约 230KB 嵌入二进制）/ font rendering (embeds Go Regular TTF, ~230KB into the binary)

如果下载遇到 `missing GOSUMDB` 等校验错误：

```powershell
go env -w GOSUMDB=sum.golang.org
```

## 运行 / Run

右键 `wifi_password_tool.exe` → "以管理员身份运行" / Right-click → "Run as administrator"。

也可命令行：

```powershell
# 自动检测系统语言
.\wifi_password_tool.exe

# 强制指定语言
.\wifi_password_tool.exe zh
.\wifi_password_tool.exe en
```

支持的语言代码与 BAT 版一致（`zh` / `en` / `ja` / `ko` / `de` / `fr` / `ru` / `es` / `it` / `pt` / `pl` / `nl` / `tr` / `ar` / `he` / `cs` / `hu` / `sv` / `fi` / `da` / `no`）。

## 功能对照 / Feature Parity

| 功能 Feature | BAT 版 | Go 版 |
|--------------|:------:|:-----:|
| 显示所有已保存 WiFi / List saved WiFi | ✅ | ✅ |
| 按序号查询 / Query by index | ✅ | ✅ |
| 按名称查询 / Query by name | ✅ | ✅ |
| 模糊搜索（`/关键词`） / Fuzzy search (`/keyword`) | ❌ | ✅ |
| 自动识别语言 / Auto language detect | ✅ | ✅ |
| 强制指定语言 / Force language | ✅ | ✅ |
| 18 种语言 netsh 解析 / 18-lang netsh parsing | ✅ | ✅ |
| 密码复制到剪贴板 / Copy pwd to clipboard | ✅ | ✅ |
| 批量导出 TXT / Batch export TXT | ✅ | ✅ |
| 批量导出 CSV（带 BOM） / CSV export with BOM | ✅ | ✅ |
| 导出范围可选 / Export scope select | ✅ | ✅ |
| 进度条 / Progress bar | ✅ | ✅ |
| 显示/隐藏密码 / Password toggle | ✅ | ✅ |
| 密码强度评分 / Password strength meter | ❌ | ✅ |
| 查询历史（10 条）/ Query history (10) | ✅ | ✅ |
| ANSI 颜色 / ANSI colors | ✅ | ✅ |
| WiFi 连接字符串 / Connect string | ✅ | ✅ |
| 二维码图片（PNG） / QR image (PNG) | ❌ | ✅ |
| 二维码带 SSID 标注 / QR with SSID label | ❌ | ✅ |
| 二维码文件名带时间戳 / QR filename with timestamp | ❌ | ✅ |
| 二维码路径复制剪贴板 / QR path copied to clipboard | ❌ | ✅ |
| Ctrl+C 优雅退出 / Ctrl+C graceful shutdown | ❌ | ✅ |
| panic 恢复（堆栈输出）/ Panic recovery with stack | ❌ | ✅ |
| 单元测试 / Unit tests | ❌ | ✅ (13 函数 / ~103 用例) |
| 版本信息嵌入 / Version embedded in binary | ❌ | ✅ |

## 输出文件 / Output Files

- 导出 TXT：`WiFi密码导出_YYYY-MM-DD_HH-MM-SS.txt`（exe 同目录）/ same dir as exe
- 导出 CSV：`WiFi密码导出_YYYY-MM-DD_HH-MM-SS.csv`（exe 同目录，含 UTF-8 BOM） / same dir, with UTF-8 BOM
- 二维码：`WiFi_QR_<SSID>_YYYYMMDD_HHMMSS.png`（exe 同目录；生成时路径自动复制到剪贴板）/ same dir; path auto-copied to clipboard on generation

## 测试 / Testing

```powershell
go test ./...              # 跑全部测试
go test -v ./...           # 显示每个用例名
go test -cover ./...       # 看覆盖率
go test -run TestPasswordStrength -v ./...   # 只跑某个测试
```

## 版本 / Version

v3.1 (Go edition) — BAT 版 v3.0 功能对齐 + 二维码增强 + 模糊搜索 + 密码强度评分 + Ctrl+C 优雅退出 + panic 恢复 + 单元测试 + 版本信息嵌入。

二进制版本号通过 `-ldflags` 注入（见上方"编译"章节），启动时显示在主界面抬头。

## 开源协议 / License

[MIT License](../LICENSE)