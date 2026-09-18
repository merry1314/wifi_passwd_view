// ============================================================
// WiFi Password Query Tool v3.1 (Rust edition)
// Single-file reimplementation of wifi_password_tool_auto.bat
// and go-wifi-view/main.go.
//
// Build:  cargo build --release
// Run:    wifi_password_tool.exe  (as Administrator)
// ============================================================

use std::collections::HashMap;
use std::fs;
use std::io::{self, Write};
use std::path::Path;
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use qrcode::{Color, EcLevel, QrCode};

// ============================================================
// 0. CRT startup shim (provides symbols normally in MSVC CRT)
// ============================================================
//
// This tool is linked with `lld-link` against import libraries generated
// from the system DLLs (see `gen_libs.py`), so no MSVC CRT startup code
// is available. Two things must therefore be provided by hand:
//
//   1. `_tls_used` / `_tls_index` — the PE TLS directory. Rust's std uses
//      `#[thread_local]` statics (emitted into the `.tls$` section), so the
//      directory MUST span the whole `.tls$` group. `_tls_start` is placed
//      in `.tls$` (sorts first) and `_tls_end` in `.tls$ZZZ` (sorts last);
//      the linker lays out the Rust thread-locals between them.
//      Getting the bounds wrong makes every TLS access read out of bounds,
//      which surfaces as "the System allocator may not use TLS with
//      destructors" or an immediate 0xc0000005.
//
//   2. `const type_info::\`vftable'` — referenced by the panic runtime's
//      RTTI descriptors. It is mapped onto a zeroed placeholder via
//      `/alternatename` and is never dereferenced with `panic = "abort"`.
//
// The entry point is also remapped (`mainCRTStartup` -> `main`) because the
// CRT startup stub is unavailable.

#[cfg(windows)]
mod crt_shim {
    use std::ffi::c_void;

    #[repr(C)]
    struct ImageTlsDirectory64 {
        start: *const u8,
        end: *const u8,
        index: *const u32,
        callbacks: *const u8,
        size_of_zero_fill: u32,
        characteristics: u32,
    }
    unsafe impl Sync for ImageTlsDirectory64 {}

    /// `PIMAGE_TLS_CALLBACK`
    type TlsCallback = unsafe extern "system" fn(*mut c_void, u32, *mut c_void);

    /// Head of the TLS callback array.
    ///
    /// Rust's std installs its own TLS destructor hook in `.CRT$XLB`
    /// (`std::sys::thread_local::guard::windows::CALLBACK`). The PE loader only
    /// walks that array if `_tls_used.AddressOfCallBacks` points at it, and it
    /// stops at the first NULL entry — so `.CRT$XLA` must hold a non-NULL
    /// entry and `.CRT$XLZ` the NULL terminator. Both markers normally come
    /// from the CRT (`__xl_a` / `__xl_z`); here they are supplied by hand.
    unsafe extern "system" fn tls_callback_noop(
        _handle: *mut c_void,
        _reason: u32,
        _reserved: *mut c_void,
    ) {
    }

    #[no_mangle]
    #[link_section = ".CRT$XLA"]
    static __xl_a: Option<TlsCallback> = Some(tls_callback_noop);

    #[no_mangle]
    #[link_section = ".CRT$XLZ"]
    static __xl_z: Option<TlsCallback> = None;

    // Bounds of the merged `.tls` section. `_tls_start` must sort before the
    // Rust-emitted `.tls$` data, `_tls_end` after it.
    #[no_mangle]
    #[link_section = ".tls$"]
    static _tls_start: u8 = 0;

    #[no_mangle]
    #[link_section = ".tls$ZZZ"]
    static _tls_end: u8 = 0;

    // Written by the PE loader with this module's TLS slot index.
    #[no_mangle]
    #[link_section = ".data"]
    static _tls_index: u32 = 0;

    #[used]
    #[no_mangle]
    #[link_section = ".rdata$T"]
    static _tls_used: ImageTlsDirectory64 = ImageTlsDirectory64 {
        start: &_tls_start as *const u8,
        end: &_tls_end as *const u8,
        index: &_tls_index as *const u32,
        callbacks: &__xl_a as *const Option<TlsCallback> as *const u8,
        size_of_zero_fill: 0,
        characteristics: 0,
    };

    /// Placeholder for `const type_info::\`vftable'`, aliased through
    /// `/alternatename` in `.cargo/config.toml`.
    #[no_mangle]
    static _type_info_vftable: [usize; 2] = [0, 0];
}

// ============================================================
// 1. Windows FFI — kernel32 (SetConsoleMode for VT-100)
// ============================================================

#[cfg(windows)]
mod winapi {
    use std::io;
    use std::io::Write;
    use std::os::raw::c_void;

    #[link(name = "kernel32")]
    extern "system" {
        fn GetStdHandle(n_std_handle: u32) -> *mut c_void;
        fn GetConsoleMode(handle: *mut c_void, mode: *mut u32) -> i32;
        fn SetConsoleMode(handle: *mut c_void, mode: u32) -> i32;
        fn SetConsoleCtrlHandler(handler: *const c_void, add: i32) -> i32;
    }

    /// Console control handler: 0 = CTRL_C_EVENT, 1 = CTRL_BREAK_EVENT.
    /// Prints a trailing newline so the shell prompt isn't left on a dirty
    /// line, then exits cleanly. Other events (close / logoff / shutdown)
    /// are left to the default handler.
    unsafe extern "system" fn ctrl_handler(ctrl_type: u32) -> i32 {
        match ctrl_type {
            0 | 1 => {
                println!();
                println!("  [Ctrl+C] Bye.");
                let _ = io::stdout().flush();
                std::process::exit(0);
            }
            _ => 0,
        }
    }

    /// Install the Ctrl+C handler. Best-effort: a failure just means the
    /// default (immediate exit) behaviour applies.
    pub fn install_ctrl_handler() {
        unsafe {
            SetConsoleCtrlHandler(ctrl_handler as *const c_void, 1);
        }
    }

    const STD_OUTPUT_HANDLE: u32 = 0xFFFF_FFF5; // (u32)-11
    const ENABLE_VIRTUAL_TERMINAL_PROCESSING: u32 = 0x0004;

    /// Try to enable VT-100. Returns false if the terminal doesn't support it.
    pub fn enable_vt() -> bool {
        unsafe {
            let h = GetStdHandle(STD_OUTPUT_HANDLE);
            if h.is_null() {
                return false;
            }
            let mut mode: u32 = 0;
            if GetConsoleMode(h, &mut mode) == 0 {
                return false;
            }
            mode |= ENABLE_VIRTUAL_TERMINAL_PROCESSING;
            SetConsoleMode(h, mode) != 0
        }
    }

    #[repr(C)]
    struct SystemTime {
        year: u16,
        month: u16,
        day_of_week: u16,
        day: u16,
        hour: u16,
        minute: u16,
        second: u16,
        milliseconds: u16,
    }

    #[repr(C)]
    struct TimeZoneInformation {
        bias: i32,
        standard_name: [u16; 32],
        standard_date: SystemTime,
        standard_bias: i32,
        daylight_name: [u16; 32],
        daylight_date: SystemTime,
        daylight_bias: i32,
    }

    extern "system" {
        fn GetTimeZoneInformation(tzi: *mut TimeZoneInformation) -> u32;
    }

    /// Returns the local-time offset from UTC, in seconds. Falls back to 0
    /// (UTC) if the API is unavailable.
    pub fn local_offset_seconds() -> i64 {
        unsafe {
            let mut tzi: TimeZoneInformation = std::mem::zeroed();
            let ret = GetTimeZoneInformation(&mut tzi);
            // TIME_ZONE_ID_DAYLIGHT == 2
            let bias_minutes = if ret == 2 {
                tzi.bias + tzi.daylight_bias
            } else {
                tzi.bias + tzi.standard_bias
            };
            // Bias is "UTC - local" in minutes, so local = UTC - bias.
            -(bias_minutes as i64) * 60
        }
    }
}

#[cfg(not(windows))]
mod winapi {
    pub fn enable_vt() -> bool { false }
    pub fn local_offset_seconds() -> i64 { 0 }
    pub fn install_ctrl_handler() {}
}

// ============================================================
// 2. ANSI color constants + VT toggle
// ============================================================

static COLORS_ON: AtomicBool = AtomicBool::new(true);

fn disable_colors() {
    COLORS_ON.store(false, Ordering::Relaxed);
}

/// Returns the ANSI code if colors are enabled, otherwise "".
fn p(code: &'static str) -> &'static str {
    if COLORS_ON.load(Ordering::Relaxed) {
        code
    } else {
        ""
    }
}

const C_RESET: &str = "\x1b[0m";
const C_TITLE: &str = "\x1b[36m";
const C_OK: &str = "\x1b[32m";
const C_WARN: &str = "\x1b[33m";
const C_ERROR: &str = "\x1b[31m";
const C_NAME: &str = "\x1b[33m";
const C_PWD: &str = "\x1b[97m";
const C_HINT: &str = "\x1b[90m";
const C_BAR_FILL: &str = "\x1b[42m";
const C_BAR_EMPTY: &str = "\x1b[100m";

const SEP: &str = "\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}";

// ============================================================
// 3. Netsh password keywords (19 languages + fallback)
// ============================================================

const PWD_KEYWORDS: &[&str] = &[
    "Key Content",       // en
    "\u{5173}\u{952e}\u{5185}\u{5bb9}", // zh: 关键内容
    "\u{30ad}\u{30fc} \u{30b3}\u{30f3}\u{30c6}\u{30f3}\u{30c4}", // ja
    "\u{30ad}\u{30fc}\u{30b3}\u{30f3}\u{30c6}\u{30f3}\u{30c4}",   // ja alt
    "Schl\u{00fc}sselinhalt",  // de
    "Contenu de la cl\u{00e9}", // fr
    "Contenido de la clave",    // es
    "\u{421}\u{43e}\u{434}\u{435}\u{440}\u{436}\u{438}\u{43c}\u{43e}\u{435} \u{43a}\u{43b}\u{44e}\u{447}\u{430}", // ru
    "Conte\u{00fa}do da chave", // pt
    "Contenuto della chiave",    // it
    "Zawartosc klucza",          // pl
    "Sleutelinhoud",             // nl
    "\u{d0a4} \u{cf58}\u{d150}\u{ce58}", // ko
    "Anahtar I\u{00e7}erigi",    // tr
    "Kulcstartalom",             // hu
    "Nyckelinnehall",            // sv
    "Avaimen sisalto",           // fi
    "N\u{00f8}gleindhold",       // da
    "N\u{00f8}kkelinnhold",     // no
];

// ============================================================
// 4. Common password blacklist
// ============================================================

const COMMON_PASSWORDS: &[&str] = &[
    "123456", "123456789", "12345678", "1234567", "password",
    "1234567890", "111111", "123123", "000000", "admin",
    "root", "guest", "user", "test", "abc123",
    "qwerty", "password1", "iloveyou", "letmein", "welcome",
    "monkey", "dragon", "master", "sunshine", "princess",
    "football", "shadow", "superman", "michael", "trustno1",
    "password123", "admin123", "123abc",
];

// ============================================================
// 5. Date/time utilities (no chrono dependency)
// ============================================================

fn now_parts() -> (i64, u32, u32, u32, u32, u32) {
    let secs_utc = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64;

    // `SystemTime` is UTC; exports must show wall-clock local time.
    let secs = secs_utc + winapi::local_offset_seconds();

    let days = secs.div_euclid(86400);
    let rem = secs.rem_euclid(86400);
    let hour = rem / 3600;
    let min = (rem % 3600) / 60;
    let sec = rem % 60;

    // Howard Hinnant's civil-from-days algorithm
    let z = days + 719468;
    let era = z.div_euclid(146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };

    (y, m as u32, d as u32, hour as u32, min as u32, sec as u32)
}

fn timestamp_filename() -> String {
    let (y, mo, d, h, mi, s) = now_parts();
    format!("{:04}-{:02}-{:02}_{:02}-{:02}-{:02}", y, mo, d, h, mi, s)
}

fn timestamp_display() -> String {
    let (y, mo, d, h, mi, s) = now_parts();
    format!("{:04}/{:02}/{:02}  {:02}:{:02}:{:02}", y, mo, d, h, mi, s)
}

// ============================================================
// 6. UI strings (zh / en)
// ============================================================

fn load_strings(lang: &str) -> HashMap<&'static str, &'static str> {
    let mut s = HashMap::new();
    if lang == "zh" {
        s.insert("title", "WiFi\u{5bc6}\u{7801}\u{67e5}\u{8be2}\u{5de5}\u{5177}");
        s.insert("subtitle", "\u{5df2}\u{4fdd}\u{5b58}\u{7684} WiFi \u{7f51}\u{7edc}\u{5217}\u{8868}");
        s.insert("prompt", "\u{8bf7}\u{8f93}\u{5165}\u{5e8f}\u{53f7}\u{6216}\u{540d}\u{79f0}\u{ff08}/? \u{6a21}\u{7cca}\u{641c}\u{7d22}\u{ff0c}e \u{5bfc}\u{51fa}\u{ff0c}h \u{5386}\u{53f2}\u{ff0c}q \u{9000}\u{51fa}\u{ff09}");
        s.insert("found", "\u{5df2}\u{627e}\u{5230}");
        s.insert("password", "\u{5bc6}\u{7801}");
        s.insert("strength", "\u{5f3a}\u{5ea6}");
        s.insert("copied", "\u{5bc6}\u{7801}\u{5df2}\u{590d}\u{5236}\u{5230}\u{526a}\u{8d34}\u{677f}");
        s.insert("no_pwd", "\u{8be5} WiFi \u{6ca1}\u{6709}\u{4fdd}\u{5b58}\u{5bc6}\u{7801}");
        s.insert("not_found", "\u{672a}\u{627e}\u{5230}\u{5339}\u{914d}\u{7684} WiFi");
        s.insert("export_time", "\u{5bfc}\u{51fa}\u{65f6}\u{95f4}");
        s.insert("tool_version", "\u{5bfc}\u{51fa}\u{5de5}\u{5177}");
        s.insert("total_count", "WiFi\u{603b}\u{6570}");
        s.insert("qr_generated", "\u{4e8c}\u{7ef4}\u{7801}\u{5df2}\u{751f}\u{6210}");
        s.insert("qr_path", "\u{56fe}\u{7247}\u{8def}\u{5f84}");
        s.insert("err_no_profiles", "[INFO] \u{672a}\u{68c0}\u{6d4b}\u{5230}\u{4efb}\u{4f55}\u{5df2}\u{4fdd}\u{5b58}\u{7684} WiFi \u{914d}\u{7f6e}\u{3002}\u{8bf7}\u{5148}\u{8fde}\u{63a5}\u{4e00}\u{4e2a} WiFi \u{540e}\u{518d}\u{8fd0}\u{884c}\u{672c}\u{5de5}\u{5177}\u{3002}");
        s.insert("press_exit", "\u{6309}\u{56de}\u{8f66}\u{952e}\u{9000}\u{51fa}...");
        s.insert("show_pwd", "[s] \u{663e}\u{793a}\u{5bc6}\u{7801}");
        s.insert("hide_pwd", "[s] \u{9690}\u{85cf}\u{5bc6}\u{7801}");
        s.insert("qr_hint", "[r] \u{751f}\u{6210}\u{4e8c}\u{7ef4}\u{7801}");
        s.insert("copy_wifi", "[c] \u{590d}\u{5236}\u{8fde}\u{63a5}\u{4e32}");
        s.insert("back", "[b] \u{8fd4}\u{56de}");
        s.insert("history_title", "\u{67e5}\u{8be2}\u{5386}\u{53f2}");
        s.insert("history_empty", "\u{6682}\u{65e0}\u{67e5}\u{8be2}\u{5386}\u{53f2}");
        s.insert("export_title", "\u{5bfc}\u{51fa}\u{5b8c}\u{6210}");
        s.insert("exported_to", "\u{5df2}\u{5bfc}\u{51fa}\u{5230}");
        s.insert("select_range", "\u{5bfc}\u{51fa}\u{8303}\u{56f4}\u{ff1a}0=\u{5168}\u{90e8} \u{6216}\u{8f93}\u{5165}\u{5e8f}\u{53f7}\u{ff08}1,3,5\u{ff09}");
        s.insert("select_format", "\u{5bfc}\u{51fa}\u{683c}\u{5f0f}\u{ff1a}1=TXT 2=CSV");
        s.insert("search_prompt", "\u{641c}\u{7d22} /");
        s.insert("err_export", "\u{5bfc}\u{51fa}\u{5931}\u{8d25}");
        s.insert("select_invalid", "\u{9009}\u{62e9}\u{65e0}\u{6548}\u{ff0c}\u{672a}\u{5bfc}\u{51fa}\u{4efb}\u{4f55}\u{5185}\u{5bb9}");
        s.insert("usage_title", "\u{4f7f}\u{7528}\u{65b9}\u{5f0f}");
        s.insert("usage_body", "wifi_password_tool.exe [zh|en|ja|...]   \u{5f3a}\u{5236}\u{6307}\u{5b9a}\u{754c}\u{9762} / netsh \u{8bed}\u{8a00}\n  wifi_password_tool.exe -h              \u{663e}\u{793a}\u{5e2e}\u{52a9}\n  wifi_password_tool.exe -v              \u{663e}\u{793a}\u{7248}\u{672c}");
        s.insert("version_label", "\u{7248}\u{672c}");
    } else {
        s.insert("title", "WiFi Password Query Tool");
        s.insert("subtitle", "Saved WiFi networks");
        s.insert("prompt", "Enter index or name (/? fuzzy, e export, h history, q quit)");
        s.insert("found", "Found");
        s.insert("password", "Password");
        s.insert("strength", "Strength");
        s.insert("copied", "Password copied to clipboard");
        s.insert("no_pwd", "This WiFi has no saved password");
        s.insert("not_found", "No matching WiFi found");
        s.insert("export_time", "Export Time");
        s.insert("tool_version", "Tool Version");
        s.insert("total_count", "Total WiFi Count");
        s.insert("qr_generated", "QR code generated");
        s.insert("qr_path", "Image path");
        s.insert("err_no_profiles", "[INFO] No saved WiFi profiles detected. Please connect to a WiFi network before running this tool.");
        s.insert("press_exit", "Press Enter to exit...");
        s.insert("show_pwd", "[s] Show password");
        s.insert("hide_pwd", "[s] Hide password");
        s.insert("qr_hint", "[r] Generate QR code");
        s.insert("copy_wifi", "[c] Copy connect string");
        s.insert("back", "[b] Back");
        s.insert("history_title", "Query history");
        s.insert("history_empty", "No query history");
        s.insert("export_title", "Export complete");
        s.insert("exported_to", "Exported to");
        s.insert("select_range", "Export range: 0=all or enter indices (1,3,5)");
        s.insert("select_format", "Export format: 1=TXT 2=CSV");
        s.insert("search_prompt", "Search /");
        s.insert("err_export", "Export failed");
        s.insert("select_invalid", "Invalid selection, nothing exported");
        s.insert("usage_title", "Usage");
        s.insert("usage_body", "wifi_password_tool.exe [zh|en|ja|...]   force UI / netsh language\n  wifi_password_tool.exe -h              show this help\n  wifi_password_tool.exe -v              show version");
        s.insert("version_label", "Version");
    }
    s
}

fn strength_label(lang: &str, score: u8) -> &'static str {
    if lang == "zh" {
        match score {
            0 | 1 => "\u{6781}\u{5f31}",
            2 => "\u{5f31}",
            3 => "\u{4e00}\u{822c}",
            4 => "\u{5f3a}",
            _ => "\u{6781}\u{5f3a}",
        }
    } else {
        match score {
            0 | 1 => "Very weak",
            2 => "Weak",
            3 => "Fair",
            4 => "Strong",
            _ => "Very strong",
        }
    }
}

// ============================================================
// 7. Language detection
// ============================================================

/// Parses an explicit language argument (`zh`, `EN`, ...).
/// Returns `None` when the argument is not a supported language code.
fn lang_from_arg(arg: &str) -> Option<String> {
    let a = arg.trim().to_lowercase();
    if is_valid_lang(&a) {
        Some(a)
    } else {
        None
    }
}

fn detect_language() -> String {
    // 1. Command-line argument (skip flags such as -h / -v)
    let args: Vec<String> = std::env::args().collect();
    for a in &args[1..] {
        if a.starts_with('-') || a.starts_with('/') {
            continue;
        }
        if let Some(lang) = lang_from_arg(a) {
            return lang;
        }
    }

    // 2. Registry: HKCU\Control Panel\International -> LocaleName
    if let Ok(out) = Command::new("cmd")
        .args(["/c", "reg", "query", r"HKCU\Control Panel\International", "/v", "LocaleName"])
        .output()
    {
        let text = String::from_utf8_lossy(&out.stdout);
        for line in text.lines() {
            if line.contains("LocaleName") {
                if let Some(idx) = line.rfind('-') {
                    // Extract language code (e.g. "zh-CN" -> "zh")
                    let before = &line[..idx];
                    if let Some(start) = before.rfind(|c: char| !c.is_alphanumeric()) {
                        let lang = &before[start + 1..];
                        let lang = lang.to_lowercase();
                        if is_valid_lang(&lang) {
                            return lang;
                        }
                    }
                    // Fallback: try to extract from the value
                    let parts: Vec<&str> = line.split_whitespace().collect();
                    if let Some(last) = parts.last() {
                        let lang = last.split('-').next().unwrap_or("").to_lowercase();
                        if is_valid_lang(&lang) {
                            return lang;
                        }
                    }
                }
            }
        }
    }

    // 3. LANG environment variable
    if let Ok(lang) = std::env::var("LANG") {
        let lang = lang.split('-').next().unwrap_or("").to_lowercase();
        if is_valid_lang(&lang) {
            return lang;
        }
    }

    // Default: English
    "en".to_string()
}

fn is_valid_lang(code: &str) -> bool {
    matches!(code,
        "zh" | "en" | "ja" | "ko" | "de" | "fr" | "ru" | "es" | "it" |
        "pt" | "pl" | "nl" | "tr" | "ar" | "he" | "cs" | "hu" |
        "sv" | "fi" | "da" | "no"
    )
}

// ============================================================
// 8. WiFi operations
// ============================================================

fn get_wifi_profiles() -> Vec<String> {
    let out = match Command::new("cmd")
        .args(["/c", "chcp 65001 >nul & netsh wlan show profiles"])
        .output()
    {
        Ok(o) => o,
        Err(_) => return Vec::new(),
    };
    let text = String::from_utf8_lossy(&out.stdout);
    parse_profiles(&text)
}

/// Extracts de-duplicated SSIDs from the raw `netsh wlan show profiles`
/// output. Kept separate from the shell call so it can be unit-tested with
/// captured sample output.
fn parse_profiles(text: &str) -> Vec<String> {
    let mut profiles = Vec::new();
    for line in text.lines() {
        if let Some(ssid) = parse_profile_line(line) {
            if !profiles.contains(&ssid) {
                profiles.push(ssid);
            }
        }
    }
    profiles
}

fn parse_profile_line(line: &str) -> Option<String> {
    let trimmed = line.trim();
    let idx = trimmed.find(':')?;
    let before = trimmed[..idx].to_lowercase();
    let after = trimmed[idx + 1..].trim();
    let is_profile = before.contains("profile")
        || before.contains("profil")
        || before.contains("perfil")
        || before.contains("\u{914d}\u{7f6e}\u{6587}\u{4ef6}") // 配置文件
        || before.contains("\u{30d7}\u{30ed}\u{30d5}\u{30a1}\u{30a4}\u{30eb}") // プロファイル
        || before.contains("\u{d504}\u{b85c}\u{d544}") // 프로필
        || before.contains("\u{43f}\u{440}\u{43e}\u{444}\u{438}\u{43b}\u{44c}"); // профиль
    if is_profile && !after.is_empty() && !after.starts_with('<') {
        Some(after.to_string())
    } else {
        None
    }
}

fn get_wifi_password(name: &str) -> Option<String> {
    let escaped = escape_for_shell_arg(name);
    let cmd = format!(
        "chcp 65001 >nul & netsh wlan show profile name=\"{}\" key=clear",
        escaped
    );
    let out = Command::new("cmd").args(["/c", &cmd]).output().ok()?;
    let text = String::from_utf8_lossy(&out.stdout);
    parse_password(&text)
}

/// Extracts the clear-text key from raw `netsh ... key=clear` output.
fn parse_password(text: &str) -> Option<String> {
    for line in text.lines() {
        if let Some(pwd) = extract_password(line) {
            return Some(pwd);
        }
    }
    None
}

// ============================================================
// 9. Password extraction (multi-language)
// ============================================================

fn extract_password(line: &str) -> Option<String> {
    for kw in PWD_KEYWORDS {
        if line.contains(kw) {
            if let Some(idx) = line.find(':') {
                let pwd = line[idx + 1..].trim();
                if !pwd.is_empty() {
                    return Some(pwd.to_string());
                }
            }
        }
    }
    // Fallback: line containing both "key" and "content"
    let lower = line.to_lowercase();
    if lower.contains("key") && lower.contains("content") {
        if let Some(idx) = line.find(':') {
            let pwd = line[idx + 1..].trim();
            if !pwd.is_empty() {
                return Some(pwd.to_string());
            }
        }
    }
    None
}

// ============================================================
// 10. SSID escape (prevent cmd.exe injection)
// ============================================================

/// Escapes a string for safe inclusion as a quoted argument inside a
/// `cmd.exe /c "..."` invocation. Prevents SSID injection attacks
/// where a WiFi name like `Foo"&calc&"` would execute `calc.exe`.
fn escape_for_shell_arg(s: &str) -> String {
    s.replace('^', "^^")
        .replace('&', "^&")
        .replace('|', "^|")
        .replace('<', "^<")
        .replace('>', "^>")
        .replace('(', "^(")
        .replace(')', "^)")
        .replace(',', "^,")
        .replace(';', "^;")
        .replace('"', "\"\"")
}

// ============================================================
// 11. Filename utilities
// ============================================================

fn sanitize_filename(name: &str) -> String {
    name.chars()
        .map(|c| match c {
            '\\' | '/' | ':' | '*' | '?' | '"' | '<' | '>' | '|' | ' ' => '_',
            _ => c,
        })
        .collect()
}

/// Returns `path` if no file exists there, otherwise appends
/// "_(2)", "_(3)", ... before the extension.
fn unique_filename(path: &str) -> String {
    if !Path::new(path).exists() {
        return path.to_string();
    }
    let p = Path::new(path);
    let ext = match p.extension() {
        Some(e) => format!(".{}", e.to_string_lossy()),
        None => String::new(),
    };
    let base = &path[..path.len() - ext.len()];
    for i in 2..10000 {
        let candidate = format!("{}_({}){}", base, i, ext);
        if !Path::new(&candidate).exists() {
            return candidate;
        }
    }
    path.to_string()
}

// ============================================================
// 12. Password strength (5-dimension, 0-5 score)
// ============================================================

fn password_strength(pwd: &str, ssid: &str) -> u8 {
    let mut score: u8 = 0;

    // 1. Length tiers
    let len = pwd.len();
    score += match len {
        0..=7 => 0,
        8..=11 => 1,
        12..=15 => 2,
        16..=19 => 3,
        _ => 4,
    };

    // 2. Character classes
    let has_lower = pwd.chars().any(|c| c.is_ascii_lowercase());
    let has_upper = pwd.chars().any(|c| c.is_ascii_uppercase());
    let has_digit = pwd.chars().any(|c| c.is_ascii_digit());
    let has_special = pwd.chars().any(|c| !c.is_ascii_alphanumeric());
    let classes = [has_lower, has_upper, has_digit, has_special]
        .iter()
        .filter(|&&b| b)
        .count();
    score += match classes {
        4 => 1,
        3 => 1,
        _ => 0,
    };

    // 3. Common password blacklist
    let pwd_lower = pwd.to_lowercase();
    if COMMON_PASSWORDS.contains(&pwd_lower.as_str()) {
        score = score.saturating_sub(3);
    }

    // 4. SSID substring penalty
    if !ssid.is_empty() && pwd_lower.contains(&ssid.to_lowercase()) {
        score = score.saturating_sub(1);
    }

    // 5. Sequential / repeated char penalties
    if is_sequential(pwd) {
        score = score.saturating_sub(1);
    }
    if is_repeated(pwd) {
        score = score.saturating_sub(1);
    }

    score.min(5)
}

fn is_sequential(s: &str) -> bool {
    let chars: Vec<char> = s.chars().collect();
    if chars.len() < 4 {
        return false;
    }
    for i in 0..chars.len() - 3 {
        let a = chars[i] as i32;
        let b = chars[i + 1] as i32;
        let c = chars[i + 2] as i32;
        let d = chars[i + 3] as i32;
        // Ascending: abcd
        if b - a == 1 && c - b == 1 && d - c == 1 {
            return true;
        }
        // Descending: dcba
        if a - b == 1 && b - c == 1 && c - d == 1 {
            return true;
        }
    }
    false
}

fn is_repeated(s: &str) -> bool {
    let chars: Vec<char> = s.chars().collect();
    if chars.len() < 3 {
        return false;
    }
    for i in 0..chars.len() - 2 {
        if chars[i] == chars[i + 1] && chars[i + 1] == chars[i + 2] {
            return true;
        }
    }
    false
}

fn build_strength_bar(score: u8) -> String {
    let filled = score as usize;
    let empty = 5 - filled;
    let bar: String = "\u{2588}".repeat(filled);
    let empty_bar: String = "\u{2591}".repeat(empty);
    format!("[{}{}] {}/5", bar, empty_bar, score)
}

// ============================================================
// 13. Fuzzy search (multi-token AND)
// ============================================================

fn fuzzy_search(profiles: &[String], query: &str) -> Vec<(usize, String)> {
    let tokens: Vec<&str> = query.split_whitespace().filter(|t| !t.is_empty()).collect();
    if tokens.is_empty() {
        return Vec::new();
    }
    profiles
        .iter()
        .enumerate()
        .filter(|(_, name)| {
            let lower = name.to_lowercase();
            tokens.iter().all(|t| lower.contains(&t.to_lowercase()))
        })
        .map(|(i, n)| (i, n.clone()))
        .collect()
}

/// Escapes the WIFI: URI reserved characters (see the `WIFI:` scheme spec).
fn escape_wifi_value(s: &str) -> String {
    s.replace('\\', "\\\\")
        .replace(';', "\\;")
        .replace(',', "\\,")
        .replace(':', "\\:")
}

/// Builds a `WIFI:T:WPA;S:<ssid>;P:<password>;;` payload for QR / clipboard.
fn wifi_payload(ssid: &str, password: &str) -> String {
    format!(
        "WIFI:T:WPA;S:{};P:{};;",
        escape_wifi_value(ssid),
        escape_wifi_value(password)
    )
}

// ============================================================
// 14. QR code generation (SVG with SSID label)
// ============================================================

fn generate_qr_svg(ssid: &str, password: &str) -> Option<String> {
    let wifi_str = wifi_payload(ssid, password);

    let code = QrCode::with_error_correction_level(wifi_str.as_bytes(), EcLevel::H).ok()?;
    let width = code.width();
    let pixel = 8; // px per QR module
    let text_h = 36;
    let total_w = width * pixel;
    let total_h = width * pixel + text_h;

    let mut svg = format!(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n\
         <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{}\" height=\"{}\" viewBox=\"0 0 {} {}\">\n\
         <rect width=\"{}\" height=\"{}\" fill=\"#FFFFFF\"/>\n",
        total_w, total_h, total_w, total_h, total_w, total_h
    );

    // Draw QR modules
    for y in 0..width {
        for x in 0..width {
            if code[(x, y)] == Color::Dark {
                svg.push_str(&format!(
                    "<rect x=\"{}\" y=\"{}\" width=\"{}\" height=\"{}\" fill=\"#000000\"/>\n",
                    x * pixel, y * pixel, pixel, pixel
                ));
            }
        }
    }

    // SSID text label below QR code
    let escaped_ssid = escape_xml(ssid);
    svg.push_str(&format!(
        "<text x=\"{}\" y=\"{}\" text-anchor=\"middle\" dominant-baseline=\"central\" \
         font-family=\"sans-serif\" font-size=\"14\" fill=\"#333333\">{}</text>\n</svg>",
        total_w / 2,
        width * pixel + text_h / 2,
        escaped_ssid
    ));

    Some(svg)
}

fn escape_xml(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&apos;")
}

// ============================================================
// 15. Clipboard (via clip.exe — no external crate needed)
// ============================================================

fn copy_to_clipboard(text: &str) {
    use std::io::Write;
    use std::process::Stdio;
    let mut child = match Command::new("cmd")
        .args(["/c", "clip"])
        .stdin(Stdio::piped())
        .spawn()
    {
        Ok(c) => c,
        Err(_) => return,
    };
    if let Some(stdin) = child.stdin.as_mut() {
        let _ = stdin.write_all(text.as_bytes());
    }
    let _ = child.wait();
}

// ============================================================
// 16. Export (TXT / CSV)
// ============================================================

/// Builds the full file body for an export.
///
/// `passwords` is parallel to `selected` (the resolved password, if any).
/// Note: no ANSI escapes are emitted here — exported files must stay plain
/// text even when the console has VT-100 enabled.
fn build_export_content(
    profiles: &[String],
    selected: &[usize],
    format: &str,
    strings: &HashMap<&'static str, &'static str>,
    passwords: &[Option<String>],
) -> String {
    let mut content = String::new();
    let sep_str = SEP.to_string();

    // BOM for UTF-8 (Excel needs it to detect UTF-8 in CSV)
    content.push_str("\u{FEFF}");

    content.push_str(&sep_str);
    content.push('\n');
    content.push_str(&format!("  {}\n", strings["title"]));
    content.push_str(&sep_str);
    content.push('\n');
    content.push('\n');
    content.push_str(&format!("{}: {}\n", strings["export_time"], timestamp_display()));
    content.push_str(&format!(
        "{}: {} v{} (Rust)\n",
        strings["tool_version"],
        strings["title"],
        env!("CARGO_PKG_VERSION")
    ));
    content.push_str(&format!("{}: {}\n", strings["total_count"], selected.len()));
    content.push('\n');
    content.push_str(&sep_str);
    content.push('\n');

    if format == "csv" {
        content.push_str("Index,SSID,Password\n");
        for (i, &idx) in selected.iter().enumerate() {
            if idx >= profiles.len() {
                continue;
            }
            let pwd = passwords.get(i).and_then(|p| p.clone()).unwrap_or_default();
            content.push_str(&format!(
                "{},{},{}\n",
                i + 1,
                csv_field(&profiles[idx]),
                csv_field(&pwd)
            ));
        }
    } else {
        for (i, &idx) in selected.iter().enumerate() {
            if idx >= profiles.len() {
                continue;
            }
            let pwd = passwords.get(i).and_then(|p| p.clone()).unwrap_or_default();
            content.push_str(&format!("{:>3}.  {:<36}  {}\n", i + 1, profiles[idx], pwd));
        }
    }

    content.push_str(&sep_str);
    content.push('\n');
    content
}

/// RFC 4180 field quoting.
fn csv_field(s: &str) -> String {
    if s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r') {
        format!("\"{}\"", s.replace('"', "\"\""))
    } else {
        s.to_string()
    }
}

/// Parse the export-range input.
/// - "" or "0"  → all profiles (0-based indices 0..total)
/// - "1,3,5"    → 1-based serial numbers, mapped to 0-based indices
/// - out-of-range / non-numeric tokens are ignored; duplicates removed, order kept
fn parse_export_selection(input: &str, total: usize) -> Vec<usize> {
    let t = input.trim();
    if t.is_empty() || t == "0" {
        return (0..total).collect();
    }
    let mut out = Vec::new();
    for tok in t.split(',') {
        if let Ok(n) = tok.trim().parse::<usize>() {
            if n >= 1 && n <= total && !out.contains(&(n - 1)) {
                out.push(n - 1);
            }
        }
    }
    out
}

fn do_export(
    profiles: &[String],
    selected: &[usize],
    format: &str,
    lang: &str,
    strings: &HashMap<&'static str, &'static str>,
) {
    let ts = timestamp_filename();
    let ext = if format == "csv" { "csv" } else { "txt" };
    let prefix = if lang == "zh" {
        "WiFi\u{5bc6}\u{7801}\u{5bfc}\u{51fa}"
    } else {
        "WiFi_Password_Export"
    };
    let filename = unique_filename(&format!("{}_{}.{}", prefix, ts, ext));

    // Resolve passwords first so the progress bar can report real progress.
    let total = selected.len();
    let mut passwords: Vec<Option<String>> = Vec::with_capacity(total);
    for (i, &idx) in selected.iter().enumerate() {
        let pwd = if idx < profiles.len() {
            get_wifi_password(&profiles[idx])
        } else {
            None
        };
        passwords.push(pwd);

        // Progress bar (stderr — safe to colour)
        let pct = ((i + 1) * 100 / total.max(1)) as usize;
        let filled = pct / 10;
        let bar: String = "\u{2588}".repeat(filled);
        let empty: String = "\u{2591}".repeat(10 - filled);
        eprint!(
            "\r  {}{}{}{}{} {}/{} ({}%)",
            p(C_BAR_FILL),
            bar,
            p(C_BAR_EMPTY),
            empty,
            p(C_RESET),
            i + 1,
            total,
            pct
        );
        let _ = io::stderr().flush();
    }
    eprintln!();

    let content = build_export_content(profiles, selected, format, strings, &passwords);

    match fs::write(&filename, content) {
        Ok(_) => {
            println!("\n  {}{}{} {}", p(C_OK), strings["export_title"], p(C_RESET), strings["exported_to"]);
            println!("  {}{}{}", p(C_NAME), filename, p(C_RESET));
        }
        Err(e) => {
            eprintln!("  {}[ERROR]{} {}: {}", p(C_ERROR), p(C_RESET), strings["err_export"], e);
        }
    }
}

// ============================================================
// 17. Display helpers
// ============================================================

fn print_help(strings: &HashMap<&'static str, &'static str>) {
    let sep = SEP;
    println!("{}", sep);
    println!("  {}{}{}", p(C_TITLE), strings["title"], p(C_RESET));
    println!("{}", sep);
    println!();
    println!("  {}{}{}", p(C_HINT), strings["usage_title"], p(C_RESET));
    println!("  {}", strings["usage_body"]);
    println!();
    println!("  {}", strings["prompt"]);
    println!("{}", sep);
}

fn clear_screen() {
    let _ = Command::new("cmd").args(["/c", "cls"]).status();
}

fn show_main(profiles: &[String], strings: &HashMap<&'static str, &'static str>) {
    clear_screen();
    let sep = SEP;
    println!("{}", sep);
    println!("  {}{}{}", p(C_TITLE), strings["title"], p(C_RESET));
    println!("  {}{}{}", p(C_HINT), strings["subtitle"], p(C_RESET));
    println!("{}", sep);
    println!();

    for (i, name) in profiles.iter().enumerate() {
        println!("  {}{:>2}.{} {}{}{}", p(C_HINT), i + 1, p(C_RESET), p(C_NAME), name, p(C_RESET));
    }

    println!();
    println!("{}", sep);
    println!("  {}{}{}", p(C_HINT), strings["prompt"], p(C_RESET));
}

fn show_detail(
    ssid: &str,
    lang: &str,
    strings: &HashMap<&'static str, &'static str>,
    masked: bool,
) {
    clear_screen();
    let sep = SEP;
    println!("{}", sep);
    println!("  {}{}{}", p(C_TITLE), strings["title"], p(C_RESET));
    println!("{}", sep);
    println!();

    let pwd = get_wifi_password(ssid);

    println!("  {}{}{}: {}{}{}", p(C_HINT), strings["found"], p(C_RESET), p(C_NAME), ssid, p(C_RESET));
    println!();

    match &pwd {
        Some(pw) => {
            let display = if masked {
                "*".repeat(pw.len().min(32))
            } else {
                pw.clone()
            };
            println!("  {}{}{}: {}{}{}", p(C_HINT), strings["password"], p(C_RESET), p(C_PWD), display, p(C_RESET));
            let score = password_strength(pw, ssid);
            let label = strength_label(lang, score);
            println!("  {}{}{}: {}{} {}({} {}/5){}", p(C_HINT), strings["strength"], p(C_RESET), p(C_OK), build_strength_bar(score), p(C_HINT), label, score, p(C_RESET));

            if !masked {
                copy_to_clipboard(pw);
                println!();
                println!("  {}{}{}", p(C_OK), strings["copied"], p(C_RESET));
            }
        }
        None => {
            println!("  {}{}{}", p(C_WARN), strings["no_pwd"], p(C_RESET));
        }
    }

    println!();
    println!("{}", sep);
    let toggle = if masked { strings["show_pwd"] } else { strings["hide_pwd"] };
    println!("  {}  {}  {}  {}", toggle, strings["qr_hint"], strings["copy_wifi"], strings["back"]);
}

fn show_history(history: &[(usize, String)], _lang: &str, strings: &HashMap<&'static str, &'static str>) {
    clear_screen();
    let sep = SEP;
    println!("{}", sep);
    println!("  {}{}{}", p(C_TITLE), strings["history_title"], p(C_RESET));
    println!("{}", sep);
    println!();

    if history.is_empty() {
        println!("  {}{}{}", p(C_HINT), strings["history_empty"], p(C_RESET));
    } else {
        for (i, (idx, name)) in history.iter().enumerate() {
            println!("  {}{}.{} {}{}{} ({})", p(C_HINT), i + 1, p(C_RESET), p(C_NAME), name, p(C_RESET), idx + 1);
        }
    }

    println!();
    println!("{}", sep);
    println!("  {}", strings["back"]);
}

// ============================================================
// 18. Main
// ============================================================

fn main() {
    // Panic hook — print and wait, like Go's debug.PrintStack
    std::panic::set_hook(Box::new(|info| {
        eprintln!("\n  [PANIC] {}", info);
        eprintln!("  Press Enter to exit...");
        let _ = io::stdin().read_line(&mut String::new());
    }));

    // Enable VT-100 (or disable colors on failure)
    if !winapi::enable_vt() {
        disable_colors();
    }

    // Exit cleanly on Ctrl+C instead of being killed mid-prompt
    winapi::install_ctrl_handler();

    // Detect language and load strings
    let lang = detect_language();
    let strings = load_strings(&lang);

    // -h / -v are honoured in any argument position, and are handled after
    // string loading so that they are localised.
    let args: Vec<String> = std::env::args().collect();
    if args.iter().any(|a| a == "-h" || a == "--help" || a == "/?") {
        print_help(&strings);
        return;
    }
    if args.iter().any(|a| a == "-v" || a == "--version") {
        println!(
            "  {} {} v{} (Rust edition)",
            strings["title"],
            strings["version_label"],
            env!("CARGO_PKG_VERSION")
        );
        return;
    }

    // Console title
    let title_cmd = format!("title {}", strings["title"]);
    let _ = Command::new("cmd").args(["/c", &title_cmd]).output();

    // Clear screen
    clear_screen();

    // Get WiFi profiles — empty state guard
    let profiles = get_wifi_profiles();
    if profiles.is_empty() {
        let sep = SEP;
        println!("{}", sep);
        println!("  {}{}{}", p(C_TITLE), strings["title"], p(C_RESET));
        println!("{}", sep);
        println!();
        println!("  {}", strings["err_no_profiles"]);
        println!();
        println!("  {}{}{}", p(C_HINT), strings["press_exit"], p(C_RESET));
        let _ = io::stdin().read_line(&mut String::new());
        return;
    }

    // State
    let mut history: Vec<(usize, String)> = Vec::new();
    let mut in_detail = false;
    let mut current_ssid = String::new();
    let mut masked = true;

    // Main loop
    loop {
        if in_detail {
            show_detail(&current_ssid, &lang, &strings, masked);
        } else {
            show_main(&profiles, &strings);
        }

        // Read input
        let mut input = String::new();
        if io::stdin().read_line(&mut input).is_err() {
            continue;
        }
        let input = input.trim().to_string();

        if input.is_empty() {
            continue;
        }

        // Global commands
        match input.as_str() {
            "q" | "Q" => break,
            "h" | "H" => {
                show_history(&history, &lang, &strings);
                let _ = io::stdin().read_line(&mut String::new());
                continue;
            }
            _ => {}
        }

        if in_detail {
            match input.as_str() {
                "b" | "B" => {
                    in_detail = false;
                    masked = true;
                }
                "s" | "S" => {
                    masked = !masked;
                }
                "r" | "R" => {
                    // Generate QR code
                    if let Some(pwd) = get_wifi_password(&current_ssid) {
                        match generate_qr_svg(&current_ssid, &pwd) {
                            Some(svg) => {
                                let safe = sanitize_filename(&current_ssid);
                                let ts = timestamp_filename();
                                let fname = unique_filename(&format!(
                                    "WiFi_QR_{}_{}.svg", safe, ts
                                ));
                                if fs::write(&fname, svg).is_ok() {
                                    copy_to_clipboard(&fname);
                                    let _ = Command::new("cmd")
                                        .args(["/c", "start", "", &fname])
                                        .spawn();
                                    println!("\n  {}{}: {}{}", p(C_OK), strings["qr_path"], p(C_NAME), fname);
                                    println!("  {}{}{}", p(C_OK), strings["qr_generated"], p(C_RESET));
                                } else {
                                    eprintln!("  {}[ERROR] QR write failed{}", p(C_ERROR), p(C_RESET));
                                }
                            }
                            None => {
                                eprintln!("  {}[ERROR] {}", p(C_ERROR), p(C_RESET));
                            }
                        }
                    }
                    let _ = io::stdin().read_line(&mut String::new());
                }
                "c" | "C" => {
                    // Copy WiFi connect string
                    if let Some(pwd) = get_wifi_password(&current_ssid) {
                        let wifi_str = wifi_payload(&current_ssid, &pwd);
                        copy_to_clipboard(&wifi_str);
                        println!("\n  {}WiFi connect string copied{}", p(C_OK), p(C_RESET));
                    }
                    let _ = io::stdin().read_line(&mut String::new());
                }
                _ => {
                    // Try to interpret as number (history quick-select)
                    if let Ok(n) = input.parse::<usize>() {
                        if n > 0 && n <= history.len() {
                            let (idx, _) = &history[n - 1];
                            current_ssid = profiles[*idx].clone();
                            masked = true;
                        }
                    }
                }
            }
            continue;
        }

        // Main menu mode
        if input.starts_with('/') {
            // Fuzzy search
            let query = &input[1..];
            let results = fuzzy_search(&profiles, query);
            if results.is_empty() {
                println!("  {}{}{}", p(C_WARN), strings["not_found"], p(C_RESET));
                let _ = io::stdin().read_line(&mut String::new());
            } else {
                clear_screen();
                let sep = SEP;
                println!("{}", sep);
                println!("  {}{} {}{}", p(C_TITLE), strings["search_prompt"], query, p(C_RESET));
                println!("{}", sep);
                println!();
                for (i, (_idx, name)) in results.iter().enumerate() {
                    println!("  {}{}.{} {}{}{}", p(C_HINT), i + 1, p(C_RESET), p(C_NAME), name, p(C_RESET));
                }
                println!();
                println!("{}", sep);
                println!("  {}", strings["prompt"]);
                let mut s2 = String::new();
                let _ = io::stdin().read_line(&mut s2);
                let s2 = s2.trim();
                if let Ok(n) = s2.parse::<usize>() {
                    if n > 0 && n <= results.len() {
                        let (idx, _) = results[n - 1];
                        current_ssid = profiles[idx].clone();
                        masked = true;
                        in_detail = true;
                        // Add to history
                        history.insert(0, (idx, current_ssid.clone()));
                        if history.len() > 10 {
                            history.pop();
                        }
                    }
                }
            }
            continue;
        }

        if input == "e" || input == "E" {
            // Export mode
            clear_screen();
            let sep = SEP;
            println!("{}", sep);
            println!("  {}{}{}", p(C_TITLE), strings["select_range"], p(C_RESET));
            println!("{}", sep);
            let mut range_input = String::new();
            let _ = io::stdin().read_line(&mut range_input);
            let range_input = range_input.trim();

            let selected: Vec<usize> = parse_export_selection(range_input, profiles.len());

            if selected.is_empty() {
                println!("  {}{}{}", p(C_WARN), strings["select_invalid"], p(C_RESET));
                let _ = io::stdin().read_line(&mut String::new());
                continue;
            }

            println!("  {}{}{}", p(C_HINT), strings["select_format"], p(C_RESET));
            let mut fmt_input = String::new();
            let _ = io::stdin().read_line(&mut fmt_input);
            let format = if fmt_input.trim() == "2" { "csv" } else { "txt" };

            do_export(&profiles, &selected, format, &lang, &strings);
            let _ = io::stdin().read_line(&mut String::new());
            continue;
        }

        // Try to interpret as profile index or name
        let found_idx = if let Ok(n) = input.parse::<usize>() {
            if n > 0 && n <= profiles.len() {
                Some(n - 1)
            } else {
                None
            }
        } else {
            // Search by name (case-insensitive)
            let lower = input.to_lowercase();
            profiles.iter().position(|p| p.to_lowercase() == lower)
                .or_else(|| profiles.iter().position(|p| p.to_lowercase().contains(&lower)))
        };

        match found_idx {
            Some(idx) => {
                current_ssid = profiles[idx].clone();
                masked = true;
                in_detail = true;
                // Add to history
                history.insert(0, (idx, current_ssid.clone()));
                if history.len() > 10 {
                    history.pop();
                }
            }
            None => {
                println!("  {}{}{}", p(C_WARN), strings["not_found"], p(C_RESET));
                let _ = io::stdin().read_line(&mut String::new());
            }
        }
    }
}

// ============================================================
// 19. Unit tests
// ============================================================

#[cfg(test)]
mod tests {
    use super::*;

    // --- extract_password ---

    #[test]
    fn test_extract_password_english() {
        let line = "    Key Content    : MyPassword123";
        assert_eq!(extract_password(line), Some("MyPassword123".to_string()));
    }

    #[test]
    fn test_extract_password_chinese() {
        let line = "    \u{5173}\u{952e}\u{5185}\u{5bb9}    : mywifi";
        assert_eq!(extract_password(line), Some("mywifi".to_string()));
    }

    #[test]
    fn test_extract_password_german() {
        let line = "    Schl\u{00fc}sselinhalt    : passwort";
        assert_eq!(extract_password(line), Some("passwort".to_string()));
    }

    #[test]
    fn test_extract_password_danish() {
        let line = "    N\u{00f8}gleindhold    : kode";
        assert_eq!(extract_password(line), Some("kode".to_string()));
    }

    #[test]
    fn test_extract_password_norwegian() {
        let line = "    N\u{00f8}kkelinnhold    : passord";
        assert_eq!(extract_password(line), Some("passord".to_string()));
    }

    #[test]
    fn test_extract_password_fallback() {
        let line = "    Key content    : fallback_pwd";
        assert_eq!(extract_password(line), Some("fallback_pwd".to_string()));
    }

    #[test]
    fn test_extract_password_no_match() {
        let line = "    Some other line: not a password";
        assert_eq!(extract_password(line), None);
    }

    // --- escape_for_shell_arg ---

    #[test]
    fn test_escape_plain() {
        assert_eq!(escape_for_shell_arg("HomeWiFi-5G"), "HomeWiFi-5G");
    }

    #[test]
    fn test_escape_empty() {
        assert_eq!(escape_for_shell_arg(""), "");
    }

    #[test]
    fn test_escape_ampersand() {
        assert_eq!(escape_for_shell_arg("Foo&Bar"), "Foo^&Bar");
    }

    #[test]
    fn test_escape_pipe() {
        assert_eq!(escape_for_shell_arg("Foo|Bar"), "Foo^|Bar");
    }

    #[test]
    fn test_escape_quotes() {
        assert_eq!(escape_for_shell_arg("Foo\"Bar"), "Foo\"\"Bar");
    }

    #[test]
    fn test_escape_caret_first() {
        assert_eq!(escape_for_shell_arg("Foo^Bar"), "Foo^^Bar");
    }

    #[test]
    fn test_escape_injection_attempt() {
        assert_eq!(
            escape_for_shell_arg("Foo\"&calc&\""),
            "Foo\"\"^&calc^&\"\""
        );
    }

    #[test]
    fn test_escape_angle_brackets() {
        assert_eq!(escape_for_shell_arg("Foo<Bar>Baz"), "Foo^<Bar^>Baz");
    }

    #[test]
    fn test_escape_parens() {
        assert_eq!(escape_for_shell_arg("Foo(Bar)"), "Foo^(Bar^)");
    }

    #[test]
    fn test_escape_space_kept() {
        assert_eq!(escape_for_shell_arg("Foo Bar"), "Foo Bar");
    }

    // --- unique_filename ---

    #[test]
    fn test_unique_filename_no_conflict() {
        let path = "nonexistent_test_file_12345.txt";
        let result = unique_filename(path);
        assert_eq!(result, path);
    }

    #[test]
    fn test_unique_filename_with_conflict() {
        // Use the OS temp dir: tests must never litter (or depend on) the CWD.
        let dir = std::env::temp_dir().join("wifi_tool_test_unique");
        let _ = fs::create_dir_all(&dir);
        let path = dir.join("test_conflict_file.txt");
        let path_str = path.to_string_lossy().to_string();
        fs::write(&path, "test").unwrap();
        let result = unique_filename(&path_str);
        assert_ne!(result, path_str);
        assert_eq!(result, path_str.replace(".txt", "_(2).txt"), "got {}", result);
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(&result);
        let _ = fs::remove_dir(&dir);
    }

    #[test]
    fn test_unique_filename_many_conflicts() {
        let dir = std::env::temp_dir().join("wifi_tool_test_many");
        let _ = fs::create_dir_all(&dir);
        let base = dir.join("a.txt");
        let base_str = base.to_string_lossy().to_string();
        fs::write(&base, "x").unwrap();
        fs::write(format!("{}_(2).txt", base_str.strip_suffix(".txt").unwrap()), "x").unwrap();
        let result = unique_filename(&base_str);
        assert!(result.ends_with("_(3).txt"), "got {}", result);
        let _ = fs::remove_dir_all(&dir);
    }

    // --- password_strength ---

    #[test]
    fn test_strength_common_password() {
        let score = password_strength("123456", "MyWiFi");
        assert!(score <= 1, "common password should be very weak, got {}", score);
    }

    #[test]
    fn test_strength_strong() {
        let score = password_strength("Xc7#mK9$pL2v", "MyWiFi");
        assert!(score >= 3, "strong password should score >= 3, got {}", score);
    }

    #[test]
    fn test_strength_sequential() {
        let score = password_strength("1234abcd", "TestSSID");
        assert!(score <= 2, "sequential password should be penalized, got {}", score);
    }

    #[test]
    fn test_strength_repeated() {
        let score = password_strength("aaaBBBccc", "TestSSID");
        assert!(score <= 3, "repeated password should be penalized, got {}", score);
    }

    #[test]
    fn test_strength_ssid_substring() {
        let score = password_strength("MyWiFi123456", "MyWiFi");
        assert!(score <= 2, "SSID substring should be penalized, got {}", score);
    }

    // --- is_sequential ---

    #[test]
    fn test_sequential_ascending() {
        assert!(is_sequential("1234abcd"));
        assert!(is_sequential("abcdef"));
    }

    #[test]
    fn test_sequential_descending() {
        assert!(is_sequential("dcba4321"));
    }

    #[test]
    fn test_not_sequential() {
        assert!(!is_sequential("a1b2c3"));
        assert!(!is_sequential("xyz"));
    }

    // --- is_repeated ---

    #[test]
    fn test_repeated_yes() {
        assert!(is_repeated("aaabbb"));
        assert!(is_repeated("111password"));
    }

    #[test]
    fn test_not_repeated() {
        assert!(!is_repeated("abc"));
        assert!(!is_repeated("abab"));
    }

    // --- sanitize_filename ---

    #[test]
    fn test_sanitize_basic() {
        assert_eq!(sanitize_filename("Hello World"), "Hello_World");
        assert_eq!(sanitize_filename("file:name?.txt"), "file_name_.txt");
    }

    #[test]
    fn test_sanitize_clean() {
        assert_eq!(sanitize_filename("CleanName"), "CleanName");
    }

    // --- parse_profile_line ---

    #[test]
    fn test_parse_profile_english() {
        let line = "    All User Profile     : MyHomeWiFi";
        assert_eq!(parse_profile_line(line), Some("MyHomeWiFi".to_string()));
    }

    #[test]
    fn test_parse_profile_chinese() {
        let line = "    \u{6240}\u{6709}\u{7528}\u{6237}\u{914d}\u{7f6e}\u{6587}\u{4ef6}     : \u{6211}\u{7684}WiFi";
        assert_eq!(
            parse_profile_line(line),
            Some("\u{6211}\u{7684}WiFi".to_string())
        );
    }

    #[test]
    fn test_parse_profile_none() {
        assert_eq!(parse_profile_line("    Interface name       : Wi-Fi"), None);
        assert_eq!(parse_profile_line("    There is no profile."), None);
    }

    // --- fuzzy_search ---

    #[test]
    fn test_fuzzy_single_token() {
        let profiles = vec![
            "HomeWiFi".to_string(),
            "OfficeNet".to_string(),
            "CafeWiFi".to_string(),
        ];
        let results = fuzzy_search(&profiles, "wifi");
        assert_eq!(results.len(), 2);
        assert_eq!(results[0].1, "HomeWiFi");
        assert_eq!(results[1].1, "CafeWiFi");
    }

    #[test]
    fn test_fuzzy_multi_token() {
        let profiles = vec![
            "HomeWiFi-5G".to_string(),
            "HomeWiFi-2G".to_string(),
            "OfficeWiFi-5G".to_string(),
        ];
        let results = fuzzy_search(&profiles, "home 5g");
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].1, "HomeWiFi-5G");
    }

    #[test]
    fn test_fuzzy_no_match() {
        let profiles = vec!["ABC".to_string()];
        let results = fuzzy_search(&profiles, "xyz");
        assert!(results.is_empty());
    }

    // --- parse_export_selection ---

    #[test]
    fn test_parse_export_selection_all() {
        // "0" and empty input both mean "all"
        assert_eq!(parse_export_selection("0", 5), vec![0, 1, 2, 3, 4]);
        assert_eq!(parse_export_selection("", 5), vec![0, 1, 2, 3, 4]);
        assert_eq!(parse_export_selection("  0  ", 3), vec![0, 1, 2]);
        assert_eq!(parse_export_selection("0", 0), Vec::<usize>::new());
    }

    #[test]
    fn test_parse_export_selection_serials() {
        // 1-based serial numbers map to 0-based indices
        assert_eq!(parse_export_selection("1", 5), vec![0]);
        assert_eq!(parse_export_selection("1,3,5", 5), vec![0, 2, 4]);
        assert_eq!(parse_export_selection(" 2, 4 ", 5), vec![1, 3]);
    }

    #[test]
    fn test_parse_export_selection_invalid_tokens() {
        // Out-of-range and non-numeric tokens are ignored
        assert_eq!(parse_export_selection("0,2", 5), vec![1]); // 0 inside a list is ignored
        assert_eq!(parse_export_selection("6", 5), Vec::<usize>::new());
        assert_eq!(parse_export_selection("a,b", 5), Vec::<usize>::new());
        assert_eq!(parse_export_selection("1,1,3", 5), vec![0, 2]); // duplicates removed
    }

    // --- lang_from_arg / is_valid_lang ---

    #[test]
    fn test_lang_from_arg_supported() {
        assert_eq!(lang_from_arg("zh").unwrap(), "zh");
        assert_eq!(lang_from_arg("EN").unwrap(), "en"); // case-insensitive
        assert_eq!(lang_from_arg(" ja ").unwrap(), "ja"); // trimmed
    }

    #[test]
    fn test_lang_from_arg_unsupported() {
        assert!(lang_from_arg("xx").is_none());
        assert!(lang_from_arg("").is_none());
        assert!(lang_from_arg("-v").is_none());
    }

    #[test]
    fn test_is_valid_lang_covers_all_supported() {
        for code in ["zh", "en", "ja", "ko", "de", "fr", "ru", "es", "it",
                     "pt", "pl", "nl", "tr", "ar", "he", "cs", "hu",
                     "sv", "fi", "da", "no"] {
            assert!(is_valid_lang(code), "{} should be valid", code);
        }
        assert!(!is_valid_lang("zz"));
    }

    // --- UI strings ---

    #[test]
    fn test_strings_zh_and_en_have_same_keys() {
        let zh = load_strings("zh");
        let en = load_strings("en");
        assert_eq!(zh.len(), en.len());
        for key in zh.keys() {
            assert!(en.contains_key(key), "missing EN key: {}", key);
        }
        // Language-specific content actually differs
        assert_ne!(zh["title"], en["title"]);
    }

    #[test]
    fn test_strength_label_bilingual() {
        assert_eq!(strength_label("en", 5), "Very strong");
        assert_eq!(strength_label("en", 0), "Very weak");
        assert_eq!(strength_label("zh", 5), "\u{6781}\u{5f3a}");
        assert_eq!(strength_label("zh", 3), "\u{4e00}\u{822c}");
    }

    // --- timestamps ---

    #[test]
    fn test_timestamp_formats() {
        let disp = timestamp_display();
        // "YYYY/MM/DD  HH:MM:SS" = 20 chars
        assert_eq!(disp.len(), 20, "got {}", disp);
        let bytes: Vec<char> = disp.chars().collect();
        assert_eq!(bytes[4], '/');
        assert_eq!(bytes[7], '/');
        assert_eq!(&bytes[10..12], [' ', ' ']);
        assert_eq!(bytes[14], ':');
        assert_eq!(bytes[17], ':');
        assert!(bytes.iter().all(|c| c.is_ascii_digit() || *c == '/' || *c == ':' || *c == ' '));

        let file = timestamp_filename();
        // "YYYY-MM-DD_HH-MM-SS" = 19 chars
        assert_eq!(file.len(), 19, "got {}", file);
        let fb: Vec<char> = file.chars().collect();
        assert_eq!(fb[4], '-');
        assert_eq!(fb[7], '-');
        assert_eq!(fb[10], '_');
        assert_eq!(fb[13], '-');
        assert_eq!(fb[16], '-');
    }

    #[test]
    fn test_now_parts_is_local_time() {
        // The tool is used in CN (UTC+8); the displayed hour must track
        // local wall clock rather than UTC.
        let (_y, _mo, _d, h, _mi, _s) = now_parts();
        let utc_h = (SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs()
            / 3600)
            % 24;
        let offset_h = winapi::local_offset_seconds() / 3600;
        let expected = (utc_h as i64 + offset_h).rem_euclid(24) as u32;
        assert_eq!(h, expected, "hour should be local (offset {}h)", offset_h);
        assert!(winapi::local_offset_seconds() != 0 || cfg!(not(windows)));
    }

    // --- strength bar ---

    #[test]
    fn test_build_strength_bar() {
        let bar = build_strength_bar(3);
        assert!(bar.starts_with('['));
        assert!(bar.ends_with("3/5"));
        assert_eq!(bar.matches('\u{2588}').count(), 3); // filled
        assert_eq!(bar.matches('\u{2591}').count(), 2); // empty
    }

    // --- CSV field quoting ---

    #[test]
    fn test_csv_field_plain() {
        assert_eq!(csv_field("HomeWiFi"), "HomeWiFi");
    }

    #[test]
    fn test_csv_field_needs_quoting() {
        assert_eq!(csv_field("a,b"), "\"a,b\"");
        assert_eq!(csv_field("say \"hi\""), "\"say \"\"hi\"\"\"");
        assert_eq!(csv_field("line\nbreak"), "\"line\nbreak\"");
    }

    // --- export content ---

    fn sample_profiles() -> Vec<String> {
        vec![
            "HomeWiFi".to_string(),
            "Office, 5G".to_string(),
            "Cafe".to_string(),
        ]
    }

    #[test]
    fn test_export_txt_has_no_ansi_and_lists_all() {
        let profiles = sample_profiles();
        let selected = vec![0, 1, 2];
        let strings = load_strings("en");
        let pwds = vec![
            Some("pw1".to_string()),
            Some("pw2".to_string()),
            None,
        ];
        let body = build_export_content(&profiles, &selected, "txt", &strings, &pwds);
        assert!(!body.contains('\u{1b}'), "export must not contain ANSI escapes");
        assert!(body.starts_with('\u{FEFF}'), "must start with UTF-8 BOM");
        assert!(body.contains("HomeWiFi"));
        assert!(body.contains("Office, 5G"));
        assert!(body.contains("Total WiFi Count: 3"));
    }

    #[test]
    fn test_export_csv_quotes_and_counts() {
        let profiles = sample_profiles();
        let selected = vec![0, 1];
        let strings = load_strings("en");
        let pwds = vec![Some("pw1".to_string()), Some("p,w2".to_string())];
        let body = build_export_content(&profiles, &selected, "csv", &strings, &pwds);
        assert!(body.contains("Index,SSID,Password"));
        assert!(body.contains("1,HomeWiFi,pw1"));
        assert!(body.contains("2,\"Office, 5G\",\"p,w2\""), "got:\n{}", body);
        assert!(!body.contains('\u{1b}'));
    }

    #[test]
    fn test_export_skips_out_of_range_index() {
        let profiles = sample_profiles();
        let selected = vec![0, 99];
        let strings = load_strings("en");
        let pwds = vec![Some("pw1".to_string()), None];
        let body = build_export_content(&profiles, &selected, "txt", &strings, &pwds);
        assert!(body.contains("HomeWiFi"));
        assert!(!body.contains("  2.  "), "out-of-range row must be skipped:\n{}", body);
    }

    // --- QR code ---

    #[test]
    fn test_qr_svg_generated() {
        let svg = generate_qr_svg("HomeWiFi", "pass1234").expect("QR must render");
        assert!(svg.starts_with("<?xml"));
        assert!(svg.trim_end().ends_with("</svg>"));
        assert!(svg.contains("<rect"), "must contain QR modules");
        assert!(svg.contains("HomeWiFi"), "must carry the SSID label");
        // WPA payload is not stored verbatim, but the module grid must be square
        let w: usize = svg
            .split("width=\"")
            .nth(1)
            .unwrap()
            .split('"')
            .next()
            .unwrap()
            .parse()
            .unwrap();
        assert_eq!(w % 8, 0, "width must be a multiple of the 8px module size");
    }

    #[test]
    fn test_qr_svg_escapes_xml_special_chars() {
        let svg = generate_qr_svg("A&B<C>", "p").expect("QR must render");
        assert!(svg.contains("A&amp;B&lt;C&gt;"), "xml must be escaped:\n{}", svg);
        assert!(!svg.contains("A&B"), "raw & must not appear in the label");
    }

    // --- WiFi QR payload escaping ---

    #[test]
    fn test_wifi_payload_escaping() {
        assert_eq!(wifi_payload("MySSID", "pass"), "WIFI:T:WPA;S:MySSID;P:pass;;");
        // ; , : \ are the WIFI: URI reserved characters
        assert_eq!(
            wifi_payload("a;b", "c:d"),
            "WIFI:T:WPA;S:a\\;b;P:c\\:d;;"
        );
        assert_eq!(wifi_payload("a,b", "e\\f"), "WIFI:T:WPA;S:a\\,b;P:e\\\\f;;");
    }

    // --- end-to-end netsh output parsing (captured samples) ---

    const NETSH_PROFILES_EN: &str = "\r\n\
Profiles on interface Wi-Fi:\r\n\
\r\n\
Group policy profiles (read only)\r\n\
---------------------------------\r\n\
    <None>\r\n\
\r\n\
User profiles\r\n\
-------------\r\n\
    All User Profile     : HomeWiFi-5G\r\n\
    All User Profile     : OfficeNet\r\n\
    All User Profile     : HomeWiFi-5G\r\n\
\r\n";

    const NETSH_PROFILES_ZH: &str = "\r\n\
接口 Wi-Fi 上的配置文件:\r\n\
\r\n\
组策略配置文件(只读)\r\n\
---------------------------------\r\n\
    <无>\r\n\
\r\n\
用户配置文件\r\n\
-------------\r\n\
    所有用户配置文件     : 我的WiFi\r\n\
    所有用户配置文件     : 办公室网络\r\n\
\r\n";

    const NETSH_KEY_EN: &str = "\r\n\
Profile HomeWiFi-5G on interface Wi-Fi:\r\n\
=======================================================================\r\n\
Applied: All User Profile\r\n\
Profile version                : 1\r\n\
Type                           : Wireless LAN\r\n\
Access type                    : Secure\r\n\
Authentication                 : WPA2-Personal\r\n\
Security settings\r\n\
-----------------\r\n\
    Key Content                : S3cret-Pass!\r\n\
\r\n";

    const NETSH_KEY_ZH: &str = "\r\n\
配置文件 HomeWiFi-5G 在接口 Wi-Fi 上:\r\n\
=======================================================================\r\n\
已应用: 所有用户配置文件\r\n\
安全设置\r\n\
-----------------\r\n\
    关键内容            : mima1234\r\n\
\r\n";

    #[test]
    fn test_parse_profiles_english() {
        let p = parse_profiles(NETSH_PROFILES_EN);
        assert_eq!(p, vec!["HomeWiFi-5G".to_string(), "OfficeNet".to_string()]);
    }

    #[test]
    fn test_parse_profiles_chinese() {
        let p = parse_profiles(NETSH_PROFILES_ZH);
        assert_eq!(
            p,
            vec![
                "\u{6211}\u{7684}WiFi".to_string(),
                "\u{529e}\u{516c}\u{5ba4}\u{7f51}\u{7edc}".to_string()
            ]
        );
    }

    #[test]
    fn test_parse_profiles_empty_output() {
        assert!(parse_profiles("").is_empty());
        assert!(parse_profiles("There is no such wireless interface.\r\n").is_empty());
    }

    #[test]
    fn test_parse_password_english() {
        assert_eq!(parse_password(NETSH_KEY_EN), Some("S3cret-Pass!".to_string()));
    }

    #[test]
    fn test_parse_password_chinese() {
        assert_eq!(parse_password(NETSH_KEY_ZH), Some("mima1234".to_string()));
    }

    #[test]
    fn test_parse_password_open_network() {
        // An open network has no "Key Content" line at all.
        let out = "\r\nSecurity settings\r\n-----------------\r\n    Authentication : Open\r\n";
        assert_eq!(parse_password(out), None);
    }

    // --- escape_xml ---

    #[test]
    fn test_escape_xml_all_specials() {
        assert_eq!(
            escape_xml("<a>&\"'\""),
            "&lt;a&gt;&amp;&quot;&apos;&quot;"
        );
        assert_eq!(escape_xml("plain"), "plain");
    }
}
