# 多语言适配

## 1. 语言检测

### PowerShell

```powershell
# 方法 1：注册表
$reg = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' -ErrorAction SilentlyContinue
$locale = if ($reg) { $reg.InstallLanguage } else { '0409' }
# 0409 = English, 0804 = Chinese (Simplified), 0411 = Japanese, 0412 = Korean
```

### Go

```go
// 读取注册表（需 golang.org/x/sys/windows/registry）
k, _ := registry.OpenKey(registry.LOCAL_MACHINE, `SYSTEM\CurrentControlSet\Control\Nls\Language`, registry.QUERY_VALUE)
defer k.Close()
val, _, _ := k.GetStringValue("InstallLanguage")
```

### Rust

```rust
// Win32 API
use windows::Win32::System::Registry::*;
let mut buf = [0u16; 16];
let mut len = 0u32;
unsafe {
    RegGetValueW(
        HKEY_LOCAL_MACHINE,
        w!("SYSTEM\\CurrentControlSet\\Control\\Nls\\Language"),
        w!("InstallLanguage"),
        RRF_RT_REG_SZ,
        None,
        Some(buf.as_mut_ptr() as *mut _),
        Some(&mut len),
    );
}
```

## 2. 支持的 21 种语言

| 语言 | 代码 | Profile 关键词 | Password 关键词 |
|------|------|---------------|----------------|
| English | en | `profile` | `Key Content` |
| 中文 | zh | `配置文件` | `密钥内容` |
| 日本語 | ja | `プロファイル` | `キーコンテンツ` |
| 한국어 | ko | `프로필` | `키 콘텐츠` |
| Deutsch | de | `profil` | `Schlüsselinhalt` |
| Français | fr | `profil` | `Contenu de la clé` |
| Español | es | `perfil` | `Contenido de la clave` |
| Português | pt | `perfil` | `Conteúdo da chave` |
| Italiano | it | `profilo` | `Contenuto della chiave` |
| Polski | pl | `profil` | `Zawartosc klucza` |
| Nederlands | nl | `profiel` | `Sleutelinhoud` |
| Русский | ru | `профиль` | `Содержание ключа` |
| Türkçe | tr | `profil` | `Anahtar İçeriği` |
| العربية | ar | `profile` | `Key Content` |
| עברית | he | `profile` | `Key Content` |
| Čeština | cs | `profil` | `Key Content` |
| Magyar | hu | `profil` | `Kulcstartalom` |
| Svenska | sv | `profil` | `Nyckelinnehall` |
| Suomi | fi | `profiili` | `Avaimen sisalto` |
| Dansk | da | `profil` | `Nøgleindhold` |
| Norsk | no | `profil` | `Nøkkelinnhold` |

## 3. PowerShell 码点构建函数

> **核心陷阱**：PS 5.1 中 `'N' + [char]0xF8 + 'gleindhold'` 会截断为 `"N"`，必须用 `U()` 函数。

```powershell
function U { -join ($args | ForEach-Object { [char]$_ }) }

# 示例
$zhPwd    = U 0x5BC6 0x94AE 0x5185 0x5BB9        # 密钥内容
$jaPwd    = U 0x30AD 0x30FC 0x30B3 0x30F3 0x30C6 0x30F3 0x30C4  # キーコンテンツ
$daPwd    = U 0x4E 0xF8 0x67 0x6C 0x65 0x69 0x6E 0x64 0x68 0x6F 0x6C 0x64  # Nøgleindhold
$noPwd    = U 0x4E 0xF8 0x6B 0x6B 0x65 0x6C 0x69 0x6E 0x6E 0x68 0x6F 0x6C 0x64  # Nøkkelinnhold
```

## 4. 界面语言

- `zh` → 中文界面
- `en` → 英文界面
- 其余语言 → 界面回退英文，但 netsh 解析仍用对应语言关键词

## 5. 关键词匹配逻辑

```
Extract-Password(line):
  ci = line.IndexOf(':')
  if ci < 0: return null
  before = line[0..ci]
  after  = line[ci+1..].trim()
  if after == "": return null
  for kw in passwordKeywords:
    if before.Contains(kw): return after
  # fallback: 英文 "key" + "content" 同时出现
  if before.ToLower() contains "key" and "content": return after
  return null
```

> **关键**：只在冒号**前**匹配关键词，防止 `Type : Wireless LAN` 等行误匹配。