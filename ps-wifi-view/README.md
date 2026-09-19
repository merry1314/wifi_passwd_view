# WiFi Password Query Tool v3.2.1 — PowerShell edition

Windows WiFi 密码查看工具的 PowerShell 单文件实现，与 [BAT 版](../bat-wifi-view/)、[Go 版](../go-wifi-view/)、[Rust 版](../rust-wifi-view/) 功能对齐。

A Windows utility for viewing saved WiFi passwords, reimplemented as a single PowerShell script. Feature-compatible with the BAT, Go and Rust editions.

> **特点**：零安装、零编译、Windows 10/11 系统自带 PowerShell 即可运行；单 `.ps1` 文件约 1300 行 / 46 KB。

---

## 特性 / Features

| 功能 | 说明 |
|------|------|
| 列表 | 列出所有已保存 WiFi，序号从 1 开始 |
| 按序号/名称查询 | 名称匹配大小写不敏感，支持子串匹配 |
| 模糊搜索 | `/关键词`，空格分隔多个 token（AND 逻辑） |
| 密码强度 | 0–5 分评分 + 进度条（长度、字符类别、黑名单、连续/重复、SSID 子串） |
| 显示/隐藏 | 密码默认掩码，`s` 切换 |
| 查询历史 | 最近 10 条（`h` 查看）；详情界面输入历史序号可直接跳转 |
| 批量导出 | TXT（对齐排版）/ CSV（RFC 4180 转义），均带 UTF-8 BOM |
| 导出范围 | 输入 `0` 或直接回车 = 全部；输入 `1,3,5` 按序号导出 |
| QR 码 | **SVG 矢量**（内嵌自研 C# QR 编码器，High 级纠错），自动复制路径并打开 |
| 连接字符串 | `WIFI:T:WPA;S:<SSID>;P:<PWD>;;` 一键复制，手机扫码即连 |

### 兼容与安全

- 21 种语言 netsh 输出解析（zh/en/ja/ko/de/fr/ru/es/it/pt/pl/nl/tr/ar/he/cs/hu/sv/fi/da/no）
- 自动识别系统语言：zh / en 完整界面，其余语言界面回退英文（解析不受影响）
- SSID shell 注入防护（cmd.exe 转义）
- ANSI 颜色，`NO_COLOR` 环境变量或输出重定向时自动降级
- `-h` / `-v` 命令行开关
- 文件名净化 + 防覆盖（重名自动追加 `_(2)`、`_(3)`…）
- 整个脚本文件为**纯 ASCII**，所有非 ASCII 文案用 Unicode 码点拼接，无编码/BOM 困扰

---

## 运行 / Run

打开 **管理员权限** 的 PowerShell，执行：

```powershell
# 方式一：Bypass 策略直接运行
powershell -ExecutionPolicy Bypass -File wifi_password_tool.ps1

# 方式二：在当前 PS 会话中运行
cd ps-wifi-view
.\wifi_password_tool.ps1
```

> 若本机禁止脚本执行（ExecutionPolicy），用方式一即可，无需永久修改系统策略。

### 命令行参数

```
wifi_password_tool.ps1            # 自动检测语言
wifi_password_tool.ps1 zh         # 强制中文界面
wifi_password_tool.ps1 en         # English UI
wifi_password_tool.ps1 ja         # 日本語 netsh 解析（UI 回退英文）
wifi_password_tool.ps1 -h         # 显示帮助
wifi_password_tool.ps1 -v         # 显示版本
wifi_password_tool.ps1 -d         # 诊断模式（输出 netsh 原始文本 + 密码提取 + QR 编译状态）
```

### 交互按键 / Key bindings

列表界面：序号 / WiFi 名称 / `/关键词`（模糊搜索）/ `e` 导出 / `h` 历史 / `q` 退出
详情界面：`s` 显隐密码 / `r` 生成二维码（SVG）/ `c` 复制连接串 / 数字（跳历史）/ `b` 返回 / `q` 退出

---

## 实现要点 / Implementation Notes

### 为什么是纯 ASCII 文件

PowerShell 5.1 对**无 BOM 的 UTF-8 脚本按系统 ANSI 代码页解析**，中文字面量会乱码。
本脚本所有中文/韩文/日文/俄文/重音字符都通过 `U()` 函数从 Unicode 码点拼接，
因此文件无需 BOM、任意编码保存/传输都不会坏。

### QR 码（内嵌 C#）

PowerShell 没有内置二维码库，本脚本内嵌了一段**自研的纯 .NET QR 编码器**
（`QrSvg` 类，`Add-Type` 运行时编译，使用 Windows 自带的 .NET Framework csc）：

- byte 模式，版本 1–10 自适应，纠错等级 H（优先）→ Q → M → L
- Reed-Solomon 纠错码（GF(256)）、数据交织、格式信息 BCH、版本信息 BCH
- 固定 mask 0，输出 SVG 矢量图（比 PNG 更小且可无限缩放）
- 无需任何外部 DLL / NuGet 包
- `Add-Type` 失败时自动回退 `CSharpCodeProvider` 直接编译；同会话重复运行时跳过已加载类型

### netsh 输出编码

采用 `chcp 65001` + `[Console]::OutputEncoding = UTF8` + `cmd /c "chcp 65001 >nul & netsh ..."`
方式，确保中文/日文/韩文等 netsh 输出以 UTF-8 正确解码。所有非 ASCII 关键词均通过 `U()`
函数从 Unicode 码点构建，避免 PS 5.1 中 `[string] + [char]` 拼接截断问题。

---

## 功能对照 / Feature Parity

| 功能 / Feature | BAT | Go | Rust | PowerShell |
|---|---|---|---|---|
| 查看 WiFi 列表 / List WiFi | ✅ | ✅ | ✅ | ✅ |
| 按序号/名称查询 / Query by index/name | ✅ | ✅ | ✅ | ✅ |
| 模糊搜索 / Fuzzy search | ✅ | ✅ | ✅ | ✅ |
| 密码强度 / Password strength | ✅ | ✅ | ✅ | ✅ |
| 密码显示/隐藏 / Show/hide toggle | ✅ | ✅ | ✅ | ✅ |
| 查询历史 / Query history | ✅ | ✅ | ✅ | ✅ |
| 批量导出 TXT / Export TXT | ✅ | ✅ | ✅ | ✅ |
| 批量导出 CSV / Export CSV | ✅ | ✅ | ✅ | ✅ |
| WiFi 连接字符串 / Connect string | ✅ | ✅ | ✅ | ✅ |
| QR 码 / QR code | ❌ | ✅ (PNG) | ✅ (SVG) | ✅ (SVG) |
| 21 语言解析 / 21-lang parsing | ✅ | ✅ | ✅ | ✅ |
| 自动语言检测 / Auto lang detect | ✅ | ✅ | ✅ | ✅ |
| ANSI 颜色 / ANSI colors | ✅ | ✅ | ✅ | ✅ |
| SSID 注入防护 / Injection guard | ❌ | ✅ | ✅ | ✅ |
| Ctrl+C 优雅退出 / Graceful exit | ❌ | ✅ | ✅ | ✅ |
| 空列表早退 / Empty-state guard | ❌ | ✅ | ✅ | ✅ |
| 文件名防覆盖 / Unique filename | ❌ | ✅ | ✅ | ✅ |
| `-h` / `-v` / `-d` 命令行开关 / CLI flags | ❌ | ❌ | ✅ | ✅ |

| 对比项 | Go 版 | Rust 版 | PowerShell 版 |
|--------|-------|---------|---------------|
| 二进制大小 / 文件大小 | ~1.5 MB (UPX) | ~307 KB | **~46 KB 文本** |
| 工具链 / Toolchain | Go 1.21 | Rust + Python | **无（系统自带）** |
| 编译 / Build | 需要 | 需要 | **不需要** |
| 启动速度 / Startup | ~5–10ms | ~1ms | ~300ms（含启动 PS） |
| QR 格式 | PNG | SVG | SVG |

---

## 排障 / Troubleshooting

| 现象 | 原因与处理 |
|------|-----------|
| 提示"未检测到已保存的 WiFi 配置" | 本机从未连接过 WiFi；先连一次再运行 |
| 密码为空 | 开放网络（无密码），或未以管理员身份运行 |
| 中文乱码 | 请用真实控制台（Windows Terminal 更佳），勿在重定向管道中查看 |
| 密码显示为 WiFi 名称而非密码 | 旧版关键词构建截断导致误匹配，v3.2.1 已修复；运行 `-d` 确认提取结果 |
| 按 `r` 提示 QR 失败 | 先用 `-d` 诊断模式查看实际编译错误；`Add-Type` 失败时脚本自动回退 `CSharpCodeProvider` 备用编译；若仍失败说明系统 .NET Framework 损坏，其余功能不受影响 |
| 无法运行 .ps1 | 用 `powershell -ExecutionPolicy Bypass -File wifi_password_tool.ps1` |

---

## 开源协议 / License

[MIT License](../LICENSE)

## 参考 / References

- [BAT 版](../bat-wifi-view/) — Batch 脚本实现
- [Go 版](../go-wifi-view/) — Go 单文件实现
- [Rust 版](../rust-wifi-view/) — Rust 单文件实现
- [CHANGELOG](../CHANGELOG.md) — 项目变更日志