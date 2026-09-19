# netsh 解析与编码处理

## 1. netsh 命令

### 列出所有已保存 WiFi 配置

```cmd
netsh wlan show profiles
```

输出格式（英文系统）：
```
Profiles on interface Wi-Fi:

Group policy profiles (read only)
    <none>

User profiles
    All User Profile     : CMCC-Home-5G
    All User Profile     : Office-WiFi
```

输出格式（中文系统）：
```
接口 WLAN 上的配置文件:

组策略配置文件（只读）
    <无>

用户配置文件
    所有用户配置文件     : CMCC-Home-5G
```

### 查询单个 WiFi 密码

```cmd
netsh wlan show profile name="SSID" key=clear
```

密码行格式（英文）：
```
    Key Content            : mypassword
```

密码行格式（中文）：
```
    密钥内容               : mypassword
```

> **需要管理员权限**，否则密码行不显示。

## 2. 编码处理

### 问题

netsh 输出使用系统 OEM/ANSI 代码页（如 GBK 936）。直接捕获会乱码。

### Go 方案

```go
cmd := exec.Command("cmd", "/c", "chcp 65001 >nul & netsh wlan show profiles")
cmd.Stdout = &buf
cmd.Stderr = nil
cmd.Run()
// buf 现在是 UTF-8
```

### PowerShell 方案

```powershell
# 脚本启动时设置
try { & chcp 65001 > $null } catch {}
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

# 调用 netsh
$out = & cmd.exe /c 'chcp 65001 >nul & netsh wlan show profiles' 2>$null
# $out 已是 UTF-8 解码的字符串数组
```

### Rust 方案

```rust
let output = Command::new("cmd")
    .args(&["/c", "chcp 65001 >nul & netsh wlan show profiles"])
    .output()?;
let text = String::from_utf8_lossy(&output.stdout);
```

## 3. 解析逻辑

### Profile 列表解析

```
对每行:
  找冒号位置 ci
  before = 行[:ci]  （转小写）
  after  = 行[ci+1:].trim()
  如果 before 包含 profile 关键词 且 after 非空 且不以 '<' 开头:
    加入 profile 列表
```

### Password 提取

```
对每行:
  找冒号位置 ci
  before = 行[:ci]
  after  = 行[ci+1:].trim()
  如果 before 包含 password 关键词:
    返回 after 作为密码
```

> **关键**：关键词匹配只在冒号**前**的文本中查找，避免字段值误匹配。

## 4. SSID 注入防护

SSID 通过 `name="SSID"` 传入 cmd.exe，需转义特殊字符：

```
^ → ^^
& → ^&
| → ^|
< → ^<
> → ^>
( → ^(
) → ^)
, → ^,
; → ^;
" → ""
```

Go 实现：
```go
func escapeForShellArg(s string) string {
    replacer := strings.NewReplacer("^", "^^", "&", "^&", "|", "^|", "<", "^<", ">", "^>", "(", "^(", ")", "^)", ",", "^,", ";", "^;", "\"", "\"\"")
    return replacer.Replace(s)
}
```

PowerShell 实现：
```powershell
function Escape-ForShellArg([string]$s) {
    return $s.Replace('^','^^').Replace('&','^&').Replace('|','^|').Replace('<','^<').Replace('>','^>').Replace('(','^(').Replace(')','^)').Replace(',','^,').Replace(';','^;').Replace('"','""')
}
```