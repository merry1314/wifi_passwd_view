#requires -Version 5.1
<#
  ============================================================
  WiFi Password Query Tool v3.2 (PowerShell edition)
  Single-file reimplementation of the BAT / Go / Rust editions.
  Zero-install: runs on any Windows 10/11 with built-in PowerShell.

  Run:
      powershell -ExecutionPolicy Bypass -File wifi_password_tool.ps1

  Features:
    - List saved WiFi networks (indexed from 1)
    - Query password by index / name / fuzzy search (/keyword)
    - 21-language netsh output parsing (zh/en/ja/ko/de/fr/ru/es/it/
      pt/pl/nl/tr/ar/he/cs/hu/sv/fi/da/no)
    - Automatic UI language detection (zh / en full UI, others fall back to en)
    - Password strength scoring (0-5) with progress bar
    - Show/hide password, auto-copy to clipboard
    - Copy WiFi connect string (WIFI:T:WPA;S:ssid;P:pwd;;)
    - QR code as SVG (vector, high error correction) via embedded C# encoder
    - Export TXT / CSV (UTF-8 BOM, RFC 4180 quoting), selectable range
    - Query history (last 10), progress bar, ANSI colors
    - The whole file is pure ASCII; all non-ASCII text is built from
      Unicode code points, so no BOM / encoding issues anywhere.
  ============================================================
#>
param()

$UserArgs = @($args)
$Version  = '3.2.1'

# ============================================================
# 0. Console setup
# ============================================================
try { & chcp 65001 > $null } catch {}
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
try { [Console]::InputEncoding  = [Text.Encoding]::UTF8 } catch {}
$OutputEncoding = [Text.Encoding]::UTF8

# Colors on/off (NO_COLOR env or redirected output disables them)
$script:Color = $true
if ($env:NO_COLOR) { $script:Color = $false }
if ([Console]::IsOutputRedirected) { $script:Color = $false }

function P([string]$code) { if ($script:Color) { $code } else { '' } }

# ANSI codes (esc built from char code -> file stays ASCII)
$Esc  = [char]27
$C_RESET = "$Esc[0m"
$C_TITLE = "$Esc[36m"
$C_OK    = "$Esc[32m"
$C_WARN  = "$Esc[33m"
$C_ERROR = "$Esc[31m"
$C_NAME  = "$Esc[33m"
$C_PWD   = "$Esc[97m"
$C_HINT  = "$Esc[90m"
$C_BAR_FILL  = "$Esc[42m"
$C_BAR_EMPTY = "$Esc[100m"

$Sep = ([string][char]0x2500) * 56    # ---- unicode box-drawing separator

# ============================================================
# 1. Unicode helper (build strings from code points)
# ============================================================
function U { -join ($args | ForEach-Object { [char]$_ }) }

# ============================================================
# 2. Common password blacklist
# ============================================================
$CommonPasswords = @(
    '123456','123456789','12345678','1234567','password','1234567890',
    '111111','123123','000000','admin','root','guest','user','test',
    'abc123','qwerty','password1','iloveyou','letmein','welcome',
    'monkey','dragon','master','sunshine','princess','football',
    'shadow','superman','michael','trustno1','password123','admin123','123abc'
)

# ============================================================
# 3. netsh parsing keywords (21 languages)
# ============================================================
# Profile label keywords (before the ':' of "All User Profile : xxx")
$ProfKw = @(
    'profile',                        # en
    'profil',                         # de / fr / sv / no / da partial
    'perfil',                         # es / pt
    (U 0x914D 0x7F6E 0x6587 0x4EF6),  # zh: 配置文件
    (U 0x30D7 0x30ED 0x30D5 0x30A1 0x30A4 0x30EB),  # ja: プロファイル
    (U 0xD504 0xB85C 0xD544),         # ko: 프로필
    (U 0x43F 0x440 0x43E 0x444 0x438 0x43B 0x44C)   # ru: профиль
)

# Password label keywords (after "Key Content : xxx")
$KwPwd = @(
    'Key Content',                     # en
    (U 0x5BC6 0x94AE 0x5185 0x5BB9),   # zh: 密钥内容
    (U 0x30AD 0x30FC 0x20 0x30B3 0x30F3 0x30C6 0x30F3 0x30C4),  # ja: キー コンテンツ
    (U 0x30AD 0x30FC 0x30B3 0x30F3 0x30C6 0x30F3 0x30C4),       # ja alt: キーコンテンツ
    (U 0x53 0x63 0x68 0x6C 0xFC 0x73 0x73 0x65 0x6C 0x69 0x6E 0x68 0x61 0x6C 0x74),  # de: Schlüsselinhalt
    (U 0x43 0x6F 0x6E 0x74 0x65 0x6E 0x75 0x20 0x64 0x65 0x20 0x6C 0x61 0x20 0x63 0x6C 0xE9),  # fr: Contenu de la clé
    'Contenido de la clave',                                    # es
    (U 0x421 0x43E 0x434 0x435 0x440 0x436 0x438 0x43C 0x43E 0x435 0x20 0x43A 0x43B 0x44E 0x447 0x430),  # ru
    (U 0x43 0x6F 0x6E 0x74 0x65 0xFA 0x64 0x6F 0x20 0x64 0x61 0x20 0x63 0x68 0x61 0x76 0x65),  # pt: Conteúdo da chave
    'Contenuto della chiave',                                   # it
    'Zawartosc klucza',                                         # pl
    'Sleutelinhoud',                                            # nl
    (U 0xD0A4 0x20 0xCF58 0xD150 0xCE58),                       # ko
    (U 0x41 0x6E 0x61 0x68 0x74 0x61 0x72 0x20 0x49 0x130 0xE7 0x65 0x72 0x69 0x67 0x69),  # tr: Anahtar İçeriği
    'Kulcstartalom',                                            # hu
    'Nyckelinnehall',                                           # sv
    'Avaimen sisalto',                                          # fi
    (U 0x4E 0xF8 0x67 0x6C 0x65 0x69 0x6E 0x64 0x68 0x6F 0x6C 0x64),  # da: Nøgleindhold
    (U 0x4E 0xF8 0x6B 0x6B 0x65 0x6C 0x69 0x6E 0x6E 0x68 0x6F 0x6C 0x64)   # no: Nøkkelinnhold
)

# ============================================================
# 4. UI strings (zh / en)
# ============================================================
function Get-Strings([string]$lang) {
    $s = @{}
    $zh = ($lang -eq 'zh')
    # title / subtitle
    if ($zh) {
        $s['title']    = 'WiFi' + (U 0x5BC6 0x7801 0x67E5 0x8BE2 0x5DE5 0x5177)
        $s['subtitle'] = (U 0x5DF2 0x4FDD 0x5B58 0x7684) + ' WiFi ' + (U 0x7F51 0x7EDC 0x5217 0x8868)
        $s['prompt']   = (U 0x8BF7 0x8F93 0x5165 0x5E8F 0x53F7 0x6216 0x540D 0x79F0) + " (/? " + (U 0x6A21 0x7CCA 0x641C 0x7D22) + ", e " + (U 0x5BFC 0x51FA) + ", h " + (U 0x5386 0x53F2) + ", q " + (U 0x9000 0x51FA) + ")"
        $s['found']          = (U 0x5DF2 0x627E 0x5230)
        $s['password']       = (U 0x5BC6 0x7801)
        $s['strength']       = (U 0x5F3A 0x5EA6)
        $s['copied']         = (U 0x5BC6 0x7801 0x5DF2 0x590D 0x5236 0x5230 0x526A 0x8D34 0x677F)
        $s['no_pwd']         = (U 0x8BE5) + ' WiFi ' + (U 0x6CA1 0x6709 0x4FDD 0x5B58 0x5BC6 0x7801)
        $s['not_found']      = (U 0x672A 0x627E 0x5230 0x5339 0x914D 0x7684) + ' WiFi'
        $s['export_time']    = (U 0x5BFC 0x51FA 0x65F6 0x95F4)
        $s['tool_version']   = (U 0x5BFC 0x51FA 0x5DE5 0x5177)
        $s['total_count']    = 'WiFi' + (U 0x603B 0x6570)
        $s['qr_generated']   = (U 0x4E8C 0x7EF4 0x7801 0x5DF2 0x751F 0x6210)
        $s['qr_path']        = (U 0x56FE 0x7247 0x8DEF 0x5F84)
        $s['press_exit']     = (U 0x6309 0x56DE 0x8F66 0x952E 0x9000 0x51FA) + '...'
        $s['show_pwd']       = '[s] ' + (U 0x663E 0x793A 0x5BC6 0x7801)
        $s['hide_pwd']       = '[s] ' + (U 0x9690 0x85CF 0x5BC6 0x7801)
        $s['qr_hint']        = '[r] ' + (U 0x751F 0x6210 0x4E8C 0x7EF4 0x7801)
        $s['copy_wifi']      = '[c] ' + (U 0x590D 0x5236 0x8FDE 0x63A5 0x4E32)
        $s['back']           = '[b] ' + (U 0x8FD4 0x56DE)
        $s['history_title']  = (U 0x67E5 0x8BE2 0x5386 0x53F2)
        $s['history_empty']  = (U 0x6682 0x65E0 0x67E5 0x8BE2 0x5386 0x53F2)
        $s['export_title']   = (U 0x5BFC 0x51FA 0x5B8C 0x6210)
        $s['exported_to']    = (U 0x5DF2 0x5BFC 0x51FA 0x5230)
        $s['select_range']   = (U 0x5BFC 0x51FA 0x8303 0x56F4) + ": 0=" + (U 0x5168 0x90E8) + ' ' + (U 0x6216 0x8F93 0x5165 0x5E8F 0x53F7) + ' (1,3,5)'
        $s['select_format']  = (U 0x5BFC 0x51FA 0x683C 0x5F0F) + ': 1=TXT 2=CSV'
        $s['search_prompt']  = (U 0x641C 0x7D22) + ' /'
        $s['err_export']     = (U 0x5BFC 0x51FA 0x5931 0x8D25)
        $s['select_invalid'] = (U 0x9009 0x62E9 0x65E0 0x6548 0xFF0C 0x672A 0x5BFC 0x51FA 0x4EFB 0x4F55 0x5185 0x5BB9)
        $s['usage_title']    = (U 0x4F7F 0x7528 0x65B9 0x5F0F)
        $s['version_label']  = (U 0x7248 0x672C)
        $s['copied_conn']    = 'WiFi ' + (U 0x8FDE 0x63A5 0x4E32 0x5DF2 0x590D 0x5236)
        $s['qr_fail']        = '[ERROR] QR ' + (U 0x751F 0x6210 0x5931 0x8D25) + ' (.NET ' + (U 0x7F16 0x8BD1 0x5668) + ' ' + (U 0x4E0D 0x53EF 0x7528) + ')'
        $s['pwd_label']      = (U 0x5BC6 0x7801) + ': '
        $s['err_no_profiles'] = '[INFO] ' + (U 0x672A 0x68C0 0x6D4B 0x5230 0x4EFB 0x4F55 0x5DF2 0x4FDD 0x5B58 0x7684) + ' WiFi ' + (U 0x914D 0x7F6E 0x3002 0x8BF7 0x5148 0x8FDE 0x63A5 0x4E00 0x4E2A) + ' WiFi ' + (U 0x540E 0x518D 0x8FD0 0x884C 0x672C 0x5DE5 0x5177 0x3002)
        $s['usage_body']     = 'wifi_password_tool.ps1 [zh|en|ja|...]  ' + (U 0x5F3A 0x5236 0x6307 0x5B9A 0x754C 0x9762) + ' / netsh ' + (U 0x8BED 0x8A00) + "`n" + '  wifi_password_tool.ps1 -h              ' + (U 0x663E 0x793A 0x5E2E 0x52A9) + "`n" + '  wifi_password_tool.ps1 -v              ' + (U 0x663E 0x793A 0x7248 0x672C) + "`n" + '  wifi_password_tool.ps1 -d              ' + (U 0x8BCA 0x65AD 0x6A21 0x5F0F)
    } else {
        $s['title']    = 'WiFi Password Query Tool'
        $s['subtitle'] = 'Saved WiFi networks'
        $s['prompt']   = 'Enter index or name (/? fuzzy, e export, h history, q quit)'
        $s['found']          = 'Found'
        $s['password']       = 'Password'
        $s['strength']       = 'Strength'
        $s['copied']         = 'Password copied to clipboard'
        $s['no_pwd']         = 'This WiFi has no saved password'
        $s['not_found']      = 'No matching WiFi found'
        $s['export_time']    = 'Export Time'
        $s['tool_version']   = 'Tool Version'
        $s['total_count']    = 'Total WiFi Count'
        $s['qr_generated']   = 'QR code generated'
        $s['qr_path']        = 'Image path'
        $s['press_exit']     = 'Press Enter to exit...'
        $s['show_pwd']       = '[s] Show password'
        $s['hide_pwd']       = '[s] Hide password'
        $s['qr_hint']        = '[r] Generate QR code'
        $s['copy_wifi']      = '[c] Copy connect string'
        $s['back']           = '[b] Back'
        $s['history_title']  = 'Query history'
        $s['history_empty']  = 'No query history'
        $s['export_title']   = 'Export complete'
        $s['exported_to']    = 'Exported to'
        $s['select_range']   = 'Export range: 0=all or enter indices (1,3,5)'
        $s['select_format']  = 'Export format: 1=TXT 2=CSV'
        $s['search_prompt']  = 'Search /'
        $s['err_export']     = 'Export failed'
        $s['select_invalid'] = 'Invalid selection, nothing exported'
        $s['usage_title']    = 'Usage'
        $s['version_label']  = 'Version'
        $s['copied_conn']    = 'WiFi connect string copied'
        $s['qr_fail']        = '[ERROR] QR generation failed (.NET compiler unavailable)'
        $s['pwd_label']      = 'Password: '
        $s['err_no_profiles'] = '[INFO] No saved WiFi profiles detected. Please connect to a WiFi network before running this tool.'
        $s['usage_body']     = 'wifi_password_tool.ps1 [zh|en|ja|...]   force UI / netsh language' + "`n" + '  wifi_password_tool.ps1 -h              show this help' + "`n" + '  wifi_password_tool.ps1 -v              show this version' + "`n" + '  wifi_password_tool.ps1 -d              debug mode'
    }

    return $s
}

# Strength labels
function Get-StrengthLabel([string]$lang, [int]$score) {
    if ($lang -eq 'zh') {
        switch ($score) {
            0 { $v = U 0x6781 0x5F31 }   # 极弱
            1 { $v = U 0x6781 0x5F31 }
            2 { $v = U 0x5F31 }           # 弱
            3 { $v = U 0x4E00 0x822C }    # 一般
            4 { $v = U 0x5F3A }           # 强
            default { $v = U 0x6781 0x5F3A }  # 极强
        }
        return $v
    }
    switch ($score) {
        0 { return 'Very weak' }
        1 { return 'Very weak' }
        2 { return 'Weak' }
        3 { return 'Fair' }
        4 { return 'Strong' }
        default { return 'Very strong' }
    }
}

# ============================================================
# 5. Language detection
# ============================================================
$SupportedLangs = @('zh','en','ja','ko','de','fr','ru','es','it','pt','pl','nl','tr','ar','he','cs','hu','sv','fi','da','no')

function Detect-Language {
    # 1. Command-line argument (skip -h / -v style flags)
    foreach ($a in $UserArgs) {
        if ($a.StartsWith('-') -or $a.StartsWith('/')) { continue }
        $la = $a.Trim().ToLower()
        if ($SupportedLangs -contains $la) { return $la }
    }
    # 2. Registry: HKCU\Control Panel\International -> LocaleName
    try {
        $ln = Get-ItemPropertyValue -Path 'HKCU:\Control Panel\International' -Name 'LocaleName' -ErrorAction Stop
        if ($ln) {
            $code = ($ln -split '-')[0].ToLower()
            if ($SupportedLangs -contains $code) { return $code }
        }
    } catch {}
    # 3. Get-WinSystemLocale (Win8+)
    try {
        $lc = (Get-WinSystemLocale).Name
        if ($lc) {
            $code = ($lc -split '-')[0].ToLower()
            if ($SupportedLangs -contains $code) { return $code }
        }
    } catch {}
    # 4. LANG environment variable
    $envLang = $env:LANG
    if ($envLang) {
        $code = ($envLang -split '-')[0].ToLower()
        if ($SupportedLangs -contains $code) { return $code }
    }
    return 'en'
}

# ============================================================
# 6. netsh operations
# ============================================================
function Get-WifiProfiles {
    $out = & cmd.exe /c 'chcp 65001 >nul & netsh wlan show profiles' 2>$null
    $list = (New-Object System.Collections.ArrayList)
    foreach ($line in $out) {
        $s = [string]$line
        $ci = $s.IndexOf(':')
        if ($ci -lt 0) { continue }
        $before = $s.Substring(0, $ci).ToLower()
        $after  = $s.Substring($ci + 1).Trim()
        $isProfile = $false
        foreach ($k in $ProfKw) { if ($before.Contains($k)) { $isProfile = $true; break } }
        if ($isProfile -and $after -ne '' -and (-not $after.StartsWith('<')) -and ($list -notcontains $after)) {
            $null = $list.Add($after)
        }
    }
    return @($list)
}

function Get-WifiPassword([string]$name) {
    $esc = Escape-ForShellArg $name
    $cmdstr = 'chcp 65001 >nul & netsh wlan show profile name="' + $esc + '" key=clear'
    $out = & cmd.exe /c $cmdstr 2>$null
    foreach ($line in $out) {
        $pwd = Extract-Password ([string]$line)
        if ($pwd) { return $pwd }
    }
    return $null
}

function Extract-Password([string]$line) {
    $ci = $line.IndexOf(':')
    if ($ci -lt 0) { return $null }
    $before = $line.Substring(0, $ci)
    $after  = $line.Substring($ci + 1).Trim()
    if ($after -eq '') { return $null }
    foreach ($kw in $KwPwd) {
        if ($before.Contains($kw)) { return $after }
    }
    $lower = $before.ToLower()
    if ($lower.Contains('key') -and $lower.Contains('content')) { return $after }
    return $null
}

# Escape for safe inclusion inside cmd.exe /c "..." (SSID injection guard)
function Escape-ForShellArg([string]$s) {
    return $s.Replace('^','^^').Replace('&','^&').Replace('|','^|').Replace('<','^<').Replace('>','^>').Replace('(','^(').Replace(')','^)').Replace(',','^,').Replace(';','^;').Replace('"','""')
}

# ============================================================
# 7. Utilities
# ============================================================
function Get-TimestampFilename { return (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss') }
function Get-TimestampDisplay  { return (Get-Date -Format 'yyyy/MM/dd  HH:mm:ss') }

function Get-SafeName([string]$s) {
    foreach ($b in @('\\','/',':','*','?','"','<','>','|',' ')) { $s = $s.Replace($b, '_') }
    return $s
}

function Get-UniqueFilename([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $path }
    $ext  = [IO.Path]::GetExtension($path)
    $base = $path.Substring(0, $path.Length - $ext.Length)
    for ($i = 2; $i -lt 10000; $i++) {
        $cand = ($base + '_(' + $i + ')' + $ext)
        if (-not (Test-Path -LiteralPath $cand)) { return $cand }
    }
    return $path
}

function Get-CsvField([string]$s) {
    if ($s.Contains(',') -or $s.Contains('"') -or $s.Contains("`n") -or $s.Contains("`r")) {
        return ('"' + $s.Replace('"','""') + '"')
    }
    return $s
}

# ============================================================
# 8. Password strength (0-5)
# ============================================================
function Test-Sequential([string]$s) {
    if ($s.Length -lt 4) { return $false }
    $chars = $s.ToCharArray()
    for ($i = 0; $i -lt ($chars.Length - 3); $i++) {
        $a = [int]$chars[$i]; $b = [int]$chars[$i+1]; $c = [int]$chars[$i+2]; $d = [int]$chars[$i+3]
        if (($b - $a -eq 1 -and $c - $b -eq 1 -and $d - $c -eq 1) -or
            ($a - $b -eq 1 -and $b - $c -eq 1 -and $c - $d -eq 1)) { return $true }
    }
    return $false
}

function Test-Repeated([string]$s) {
    if ($s.Length -lt 3) { return $false }
    $chars = $s.ToCharArray()
    for ($i = 0; $i -lt ($chars.Length - 2); $i++) {
        if ($chars[$i] -eq $chars[$i+1] -and $chars[$i+1] -eq $chars[$i+2]) { return $true }
    }
    return $false
}

function Get-PasswordStrength([string]$pwd, [string]$ssid) {
    if (-not $pwd) { return 0 }
    $score = switch ($pwd.Length) {
        { $_ -le 7 }  { 0; break }
        { $_ -le 11 } { 1; break }
        { $_ -le 15 } { 2; break }
        { $_ -le 19 } { 3; break }
        default       { 4 }
    }
    $hasLower = ($pwd -cmatch '[a-z]')
    $hasUpper = ($pwd -cmatch '[A-Z]')
    $hasDigit = ($pwd -cmatch '[0-9]')
    $hasSpec  = ($pwd -cmatch '[^0-9A-Za-z]')
    $classes = @($hasLower, $hasUpper, $hasDigit, $hasSpec) | Where-Object { $_ }
    if (@($classes).Count -ge 3) { $score++ }
    if ($CommonPasswords -contains $pwd.ToLower()) { $score -= 3 }
    if ($ssid -and $ssid -ne '' -and $pwd.ToLower().Contains($ssid.ToLower())) { $score-- }
    if (Test-Sequential $pwd) { $score-- }
    if (Test-Repeated $pwd) { $score-- }
    if ($score -lt 0) { $score = 0 }
    if ($score -gt 5) { $score = 5 }
    return $score
}

function Get-StrengthBar([int]$score) {
    $filled = [string][char]0x2588
    $empty  = [string][char]0x2591
    $f = $filled * $score
    $e = $empty * (5 - $score)
    return ('[' + $f + $e + '] ' + $score + '/5')
}

# ============================================================
# 9. Fuzzy search (multi-token AND)
# ============================================================
function Search-Wifi([string[]]$profiles, [string]$query) {
    $tokens = @($query -split '\s+' | Where-Object { $_ })
    $results = (New-Object System.Collections.ArrayList)
    for ($i = 0; $i -lt $profiles.Length; $i++) {
        $nameLower = $profiles[$i].ToLower()
        $ok = $true
        foreach ($t in $tokens) {
            if (-not $nameLower.Contains($t.ToLower())) { $ok = $false; break }
        }
        if ($ok) {
            $null = $results.Add([pscustomobject]@{ Index = $i; Name = $profiles[$i] })
        }
    }
    return @($results)
}

# Escape reserved chars for the WIFI: URI scheme
function Get-WifiPayload([string]$ssid, [string]$pwd) {
    function EscU([string]$v) {
        return $v.Replace('\','\\').Replace(';','\;').Replace(',','\,').Replace(':','\:')
    }
    return ('WIFI:T:WPA;S:' + (EscU $ssid) + ';P:' + (EscU $pwd) + ';;')
}

# ============================================================
# 10. Embedded C# QR encoder (pure .NET, no external DLL)
#     Outputs an SVG string. Level H, mask 0, versions 1-10.
# ============================================================
$QrCs = @'
using System;
using System.Collections.Generic;
using System.Text;

public static class QrSvg
{
    private static readonly int[] EXP;
    private static readonly int[] LOG;
    static QrSvg()
    {
        EXP = new int[512];
        LOG = new int[256];
        int x = 1;
        for (int i = 0; i < 255; i++)
        {
            EXP[i] = x;
            LOG[x] = i;
            x <<= 1;
            if ((x & 0x100) != 0) x ^= 0x11D;
        }
        for (int i = 255; i < 512; i++) EXP[i] = EXP[i - 255];
    }
    private static int Mul(int a, int b)
    {
        if (a == 0 || b == 0) return 0;
        return EXP[LOG[a] + LOG[b]];
    }

    // RS table: [version][level] = { ecPerBlock, g1Blocks, g1Data, g2Blocks, g2Data }
    // level: 0=L 1=M 2=Q 3=H
    private static readonly int[][][] RS = new int[][][]
    {
        null,
        new int[][]{ new int[]{7,1,19,0,0}, new int[]{10,1,16,0,0}, new int[]{13,1,13,0,0}, new int[]{17,1,9,0,0} },
        new int[][]{ new int[]{10,1,34,0,0}, new int[]{16,1,28,0,0}, new int[]{22,1,22,0,0}, new int[]{28,1,16,0,0} },
        new int[][]{ new int[]{15,1,55,0,0}, new int[]{26,1,44,0,0}, new int[]{18,2,17,0,0}, new int[]{22,2,13,0,0} },
        new int[][]{ new int[]{20,1,80,0,0}, new int[]{18,2,32,0,0}, new int[]{26,2,24,0,0}, new int[]{16,4,9,0,0} },
        new int[][]{ new int[]{26,1,108,0,0}, new int[]{24,2,43,0,0}, new int[]{18,2,15,2,16}, new int[]{22,2,11,2,12} },
        new int[][]{ new int[]{18,2,68,0,0}, new int[]{16,4,27,0,0}, new int[]{24,4,19,0,0}, new int[]{28,4,15,0,0} },
        new int[][]{ new int[]{20,2,78,0,0}, new int[]{18,4,31,0,0}, new int[]{18,2,14,4,15}, new int[]{26,4,13,1,14} },
        new int[][]{ new int[]{24,2,97,0,0}, new int[]{22,2,38,2,39}, new int[]{22,4,18,2,19}, new int[]{26,4,14,2,15} },
        new int[][]{ new int[]{30,2,116,0,0}, new int[]{22,3,36,2,37}, new int[]{20,4,16,4,17}, new int[]{24,4,12,4,13} },
        new int[][]{ new int[]{18,2,68,2,69}, new int[]{26,4,43,1,44}, new int[]{24,6,19,2,20}, new int[]{28,6,15,2,16} }
    };

    // alignment pattern centres
    private static readonly int[][] AL = new int[][]
    {
        null,
        new int[]{}, new int[]{6,18}, new int[]{6,22}, new int[]{6,26}, new int[]{6,30},
        new int[]{6,34}, new int[]{6,22,38}, new int[]{6,24,42}, new int[]{6,26,46}, new int[]{6,28,50}
    };

    private static int[] RsGeneratePoly(int ecCount)
    {
        int[] gen = new int[1];
        gen[0] = 1;
        for (int i = 0; i < ecCount; i++)
        {
            int[] ng = new int[gen.Length + 1];
            for (int j = 0; j < gen.Length; j++)
            {
                ng[j] ^= gen[j];
                ng[j + 1] ^= Mul(gen[j], EXP[i]);
            }
            gen = ng;
        }
        return gen;
    }

    private static int[] RsEncode(int[] data, int ecCount)
    {
        int[] gen = RsGeneratePoly(ecCount);
        int[] rem = new int[ecCount];
        for (int i = 0; i < data.Length; i++)
        {
            int factor = data[i] ^ rem[0];
            Array.Copy(rem, 1, rem, 0, ecCount - 1);
            rem[ecCount - 1] = 0;
            if (factor != 0)
            {
                for (int j = 0; j < ecCount; j++)
                    rem[j] ^= Mul(gen[j + 1], factor);
            }
        }
        return rem;
    }

    private static void AddBits(List<int> bits, int value, int count)
    {
        for (int i = count - 1; i >= 0; i--)
            bits.Add((value >> i) & 1);
    }

    public static string Generate(string text, string label, int scale)
    {
        byte[] data = Encoding.UTF8.GetBytes(text);

        // Choose level H first, then Q, M, L
        int ver = 0;
        int[] useLevels = { 3, 2, 1, 0 };
        int useLevel = 3;
        foreach (int lvl in useLevels)
        {
            for (int v = 1; v <= 10; v++)
            {
                int[] r = RS[v][lvl];
                int td = r[1] * r[3] + r[2] * r[4];
                int lb = (v <= 9) ? 8 : 16;
                int needBits = 4 + lb + 8 * data.Length;
                if (td * 8 >= needBits)
                {
                    ver = v;
                    useLevel = lvl;
                    break;
                }
            }
            if (ver != 0) break;
        }
        if (ver == 0) return null;

        int[] rsInfo = RS[ver][useLevel];
        int ecPerBlock = rsInfo[0];
        int g1Count = rsInfo[1], g1D = rsInfo[3], g2Count = rsInfo[2], g2D = rsInfo[4];
        int totalData = g1Count * g1D + g2Count * g2D;
        int nBlocks = g1Count + g2Count;
        int lenBits = (ver <= 9) ? 8 : 16;

        // Bit stream: mode(4) + length + data + pad bytes
        List<int> bits = new List<int>();
        AddBits(bits, 4, 4);            // 0100 = byte mode
        AddBits(bits, data.Length, lenBits);
        foreach (byte b in data) AddBits(bits, b, 8);
        while ((bits.Count % 8) != 0) bits.Add(0);
        int dataCodewords = bits.Count / 8;

        int[] payload = new int[totalData];
        for (int i = 0; i < dataCodewords; i++)
        {
            int v0 = 0;
            for (int j = 0; j < 8; j++) v0 = (v0 << 1) | bits[i * 8 + j];
            payload[i] = v0;
        }
        for (int i = dataCodewords; i < totalData; i++)
            payload[i] = ((i - dataCodewords) % 2 == 0) ? 0xEC : 0x11;

        // Split into blocks
        int[][] blockData = new int[nBlocks][];
        int idx = 0;
        for (int b = 0; b < nBlocks; b++)
        {
            int bd = (b < g1Count) ? g1D : (g1D + 1);
            blockData[b] = new int[bd];
            for (int j = 0; j < bd; j++) blockData[b][j] = payload[idx++];
        }
        int[][] blockEc = new int[nBlocks][];
        for (int b = 0; b < nBlocks; b++) blockEc[b] = RsEncode(blockData[b], ecPerBlock);

        // Interleave data then ec codewords
        List<int> all = new List<int>();
        int maxD = 0;
        for (int b = 0; b < nBlocks; b++) if (blockData[b].Length > maxD) maxD = blockData[b].Length;
        for (int j = 0; j < maxD; j++)
            for (int b = 0; b < nBlocks; b++)
                if (j < blockData[b].Length) all.Add(blockData[b][j]);
        for (int j = 0; j < ecPerBlock; j++)
            for (int b = 0; b < nBlocks; b++)
                all.Add(blockEc[b][j]);

        // Bit sequence MSB-first
        List<int> databits = new List<int>();
        foreach (int code in all)
            for (int j = 7; j >= 0; j--) databits.Add((code >> j) & 1);

        // Matrix
        int size = 17 + 4 * ver;
        bool[,] m = new bool[size, size];

        // Finder patterns + separators
        for (int r = -1; r <= 7; r++)
            for (int c = -1; c <= 7; c++)
            {
                bool on = (r >= 0 && r < 7 && c >= 0 && c < 7) &&
                          (r == 0 || r == 6 || c == 0 || c == 6 ||
                           (r >= 2 && r <= 4 && c >= 2 && c <= 4));
                if (r >= 0 && r < size && c >= 0 && c < size) m[r, c] = on;
            }

        // Top-right and bottom-left finders
        DrawFinder(m, size, 0, size - 7);
        DrawFinder(m, size, size - 7, 0);

        // Timing patterns
        for (int c = 8; c <= size - 9; c++)
        {
            m[6, c] = (c % 2 == 0);
            m[c, 6] = (c % 2 == 0);
        }

        // Alignment patterns
        int[] aph = AL[ver];
        for (int i = 0; i < aph.Length; i++)
            for (int j = 0; j < aph.Length; j++)
            {
                int rr = aph[i], cc = aph[j];
                if (InFinder(size, rr, cc)) continue;
                DrawAlign(m, rr, cc);
            }

        // Dark module
        m[size - 8, 8] = true;

        // Place data bits (zig-zag from bottom-right), skip function areas, mask 0
        List<int> bits2 = databits;
        int bitPos = 0;
        bool upward = true;
        for (int c = size - 1; c > 0; c -= 2)
        {
            if (c == 6) c--;
            for (int i = 0; i < size; i++)
            {
                int r = upward ? (size - 1 - i) : i;
                for (int k = 0; k < 2; k++)
                {
                    int cc = c - k;
                    if (cc < 0) continue;
                    if (IsFunction(m, size, ver, aph, r, cc)) continue;
                    bool dark = false;
                    if (bitPos < bits2.Count)
                    {
                        dark = (bits2[bitPos] == 1);
                        if ((r + cc) % 2 == 0) dark = !dark;   // mask 0
                        bitPos++;
                    }
                    m[r, cc] = dark;
                }
            }
            upward = !upward;
        }

        // Format info (always mask 0), level bits: L=01 M=00 Q=11 H=10
        int ecBits = new int[] { 1, 0, 3, 2 }[useLevel];
        int data5 = (ecBits << 3) | 0;
        long remV = (long)data5 << 10;
        for (int i = 14; i >= 10; i--)
            if ((remV & (1L << i)) != 0) remV ^= (0x537L << (i - 10));
int fmt = (int)((((long)data5 << 10) | remV) ^ 0x5412L);

        m[8, 0] = ((fmt >> 14) & 1) == 1;          // b14
        m[8, 1] = ((fmt >> 13) & 1) == 1;          // b13
        m[8, 2] = ((fmt >> 12) & 1) == 1;
        m[8, 3] = ((fmt >> 11) & 1) == 1;
        m[8, 4] = ((fmt >> 10) & 1) == 1;
        m[8, 5] = ((fmt >> 9) & 1) == 1;
        m[8, 7] = ((fmt >> 8) & 1) == 1;
        m[8, 8] = ((fmt >> 7) & 1) == 1;
        m[7, 8] = ((fmt >> 6) & 1) == 1;
        m[5, 8] = ((fmt >> 5) & 1) == 1;
        m[4, 8] = ((fmt >> 4) & 1) == 1;
        m[3, 8] = ((fmt >> 3) & 1) == 1;
        m[2, 8] = ((fmt >> 2) & 1) == 1;
        m[1, 8] = ((fmt >> 1) & 1) == 1;
        m[0, 8] = (fmt & 1) == 1;                  // b0

        // Copy 2: top-right + bottom-left
        for (int j = 0; j < 7; j++)
            m[size - 1 - j, 8] = ((fmt >> (14 - j)) & 1) == 1;   // b14..b8
        m[8, size - 8] = ((fmt >> 7) & 1) == 1;
        m[8, size - 7] = ((fmt >> 6) & 1) == 1;
        m[8, size - 6] = ((fmt >> 5) & 1) == 1;
        m[8, size - 5] = ((fmt >> 4) & 1) == 1;
        m[8, size - 4] = ((fmt >> 3) & 1) == 1;
        m[8, size - 3] = ((fmt >> 2) & 1) == 1;
        m[8, size - 2] = ((fmt >> 1) & 1) == 1;
        m[8, size - 1] = (fmt & 1) == 1;           // b0

        // Version info (v >= 7, 18 bits, BCH(18,6) generator 0x1F25)
        if (ver >= 7)
        {
            long vr = (long)ver << 12;
            for (int i = 17; i >= 12; i--)
                if ((vr & (1L << i)) != 0) vr ^= (0x1F25L << (i - 12));
            int vInfo = (int)(((long)ver << 12) | vr);
            int bitPosV = 17;
            for (int c = 0; c < 6; c++)
                for (int r = size - 11; r <= size - 9; r++)
                {
                    m[r, c] = ((vInfo >> bitPosV) & 1) == 1;
                    bitPosV--;
                }
            bitPosV = 17;
            for (int r = 0; r < 6; r++)
                for (int c = size - 11; c <= size - 9; c++)
                {
                    m[r, c] = ((vInfo >> bitPosV) & 1) == 1;
                    bitPosV--;
                }
        }

        // SVG output with label below
        int pix = scale;
        int q = scale * 4;
        int w = size * pix + q * 2;
        int textH = 36;
        StringBuilder sb = new StringBuilder();
        sb.Append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
        sb.AppendFormat("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{0}\" height=\"{1}\" viewBox=\"0 0 {0} {1}\">\n", w, w + textH);
        sb.AppendFormat("<rect width=\"{0}\" height=\"{1}\" fill=\"#FFFFFF\"/>\n", w, w + textH);
        string esc = label.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("\"", "&quot;").Replace("'", "&apos;");
        for (int r = 0; r < size; r++)
            for (int c = 0; c < size; c++)
                if (m[r, c])
                    sb.AppendFormat("<rect x=\"{0}\" y=\"{1}\" width=\"{2}\" height=\"{2}\" fill=\"#000000\"/>\n", c * pix + q, r * pix + q, pix);
        sb.AppendFormat("<text x=\"{0}\" y=\"{1}\" text-anchor=\"middle\" dominant-baseline=\"central\" font-family=\"sans-serif\" font-size=\"14\" fill=\"#333333\">{2}</text>\n</svg>", w / 2, w + textH / 2, esc);
        return sb.ToString();
    }

    private static void DrawFinder(bool[,] m, int size, int tr, int tc)
    {
        for (int r = -1; r <= 7; r++)
            for (int c = -1; c <= 7; c++)
            {
                int rr = tr + r, cc = tc + c;
                if (rr < 0 || cc < 0 || rr >= size || cc >= size) continue;
                bool on = (r >= 0 && r < 7 && c >= 0 && c < 7) &&
                          (r == 0 || r == 6 || c == 0 || c == 6 ||
                           (r >= 2 && r <= 4 && c >= 2 && c <= 4));
                m[rr, cc] = on;
            }
    }

    private static void DrawAlign(bool[,] m, int cr, int cc)
    {
        for (int r = -2; r <= 2; r++)
            for (int c = -2; c <= 2; c++)
            {
                bool on = (Math.Abs(r) == 2 || Math.Abs(c) == 2 || (r == 0 && c == 0));
                m[cr + r, cc + c] = on;
            }
    }

    private static bool InFinder(int size, int r, int c)
    {
        return (r < 8 && c < 8) || (r < 8 && c >= size - 8) || (r >= size - 8 && c < 8);
    }

    private static bool IsFunction(bool[,] m, int size, int ver, int[] aph, int r, int c)
    {
        if ((r < 8 && c < 8) || (r < 8 && c >= size - 8) || (r >= size - 8 && c < 8)) return true;
        if (r == 6 && c >= 8 && c <= size - 9) return true;
        if (c == 6 && r >= 8 && r <= size - 9) return true;
        for (int i = 0; i < aph.Length; i++)
            for (int j = 0; j < aph.Length; j++)
                if (Math.Abs(r - aph[i]) <= 2 && Math.Abs(c - aph[j]) <= 2) return true;
        if (r == 8) { if (c <= 8 || c >= size - 8) return true; }
        if (c == 8) { if (r <= 8 || r >= size - 8) return true; }
        if (ver >= 7)
        {
            if (r >= size - 11 && r <= size - 9 && c <= 5) return true;
            if (c >= size - 11 && c <= size - 9 && r <= 5) return true;
        }
        return false;
    }
}
'@

$script:QrReady = $false
$script:QrError = $null
function Ensure-Qr {
    if ($script:QrReady) { return $true }
    if ($script:QrError) { return $false }
    if ('QrSvg' -as [type]) { $script:QrReady = $true; return $true }
    try {
        Add-Type -TypeDefinition $QrCs -ErrorAction Stop
        $script:QrReady = $true
        return $true
    } catch {
        $msg1 = $_.Exception.Message
    }
    try {
        $provider = New-Object Microsoft.CSharp.CSharpCodeProvider
        $params = New-Object System.CodeDom.Compiler.CompilerParameters
        $params.GenerateInMemory = $true
        $params.ReferencedAssemblies.Add('System.dll') | Out-Null
        $params.ReferencedAssemblies.Add('System.Core.dll') | Out-Null
        $result = $provider.CompileAssemblyFromSource($params, $QrCs)
        if ($result.Errors.HasErrors) {
            $errs = @()
            foreach ($e in $result.Errors) { $errs += $e.ToString() }
            $script:QrError = ($errs -join '; ')
        } else {
            [void][Reflection.Assembly]::Load($result.CompiledAssembly)
            $script:QrReady = $true
            return $true
        }
    } catch {
        $script:QrError = $msg1 + ' | Fallback: ' + $_.Exception.Message
    }
    return $false
}

function New-QrSvg([string]$payload, [string]$label) {
    if (-not (Ensure-Qr)) { return $null }
    return [QrSvg]::Generate($payload, $label, 8)
}

# ============================================================
# 11. Clipboard
# ============================================================
function Set-ClipboardText([string]$text) {
    if ($text) {
        try { Set-Clipboard -Value $text } catch {}
    }
}

# ============================================================
# 12. Export (TXT / CSV)
# ============================================================
function Resolve-ExportSelection([string]$line, [int]$total) {
    $t = $line.Trim()
    $sel = (New-Object System.Collections.ArrayList)
    if ($t -eq '' -or $t -eq '0') {
        for ($i = 0; $i -lt $total; $i++) { $null = $sel.Add($i) }
        return @($sel)
    }
    foreach ($tok in ($t -split ',')) {
        $n = 0
        if ([int]::TryParse($tok.Trim(), [ref]$n)) {
            if ($n -ge 1 -and $n -le $total -and $sel -notcontains ($n - 1)) {
                $null = $sel.Add($n - 1)
            }
        }
    }
    return @($sel)
}

function Do-Export([string[]]$profiles, [int[]]$selected, [string]$format, [string]$lang, $strings) {
    $ts = Get-TimestampFilename
    $ext = if ($format -eq 'csv') { 'csv' } else { 'txt' }
    if ($lang -eq 'zh') {
        $prefix = 'WiFi' + (U 0x5BC6 0x7801 0x5BFC 0x51FA)
    } else {
        $prefix = 'WiFi_Password_Export'
    }
    $filename = Get-UniqueFilename ($prefix + '_' + $ts + '.' + $ext)

    # Resolve passwords first so the progress bar reports real progress
    $total = $selected.Length
    if ($total -lt 1) { $total = 1 }
    $passwords = (New-Object System.Collections.ArrayList)
    $i = 0
    foreach ($idx in $selected) {
        $pwd = $null
        if ($idx -ge 0 -and $idx -lt $profiles.Length) {
            $pwd = Get-WifiPassword $profiles[$idx]
        }
        $null = $passwords.Add([pscustomobject]@{ Index = $idx; Pwd = $pwd })
        $i++
        $pct = [int](($i) * 100 / $total)
        $filled = [int]($pct / 10)
        $bar  = ([string][char]0x2588) * $filled
        $emp  = ([string][char]0x2591) * (10 - $filled)
        [Console]::Error.Write([char]13 + ('  {0}{1}{2}{3}{4} {5}/{6} ({7}%)' -f (P $C_BAR_FILL), $bar, (P $C_BAR_EMPTY), $emp, (P $C_RESET), $i, $total, $pct))
    }
    [Console]::Error.WriteLine()

    # Build content
    $content = New-Object System.Text.StringBuilder
    $null = $content.Append([char]0xFEFF)   # UTF-8 BOM
    $null = $content.AppendLine($Sep)
    $null = $content.AppendLine('  ' + $strings['title'])
    $null = $content.AppendLine($Sep)
    $null = $content.AppendLine()
    $null = $content.AppendLine($strings['export_time'] + ': ' + (Get-TimestampDisplay))
    $null = $content.AppendLine($strings['tool_version'] + ': ' + $strings['title'] + ' v' + $Version + ' (PowerShell)')
    $null = $content.AppendLine($strings['total_count'] + ': ' + $selected.Length)
    $null = $content.AppendLine()
    $null = $content.AppendLine($Sep)

    if ($format -eq 'csv') {
        $null = $content.AppendLine('Index,SSID,Password')
        $j = 0
        foreach ($item in $passwords) {
            $null = $content.AppendLine((($j + 1).ToString()) + ',' + (Get-CsvField $profiles[$item.Index]) + ',' + (Get-CsvField ([string]$item.Pwd)))
            $j++
        }
    } else {
        $j = 0
        foreach ($item in $passwords) {
            $ssidLine = '{0,3}.' -f ($j + 1)
            $null = $content.AppendLine($ssidLine + '  ' + ($profiles[$item.Index]).PadRight(36) + '  ' + ([string]$item.Pwd))
            $j++
        }
    }
    $null = $content.AppendLine($Sep)

    try {
        $enc = New-Object System.Text.UTF8Encoding($true)
        [IO.File]::WriteAllText($filename, $content.ToString(), $enc)
        [Console]::WriteLine()
        [Console]::WriteLine(('  {0}{1}{2} {3}' -f (P $C_OK), $strings['export_title'], (P $C_RESET), $strings['exported_to']))
        [Console]::WriteLine(('  {0}{1}{2}' -f (P $C_NAME), $filename, (P $C_RESET)))
    } catch {
        [Console]::Error.WriteLine(('  {0}{1}{2} {3}: {4}' -f (P $C_ERROR), $strings['err_export'], (P $C_RESET), $_.Exception.Message))
    }
}

# ============================================================
# 13. Display helpers
# ============================================================
function Show-Main([string[]]$profiles, $strings) {
    Clear-Host
    [Console]::WriteLine($Sep)
    [Console]::WriteLine(('  {0}{1}{2}' -f (P $C_TITLE), $strings['title'], (P $C_RESET)))
    [Console]::WriteLine(('  {0}{1}{2}' -f (P $C_HINT), $strings['subtitle'], (P $C_RESET)))
    [Console]::WriteLine($Sep)
    [Console]::WriteLine()
    for ($i = 0; $i -lt $profiles.Length; $i++) {
        [Console]::WriteLine(('  {0}{1,3}.{2} {3}{4}{5}' -f (P $C_HINT), ($i + 1), (P $C_RESET), (P $C_NAME), $profiles[$i], (P $C_RESET)))
    }
    [Console]::WriteLine()
    [Console]::WriteLine($Sep)
    [Console]::WriteLine(('  {0}{1}{2}' -f (P $C_HINT), $strings['prompt'], (P $C_RESET)))
}

function Show-Detail([string]$ssid, [string]$lang, $strings, [bool]$masked) {
    Clear-Host
    [Console]::WriteLine($Sep)
    [Console]::WriteLine(('  {0}{1}{2}' -f (P $C_TITLE), $strings['title'], (P $C_RESET)))
    [Console]::WriteLine($Sep)
    [Console]::WriteLine()
    $pwd = Get-WifiPassword $ssid
    [Console]::WriteLine(('  {0}{1}{2}: {3}{4}{5}' -f (P $C_HINT), $strings['found'], (P $C_RESET), (P $C_NAME), $ssid, (P $C_RESET)))
    [Console]::WriteLine()

    if ($pwd) {
        $pw = [string]$pwd
        $display = if ($masked) { ('*' * [Math]::Min($pw.Length, 32)) } else { $pw }
        [Console]::WriteLine(('  {0}{1}{2}: {3}{4}{5}' -f (P $C_HINT), $strings['password'], (P $C_RESET), (P $C_PWD), $display, (P $C_RESET)))
        $score = Get-PasswordStrength $pw $ssid
        $bar = Get-StrengthBar $score
        $label = Get-StrengthLabel $lang $score
        [Console]::WriteLine(('  {0}{1}{2}: {3}{4}{5} ({6}{7} {8}/5{9})' -f (P $C_HINT), $strings['strength'], (P $C_RESET), (P $C_OK), $bar, (P $C_RESET), (P $C_HINT), $label, $score, (P $C_RESET)))
        if (-not $masked) {
            Set-ClipboardText $pw
            [Console]::WriteLine()
            [Console]::WriteLine(('  {0}{1}{2}' -f (P $C_OK), $strings['copied'], (P $C_RESET)))
        }
    } else {
        [Console]::WriteLine(('  {0}{1}{2}' -f (P $C_WARN), $strings['no_pwd'], (P $C_RESET)))
    }

    [Console]::WriteLine()
    [Console]::WriteLine($Sep)
    $toggle = if ($masked) { $strings['show_pwd'] } else { $strings['hide_pwd'] }
    [Console]::WriteLine(('  {0}   {1}   {2}   {3}' -f $toggle, $strings['qr_hint'], $strings['copy_wifi'], $strings['back']))
}

function Show-History($history, $strings) {
    Clear-Host
    [Console]::WriteLine($Sep)
    [Console]::WriteLine(('  {0}{1}{2}' -f (P $C_TITLE), $strings['history_title'], (P $C_RESET)))
    [Console]::WriteLine($Sep)
    [Console]::WriteLine()
    if ($history.Count -eq 0) {
        [Console]::WriteLine(('  {0}{1}{2}' -f (P $C_HINT), $strings['history_empty'], (P $C_RESET)))
    } else {
        for ($i = 0; $i -lt $history.Count; $i++) {
            $h = $history[$i]
            [Console]::WriteLine(('  {0}{1}.{2} {3}{4}{5} ({6})' -f (P $C_HINT), ($i + 1), (P $C_RESET), (P $C_NAME), $h.Name, (P $C_RESET), ($h.Index + 1)))
        }
    }
    [Console]::WriteLine()
    [Console]::WriteLine($Sep)
    [Console]::WriteLine(('  {0}' -f $strings['back']))
}

function Show-Help($strings) {
    [Console]::WriteLine($Sep)
    [Console]::WriteLine(('  {0}{1}{2}' -f (P $C_TITLE), $strings['title'], (P $C_RESET)))
    [Console]::WriteLine($Sep)
    [Console]::WriteLine()
    [Console]::WriteLine(('  {0}{1}{2}' -f (P $C_HINT), $strings['usage_title'], (P $C_RESET)))
    if ($strings['usage_body']) {
        $us = $strings['usage_body']
    } else {
        $us = 'wifi_password_tool.ps1 [zh|en|ja|...]   force UI / netsh language' + "`n" +
              '  wifi_password_tool.ps1 -h              show help' + "`n" +
              '  wifi_password_tool.ps1 -v              show version' + "`n" +
              '  wifi_password_tool.ps1 -d              debug mode'
    }
    [Console]::WriteLine('  ' + $us.Replace("`n", "`n  "))
    [Console]::WriteLine()
    [Console]::WriteLine($Sep)
}

# ============================================================
# 14. Main
# ============================================================
# Ctrl+C graceful exit
try {
    [Console]::CancelKeyPress.Add({
        [Console]::WriteLine()
        [Console]::WriteLine([char]27 + '[0m  [Ctrl+C] Bye.')
        [Environment]::Exit(0)
    })
} catch {}

# Detect language
$lang = Detect-Language
$strings = Get-Strings $lang


# -h / -v / -d any position
foreach ($a in $UserArgs) {
    if ($a -eq '-h' -or $a -eq '--help' -or $a -eq '/?') {
        Show-Help $strings
        exit 0
    }
    if ($a -eq '-v' -or $a -eq '--version') {
        [Console]::WriteLine(('  {0} {1} v{2} (PowerShell edition)' -f $strings['title'], $strings['version_label'], $Version))
        exit 0
    }
    if ($a -eq '-d' -or $a -eq '--debug') {
        [Console]::WriteLine('=== DEBUG: netsh raw output ===')
        $dbgProfiles = Get-WifiProfiles
        [Console]::WriteLine(('Profiles count: {0}' -f $dbgProfiles.Count))
        if ($dbgProfiles.Count -gt 0) {
            $dbgName = $dbgProfiles[0]
            [Console]::WriteLine(('First profile: {0}' -f $dbgName))
            $dbgEsc = Escape-ForShellArg $dbgName
            $dbgCmd = 'chcp 65001 >nul & netsh wlan show profile name="' + $dbgEsc + '" key=clear'
            [Console]::WriteLine('--- raw netsh output ---')
            $dbgOut = & cmd.exe /c $dbgCmd 2>$null
            $dbgAll = New-Object System.Collections.ArrayList
            foreach ($dbgLine in $dbgOut) {
                $dbgStr = [string]$dbgLine
                [Console]::WriteLine($dbgStr)
                $null = $dbgAll.Add($dbgStr)
            }
            [Console]::WriteLine('--- end raw output ---')
            [Console]::WriteLine('--- password extraction ---')
            $dbgPwd = Get-WifiPassword $dbgName
            [Console]::WriteLine(('Extracted password: [{0}]' -f $dbgPwd))
            [Console]::WriteLine('--- QR compilation ---')
            $dbgQr = Ensure-Qr
            [Console]::WriteLine(('QR ready: {0}' -f $dbgQr))
            if ($script:QrError) { [Console]::WriteLine(('QR error: {0}' -f $script:QrError)) }
            $dbgReport = '=== DEBUG REPORT ===' + "`n"

            $dbgReport += 'OutputEncoding: ' + [Console]::OutputEncoding.EncodingName + "`n"
            $dbgReport += 'Profile: ' + $dbgName + "`n"
            $dbgReport += '--- raw lines (with char codes) ---' + "`n"
            for ($di = 0; $di -lt $dbgAll.Count; $di++) {
                $dbgLine = $dbgAll[$di]
                $dbgReport += ('Line {0}: {1}' -f $di, $dbgLine) + "`n"
                $ci = $dbgLine.IndexOf(':')
                if ($ci -ge 0) {
                    $before = $dbgLine.Substring(0, $ci)
                    $after = $dbgLine.Substring($ci + 1).Trim()
                    $dbgReport += ('  colon at {0}, before=[{1}], after=[{2}]' -f $ci, $before, $after) + "`n"
                    $matched = $false
                    foreach ($kw in $KwPwd) {
                        if ($before.Contains($kw)) {
                            $dbgReport += '  MATCHED keyword: ' + $kw + "`n"
                            $matched = $true
                        }
                    }
                    if (-not $matched) {
                        $lower = $before.ToLower()
                        if ($lower.Contains('key') -and $lower.Contains('content')) {
                            $dbgReport += '  MATCHED fallback (key+content)' + "`n"
                        }
                    }
                }
            }
            $dbgReport += '--- extraction result ---' + "`n"
            $dbgReport += 'Password: [' + $dbgPwd + ']' + "`n"
            $dbgReport += 'QR ready: ' + $dbgQr + "`n"
            if ($script:QrError) { $dbgReport += 'QR error: ' + $script:QrError + "`n" }
            $dbgReport += '=== END ==='
            $dbgFile = Join-Path (Get-Location) 'debug_report.txt'
            [IO.File]::WriteAllText($dbgFile, $dbgReport, [Text.Encoding]::UTF8)
            [Console]::WriteLine()
            [Console]::WriteLine('Debug report written to: ' + $dbgFile)
        }
        [Console]::WriteLine('=== END DEBUG ===')
        try { $null = [Console]::ReadLine() } catch {}
        exit 0
    }
}

try { [Console]::Title = $strings['title'] } catch {}
Clear-Host

# Empty-state guard
$profiles = Get-WifiProfiles
if ($profiles.Count -eq 0) {
    [Console]::WriteLine($Sep)
    [Console]::WriteLine(('  {0}{1}{2}' -f (P $C_TITLE), $strings['title'], (P $C_RESET)))
    [Console]::WriteLine($Sep)
    [Console]::WriteLine()
    [Console]::WriteLine('  ' + $strings['err_no_profiles'])
    [Console]::WriteLine()
    [Console]::WriteLine(('  {0}{1}{2}' -f (P $C_HINT), $strings['press_exit'], (P $C_RESET)))
    try { $null = [Console]::ReadLine() } catch {}
    exit 0
}

# State
$history = (New-Object System.Collections.ArrayList)
$inDetail = $false
$current  = ''
$masked   = $true

# Main loop
while ($true) {
    if ($inDetail) {
        Show-Detail $current $lang $strings $masked
    } else {
        Show-Main $profiles $strings
    }

    $line = ''
    try { $line = [Console]::ReadLine() } catch { exit 0 }
    if (-not $line) { continue }
    $line = $line.Trim()

    if ($line -eq '') { continue }

    # Global commands
    if ($line -eq 'q' -or $line -eq 'Q') { break }
    if ($line -eq 'h' -or $line -eq 'H') {
        Show-History $history $strings
        try { $null = [Console]::ReadLine() } catch {}
        continue
    }

    if ($inDetail) {
        switch ($line) {
            'b' { $inDetail = $false; $masked = $true; break }
            'B' { $inDetail = $false; $masked = $true; break }
            's' { $masked = -not $masked; break }
            'S' { $masked = -not $masked; break }
            'r' {
                $pwd = Get-WifiPassword $current
                if ($pwd) {
                    $payload = Get-WifiPayload $current ([string]$pwd)
                    $svg = New-QrSvg $payload $current
                    if ($svg) {
                        $safe = Get-SafeName $current
                        $ts = Get-TimestampFilename
                        $fname = Get-UniqueFilename ('WiFi_QR_' + $safe + '_' + $ts + '.svg')
                        try {
                            [IO.File]::WriteAllText($fname, $svg)
                            Set-ClipboardText $fname
                            try { Start-Process -FilePath $fname } catch {}
                            [Console]::WriteLine()
                            [Console]::WriteLine(('  {0}{1}: {2}{3}{4}' -f (P $C_OK), $strings['qr_path'], (P $C_NAME), $fname, (P $C_RESET)))
                            [Console]::WriteLine(('  {0}{1}{2}' -f (P $C_OK), $strings['qr_generated'], (P $C_RESET)))
                        } catch {
                            [Console]::Error.WriteLine(('  {0}{1}{2}' -f (P $C_ERROR), $strings['qr_fail'], (P $C_RESET)))
                        }
                    } else {
                        $__e = if ($script:QrError) { $script:QrError } else { $strings['qr_fail'] }
                        [Console]::Error.WriteLine(('  {0}{1}{2}' -f (P $C_ERROR), $__e, (P $C_RESET)))
                    }
                }
                try { $null = [Console]::ReadLine() } catch {}
                break
            }
            'R' {
                $pwd = Get-WifiPassword $current
                if ($pwd) {
                    $payload = Get-WifiPayload $current ([string]$pwd)
                    $svg = New-QrSvg $payload $current
                    if ($svg) {
                        $safe = Get-SafeName $current
                        $ts = Get-TimestampFilename
                        $fname = Get-UniqueFilename ('WiFi_QR_' + $safe + '_' + $ts + '.svg')
                        try {
                            [IO.File]::WriteAllText($fname, $svg)
                            Set-ClipboardText $fname
                            try { Start-Process -FilePath $fname } catch {}
                            [Console]::WriteLine()
                            [Console]::WriteLine(('  {0}{1}: {2}{3}{4}' -f (P $C_OK), $strings['qr_path'], (P $C_NAME), $fname, (P $C_RESET)))
                            [Console]::WriteLine(('  {0}{1}{2}' -f (P $C_OK), $strings['qr_generated'], (P $C_RESET)))
                        } catch {
                            [Console]::Error.WriteLine(('  {0}{1}{2}' -f (P $C_ERROR), $strings['qr_fail'], (P $C_RESET)))
                        }
                    } else {
                        $__e = if ($script:QrError) { $script:QrError } else { $strings['qr_fail'] }
                        [Console]::Error.WriteLine(('  {0}{1}{2}' -f (P $C_ERROR), $__e, (P $C_RESET)))
                    }
                }
                try { $null = [Console]::ReadLine() } catch {}
                break
            }
            'c' {
                $pwd = Get-WifiPassword $current
                if ($pwd) {
                    $payload = Get-WifiPayload $current ([string]$pwd)
                    Set-ClipboardText $payload
                    [Console]::WriteLine(('  {0}{1}{2}' -f (P $C_OK), $strings['copied_conn'], (P $C_RESET)))
                }
                try { $null = [Console]::ReadLine() } catch {}
                break
            }
            'C' {
                $pwd = Get-WifiPassword $current
                if ($pwd) {
                    $payload = Get-WifiPayload $current ([string]$pwd)
                    Set-ClipboardText $payload
                    [Console]::WriteLine(('  {0}{1}{2}' -f (P $C_OK), $strings['copied_conn'], (P $C_RESET)))
                }
                try { $null = [Console]::ReadLine() } catch {}
                break
            }
            default {
                $n = 0
                if ([int]::TryParse($line, [ref]$n)) {
                    if ($n -ge 1 -and $n -le $history.Count) {
                        $h = $history[$n - 1]
                        $current = $profiles[$h.Index]
                        $masked = $true
                    }
                }
            }
        }
        continue
    }

    # Main menu mode
    if ($line.StartsWith('/')) {
        $query = $line.Substring(1)
        $results = Search-Wifi $profiles $query
        if ($results.Count -eq 0) {
            [Console]::WriteLine(('  {0}{1}{2}' -f (P $C_WARN), $strings['not_found'], (P $C_RESET)))
            try { $null = [Console]::ReadLine() } catch {}
        } else {
            Clear-Host
            [Console]::WriteLine($Sep)
            [Console]::WriteLine(('  {0}{1} {2}{3}' -f (P $C_TITLE), $strings['search_prompt'], $query, (P $C_RESET)))
            [Console]::WriteLine($Sep)
            [Console]::WriteLine()
            for ($i = 0; $i -lt $results.Count; $i++) {
                [Console]::WriteLine(('  {0}{1}.{2} {3}{4}{5}' -f (P $C_HINT), ($i + 1), (P $C_RESET), (P $C_NAME), $results[$i].Name, (P $C_RESET)))
            }
            [Console]::WriteLine()
            [Console]::WriteLine($Sep)
            [Console]::WriteLine(('  {0}{1}{2}' -f (P $C_HINT), $strings['prompt'], (P $C_RESET)))
            $s2 = ''
            try { $s2 = [Console]::ReadLine() } catch {}
            $s2 = $s2.Trim()
            $n = 0
            if ([int]::TryParse($s2, [ref]$n)) {
                if ($n -ge 1 -and $n -le $results.Count) {
                    $res = $results[$n - 1]
                    $current = $profiles[$res.Index]
                    $masked = $true
                    $inDetail = $true
                    $null = $history.Insert(0, [pscustomobject]@{ Index = $res.Index; Name = $current })
                    if ($history.Count -gt 10) { $history.RemoveAt($history.Count - 1) }
                }
            }
        }
        continue
    }

    if ($line -eq 'e' -or $line -eq 'E') {
        Clear-Host
        [Console]::WriteLine($Sep)
        [Console]::WriteLine(('  {0}{1}{2}' -f (P $C_TITLE), $strings['select_range'], (P $C_RESET)))
        [Console]::WriteLine($Sep)
        $rangeInput = ''
        try { $rangeInput = [Console]::ReadLine() } catch {}
        $selected = Resolve-ExportSelection $rangeInput $profiles.Length
        if ($selected.Length -eq 0) {
            [Console]::WriteLine(('  {0}{1}{2}' -f (P $C_WARN), $strings['select_invalid'], (P $C_RESET)))
            try { $null = [Console]::ReadLine() } catch {}
            continue
        }
        [Console]::WriteLine(('  {0}{1}{2}' -f (P $C_HINT), $strings['select_format'], (P $C_RESET)))
        $fmtInput = ''
        try { $fmtInput = [Console]::ReadLine() } catch {}
        $format = if ($fmtInput.Trim() -eq '2') { 'csv' } else { 'txt' }
        Do-Export $profiles $selected $format $lang $strings
        try { $null = [Console]::ReadLine() } catch {}
        continue
    }

    # Index or (fuzzy) name
    $foundIdx = -1
    $n = 0
    if ([int]::TryParse($line, [ref]$n)) {
        if ($n -ge 1 -and $n -le $profiles.Length) { $foundIdx = $n - 1 }
    } else {
        $lower = $line.ToLower()
        for ($i = 0; $i -lt $profiles.Length; $i++) {
            if ($profiles[$i].ToLower() -eq $lower) { $foundIdx = $i; break }
        }
        if ($foundIdx -lt 0) {
            for ($i = 0; $i -lt $profiles.Length; $i++) {
                if ($profiles[$i].ToLower().Contains($lower)) { $foundIdx = $i; break }
            }
        }
    }

    if ($foundIdx -ge 0) {
        $current = $profiles[$foundIdx]
        $masked = $true
        $inDetail = $true
        $null = $history.Insert(0, [pscustomobject]@{ Index = $foundIdx; Name = $current })
        if ($history.Count -gt 10) { $history.RemoveAt($history.Count - 1) }
    } else {
        [Console]::WriteLine(('  {0}{1}{2}' -f (P $C_WARN), $strings['not_found'], (P $C_RESET)))
        try { $null = [Console]::ReadLine() } catch {}
    }
}