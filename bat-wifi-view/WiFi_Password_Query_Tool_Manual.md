# WiFi Password Query Tool User Manual

## Tool Introduction

The WiFi Password Query Tool is a Windows batch-based utility that helps users quickly view saved WiFi network passwords. The tool auto-detects system language (Chinese/English UI), dynamically matches netsh output in 21 languages, with simple operation and reliable security. See [Language_Support.md](Language_Support.md) for the full language matrix.

## Features

### Basic Features
- ✅ Display all saved WiFi configurations (with index numbers, compact format)
- ✅ Support quick selection by index, no need to manually enter WiFi name
- ✅ Support direct WiFi name input for query
- ✅ Query passwords for specified WiFi networks
- ✅ Automatically copy passwords to clipboard
- ✅ Auto-detect system language (v3.0), also supports forced language via command line (`zh`/`en`/`ja` etc.)
- ✅ Dynamic multi-language netsh keyword matching (21 languages, see [Language_Support.md](Language_Support.md))
- ✅ Secure local execution, no data uploaded

### Export Features
- ✅ Batch export WiFi passwords: choose scope (all/selected indices) and format (TXT/CSV)
- ✅ Copy WiFi connect string (`WIFI:T:WPA;S:ssid;P:password;;` format, scannable by phone camera)
- ✅ Real-time progress bar during export (`█░` 10 segments + percentage)
- ✅ CSV file includes UTF-8 BOM for Excel compatibility

### UI Enhancements
- ✅ Password show/hide toggle (menu option 4)
- ✅ Query history (up to 10 entries, quick re-query by index)
- ✅ Quick key hint bar (`[e]export [h]history [q]quit`)
- ✅ ANSI color highlighting (title: cyan, WiFi name: yellow, password: bright white, error: red, success: green)
- ✅ Unicode separator lines (`─`) replacing `====` for cleaner look

## System Requirements

- Windows 10/11 (recommended, ANSI colors need VT support)
- Windows 7/8 (basic features work, colors may not show)
- Administrator privileges (required)
- Previously connected WiFi networks with saved passwords

## Installation and Usage

### 1. Download Files

Download the following file to your desktop:
- `wifi_password_tool_auto.bat` (v3.0 unified version, auto-detects language)

### 2. Run the Tool

**Important: Must run as Administrator!**

**Method 1: Right-click**
1. Right-click on `wifi_password_tool_auto.bat`
2. Select "Run as administrator"

**Method 2: Command line**
1. Press `Win + R` to open Run dialog
2. Type `cmd` and press `Ctrl + Shift + Enter` (open as administrator)
3. Navigate to the script directory:
   ```
   cd C:\Users\YourUsername\Desktop
   ```
4. Run the script:
   ```
   wifi_password_tool_auto.bat
   ```
   Or force a specific language:
   ```
   wifi_password_tool_auto.bat en
   wifi_password_tool_auto.bat zh
   ```

## Operation Steps

### Step 1: Launch the Tool
After running as administrator, the tool displays:
- All saved WiFi configurations (with index numbers, compact format)
- Quick key hint bar: `[e]export  [h]history  [q]quit  [/keyword]fuzzy  [index/name]query`
- Input prompt: `Enter index/WiFi name to query (e=export, q=exit, /keyword fuzzy search):`

WiFi list display example:
```
  [User profiles]
  ---------------------------------
    01. CMCC-NPxe-5G
    02. HomeinnSelected
    03. Redmi 8A
    04. JinJiangRewards
   ...
    18. TPGuest_3006
```

### Step 2: Select WiFi
Four ways to select:

**Method 1: Enter index (Recommended)**
- Enter the corresponding index number, e.g., `3` for the 3rd WiFi

**Method 2: Enter WiFi name**
- Enter the full WiFi name (case-sensitive)

**Method 3: Fuzzy search (`/keyword`)**
- Long WiFi list? Use `/` to trigger fuzzy search:
  - `/home` → list all WiFis containing `home` (e.g., HomeWiFi-5G, home_office)
  - `/xana 5g` → multi-token AND, list WiFis containing both `xana` and `5g`
  - Case-insensitive, substring match; pick a number to select, Enter to cancel

**Method 4: Quick keys**
- `e` = Batch export WiFi passwords
- `h` = View query history
- `q` = Quit program

### Step 3: View Result
The tool displays:
```
────────────────────────────────────────────
  WiFi Name: [selected WiFi name] (yellow)
  WiFi Password: [actual password] (bright white)
  Password strength: Strong [█████]  ← NEW: scored on length/classes/blacklist
────────────────────────────────────────────

  [OK] [Password copied to clipboard]
```

**Password strength scoring rules** (0–5 points):
- Length ≥12: +2 points; ≥8: +1 point; <8: −1 point
- Character classes (uppercase / lowercase / digits / special) — 3+ classes = +2; exactly 2 = +1
- Blacklisted passwords (e.g. `12345678`, `password`, `qwerty`, 29 entries) −4 points
- Password contains the WiFi SSID as substring: −2 points
- Contains 4 sequential characters (e.g. `1234`, `abcd`) −2 points
- Contains 3+ repeated characters (e.g. `aaa`) −1 point
- 0–1 pts = Weak (red); 2–3 pts = Medium (yellow); 4–5 pts = Strong (green)
- The strength bar is hidden when the password is hidden (can't score what you can't see)

### Step 4: Main Menu
After query, the main menu offers 6 options:
```
  1) Query another WiFi
  2) Export current WiFi password
  3) Copy WiFi connect string (phone scan)
  4) Show/Hide password (R)
  5) View query history (H)
  6) Exit program
```

- Option 4 toggles password display (hidden shows `********`)
- Option 5 shows recent 10 query records, enter index to quick re-query

### Step 5: Batch Export (Optional)
Enter `e` at the main interface to start batch export:

1. **Select export scope**:
   - `1` Export all WiFi profiles
   - `2` Export selected WiFi profiles by index (comma separated, e.g., `1,3,5`)
   - `0` Cancel

2. **Select export format**:
   - `1` Export as TXT text file
   - `2` Export as CSV file (with UTF-8 BOM, Excel compatible)
   - `0` Cancel

3. **Export process**: Real-time progress bar
   ```
   [██████░░░░] 60% HomeinnSelected  ->  Home@2024
   ```

4. **Export complete**: Shows file location and statistics

**TXT file content example**:
```
────────────────────────────────────────────
               WiFi Password Batch Export Report
────────────────────────────────────────────

Export Time: 2026/09/17  10:30:00
Tool Version: WiFi Password Query Tool v3.0
Total WiFi Count: 18

────────────────────────────────────────────
No.   WiFi Name                             WiFi Password
────────────────────────────────────────────
 1.  CMCC-NPxe-5G                          P@ssw0rd123
 2.  HomeinnSelected                        Home@2024
 ...
────────────────────────────────────────────
Export Stats: Success 17 / No Password 1 / Total 18
────────────────────────────────────────────
```

**CSV file content example**:
```
No.,WiFi Name,WiFi Password
1,CMCC-NPxe-5G,P@ssw0rd123
2,HomeinnSelected,Home@2024
...
```

## FAQ

### Q1: Why are administrator privileges required?
A: WiFi password information is stored in a secure system area that requires administrator access.

### Q2: What if it shows "[ERROR] WiFi profile not found!"?
A: Please check:
- If using index, ensure it's within valid range
- If entering WiFi name, verify correctness (case-sensitive)
- Whether the WiFi was previously connected and saved

### Q3: What if the password is empty?
A: Possible reasons:
- The WiFi has no saved password (e.g., open network)
- Password has expired or was cleared by system
- Network configuration issue

### Q4: What if ANSI colors don't show or characters are garbled?
A:
- Ensure you're using Windows 10+ terminal
- Ensure terminal supports VT (Virtual Terminal) processing
- Ensure terminal uses UTF-8 encoding (script auto-runs `chcp 65001`)

### Q5: Where are exported files saved?
A: Export files are saved in the script's directory:
- TXT: `WiFi_Passwords_Export_YYYY-MM-DD_HH-MM-SS.txt`
- CSV: `WiFi_Passwords_Export_YYYY-MM-DD_HH-MM-SS.csv`

### Q6: How to use on non-English/non-Chinese systems?
A: The script auto-detects system language. You can also force it: `wifi_password_tool_auto.bat en` (English), `wifi_password_tool_auto.bat zh` (Chinese), etc.

## Error Messages

| Error Message | Cause | Solution |
|---------------|-------|----------|
| [ERROR] Please run this script as Administrator! | Insufficient privileges | Right-click and select "Run as administrator" |
| [ERROR] No WiFi name entered! | Empty input | Enter valid index/WiFi name, or q to quit, or e to export |
| [ERROR] WiFi profile not found! | Invalid name/index | Check if index is in range, or WiFi name is correct |
| [ERROR] Unable to retrieve password information | Password retrieval failed | WiFi may not have a saved password |
| [ERROR] No WiFi configurations available to export! | No WiFi configs in system | Connect and save at least one WiFi |
| [ERROR] No valid index selected! | Invalid export index | Enter valid indices (comma separated, e.g., 1,3,5) |

## Technical Support

If you encounter issues:

1. Ensure running as administrator
2. Check WiFi name correctness
3. Confirm the WiFi was previously connected with saved password
4. Try forcing a language: `wifi_password_tool_auto.bat en`

## Version Information

- Version: v3.1
- Updated: September 2026
- Compatibility: Windows 7/8/10/11 (Windows 10+ recommended)
- Language Support: Chinese/English UI, 21-language netsh parsing (see [Language_Support.md](Language_Support.md))
- License: MIT License
- Changelog:
  - v3.1: Fuzzy search (`/keyword`, multi-token AND, case-insensitive); password strength scoring (0–5, blacklist/sequential/repeat detection) shown only when password is visible
  - v3.0: Unified multi-language auto-detect version; dynamic 21-language netsh keyword matching; CSV export + WiFi connect string copy; export scope/format selection; UI optimization A+B+C (password toggle, progress bar, quick keys, history, ANSI colors, Unicode separators)
  - v2.1: Added batch export to TXT; added export option in main menu
  - v2.0: Added index display in WiFi list; compatible with Chinese/English system output formats

## Disclaimer

This tool is for personal learning and legal use only. Users must ensure:
- Only query passwords for WiFi networks they own
- Do not use for illegally obtaining others' network passwords
- Comply with local laws and regulations

---

**Note: Please keep your WiFi passwords safe and do not use this tool in unsafe environments.**
