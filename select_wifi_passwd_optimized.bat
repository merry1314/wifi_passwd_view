@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul
title WiFi Password Query Tool
color 0A

REM Check admin privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Please run this script as Administrator!
    echo Press any key to exit...
    pause >nul
    exit /b 1
)

cls

:main
REM Clear previous WiFi array variables to avoid pollution
for /f "tokens=1 delims==" %%v in ('set wifi_name_ 2^>nul') do set "%%v="

echo.
echo ============================================
echo            WiFi Password Query Tool
echo ============================================

REM Parse and display WiFi profile list with index numbers
set "wifi_count=0"
for /f "tokens=1,2 delims=:" %%a in ('netsh wlan show profiles 2^>nul') do (
    set "header=%%a"
    set "header=!header: =!"
    if "!header!"=="AllUserProfile" (
        set /a wifi_count+=1
        set "name=%%b"
        set "name=!name:~1!"
        set "wifi_name_!wifi_count!=!name!"
    )
    if "!header!"=="CurrentUserProfile" (
        set /a wifi_count+=1
        set "name=%%b"
        set "name=!name:~1!"
        set "wifi_name_!wifi_count!=!name!"
    )
    if "!header!"=="所有用户配置文件" (
        set /a wifi_count+=1
        set "name=%%b"
        set "name=!name:~1!"
        set "wifi_name_!wifi_count!=!name!"
    )
    if "!header!"=="当前用户配置" (
        set /a wifi_count+=1
        set "name=%%b"
        set "name=!name:~1!"
        set "wifi_name_!wifi_count!=!name!"
    )
)

echo.
echo Profiles on interface WLAN:
echo.
echo Group policy profiles (read only)
echo ---------------------------------
echo     ^<None^>
echo.
echo User profiles
echo -------------
if !wifi_count! equ 0 (
    echo     ^<None^>
) else (
    for /l %%i in (1,1,!wifi_count!) do (
        set "idx=%%i"
        if !idx! lss 10 (
            echo     !idx!. All User Profile     : !wifi_name_%%i!
        ) else if !idx! lss 100 (
            echo    !idx!. All User Profile     : !wifi_name_%%i!
        ) else (
            echo   !idx!. All User Profile     : !wifi_name_%%i!
        )
    )
)

echo.
echo.
set "input="
set /p "input=Enter index/WiFi name to query (e=export all, q=exit): "

if /i "!input!"=="q" goto exit
if /i "!input!"=="e" goto export_all

set "wifi_name="
REM Check if input is a numeric index
set "is_number=0"
for /f "delims=0123456789" %%d in ("!input!") do set "is_number=1"
if "!is_number!"=="0" if not "!input!"=="" (
    if !input! geq 1 if !input! leq !wifi_count! (
        for /l %%i in (!input!,1,!input!) do set "wifi_name=!wifi_name_%%i!"
    )
)

REM If not selected by index, use input directly as WiFi name
if "!wifi_name!"=="" (
    set "wifi_name=!input!"
)

if "!wifi_name!"=="" (
    echo.
    echo Error: No WiFi name entered!
    set "wifi_name="
    set "input="
    timeout /t 3 >nul
    goto main
)
if "!wifi_name!"==" " (
    echo.
    echo Error: No WiFi name entered!
    set "wifi_name="
    set "input="
    timeout /t 3 >nul
    goto main
)

REM Check if WiFi profile exists
netsh wlan show profile name="%wifi_name%" >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo Error: WiFi profile "%wifi_name%" not found!
    set "wifi_name="
    timeout /t 3 >nul
    goto main
)

echo.
echo ============================================
echo              WiFi Password Query Result
echo ============================================
echo.
echo Searching for password information...
echo.

REM Extract WiFi password - Method 1
set "password="
for /f "tokens=*" %%i in ('netsh wlan show profile name^="%wifi_name%" key^=clear') do (
    set "line=%%i"
    echo !line! | findstr /C:"Key Content" >nul
    if not errorlevel 1 (
        for /f "tokens=2 delims=:" %%j in ("!line!") do (
            set "password=%%j"
            set "password=!password: =!"
            if not "!password!"=="" (
                echo.
                echo ============================================
                echo WiFi Name: %wifi_name%
                echo WiFi Password: !password!
                echo ============================================
                echo !password!| clip 
                echo.
                echo [Password copied to clipboard]
                goto :main_menu
            )
        )
    )
)


REM If still no password found
echo Error: Unable to retrieve password information. This WiFi may not have a saved password.
set "wifi_name="
timeout /t 4 >nul
goto main

:main_menu
echo.
echo ============================================
echo 1. Query another WiFi
echo 2. Export all WiFi passwords to TXT
echo 3. Exit program
echo ============================================
choice /c 123 /m "Please select an option"
if errorlevel 3 goto exit
if errorlevel 2 goto export_all
if errorlevel 1 goto main

:export_all
echo.
echo ============================================
echo     Batch Export WiFi Passwords (TXT)
echo ============================================
if !wifi_count! equ 0 (
    echo.
    echo Error: No WiFi configurations available to export!
    timeout /t 3 >nul
    goto main
)

REM Generate timestamped filename
set "datestamp=%date:~0,4%-%date:~5,2%-%date:~8,2%"
set "timestamp=%time:~0,2%-%time:~3,2%-%time:~6,2%"
set "timestamp=!timestamp: =0!"
set "outfile=%~dp0WiFi_Passwords_Export_!datestamp!_!timestamp!.txt"

echo.
echo Output file: !outfile!
echo Processing !wifi_count! WiFi profiles...
echo.

REM Write file header
echo ============================================================ > "!outfile!"
echo              WiFi Password Batch Export Report              >> "!outfile!"
echo ============================================================ >> "!outfile!"
echo.  >> "!outfile!"
echo Export Time: %date% %time% >> "!outfile!"
echo Tool Version: WiFi Password Query Tool v2.1 >> "!outfile!"
echo Total WiFi Count: !wifi_count! >> "!outfile!"
echo.  >> "!outfile!"
echo ============================================================ >> "!outfile!"
echo No.   WiFi Name                             WiFi Password   >> "!outfile!"
echo ============================================================ >> "!outfile!"

set "exported_ok=0"
set "exported_none=0"
for /l %%n in (1,1,!wifi_count!) do (
    set "cur_name=!wifi_name_%%n!"
    set "cur_pwd="
    for /f "tokens=*" %%k in ('netsh wlan show profile name^="!cur_name!" key^=clear 2^>nul') do (
        set "line=%%k"
        echo !line! | findstr /C:"Key Content" /C:"关键内容" >nul
        if not errorlevel 1 (
            for /f "tokens=2 delims=:" %%p in ("!line!") do (
                set "cur_pwd=%%p"
                set "cur_pwd=!cur_pwd: =!"
            )
        )
    )

    REM Right-align index + left-padded WiFi name
    set "idx_str=%%n"
    if %%n lss 10 set "idx_str= %%n"
    if %%n lss 100 if %%n geq 10 set "idx_str=%%n"

    set "name_pad=!cur_name!                                                    "
    set "name_pad=!name_pad:~0,36!"

    if "!cur_pwd!"=="" (
        set /a exported_none+=1
        echo !idx_str!.  !name_pad! ^<No password or open network^> >> "!outfile!"
        echo [%%n/!wifi_count!] !cur_name!  -^>  ^<No password or open network^>
    ) else (
        set /a exported_ok+=1
        echo !idx_str!.  !name_pad! !cur_pwd! >> "!outfile!"
        echo [%%n/!wifi_count!] !cur_name!  -^>  !cur_pwd!
    )
)

echo. >> "!outfile!"
echo ============================================================ >> "!outfile!"
echo Export Stats: Success !exported_ok! / No Password !exported_none! / Total !wifi_count! >> "!outfile!"
echo ============================================================ >> "!outfile!"

echo.
echo ============================================
echo Export complete!
echo   File location: !outfile!
echo   Success      : !exported_ok!
echo   No password  : !exported_none!
echo ============================================
echo.
pause
goto main

:exit
echo.
echo Exiting WiFi Password Query Tool...
timeout /t 2 >nul
exit /b 0