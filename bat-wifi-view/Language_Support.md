# Language Support / 语言支持

This document describes the multi-language support in the BAT edition of the WiFi Password Query Tool. Both the user-interface language detection and the `netsh` output parser cover **21 languages** (auto-detected from the system, or forced via command-line argument).

本文档说明 BAT 版 WiFi 密码查询工具的多语言支持。UI 语言自动检测和 `netsh` 输出解析覆盖 **21 种语言**（自动从系统识别，或通过命令行参数强制指定）。

---

## Supported Languages (21)

| Code | Native Name | English Name | Example Locale | Windows LCID | netsh Password Keyword |
|------|-------------|--------------|----------------|--------------|------------------------|
| `zh` | 简体中文 / 繁體中文 | Chinese | `zh-CN`, `zh-TW`, `zh-HK` | 2052, 1028, 3076 | `关键内容` |
| `en` | English | English | `en-US`, `en-GB`, `en-AU`, `en-CA` | 1033, 2057, 3081, 4105 | `Key Content` |
| `ja` | 日本語 | Japanese | `ja-JP` | 1041 | `キー コンテンツ` |
| `ko` | 한국어 | Korean | `ko-KR` | 1042 | `키 콘텐츠` |
| `de` | Deutsch | German | `de-DE`, `de-AT`, `de-CH` | 1031, 3079, 2055 | `Schlüsselinhalt` |
| `fr` | Français | French | `fr-FR`, `fr-CA`, `fr-CH` | 1036, 3084, 4108 | `Contenu de la clé` |
| `ru` | Русский | Russian | `ru-RU` | 1049 | `Содержимое ключа` |
| `es` | Español | Spanish | `es-ES`, `es-MX`, `es-AR` | 1034, 2058, 11274 | `Contenido de la clave` |
| `it` | Italiano | Italian | `it-IT`, `it-CH` | 1040, 2064 | `Contenuto della chiave` |
| `pt` | Português | Portuguese | `pt-PT`, `pt-BR` | 2070, 1046 | `Conteúdo da chave` |
| `pl` | Polski | Polish | `pl-PL` | 1045 | `Zawartosc klucza` |
| `nl` | Nederlands | Dutch | `nl-NL`, `nl-BE` | 1043, 2067 | `Sleutelinhoud` |
| `tr` | Türkçe | Turkish | `tr-TR` | 1055 | `Anahtar Içerigi` |
| `ar` | العربية | Arabic | `ar-SA`, `ar-EG`, `ar-AE` | 1025, 3073, 14337 | `محتوى المفتاح` |
| `he` | עברית | Hebrew | `he-IL` | 1037 | `תוכן המפתח` |
| `cs` | Čeština | Czech | `cs-CZ` | 1029 | `Obsah klíče` |
| `hu` | Magyar | Hungarian | `hu-HU` | 1038 | `Kulcstartalom` |
| `sv` | Svenska | Swedish | `sv-SE` | 1053 | `Nyckelinnehall` |
| `fi` | Suomi | Finnish | `fi-FI` | 1035 | `Avaimen sisalto` |
| `da` | Dansk | Danish | `da-DK` | 1030 | `Nøgleindhold` |
| `no` | Norsk | Norwegian | `nb-NO`, `nn-NO` | 1044, 2068 | `Nøkkelinnhold` |

---

## Auto-detection Flow / 自动检测流程

The BAT script uses a three-tier detection strategy (highest priority first):

脚本使用三层检测策略（优先级从高到低）：

### 1. Command-line Argument / 命令行参数
```batch
wifi_password_tool_auto.bat zh
wifi_password_tool_auto.bat en
wifi_password_tool_auto.bat ja
```
If the first argument matches a known language code, it overrides everything else.
若第一个参数匹配已知语言代码，则强制使用该语言。

### 2. Registry LocaleName / 注册表 LocaleName
```
HKCU\Control Panel\International!LocaleName
```
Reads the Windows user locale (e.g. `zh-CN`, `en-US`, `ja-JP`) and extracts the leading two-letter ISO 639-1 code.

读取 Windows 用户区域设置（如 `zh-CN`、`en-US`、`ja-JP`），提取前两位 ISO 639-1 代码。

### 3. wmic OSLanguage LCID Map / wmic 语言代码映射
Falls back to the legacy `wmic os get oslanguage` and maps Windows LCIDs to language codes. Covers the 21 LCIDs listed in the table above.

回退到旧的 `wmic os get oslanguage`，将 Windows LCID 映射为语言代码。覆盖上表中的 21 个 LCID。

### 4. LANG Environment Variable / LANG 环境变量
Last resort: read `LANG` from the environment (used by Git Bash, Cygwin, MSYS2). Format: `zh_CN.UTF-8` → `zh`.

最后手段：从环境变量 `LANG` 读取（如 `zh_CN.UTF-8` → `zh`）。

### 5. Default / 默认值
If all detection methods fail, defaults to `en`.

若全部失败，默认使用英文界面。

---

## Forcing a Specific Language / 强制指定语言

```batch
REM Use detected language
wifi_password_tool_auto.bat

REM Force Chinese (Simplified)
wifi_password_tool_auto.bat zh

REM Force English
wifi_password_tool_auto.bat en

REM Force Japanese
wifi_password_tool_auto.bat ja

REM ... any of the 21 codes above
```

---

## UI Translation Status / 界面翻译状态

| Language | Full UI Translation | Detection | netsh Parsing |
|----------|--------------------|-----------|--------------|
| `zh` (Chinese) | ✅ Yes | ✅ | ✅ |
| `en` (English) | ✅ Yes | ✅ | ✅ |
| `ja, ko, de, fr, ru, es, it, pt, pl, nl, tr, ar, he, cs, hu, sv, fi, da, no` (19 others) | ⚠️ Falls back to English | ✅ | ✅ |

**Explanation:**
- **zh** and **en** have complete UI string tables (menu items, prompts, error messages, etc.).
- The other **19 languages** are correctly **detected** and their locale code is displayed in the header line `[Auto-detected: 日本語 / ja-JP]` so the user knows what was recognized.
- Their UI text falls back to the English string table — because the `netsh` parser is the only piece that genuinely needs to handle 18+ languages (Windows itself localizes `netsh wlan show profiles` output into the system language).
- All 21 languages' `netsh` output is correctly parsed for password retrieval.

**说明：**
- **zh** 和 **en** 有完整的 UI 字符串表（菜单项、提示、错误信息等）。
- 其他 **19 种语言**能被正确**识别**，locale 代码会显示在标题行 `[Auto-detected: 日本語 / ja-JP]` 让用户知道识别结果。
- UI 文字回退到英文字符串表 —— 因为只有 `netsh` 解析器真正需要处理 18+ 种语言（Windows 本身就会把 `netsh wlan show profiles` 的输出本地化为系统语言）。
- 所有 21 种语言的 `netsh` 输出都能被正确解析密码。

---

## netsh Output Parsing / netsh 输出解析

The BAT script parses `netsh wlan show profiles` output with **format-agnostic** matching: the part after the **last `:`** is treated as the WiFi name. This works regardless of system language, since `netsh` always emits `Name : <profile>`.

Additionally, the password line is detected by matching one of these locale-specific keywords:

脚本用**与格式无关**的方式解析 `netsh wlan show profiles` 输出：最后一个 `:` 之后的部分被当作 WiFi 名称。这种方式与系统语言无关，因为 `netsh` 始终输出 `Name : <profile>`。

密码行通过匹配下列本地化关键字之一来识别：

```
Key Content                  (en)
关键内容                      (zh)
キー コンテンツ / キーコンテンツ (ja)
키 콘텐츠                    (ko)
Schlüsselinhalt              (de)
Contenu de la clé            (fr)
Содержимое ключа             (ru)
Contenido de la clave        (es)
Contenuto della chiave       (it)
Conteúdo da chave            (pt)
Zawartosc klucza             (pl)
Sleutelinhoud                (nl)
Anahtar Içerigi              (tr)
محتوى المفتاح                (ar)
תוכן המפתח                    (he)
Obsah klíče                  (cs)
Kulcstartalom                (hu)
Nyckelinnehall               (sv)
Avaimen sisalto              (fi)
Nøgleindhold                 (da)
Nøkkelinnhold                (no)
```

### Profile Type Variants / 配置文件类型变体

For the "All User Profile" / "Current User Profile" labels, the parser matches:
对于"所有用户配置文件"/"当前用户配置文件"标签，匹配下列变体：

```
AllUserProfile, CurrentUserProfile, 所有用户配置文件, 当前用户配置,
すべてのユーザープロファイル, 現在のユーザープロファイル,
모든사용자프로필, 현재사용자프로필
```

---

## Examples / 加 `BAT` 示例

### Detect `ja-JP` System / 识别日文系统
On a Japanese Windows, the script auto-detects `ja` and shows:
在日文 Windows 上，脚本自动识别为 `ja` 并显示：
```
          WiFi密码查询工具
          [Auto-detected: 日本語 / ja-JP]   ← (after rebuild with ja strings) or
          [Auto-detected: ja-JP]            ← (current behavior — falls back to English UI)
```

### Force `zh` on Any System / 在任意系统强制中文
```batch
wifi_password_tool_auto.bat zh
```
All UI text is rendered in Chinese regardless of system locale.
所有界面文字以中文呈现，与系统区域设置无关。

### Force `en` on Chinese System / 在中文系统强制英文
```batch
wifi_password_tool_auto.bat en
```
All UI text is rendered in English.
所有界面文字以英文呈现。

---

## Troubleshooting / 故障排查

| Issue / 问题 | Cause / 原因 | Solution / 解决方案 |
|--------------|-------------|---------------------|
| Wrong language detected / 检测到错误语言 | Registry `LocaleName` overridden by app / 注册表被应用覆写 | Pass code as arg: `wifi_password_tool_auto.bat zh` |
| `[Auto-detected: xx]` shows but UI is English / 显示识别但 UI 是英文 | Expected: only `zh` and `en` have full UI strings / 符合预期：仅 zh/en 有完整 UI | Use `wifi_password_tool_auto.bat zh` for Chinese UI |
| Password not found despite correct WiFi / WiFi 正确但找不到密码 | `netsh` output uses unexpected locale keyword / netsh 输出使用了未覆盖的关键字 | Run `netsh wlan show profiles name="YourWiFi" key=clear` manually and inspect output |
| `wmic` deprecated on Win11 24H2+ / Win11 24H2+ 已弃用 `wmic` | Microsoft phasing out WMI command-line / Microsoft 弃用 WMI 命令行工具 | Registry detection (step 2) still works; if it fails, use LANG env var or CLI arg |

---

## See Also / 相关文档

- 📖 [WiFi密码查询工具使用说明.md](WiFi密码查询工具使用说明.md) — Chinese user manual
- 📖 [WiFi_Password_Query_Tool_Manual.md](WiFi_Password_Query_Tool_Manual.md) — English user manual
- 📖 [README.md](../README.md) — Project overview

---

**Version:** v3.1 (September 2026)
**Coverage:** 21 languages for detection + `netsh` parsing; 2 languages (`zh`, `en`) for full UI translation.
</content>
</invoke>