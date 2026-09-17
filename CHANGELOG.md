# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

项目地址：`e:\补丁更新工具\wifi_passwd_view\`，含 BAT 和 Go 双实现。

---

## [Unreleased]

### Added
- Go 版非 VT 终端降级：`enableVT()` 检查 `SetConsoleMode` 返回值，失败时调 `disableColors()` 把所有 ANSI 颜色常量置空（避免 Win7 旧 conhost / 重定向 stdout 输出原始 `[36m` 乱码）
- Go 版 `uniqueFilename()`：导出文件 / QR 文件名冲突时自动追加 `_(2)`, `_(3)`...，避免同秒内重复导出被静默覆盖
- Go 版空 WiFi 列表早退：检测到 0 个配置时打印本地化提示并优雅退出，避免强制用户对着空列表输入
- Go 版 `TestUniqueFilename` 单元测试（5 子用例，含间隔跳号测试）
- Go 版 `TestEscapeForShellArg` 单元测试（10 子用例，防 SSID cmd.exe 注入）
- Go 版二进制 UPX 压缩步骤文档（`go-wifi-view/README.md` 进一步压缩体积章节），可叠加 `-s -w` 把 ~3 MB 压到 ~1.5 MB
- 顶层 README.md 双实现体积对照表更新：`~6 MB` → `~3 MB (-s -w)` / `~1.5 MB (+ UPX)`

### Fixed
- Go 版 `pwdKeywords` 数组补 `Nøkkelinnhold`（挪威语），同时 BAT 两处关键词检测块同步
- Go 版 `main_test.go` 的 `TestExtractPassword` 补丹麦语 / 挪威语子用例
- Go 版多处 `exec.Command(...).Run()` / `.Wait()` 错误被忽略：现对 `chcp 65001` 和 `start ""` 加 stderr 警告，对 `title` 和剪贴板 `Wait` 用 `_ =` 显式丢弃（best-effort）

---

## [v3.1] - 2026-09

### Added
- **BAT ↔ Go 功能对齐**
  - 模糊搜索 `/关键词`（多 token AND，大小写无关）— BAT 新增 `:do_fuzzy_search`；Go 新增 `fuzzySearchWiFi()`
  - 密码强度评分（0-5 分，含黑名单 29 项 / SSID 子串 / 连续 4 字符 / 3+ 重复字符检测）
    - BAT 新增 `:password_strength` 和 `:build_strength_bar` 子例程
    - Go 新增 `passwordStrength()` 及 `isSequential()` / `isRepeated()` / `buildStrengthBar()`
- **Go 版独有**（BAT 不需要，对应 Go 的可执行文件形态）
  - Ctrl+C 优雅退出（`signal.NotifyContext`，本地化退出消息）
  - `panic` 恢复（`debug.PrintStack` + 等按键退出）
  - 单元测试 `main_test.go`（15 函数 / 120 子用例，含 SSID 注入防护 `TestEscapeForShellArg`）
  - 版本信息嵌入二进制（`-ldflags "-X main.Version=v3.1.0 -X main.Commit=... -X main.BuildDate=..."`）
- **QR 码优化**（仅 Go 版）
  - WiFi 名称移到二维码**下方**显示（避免长 SSID 居中截断）
  - 字号自适应缩放（36pt → 14pt，步长 2pt）
  - 文件名加时间戳：`WiFi_QR_<safeSSID>_<YYYYMMDD_HHMMSS>.png`
  - 生成路径自动复制到剪贴板
  - 错误纠错级 High (30%) 保证扫码成功率
- **21 种语言支持文档**
  - 新增 `bat-wifi-view/Language_Support.md`
  - 新增 `go-wifi-view/Language_Support.md`
  - 含本地语名、locale 示例、netsh 密码关键字、自动检测流程、强制指定方法、UI 翻译状态说明
- **Go 版依赖**
  - `golang.org/x/image`（TTF 字体渲染，约 230KB 嵌入二进制）

### Changed
- 顶层 README、BAT 双手册、Go README 的功能对照表统一为 21 种语言 netsh 输出解析
- 项目结构图同步新增 `main_test.go` 和 `Language_Support.md`
- 导出报告工具版本号：硬编码 `WiFi Password Query Tool v3.0` → 本地化 `!str_title! v3.1`
  - 中文界面：`导出工具: WiFi密码查询工具 v3.1`
  - 英文界面：`Tool Version: WiFi Password Query Tool v3.1`

### Fixed
- `pwdKeywords` 数组缺失挪威语 `Nøkkelinnhold`（依赖 fallback 才能匹配）
- `extractPassword` 测试用例缺失丹麦语 / 挪威语精确匹配
- 挪威语 netsh 输出：`Nøkkelinnhold` 缺失（BAT + Go 同步）
- Go 版 `exec.Command(...).Run()` 返回错误被静默吞掉

---

## [v3.0] - 2026-09

### Added
- **统一多语言自动检测版**（替代 v2.x 的多版本分支）
  - 21 种 UI 语言自动检测（基于 `reg query HKCU\Control Panel\International!LocaleName` + `wmic os get oslanguage` LCID 映射 + `LANG` 环境变量）
  - 21 种 netsh 输出多语言解析（zh / en / ja / ko / de / fr / ru / es / it / pt / pl / nl / tr / ar / he / cs / hu / sv / fi / da / no）
  - 仅 zh / en 完整 UI 字符串表；其余 19 种 locale 正确识别但 UI 回退英文
- CSV 导出（含 UTF-8 BOM，Excel 中文不乱码）
- WiFi 连接字符串复制：`WIFI:T:WPA;S:<ssid>;P:<pwd>;;`（手机相机扫码连接）
- 导出范围自选：全部 / 指定编号（逗号分隔）
- 导出格式自选：TXT / CSV
- 进度条（`█░` 10 段 + 百分比，实时显示导出进度）
- 快捷键提示栏（`[e]导出 [h]历史 [q]退出`）
- 查询历史记录（最近 10 条，序号快速重查）
- 密码显示 / 隐藏切换（主菜单选项 4）
- ANSI 颜色高亮（标题青色、WiFi 名称黄色、密码亮白、错误红色、成功绿色）
- Unicode 分隔线（`─`）替代 `====`，视觉更清爽

### Changed
- 单一入口 `wifi_password_tool_auto.bat` 替代 v2.x 的多版本分支
- 命令行支持强制指定语言：`wifi_password_tool_auto.bat {zh|en|ja|...}`

---

## [v2.1] - 2026

### Added
- 批量导出所有 WiFi 密码为 TXT 文件
- 主菜单增加"导出当前 WiFi 密码"选项

---

## [v2.0] - 2026

### Added
- WiFi 列表新增序号显示，支持按序号快速选择（无需输入完整 WiFi 名称）
- 兼容中英文系统 netsh 输出格式（动态字段匹配，不再依赖固定字符串）

---

## [v1.x] - 历史早期版本

最早期的脚本实现，仅支持中文 netsh 输出，按数字编号输入，无导出、无多语言。
具体细节请参考 `git log`。

---

## 版本对照 / Version Compatibility

| 版本 | BAT | Go | 备注 |
|------|-----|----|----|
| v3.1 | ✅ | ✅ | 功能完全对齐 |
| v3.0 | ✅ | ❌ | 仅 BAT 版 |
| v2.1 | ✅ | ❌ | 仅 BAT 版 |
| v2.0 | ✅ | ❌ | 仅 BAT 版 |
| v1.x | ✅ | ❌ | 已废弃，仅 BAT |

---

## 引用 / References

- 📖 [README.md](README.md) — 项目总览
- 📖 [bat-wifi-view/Language_Support.md](bat-wifi-view/Language_Support.md) — BAT 版 21 语言总览
- 📖 [go-wifi-view/Language_Support.md](go-wifi-view/Language_Support.md) — Go 版 21 语言总览
</content>
</invoke>