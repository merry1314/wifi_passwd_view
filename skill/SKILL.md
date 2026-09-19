# WiFi Password Query Tool — 可复用技能指南

> 从零构建 Windows WiFi 密码查看工具的完整技能文档。涵盖 netsh 解析、21 语言适配、QR 码生成、四种语言实现（BAT / Go / Rust / PowerShell）的陷阱与最佳实践。

---

## 1. 项目概述

**目标**：单文件 / 单二进制 Windows 工具，列出已保存 WiFi 配置，查询密码，导出 TXT/CSV，生成 QR 码扫码连接。

**运行条件**：Windows 10/11，管理员权限（`netsh wlan show profile key=clear` 需要管理员才能显示密码）。

**四种实现对照**：

| 实现路径 | 文件 | 体积 | 工具链 | QR 格式 |
|---------|------|------|--------|---------|
| BAT | `wifi_password_tool_auto.bat` | ~36 KB | 无 | 无 |
| Go | `main.go` | ~1.5 MB (UPX) | Go 1.21+ | PNG |
| Rust | `src/main.rs` | ~307 KB | Rust + Python | SVG |
| PowerShell | `wifi_password_tool.ps1` | ~46 KB | 无（系统自带） | SVG |

---

## 2. 核心技术模块

### 2.1 netsh 调用与编码 → [netsh-parsing.md](netsh-parsing.md)

- `netsh wlan show profiles` — 列出所有已保存 WiFi
- `netsh wlan show profile name="SSID" key=clear` — 显示密码
- 编码处理：`chcp 65001` + `[Console]::OutputEncoding = UTF8`（PS）/ `exec.Command("cmd", "/c", "chcp 65001 >nul & netsh ...")`（Go）
- SSID 注入防护：cmd.exe 转义 `^ & | < > ( ) , ; "` 等

### 2.2 21 语言关键词匹配 → [multi-language.md](multi-language.md)

- Profile 关键词（"profile" / "profil" / "配置文件" / ...）
- Password 关键词（"Key Content" / "密钥内容" / "キーコンテンツ" / ...）
- 语言自动检测（注册表 / `Get-WinSystemLocale` / `cultureinfo`）
- **关键陷阱**：PS 5.1 中 `[string] + [char]` 拼接截断 → 必须用 `U()` 码点函数

### 2.3 QR 码生成 → [qr-generation.md](qr-generation.md)

- WiFi 连接字符串格式：`WIFI:T:WPA;S:<SSID>;P:<PWD>;;`
- Go：`skip2/go-qrcode` 库生成 PNG
- Rust：`qrcode` crate 生成 SVG
- PowerShell：内嵌自研纯 .NET C# QR 编码器（`Add-Type` 运行时编译）
  - byte 模式，版本 1–10 自适应，R-S 纠错（GF(256)）
  - **C# 5.0 限制**：嵌套范围内不能声明同名变量（CS0136）
  - `Add-Type` 失败回退 `CSharpCodeProvider` 备用编译

### 2.4 密码强度评分

- 0–5 分：长度（≤7→0, ≤11→1, ≤15→2, ≤19→3, else 4）+ 字符类别（≥3 类 +1）
- 常见密码黑名单扣 3 分，SSID 子串扣 1 分，连续/重复字符扣 1 分
- **PS 陷阱**：`switch` 默认 fall-through 匹配所有条件 → 每个 case 必须加 `break`

### 2.5 导出与剪贴板

- TXT：对齐排版，UTF-8 BOM
- CSV：RFC 4180 转义（含逗号/引号/换行的字段用双引号包裹，内部引号双写）
- 剪贴板：`Set-Clipboard`（PS）/ `clipboard` 命令（BAT）/ Win32 API（Rust）

---

## 3. PowerShell 5.1 专项陷阱 → [powershell-pitfalls.md](powershell-pitfalls.md)

| 陷阱 | 症状 | 解决方案 |
|------|------|---------|
| 无 BOM UTF-8 脚本按 ANSI 解析 | 中文乱码 | 全 ASCII 写法，中文用 `U()` 码点拼接 |
| `switch` 默认匹配所有 case | 强度显示 `System.Object[]` | 每个 case 加 `break` |
| `$input` 是只读自动变量 | 赋值抛错 | 改用 `$line` |
| `[string] + [char]` 拼接截断 | 关键词退化为单字符 | 用 `U()` 函数构建 |
| `Add-Type` C# 5.0 限制 | CS0136 变量名冲突 | 嵌套范围用不同变量名 |
| `[System.Collections.ArrayList]@()` | 构造失败 | 用 `New-Object` |

---

## 4. BAT 专项陷阱 → [bat-pitfalls.md](bat-pitfalls.md)

| 陷阱 | 解决方案 |
|------|---------|
| 中文 REM 注释导致编码问题 | REM 注释必须用英文 |
| `for` 循环内 `setlocal/endlocal` | 禁用，变量永远为空 |
| 延迟展开 `!var:!=!` | `!` 是触发字符，禁止使用 |
| 临时文件首行缺 `@` | cmd 回显被当作数据捕获 |

---

## 5. Rust 专项陷阱 → [rust-pitfalls.md](rust-pitfalls.md)

| 陷阱 | 解决方案 |
|------|---------|
| rust-lld 链接 MSVC 无 CRT 启动代码 | 手工补齐 `_tls_used` / `_tls_index` / `.CRT$XLA` / `.CRT$XLZ` |
| 缺少 Windows SDK | `gen_libs.py` 从 DLL 导出表生成导入库 |
| `lld-link` 链接器配置 | `.cargo/config.toml` 指定链接器 + `/alternatename` |

---

## 6. 从零实现 Checklist

1. **netsh 调用**：`cmd /c "chcp 65001 >nul & netsh wlan show profiles"` 列出配置
2. **解析配置列表**：找含 profile 关键词且有冒号的行，取冒号后文本
3. **查询密码**：`netsh wlan show profile name="SSID" key=clear`，找含 password 关键词的行
4. **语言检测**：读注册表 `HKLM\SYSTEM\CurrentControlSet\Control\Nls\Language` 或系统 locale
5. **密码强度**：长度 + 字符类别 + 黑名单 + 连续/重复检测
6. **导出 TXT/CSV**：UTF-8 BOM，CSV 用 RFC 4180 转义
7. **QR 码**：构建 `WIFI:T:WPA;S:ssid;P:pwd;;` 连接字符串，生成二维码
8. **交互界面**：列表 → 输入序号/名称 → 详情 → 导出/QR/复制
9. **安全加固**：SSID cmd.exe 注入转义，文件名净化，防覆盖
10. **优雅退出**：Ctrl+C 处理，空列表早退

---

## 7. 文件索引

| 文档 | 内容 |
|------|------|
| [netsh-parsing.md](netsh-parsing.md) | netsh 调用、编码处理、SSID 转义、21 语言关键词表 |
| [multi-language.md](multi-language.md) | 语言检测方法、关键词完整对照表、PS 码点构建 |
| [qr-generation.md](qr-generation.md) | QR 编码原理、C# 内嵌编码器、Add-Type 编译陷阱 |
| [powershell-pitfalls.md](powershell-pitfalls.md) | PS 5.1 兼容性陷阱全集 |
| [bat-pitfalls.md](bat-pitfalls.md) | BAT 脚本陷阱全集 |
| [rust-pitfalls.md](rust-pitfalls.md) | Rust 交叉编译与链接陷阱 |