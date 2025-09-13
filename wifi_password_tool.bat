@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul
title WiFi密码查询工具
color 0A

REM 检查管理员权限
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo 请以管理员身份运行此脚本！
    echo 按任意键退出...
    pause >nul
    exit /b 1
)

cls

:main
echo.
echo ============================================
echo            WiFi密码查询工具
echo ============================================
netsh wlan show profiles

echo.
echo.
set "wifi_name="
set /p "wifi_name=请输入要查询密码的WiFi名称（输入q退出程序）："
if "%wifi_name%"=="" (
    echo.
    echo 错误：没有输入WiFi名称！
    set "wifi_name="
    timeout /t 3 >nul
    goto main
)
if "%wifi_name%"==" " (
    echo.
    echo 错误：没有输入WiFi名称！
    set "wifi_name="
    timeout /t 3 >nul
    goto main
)
if /i "%wifi_name%"=="q" goto exit

REM 检查WiFi配置文件是否存在
netsh wlan show profile name="%wifi_name%" >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo 错误：找不到名为"%wifi_name%"的WiFi配置文件！
    set "wifi_name="
    timeout /t 3 >nul
    goto main
)

echo.
echo ============================================
echo              WiFi密码查询结果
echo ============================================
echo.
echo 正在查找密码信息...
echo.

REM 提取WiFi密码 - 方法1
set "password="
for /f "tokens=*" %%i in ('netsh wlan show profile name^="%wifi_name%" key^=clear') do (
    set "line=%%i"
    echo !line! | findstr /C:"Key Content" /C:"关键内容" >nul
    if not errorlevel 1 (
        for /f "tokens=2 delims=:" %%j in ("!line!") do (
            set "password=%%j"
            set "password=!password: =!"
            if not "!password!"=="" (
                echo.
                echo ============================================
                echo WiFi名称: %wifi_name%
                echo WiFi密码: !password!
                echo ============================================
                echo !password!| clip 
                echo.
                echo [密码已复制到剪贴板]
                goto :main_menu
            )
        )
    )
)


REM 如果仍然无法获取密码
echo 错误：无法获取密码信息，可能是该WiFi没有保存密码。
set "wifi_name="
timeout /t 4 >nul
goto main

:main_menu
echo.
echo ============================================
echo 1. 继续查询其他WiFi
echo 2. 退出程序
echo ============================================
choice /c 12 /m "请选择操作"
if errorlevel 2 goto exit
if errorlevel 1 goto main

:exit
echo.
echo 正在退出WiFi密码查询工具...
timeout /t 2 >nul
exit /b 0
