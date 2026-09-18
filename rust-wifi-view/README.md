# WiFi Password Query Tool v3.1 — Rust edition

Windows WiFi 密码查看工具的 Rust 实现，与 [BAT 版](../bat-wifi-view/) 和 [Go 版](../go-wifi-view/) 功能对齐。

A Windows utility for viewing saved WiFi passwords, reimplemented in Rust. Feature-compatible with the BAT and Go editions.

> **当前状态**：功能完整，64 个单元测试全部通过，release 产物 **307 KB**（314,880 字节，无需 UPX）。

---

## 特性 / Features

### 查询

| 功能 | 说明 |
|------|------|
| 列表 | 列出所有已保存 WiFi，序号从 **1** 开始 |
| 按序号/名称查询 | 名称匹配大小写不敏感，支持子串匹配 |
| 模糊搜索 | `/关键词`，空格分隔多个 token（AND 逻辑） |
| 密码强度 | 0–5 分评分 + 进度条（长度、字符类别、常见密码、连续/重复、SSID 子串） |
| 显示/隐藏 | 密码默认掩码，`s` 切换 |
| 查询历史 | 最近 10 条（`h` 查看）；详情界面输入历史序号可直接跳转 |

### 输出

| 功能 | 说明 |
|------|------|
| 批量导出 | TXT（对齐排版）/ CSV（RFC 4180 转义），均带 UTF-8 BOM，Excel 打开不乱码 |
| 导出范围 | **输入 `0` 或直接回车 = 全部**；输入 `1,3,5` 按序号导出（非法/越界/重复项自动忽略） |
| QR 码 | SVG 矢量（High 级纠错、含 SSID 标签），自动复制路径到剪贴板并打开 |
| 连接字符串 | `WIFI:T:WPA;S:<SSID>;P:<PWD>;;` 一键复制到剪贴板，手机扫码即连 |

### 兼容与安全

- 21 种语言的 netsh 输出解析（zh/en/ja/ko/de/fr/ru/es/it/pt/pl/nl/tr/ar/he/cs/hu/sv/fi/da/no）
- 自动识别系统语言：zh / en 为完整界面，其余语言界面回退英文（仅影响 UI，解析不受影响）
- SSID shell 命令注入防护（`escape_for_shell_arg`）
- VT-100 ANSI 颜色，不支持时自动降级为纯文本
- 文件名净化 + 防覆盖（重名自动追加 `_(2)`、`_(3)`…）
- `-h/--help`、`-v/--version`（随界面语言本地化）
- Ctrl+C / panic 优雅退出

---

## 编译 / Build

### 前置依赖

- Rust stable（`x86_64-pc-windows-msvc` 目标）
- Python 3（仅用于一次性生成导入库）
- **不需要 Windows SDK，也不需要 MSVC Build Tools**

### 首次构建（只需做一次）

```bash
cd rust-wifi-view
python gen_libs.py     # 从系统 DLL 导出表生成 winlibs/*.def 与 *.lib
cargo build --release
```

产物位于 `target/release/wifi_password_tool.exe`。

> `gen_libs.py` 会把 rustup 自带的 `rust-lld.exe` 复制为 `lld-link.exe`，并解析
> `kernel32 / ntdll / userenv / ws2_32 / dbghelp` 的导出表生成导入库
> （`winlibs/` 下另有 `msvcrt`、`ucrtbase` 的导入库）。
> `.cargo/config.toml` 指定该链接器与 `/libpath:winlibs`，并用 `/alternatename` 把
> `mainCRTStartup` 映射到 `main`、`??_7type_info@@6B@` 映射到 `_type_info_vftable`。

### 体积 / Size

release profile 已配置 `opt-level="z"` + `lto=true` + `codegen-units=1` + `strip=true` + `panic="abort"`：

| 版本 | 大小 |
|------|------|
| Rust 版 `cargo build --release` | **307 KB** |
| Go 版（UPX 后） | ~1.5 MB |

### 版本信息嵌入 / Version embedding

`Cargo.toml` 的 `version` 字段在编译期通过 `env!("CARGO_PKG_VERSION")` 嵌入：

```toml
[package]
version = "3.1.0"
```

---

## 运行 / Run

右键 `wifi_password_tool.exe` → **以管理员身份运行**（读取明文密码需要管理员权限）。

### 命令行参数

```
wifi_password_tool.exe            # 自动检测语言
wifi_password_tool.exe zh         # 强制中文界面
wifi_password_tool.exe en         # English UI
wifi_password_tool.exe ja         # 日本語 netsh 解析（UI 回退英文）
wifi_password_tool.exe -h         # 显示帮助（跟随界面语言）
wifi_password_tool.exe -v         # 显示版本
```

### 交互按键 / Key bindings

列表界面：

| 按键 | 作用 |
|------|------|
| `1`、`2`… | 按序号查询 |
| WiFi 名称 | 按名称查询（子串匹配） |
| `/关键词` | 模糊搜索 |
| `e` | 进入导出流程 |
| `h` | 查看查询历史 |
| `q` | 退出 |

详情界面：

| 按键 | 作用 |
|------|------|
| `s` | 显示 / 隐藏密码 |
| `r` | 生成 QR 码（SVG） |
| `c` | 复制 WiFi 连接字符串 |
| `数字` | 跳转到查询历史中对应条目 |
| `b` | 返回列表 |
| `q` | 退出 |

### 导出流程

1. 列表界面按 `e`；
2. 提示 `导出范围：0=全部 或输入序号（1,3,5）`：
   - 输入 **`0`**（或直接回车）→ 导出全部；
   - 输入 `1` → 只导出第 1 条；`1,3,5` → 导出第 1、3、5 条。
3. 提示 `导出格式：1=TXT 2=CSV`，回车默认 TXT；
4. 导出过程中在 stderr 显示进度条，完成后输出文件名。

> 说明：`0` 专用于"全部"，与从 1 开始的序号互不冲突。列表中的 `0`、越界序号、重复序号都会被安全忽略。

导出文件命名：`WiFi密码导出_<YYYYMMDD_HH-MM-SS>.txt`（中文界面）/ `WiFi_Password_Export_<...>.csv`。

---

## 功能对照 / Feature Parity

| 功能 / Feature | BAT | Go | Rust |
|---|---|---|---|
| 查看 WiFi 列表 / List WiFi | ✅ | ✅ | ✅ |
| 按序号/名称查询 / Query by index/name | ✅ | ✅ | ✅ |
| 模糊搜索 / Fuzzy search | ✅ | ✅ | ✅ |
| 密码强度 / Password strength | ✅ | ✅ | ✅ |
| 密码显示/隐藏 / Show/hide toggle | ✅ | ✅ | ✅ |
| 查询历史 / Query history | ✅ | ✅ | ✅ |
| 批量导出 TXT / Export TXT | ✅ | ✅ | ✅ |
| 批量导出 CSV / Export CSV | ✅ | ✅ | ✅ |
| WiFi 连接字符串 / Connect string | ✅ | ✅ | ✅ |
| QR 码 / QR code | ❌ | ✅ (PNG) | ✅ (SVG) |
| 21 语言解析 / 21-lang parsing | ✅ | ✅ | ✅ |
| 自动语言检测 / Auto lang detect | ✅ | ✅ | ✅ |
| ANSI 颜色 / ANSI colors | ✅ | ✅ | ✅ |
| VT-100 降级 / VT fallback | ❌ | ✅ | ✅ |
| SSID 注入防护 / Injection guard | ❌ | ✅ | ✅ |
| Ctrl+C 优雅退出 / Graceful exit | ❌ | ✅ | ✅ |
| Panic 恢复 / Panic recovery | ❌ | ✅ | ✅ |
| 空列表早退 / Empty-state guard | ❌ | ✅ | ✅ |
| 文件名防覆盖 / Unique filename | ❌ | ✅ | ✅ |
| `-h` / `-v` 命令行开关 / CLI flags | ❌ | ❌ | ✅ |
| 单元测试 / Unit tests | ❌ | ✅ (15 函数) | ✅ (**64 用例**) |

---

## 技术细节 / Technical Notes

### 依赖 / Dependencies

仅 1 个外部 crate：

| crate | 用途 |
|-------|------|
| `qrcode` 0.13 | QR 码矩阵生成（High 级纠错） |

其余全部使用 Rust 标准库 + 原生 Windows FFI：

- `std::process::Command` — 执行 `netsh`
- `kernel32.dll` FFI — `SetConsoleMode`（VT-100）
- `clip.exe` — 剪贴板（无需额外 crate）
- `reg query` — 语言检测（无需 `winreg` crate）

### CRT 启动与 TLS shim（重要）

用 rust-lld 链接 MSVC 目标时不会链接 MSVC CRT 启动代码，Rust 标准库依赖的
**TLS（线程局部存储）目录缺失**，程序一启动即崩溃（`0xc0000005` / `STATUS_ACCESS_VIOLATION`）。

`src/main.rs` 顶部的 `crt_shim` 模块手工补齐了这些内容：

- `.tls$` / `.tls$ZZZ` 两个边界符号，界定合并后的 `.tls` 段；
- `.data` 段中的 `_tls_index`（由 PE loader 写入本模块的 TLS slot）；
- `.rdata$T` 中的 `_tls_used`（完整 `IMAGE_TLS_DIRECTORY64`）。

修改链接配置或升级工具链时，请勿删除该模块。

### QR 码格式 / QR format

Rust 版输出 **SVG** 而非 PNG（Go 版），优势：

- 矢量图形，无限缩放不失真
- 文件更小（~2–5 KB vs ~20–50 KB PNG）
- 无需 `image` crate，依赖更少
- 浏览器直接打开

### 与 Go 版差异 / Differences from Go

| 方面 | Go 版 | Rust 版 |
|------|-------|---------|
| 二进制大小 | ~1.5 MB (UPX) | ~307 KB (无 UPX) |
| 启动速度 | ~5–10ms (runtime) | ~1ms (无 runtime) |
| QR 格式 | PNG (image crate) | SVG (纯字符串) |
| 内存安全 | GC 管理 | 编译期保证 |
| UTF-8 | string 是 []byte | 原生 UTF-8 |
| 日期时间 | time 包 | 内置算法（Howard Hinnant），按本地时区输出 |

---

## 测试 / Tests

```bash
cargo test
```

**64 个测试用例**，覆盖：

- `extract_password` — 中/英/德/丹/挪等关键词 + fallback
- `parse_profile_line` / `parse_profiles` — 多语言 netsh 输出解析（含空输出、开放网络）
- `escape_for_shell_arg` — 10 个注入防护用例（空格、`&`、`|`、引号、插入符等）
- `escape_xml` / `generate_qr_svg` — XML 转义与 SVG 生成
- `wifi_payload` — WiFi 连接字符串转义
- `password_strength` — 常见密码 / 强密码 / 连续 / 重复 / SSID 子串 / 双语标签
- `is_sequential` / `is_repeated` — 字符模式检测
- `sanitize_filename` / `unique_filename` — 净化与防覆盖（含多重冲突）
- `fuzzy_search` — 单 token / 多 token / 无匹配
- `parse_export_selection` — `0`=全部 / 序号映射 / 非法 token / 去重
- `do_export` — TXT 无 ANSI 污染、CSV 引号转义、越界索引跳过
- `timestamp_display` / `timestamp_filename` / `now_parts` — 格式与本地时区
- `lang_from_arg` / `is_valid_lang` / 字符串表键一致性

> 若在某些受监控/沙箱目录中运行测试时进程卡住，是因为测试会写临时文件；
> 换到普通目录（如 `%TEMP%`）执行测试二进制即可。

---

## 项目结构 / Project Layout

```
rust-wifi-view/
├── Cargo.toml           # 项目配置 + release profile
├── .cargo/
│   └── config.toml      # linker = lld-link.exe + rustflags（alternatename / libpath）
├── gen_libs.py          # 从系统 DLL 导出表生成导入库（一次性）
├── lld-link.exe         # rust-lld 副本，由 gen_libs.py 生成
├── winlibs/             # 生成的 .def / .lib 导入库
├── README.md            # 本文件
└── src/
    └── main.rs          # 单文件实现（~2000 行，含 crt_shim 与测试）
```

---

## 排障 / Troubleshooting

| 现象 | 原因与处理 |
|------|-----------|
| 提示"未检测到已保存的 WiFi 配置" | 本机从未连接过 WiFi；先连一次再运行 |
| 密码为空 | 开放网络（无密码），或未以管理员身份运行（`key=clear` 需要管理员） |
| 中文乱码 | netsh 输出已通过 `chcp 65001` 按 UTF-8 读取；若控制台显示仍乱码，改用 Windows Terminal 等 UTF-8 终端 |
| Ctrl+C 无响应 | 已注册 console control handler，正常应打印 `[Ctrl+C] Bye.` 后退出；若无效请确认在真实控制台（而非重定向管道）中运行 |
| 启动即崩溃 `0xc0000005` | `.cargo/config.toml` 未生效或 `winlibs/` 缺失；重新运行 `python gen_libs.py` 后再构建 |
| 链接报 `undefined symbol` | 缺导入库；确认 `winlibs/` 下 `.lib` 齐全，必要时重跑 `gen_libs.py` |
| 导出文件打不开/乱码 | 文件带 UTF-8 BOM，Excel 可直接打开；非 Excel 编辑器请选择 UTF-8 编码 |

---

## 开源协议 / License

[MIT License](../LICENSE)

## 参考 / References

- [BAT 版](../bat-wifi-view/) — Batch 脚本实现
- [Go 版](../go-wifi-view/) — Go 单文件实现
- [语言支持总览](../go-wifi-view/Language_Support.md) — 21 种语言 netsh 关键词映射
- [CHANGELOG](../CHANGELOG.md) — 项目变更日志
