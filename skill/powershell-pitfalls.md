# PowerShell 5.1 陷阱全集

## 1. 编码：无 BOM UTF-8 按 ANSI 解析

**症状**：脚本中中文字面量乱码

**原因**：PS 5.1 对无 BOM 的 UTF-8 文件按系统 ANSI 代码页（如 GBK 936）解析

**解决**：全 ASCII 写法，所有非 ASCII 文案用 `U()` 码点拼接

```powershell
function U { -join ($args | ForEach-Object { [char]$_ }) }
$title = 'WiFi' + (U 0x5BC6 0x7801 0x67E5 0x8BE2 0x5DE5 0x5177)  # WiFi密码查询工具
```

## 2. switch 默认匹配所有 case

**症状**：`$score` 变成数组，显示 `System.Object[]`

**原因**：PS `switch` 默认评估**所有**条件为真的 case（不像 C/Go 只匹配第一个）

```powershell
# ❌ 危险：长度 12 会匹配 <=15、<=19 两个 case
$score = switch ($len) {
    { $_ -le 7 }  { 0 }
    { $_ -le 11 } { 1 }
    { $_ -le 15 } { 2 }
    { $_ -le 19 } { 3 }
    default       { 4 }
}
# $score = @(2, 3) → 传给 [int] 参数时报错

# ✅ 正确：每个 case 加 break
$score = switch ($len) {
    { $_ -le 7 }  { 0; break }
    { $_ -le 11 } { 1; break }
    { $_ -le 15 } { 2; break }
    { $_ -le 19 } { 3; break }
    default       { 4 }
}
```

## 3. `$input` 是只读自动变量

**症状**：`Cannot overwrite variable Input because it is read-only or constant`

**解决**：改用 `$line` 等普通变量名

## 4. `[string] + [char]` 拼接截断

**症状**：`'N' + [char]0xF8 + 'gleindhold'` 结果是 `"N"` 而非 `"Nøgleindhold"`

**影响**：关键词退化为单字符 `"N"`，所有含 N 的行误匹配

**解决**：用 `U()` 函数构建

```powershell
# ❌ 截断
$kw = 'N' + [char]0x00F8 + 'gleindhold'

# ✅ 正确
$kw = U 0x4E 0xF8 0x67 0x6C 0x65 0x69 0x6E 0x64 0x68 0x6F 0x6C 0x64
```

## 5. Add-Type C# 5.0 限制

**症状**：`error CS0136: 不能在此范围内声明名为"totalData"的局部变量`

**原因**：PS 5.1 的 `Add-Type` 使用 C# 5.0 编译器，不允许嵌套范围内同名变量

**解决**：内层用不同变量名（`td` / `lb`）

## 6. `[System.Collections.ArrayList]@()` 构造失败

**症状**：`Cannot convert` 错误

**解决**：用 `New-Object`

```powershell
# ❌
$list = [System.Collections.ArrayList]@()

# ✅
$list = New-Object System.Collections.ArrayList
```

## 7. 单引号字符串不转义 `` `r ``

**症状**：进度条回车不生效

**解决**：用 `[char]13` 或双引号

```powershell
# ❌ 单引号不转义
$cr = '`r'

# ✅
$cr = [char]13
# 或
$cr = "`r"
```

## 8. `U` 函数参数绑定

**症状**：`positional parameter cannot be found`

**原因**：`function U([int[]]$codes)` 用空格分隔多实参调用报错

**解决**：用 `$args` 收集

```powershell
# ❌
function U([int[]]$codes) { ... }
U 0x914D 0x7F6E  # 报错

# ✅
function U { -join ($args | ForEach-Object { [char]$_ }) }
U 0x914D 0x7F6E  # 正常
```

## 9. netsh 编码处理

```powershell
# 脚本启动时
try { & chcp 65001 > $null } catch {}
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

# 调用 netsh（chcp 65001 在 cmd.exe 内部执行）
$out = & cmd.exe /c 'chcp 65001 >nul & netsh wlan show profiles' 2>$null
```

> **不要**在 PS 中单独 `chcp 936` 切换编码再运行 netsh — 管道编码不受 `chcp` 影响，反而导致乱码。