# Rust 交叉编译与链接陷阱

## 1. rust-lld 链接 MSVC 目标无 CRT 启动代码

**症状**：链接成功但运行时 `0xc0000005` 崩溃

**原因**：rust-lld 链接 MSVC 目标时不自动提供 CRT 启动 TLS 代码

**解决**：手工补齐 TLS shim

```rust
// 在 main.rs 中添加
#[used]
static _TLS_USED: u32 = 0;

#[no_mangle]
static mut _tls_index: u32 = 0;

// .CRT$XLA / .CRT$XLZ 节区
#[link_section = ".CRT$XLA"]
static _CRT_XLA: extern "C" fn() = _tls_callback;

#[link_section = ".CRT$XLZ"]
static _CRT_XLZ: extern "C" fn() = _tls_callback;

extern "C" fn _tls_callback() {}
```

## 2. 缺少 Windows SDK 导入库

**症状**：链接报 `undefined symbol`，找不到 `kernel32.lib` 等

**原因**：无 Windows SDK / MSVC Build Tools

**解决**：`gen_libs.py` 从系统 DLL 导出表生成导入库

```python
# gen_libs.py
# 1. 用 dumpbin 或自定义 PE 解析器读取 DLL 导出表
# 2. 生成 .def 文件
# 3. 用 lld-link /def 生成 .lib 导入库
```

```
winlibs/
  kernel32.lib
  user32.lib
  advapi32.lib
  ...
```

## 3. lld-link 配置

**`.cargo/config.toml`**：

```toml
[target.x86_64-pc-windows-msvc]
linker = "lld-link"
rustflags = [
    "/alternatename:mainCRTStartup=main",
    "/alternatename:?type_info@@...=placeholder",
]
```

- `lld-link.exe` 放在项目根目录或 PATH 中
- `/alternatename` 映射未定义符号到已知符号

## 4. 体积优化

**`Cargo.toml`**：

```toml
[profile.release]
opt-level = "z"      # 最小体积
lto = true            # 链接时优化
strip = true          # 去除符号
panic = "abort"       # abort 而非 unwind
codegen-units = 1     # 单编译单元
```

产物约 307 KB，无需 UPX。

## 5. QR 码生成

```rust
// Cargo.toml: qrcode = "0.13"
use qrcode::{QrCode, EcLevel};
use qrcode::render::svg::Color;

let code = QrCode::with_error_correction_level(payload, EcLevel::H)?;
let svg = code.render()
    .min_dimensions(200, 200)
    .dark_color(Color("#000000"))
    .light_color(Color("#FFFFFF"))
    .build();
// svg 是 String，写入 .svg 文件
```