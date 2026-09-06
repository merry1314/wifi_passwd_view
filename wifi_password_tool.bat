@echo off
setlocal enabledelayedexpansion
chcp 936 >nul
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
REM 清除之前的WiFi数组变量，避免重复污染
for /f "tokens=1 delims==" %%v in ('set wifi_name_ 2^>nul') do set "%%v="

echo.
echo ============================================
echo            WiFi密码查询工具
echo ============================================

REM 解析并显示带序号的WiFi配置文件列表
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
echo 接口 WLAN 上的配置文件:
echo.
echo 组策略配置文件(只读)
echo ---------------------------------
echo     ^<无^>
echo.
echo 用户配置文件
echo -------------
if !wifi_count! equ 0 (
    echo     ^<无^>
) else (
    for /l %%i in (1,1,!wifi_count!) do (
        set "idx=%%i"
        if !idx! lss 10 (
            echo     !idx!. 所有用户配置文件 : !wifi_name_%%i!
        ) else if !idx! lss 100 (
            echo    !idx!. 所有用户配置文件 : !wifi_name_%%i!
        ) else (
            echo   !idx!. 所有用户配置文件 : !wifi_name_%%i!
        )
    )
)

echo.
echo.
set "input="
set /p "input=请输入序号或WiFi名称查询密码（e导出所有，q退出程序）："

if /i "!input!"=="q" goto exit
if /i "!input!"=="e" goto export_all

set "wifi_name="
REM 判断是否为数字序号
set "is_number=0"
for /f "delims=0123456789" %%d in ("!input!") do set "is_number=1"
if "!is_number!"=="0" if not "!input!"=="" (
    if !input! geq 1 if !input! leq !wifi_count! (
        for /l %%i in (!input!,1,!input!) do set "wifi_name=!wifi_name_%%i!"
    )
)

REM 如果没有通过序号选择，则直接使用输入作为WiFi名称
if "!wifi_name!"=="" (
    set "wifi_name=!input!"
)

if "!wifi_name!"=="" (
    echo.
    echo 错误：没有输入WiFi名称！
    set "wifi_name="
    set "input="
    timeout /t 3 >nul
    goto main
)
if "!wifi_name!"==" " (
    echo.
    echo 错误：没有输入WiFi名称！
    set "wifi_name="
    set "input="
    timeout /t 3 >nul
    goto main
)

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
    set "is_key="
    if not "!line:Key Content=!"=="!line!" set "is_key=1"
    if not "!line:关键内容=!"=="!line!" set "is_key=1"
    if defined is_key (
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
echo 2. 导出所有WiFi密码到TXT
echo 3. 退出程序
echo ============================================
choice /c 123 /m "请选择操作"
if errorlevel 3 goto exit
if errorlevel 2 goto export_all
if errorlevel 1 goto main

:export_all
echo.
echo ============================================
echo        批量导出WiFi密码（TXT格式）
echo ============================================
if !wifi_count! equ 0 (
    echo.
    echo 错误：当前没有可导出的WiFi配置！
    timeout /t 3 >nul
    goto main
)

REM 生成带日期时间戳的文件名
set "datestamp=%date:~0,4%-%date:~5,2%-%date:~8,2%"
set "timestamp=%time:~0,2%-%time:~3,2%-%time:~6,2%"
set "timestamp=!timestamp: =0!"
set "outfile=%~dp0WiFi密码导出_!datestamp!_!timestamp!.txt"

echo.
echo 导出文件路径 - !outfile!
echo 正在处理 共 !wifi_count! 个WiFi配置...
echo.

REM 写入文件头
echo ============================================================ > "!outfile!"
echo               WiFi密码批量导出报告                          >> "!outfile!"
echo ============================================================ >> "!outfile!"
echo.  >> "!outfile!"
echo 导出时间: %date% %time% >> "!outfile!"
echo 导出工具: WiFi密码查询工具 v2.1 >> "!outfile!"
echo WiFi总数: !wifi_count! >> "!outfile!"
echo.  >> "!outfile!"
echo ============================================================ >> "!outfile!"
echo 序号   WiFi名称                              WiFi密码       >> "!outfile!"
echo ============================================================ >> "!outfile!"

set "exported_ok=0"
set "exported_none=0"
for /l %%n in (1,1,!wifi_count!) do (
    set "cur_name=!wifi_name_%%n!"
    set "cur_pwd="
    for /f "tokens=*" %%k in ('netsh wlan show profile name^="!cur_name!" key^=clear 2^>nul') do (
        set "line=%%k"
        set "is_key="
        if not "!line:Key Content=!"=="!line!" set "is_key=1"
        if not "!line:关键内容=!"=="!line!" set "is_key=1"
        if defined is_key (
            for /f "tokens=2 delims=:" %%p in ("!line!") do (
                set "cur_pwd=%%p"
                set "cur_pwd=!cur_pwd: =!"
            )
        )
    )

    REM 序号右对齐 + WiFi名与密码左对齐填充
    set "idx_str=%%n"
    if %%n lss 10 set "idx_str= %%n"
    if %%n lss 100 if %%n geq 10 set "idx_str=%%n"

    set "name_pad=!cur_name!                                                    "
    set "name_pad=!name_pad:~0,36!"

    if "!cur_pwd!"=="" (
        set /a exported_none+=1
        echo !idx_str!.  !name_pad! ^<无密码或开放网络^> >> "!outfile!"
        echo [%%n/!wifi_count!] !cur_name!  -^>  ^<无密码或开放网络^>
    ) else (
        set /a exported_ok+=1
        echo !idx_str!.  !name_pad! !cur_pwd! >> "!outfile!"
        echo [%%n/!wifi_count!] !cur_name!  -^>  !cur_pwd!
    )
)

echo. >> "!outfile!"
echo ============================================================ >> "!outfile!"
echo 导出统计: 成功 !exported_ok! 个 / 无密码 !exported_none! 个 / 总计 !wifi_count! 个 >> "!outfile!"
echo ============================================================ >> "!outfile!"

echo.
echo ============================================
echo 导出完成！
echo   文件位置 - !outfile!
echo   成功导出 - !exported_ok! 个
echo   无密码   - !exported_none! 个
echo ============================================
echo.
pause
goto main

:exit
echo.
echo 正在退出WiFi密码查询工具...
timeout /t 2 >nul
exit /b 0
