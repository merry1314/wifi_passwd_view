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
echo.
echo ============================================
echo            WiFi Password Query Tool
echo ============================================
netsh wlan show profiles

echo.
echo.
set "wifi_name="
set /p "wifi_name=Enter WiFi name to query password (enter q to exit): "
if "%wifi_name%"=="" (
    echo.
    echo Error: No WiFi name entered!
    set "wifi_name="
    timeout /t 3 >nul
    goto main
)
if "%wifi_name%"==" " (
    echo.
    echo Error: No WiFi name entered!
    set "wifi_name="
    timeout /t 3 >nul
    goto main
)
if /i "%wifi_name%"=="q" goto exit

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
echo 2. Exit program
echo ============================================
choice /c 12 /m "Please select an option"
if errorlevel 2 goto exit
if errorlevel 1 goto main

:exit
echo.
echo Exiting WiFi Password Query Tool...
timeout /t 2 >nul
exit /b 0