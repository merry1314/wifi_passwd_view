# WiFi Password Query Tool User Manual

## Tool Introduction

The WiFi Password Query Tool is a Windows batch-based utility that helps users quickly view saved WiFi network passwords. The tool supports both Chinese and English interfaces, with simple operation and reliable security.

## Features

- ✅ Display all saved WiFi configurations
- ✅ Query passwords for specified WiFi networks
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
- All saved WiFi configurations in the current system
- Input prompt: `Enter WiFi name to query password (enter q to exit): `

### Step 2: Enter WiFi Name
- Find the WiFi network name you want to query from the list
- Enter the complete WiFi name (case-sensitive)
- Enter `q` to exit the program
- Pressing Enter directly will prompt "No WiFi name entered"

### Step 3: View Results
The tool will display:
```
============================================
WiFi Name: [Your entered WiFi name]
WiFi Password: [Actual password]
============================================
[Password copied to clipboard]
```

### Step 4: Follow-up Actions
After query completion, you can choose:
- Enter `1` to continue querying other WiFi networks
- Enter `2` to exit the program

## Frequently Asked Questions

### Q1: Why do I need administrator privileges?
A: WiFi password information is stored in the system's secure area, and only administrator privileges can access this information.

### Q2: What should I do if it says "WiFi profile not found"?
A: Please check:
- Whether the WiFi name is entered correctly (case-sensitive)
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

## Error Messages

| Error Message | Cause | Solution |
|---------------|-------|----------|
| Please run this script as Administrator! | Insufficient privileges | Right-click and select "Run as administrator" |
| Error: No WiFi name entered! | Empty input | Enter a valid WiFi name or enter q to exit |
| Error: WiFi profile "xxx" not found! | Incorrect or non-existent WiFi name | Check if the WiFi name is correct |
| Error: Unable to retrieve password information | Password retrieval failed | The WiFi may not have a saved password |

## Technical Support

If you encounter problems during use:

1. Ensure running as administrator
2. Check if the WiFi name is correct
3. Confirm that the WiFi has been connected before and the password was saved
4. Try using the English version of the script

## Version Information

- Version: v1.0
- Update Date: 2025
- Compatibility: Windows 7/8/10/11
- Language Support: Chinese/English

## Disclaimer

This tool is for personal learning and legal use only. Users should ensure:
- Only query passwords for WiFi networks they own
- Not use for illegally obtaining others' network passwords
- Comply with local laws and regulations

---

**Note: Please keep your WiFi passwords safe and do not use this tool in insecure environments.**
