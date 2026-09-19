# QR 码生成

## 1. WiFi 连接字符串

```
WIFI:T:<auth>;S:<SSID>;P:<password>;;
```

| 字段 | 说明 | 示例 |
|------|------|------|
| T | 认证类型 | `WPA` / `WEP` / `nopass` |
| S | SSID（特殊字符用 `\\` 转义） | `CMCC-Home-5G` |
| P | 密码 | `mypassword` |

```
WIFI:T:WPA;S:CMCC-Home-5G;P:mypassword;;
```

## 2. Go 实现（PNG）

```go
import "github.com/skip2/go-qrcode"

func generateQR(payload, filename string) error {
    return qrcode.WriteFile(payload, qrcode.High, 256, filename)
}
```

依赖：`github.com/skip2/go-qrcode`，生成 PNG，自动打开。

## 3. Rust 实现（SVG）

```rust
use qrcode::{QrCode, EcLevel};
use qrcode::render::svg::Color;

fn generate_qr_svg(payload: &str) -> String {
    let code = QrCode::with_error_correction_level(payload, EcLevel::H).unwrap();
    code.render()
        .min_dimensions(200, 200)
        .dark_color(Color("#000000"))
        .light_color(Color("#FFFFFF"))
        .build()
}
```

依赖：`qrcode` crate，输出 SVG 矢量图。

## 4. PowerShell 实现（内嵌 C# SVG）

### 架构

```
.ps1 脚本
  └─ $QrCs (here-string 内嵌 C# 代码)
       └─ Add-Type -TypeDefinition $QrCs  ← 运行时编译
            └─ [QrSvg]::Generate(payload, label, scale)
                 └─ 返回 SVG 字符串
```

### C# QR 编码器核心

```csharp
public static class QrSvg
{
    // GF(256) 指数/对数表
    private static readonly int[] EXP;
    private static readonly int[] LOG;

    // RS 纠错参数表 [version][level] = {ecPerBlock, g1Blocks, g1Data, g2Blocks, g2Data}
    private static readonly int[][][] RS = ...;

    // 版本 1-10，纠错等级 H→Q→M→L 自适应
    public static string Generate(string text, string label, int scale)
    {
        byte[] data = Encoding.UTF8.GetBytes(text);
        // 1. 选择最小版本
        // 2. 构建位流：mode(4) + length + data + pad
        // 3. RS 纠错编码 + 交织
        // 4. 填充矩阵 + mask 0
        // 5. 格式信息 BCH
        // 6. 输出 SVG
    }
}
```

### Add-Type 编译

```powershell
function Ensure-Qr {
    if ($script:QrReady) { return $true }
    if ('QrSvg' -as [type]) { $script:QrReady = $true; return $true }  # 已加载
    try {
        Add-Type -TypeDefinition $QrCs -ErrorAction Stop
        $script:QrReady = $true
    } catch {
        # 备用：CSharpCodeProvider 直接编译
        $provider = New-Object Microsoft.CSharp.CSharpCodeProvider
        $params = New-Object System.CodeDom.Compiler.CompilerParameters
        $params.GenerateInMemory = $true
        $result = $provider.CompileAssemblyFromSource($params, $QrCs)
        [void][Reflection.Assembly]::Load($result.CompiledAssembly)
        $script:QrReady = $true
    }
}
```

### C# 5.0 限制（CS0136）

```csharp
// ❌ 错误：内层与外层同名
foreach (int v in versions) {
    int totalData = ...;  // 内层
}
int totalData = ...;      // 外层 → CS0136

// ✅ 正确：内层用不同名
foreach (int v in versions) {
    int td = ...;         // 内层
}
int totalData = ...;      // 外层
```

## 5. QR 编码原理简述

1. **数据编码**：byte 模式，每字节 8 位
2. **版本选择**：根据数据长度选最小版本（1–40），本工具限 1–10
3. **RS 纠错**：GF(256) 上 Reed-Solomon 编码，生成多项式 `x^8 + x^4 + x^3 + x^2 + 1`（0x11D）
4. **数据交织**：多块数据按规则交织，提高抗错能力
5. **矩阵填充**：功能图案（finder + timing + alignment）→ 数据 zigzag 填充
6. **掩码**：固定 mask 0（`(r+c) % 2 == 0` 翻转）
7. **格式信息**：5 位数据 + 10 位 BCH，异或掩码图案 0x5412