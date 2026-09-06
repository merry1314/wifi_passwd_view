# WiFi Password Query Tool User Manual

## Tool Introduction

The WiFi Password Query Tool is a Windows batch-based utility that helps users quickly view saved WiFi network passwords. The tool supports both Chinese and English interfaces, with simple operation and reliable security.

## Features

- ✅ Display all saved WiFi configurations (with index numbers)
- ✅ Support quick selection by index, no need to manually enter WiFi name
- ✅ Support direct WiFi name input for query
- ✅ Query passwords for specified WiFi networks
- ✅ One-click batch export all WiFi passwords to TXT file
- ✅ Automatically copy passwords to clipboard
- ✅ Support for both Chinese and English Windows systems
- ✅ User-friendly interface with error prompts
- ✅ Secure password display method

## System Requirements

- Windows 7/8/10/11 operating system
- Administrator privileges (required)
- Previously connected WiFi networks with saved passwords

## Installation and Usage

### 1. Download Files

Download the following files to your desktop:
- `wifi_password_tool.bat` (Chinese version)
- `select_wifi_passwd_optimized.bat` (English version)

### 2. Run the Tool

**Important: Must run as Administrator!**

**Method 1: Right-click to run**
1. Right-click on the script file
2. Select "Run as administrator"

**Method 2: Command line run**
1. Press `Win + R` to open Run dialog
2. Type `cmd` and hold `Ctrl + Shift` then press Enter (opens Command Prompt as administrator)
3. Navigate to script directory:
   ```
   cd C:\Users\YourUsername\Desktop
   ```
4. Run the script:
   ```
   select_wifi_passwd_optimized.bat
   ```

## Operation Steps

### Step 1: Launch the Tool
After running the script as administrator, the tool will display:
- All saved WiFi configurations in the current system (with index numbers)
- Input prompt: `Enter index/WiFi name to query (e=export all, q=exit): `

WiFi list display example:
```
User profiles
-------------
    1. All User Profile     : CMCC-NPxe-5G
    2. All User Profile     : HomeinnSelected
    3. All User Profile     : Redmi 8A
    4. All User Profile     : JinJiangRewards
   ...
   18. All User Profile     : TPGuest_3006
```

### Step 2: Select WiFi
There are two ways to select the WiFi to query:

**Method 1: Enter index (Recommended)**
- Find the WiFi you want to query in the list
- Simply enter its corresponding index number, e.g., enter `3` to select the 3rd WiFi

**Method 2: Enter WiFi name**
- Enter the complete WiFi name (case-sensitive)

Other operations:
- Enter `e` to one-click batch export all WiFi passwords to TXT file
- Enter `q` to exit the program
- Pressing Enter directly will prompt "No WiFi name entered"

### Step 3: View Results
The tool will display:
```
============================================
WiFi Name: [Your selected WiFi name]
WiFi Password: [Actual password]
============================================
[Password copied to clipboard]
```

### Step 3B: Batch Export All WiFi Passwords (Optional)
Enter `e` at the main prompt, or select menu option `2` after a query:

```
============================================
    Batch Export WiFi Passwords (TXT)
============================================

Output file: D:\xxx\WiFi_Passwords_Export_2026-09-06_09-45-12.txt
Processing 18 WiFi profiles...

[1/18] CMCC-NPxe-5G  ->  P@ssw0rd123
[2/18] HomeinnSelected  ->  Home@2024
...
============================================
Export complete!
  File location: D:\xxx\WiFi_Passwords_Export_2026-09-06_09-45-12.txt
  Success      : 17
  No password  : 1
============================================
```

**TXT file content example**:
```
============================================================
             WiFi Password Batch Export Report
============================================================

Export Time: 2026/09/06  9:45:12
Tool Version: WiFi Password Query Tool v2.1
Total WiFi Count: 18

============================================================
No.   WiFi Name                             WiFi Password
============================================================
 1.  CMCC-NPxe-5G                          P@ssw0rd123
 2.  HomeinnSelected                        Home@2024
 3.  Redmi 8A                               abc123456
...
============================================================
Export Stats: Success 17 / No Password 1 / Total 18
============================================================
```

### Step 4: Follow-up Actions
After query completion, you can choose:
- Enter `1` to continue querying other WiFi networks
- Enter `2` to export all WiFi passwords to TXT
- Enter `3` to exit the program

## Frequently Asked Questions

### Q1: Why do I need administrator privileges?
A: WiFi password information is stored in the system's secure area, and only administrator privileges can access this information.

### Q2: What should I do if it says "WiFi profile not found"?
A: Please check:
- If using index selection, ensure the index is within the valid range
- If entering WiFi name, verify it is correct (case-sensitive)
- Whether the WiFi has been connected before and the password was saved
- Whether it appears in the WiFi configuration list

### Q3: What should I do if the password shows as empty?
A: Possible reasons:
- The WiFi has no saved password (e.g., open network)
- The password has expired or been cleared by the system
- Network configuration is abnormal

### Q4: Which WiFi encryption methods does the tool support?
A: Supports all encryption methods supported by Windows systems:
- WEP
- WPA-PSK
- WPA2-PSK
- WPA3-PSK

### Q5: Is it safe? Will it leak passwords?
A: The tool is secure:
- Only runs locally, does not upload any information
- Password is displayed on screen only once
- Automatically copied to clipboard for convenience
- Exported TXT files are stored in the script directory, keep them safe

### Q6: Where are exported TXT files saved?
A: Export files are saved in the script directory, filename format:
`WiFi_Passwords_Export_YYYY-MM-DD_HH-MM-SS.txt`
Example: `WiFi_Passwords_Export_2026-09-06_09-45-12.txt`

## Error Messages

| Error Message | Cause | Solution |
|---------------|-------|----------|
| Please run this script as Administrator! | Insufficient privileges | Right-click and select "Run as administrator" |
| Error: No WiFi name entered! | Empty input | Enter a valid index/WiFi name, or q to exit, or e to export |
| Error: WiFi profile "xxx" not found! | Incorrect/non-existent WiFi name or invalid index | Check if the index is in range, or if the WiFi name is correct |
| Error: Unable to retrieve password information | Password retrieval failed | The WiFi may not have a saved password |
| Error: No WiFi configurations available to export! | No WiFi profiles in system | Connect and save at least one WiFi first |

## Technical Support

If you encounter problems during use:

1. Ensure running as administrator
2. Check if the WiFi name is correct
3. Confirm that the WiFi has been connected before and the password was saved
4. Try using the English version of the script

## Version Information

- Version: v2.1
- Update Date: September 2026
- Compatibility: Windows 7/8/10/11
- Language Support: Chinese/English
- Update Content:
  - v2.1: Added batch export of all WiFi passwords to TXT file (timestamp-named, with stats report); added export option to main menu; main prompt supports `e` for one-click export
  - v2.0: Added index numbers to WiFi list, supported quick selection by index; compatible with both Chinese and English system output formats

## Disclaimer

This tool is for personal learning and legal use only. Users should ensure:
- Only query passwords for WiFi networks they own
- Not use for illegally obtaining others' network passwords
- Comply with local laws and regulations

---

**Note: Please keep your WiFi passwords safe and do not use this tool in insecure environments.**
