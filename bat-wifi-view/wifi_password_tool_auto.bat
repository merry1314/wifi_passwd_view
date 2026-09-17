@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

REM --- Define ESC character for ANSI color codes ---
for /f %%a in ('"prompt $E$S & echo on & for %%b in (1) do rem"') do set "ESC=%%a"

REM --- ANSI color codes ---
set "c_reset=!ESC![0m"
set "c_bold=!ESC![1m"
set "c_title=!ESC![36m"
set "c_ok=!ESC![32m"
set "c_warn=!ESC![33m"
set "c_error=!ESC![31m"
set "c_name=!ESC![33m"
set "c_pwd=!ESC![97m"
set "c_hint=!ESC![90m"
set "c_bar_fill=!ESC![32m"
set "c_bar_empty=!ESC![90m"

REM --- Unicode separator line (44 chars, light horizontal) ---
set "str_sep=────────────────────────────────────────────"

REM ============================================================
REM  WiFi Password Query Tool v3.1 - Auto Language Detection
REM  Auto-detect system language, dynamic netsh keyword matching
REM  Supports Chinese/English UI, multi-language netsh parsing
REM
REM  Usage:
REM    wifi_password_tool_auto.bat        Auto-detect language
REM    wifi_password_tool_auto.bat zh     Force Chinese UI
REM    wifi_password_tool_auto.bat en     Force English UI
REM
REM  Requires Windows 10+ (chcp 65001 UTF-8 support)
REM  NOTE: All REM comments are in English to avoid cmd.exe
REM        parsing issues with UTF-8 Chinese in comments.
REM ============================================================

REM --- Step 1: Detect system language ---
call :detect_language %1

REM --- Step 2: Load language strings ---
call :load_strings

title !str_title!
color 0F

REM --- Step 3: Check admin privileges ---
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo !str_err_admin!
    echo !str_press_exit!
    pause >nul
    exit /b 1
)

cls

REM Initialize query history
set "hist_count=0"

:main
REM Clear previous WiFi array variables to avoid pollution
for /f "tokens=1 delims==" %%v in ('set wifi_name_ 2^>nul') do set "%%v="

echo.
echo !str_sep!
echo           !c_title!!str_title!!c_reset!
echo           !c_hint!!str_lang_info!!c_reset!
echo !str_sep!

REM --- Parse WiFi profiles using dynamic matching ---
REM Strategy: extract text after last ":" as WiFi name
REM Supports two netsh output formats:
REM   Format A: "    Type : Name"        (no index)
REM   Format B: "    Index : Type : Name" (with index)
REM Also exact-match known type keywords for correctness
set "wifi_count=0"
for /f "usebackq tokens=1,* delims=:" %%a in (`netsh wlan show profiles 2^>nul`) do (
    set "prof_part1=%%a"
    set "prof_part2=%%b"
    if not "!prof_part2!"=="" (
        call :parse_profile_line "!prof_part1!" "!prof_part2!"
    )
)

REM --- Display WiFi list (compact format) ---
echo.
echo   !str_profiles_on_interface!
echo.
echo   [!str_group_policy!]
echo   ---------------------------------
echo     ^<!str_none!^>
echo.
echo   [!str_user_profiles!]
echo   ---------------------------------
if !wifi_count! equ 0 (
    echo     ^<!str_none!^>
) else (
    for /l %%i in (1,1,!wifi_count!) do (
        set "idx_str=%%i"
        if %%i lss 10 set "idx_str=0%%i"
        echo     !idx_str!. !c_name!!wifi_name_%%i!!c_reset!
    )
)

echo.
echo   !c_hint!!str_hint_bar!!c_reset!
echo.
set "input="
set /p "input=!str_input_prompt!"

if /i "!input!"=="q" goto exit
if /i "!input!"=="e" goto export_all
if /i "!input!"=="h" goto show_history

REM --- Fuzzy search: /keyword (case-insensitive substring, multi-token AND) ---
set "input_first=!input:~0,1!"
if "!input_first!"=="/" (
    if not "!input!"=="/" (
        call :do_fuzzy_search
        REM On match+select: wifi_name is set, jump to do_query.
        if not "!wifi_name!"=="" goto do_query
        REM No match or cancelled: loop back to main.
        goto main
    )
)

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
    echo !str_err_no_input!
    set "wifi_name="
    set "input="
    timeout /t 3 >nul
    goto main
)
if "!wifi_name!"==" " (
    echo.
    echo !str_err_no_input!
    set "wifi_name="
    set "input="
    timeout /t 3 >nul
    goto main
)

REM Check if WiFi profile exists
:do_query
netsh wlan show profile name="!wifi_name!" >nul 2>&1
set "netsh_err=!errorlevel!"
if !netsh_err! neq 0 (
    echo.
    echo !str_err_not_found!
    set "wifi_name="
    timeout /t 3 >nul
    goto main
)

echo.
echo !str_sep!
echo              !c_title!!str_query_result!!c_reset!
echo !str_sep!
echo.
echo   !c_hint!^>^> !str_searching!!c_reset!
echo.

REM --- Extract password using dynamic keyword matching ---
REM Multi-language keyword match + generic fallback (key + content)
set "password="
for /f "usebackq tokens=*" %%i in (`netsh wlan show profile name^="!wifi_name!" key^=clear 2^>nul`) do (
    set "line=%%i"
    set "is_key="
    if not "!line:Key Content=!"=="!line!" set "is_key=1"
    if not "!line:关键内容=!"=="!line!" set "is_key=1"
    if not "!line:キー コンテンツ=!"=="!line!" set "is_key=1"
    if not "!line:キーコンテンツ=!"=="!line!" set "is_key=1"
    if not "!line:Schlüsselinhalt=!"=="!line!" set "is_key=1"
    if not "!line:Contenu de la clé=!"=="!line!" set "is_key=1"
    if not "!line:Contenido de la clave=!"=="!line!" set "is_key=1"
    if not "!line:Содержимое ключа=!"=="!line!" set "is_key=1"
    if not "!line:Conteúdo da chave=!"=="!line!" set "is_key=1"
    if not "!line:Contenuto della chiave=!"=="!line!" set "is_key=1"
    if not "!line:Zawartosc klucza=!"=="!line!" set "is_key=1"
    if not "!line:Sleutelinhoud=!"=="!line!" set "is_key=1"
    if not "!line:키 콘텐츠=!"=="!line!" set "is_key=1"
    if not "!line:Anahtar Içerigi=!"=="!line!" set "is_key=1"
    if not "!line:Kulcstartalom=!"=="!line!" set "is_key=1"
    if not "!line:Nyckelinnehall=!"=="!line!" set "is_key=1"
    if not "!line:Avaimen sisalto=!"=="!line!" set "is_key=1"
    if not "!line:Nøgleindhold=!"=="!line!" set "is_key=1"
    if not defined is_key (
        echo "!line!"| findstr /i /c:"key" >nul && echo "!line!"| findstr /i /c:"content" >nul && set "is_key=1"
    )
    if defined is_key (
        for /f "tokens=1,* delims=:" %%j in ("!line!") do (
            set "password=%%k"
            for /f "tokens=* delims= " %%p in ("!password!") do set "password=%%p"
            if not "!password!"=="" (
                set "last_wifi_name=!wifi_name!"
                set "last_wifi_password=!password!"
                set "show_password=1"
                call :add_history "!wifi_name!" "!password!"
                echo !password!| clip
                goto :display_result
            )
        )
    )
)


REM If still no password found
echo !str_err_no_password!
set "wifi_name="
timeout /t 4 >nul
goto main

:display_result
echo.
echo !str_sep!
echo   !str_wifi_name! !c_name!!last_wifi_name!!c_reset!
if "!show_password!"=="1" (
    echo   !str_wifi_password! !c_pwd!!last_wifi_password!!c_reset!
    REM --- Password strength (only when actual pwd is visible) ---
    set "str_strength_pwd=!last_wifi_password!"
    set "str_strength_ssid=!last_wifi_name!"
    call :password_strength
    set "bar_max=5"
    call :build_strength_bar
    echo   !str_password_strength! !str_strength_color!!str_strength_label!!c_reset! [!str_strength_bar!]
) else (
    echo   !str_wifi_password! !c_hint!!str_password_masked!!c_reset!
)
echo !str_sep!
echo.
echo   !c_ok![OK]!c_reset! !str_copied!
goto :main_menu

:main_menu
echo.
echo !str_sep!
echo   1) !str_menu_continue!
echo   2) !str_menu_export!
echo   3) !str_menu_qr!
echo   4) !str_menu_toggle!
echo   5) !str_menu_history!
echo   6) !str_menu_exit!
echo !str_sep!
choice /c 123456 /n /m "  ^>^> !str_select_option! [1-6]: "
if errorlevel 6 goto exit
if errorlevel 5 goto show_history
if errorlevel 4 goto toggle_password
if errorlevel 3 goto copy_wifi_string
if errorlevel 2 goto export_current
if errorlevel 1 goto main

:toggle_password
if "!show_password!"=="1" (
    set "show_password=0"
) else (
    set "show_password=1"
)
cls
echo.
echo !str_sep!
echo           !c_title!!str_title!!c_reset!
echo           !c_hint!!str_lang_info!!c_reset!
echo !str_sep!
goto :display_result

:show_history
echo.
echo !str_sep!
echo   !c_title!!str_history_title!!c_reset!
echo !str_sep!
if !hist_count! equ 0 (
    echo   !str_history_empty!
    echo !str_sep!
    timeout /t 3 >nul
    if defined last_wifi_password (
        goto main_menu
    ) else (
        goto main
    )
)
for /l %%i in (1,1,!hist_count!) do (
    set "idx_str=%%i"
    if %%i lss 10 set "idx_str=0%%i"
    echo   !idx_str!. !c_name!!hist_name_%%i!!c_reset!  [!c_pwd!!hist_pwd_%%i!!c_reset!]
)
echo !str_sep!
set "hist_input="
set /p "hist_input=!str_history_prompt!"
if /i "!hist_input!"=="q" (
    if defined last_wifi_password (
        goto main_menu
    ) else (
        goto main
    )
)
set "is_num=0"
for /f "delims=0123456789" %%d in ("!hist_input!") do set "is_num=1"
if "!is_num!"=="0" if not "!hist_input!"=="" (
    if !hist_input! geq 1 if !hist_input! leq !hist_count! (
        call set "wifi_name=%%hist_name_!hist_input!%%"
        goto do_query
    )
)
goto main

REM --- Export only the currently queried WiFi (from main_menu option 2) ---
:export_current
echo.
if "!last_wifi_password!"=="" (
    echo !str_err_no_wifi!
    timeout /t 3 >nul
    goto main_menu
)
REM Find index of last_wifi_name in the wifi_name_ array
set "current_idx=0"
for /l %%i in (1,1,!wifi_count!) do (
    if /i "!wifi_name_%%i!"=="!last_wifi_name!" set "current_idx=%%i"
)
if "!current_idx!"=="0" (
    echo !str_err_not_found!
    timeout /t 3 >nul
    goto main_menu
)
REM Mark only this index as selected, skip scope selection
for /l %%i in (1,1,!wifi_count!) do set "sel_%%i=0"
set "sel_!current_idx!=1"
set "export_selected=1"
set "export_mode=selected"
goto export_format_choose

REM --- Copy WiFi connect string for QR scan ---
:copy_wifi_string
echo.
if "!last_wifi_password!"=="" (
    echo !str_err_no_wifi!
    timeout /t 3 >nul
    goto main_menu
)
REM Build standard WiFi connect string: WIFI:T:WPA;S:ssid;P:password;;
REM Escape special chars per QR WiFi spec
set "qr_ssid=!last_wifi_name!"
set "qr_ssid=!qr_ssid:\=\\!"
set "qr_ssid=!qr_ssid:;=\;!"
set "qr_ssid=!qr_ssid:,=\,!"
set "qr_ssid=!qr_ssid::=\:!"
set "qr_pwd=!last_wifi_password!"
set "qr_pwd=!qr_pwd:\=\\!"
set "qr_pwd=!qr_pwd:;=\;!"
set "qr_pwd=!qr_pwd:,=\,!"
set "qr_pwd=!qr_pwd::=\:!"
set "wifi_qr_string=WIFI:T:WPA;S:!qr_ssid!;P:!qr_pwd!;;"
echo !str_sep!
echo   !c_title!!str_qr_full!!c_reset!
echo !str_sep!
echo.
echo   !c_pwd!!wifi_qr_string!!c_reset!
echo.
echo !str_sep!
echo !wifi_qr_string!| clip
echo   !c_ok![OK]!c_reset! !str_qr_copied!
echo.
echo !str_sep!
echo   1) !str_menu_continue!
echo   2) !str_menu_qr!
echo   3) !str_menu_exit!
echo !str_sep!
choice /c 123 /n /m "  ^>^> !str_select_option! [1-3]: "
if errorlevel 3 goto exit
if errorlevel 2 goto copy_wifi_string
if errorlevel 1 goto main

:export_all
echo.
echo !str_sep!
echo        !c_title!!str_export_title!!c_reset!
echo !str_sep!
if !wifi_count! equ 0 (
    echo.
    echo !str_err_no_export!
    timeout /t 3 >nul
    goto main
)

echo.
echo   !str_lang_info!
echo.
echo !str_export_scope_title!
echo !str_sep!
echo   1) !str_scope_all!
echo   2) !str_scope_selected!
echo   0) !str_scope_cancel!
echo !str_sep!
choice /c 120 /n /m "  ^>^> !str_select_option! [0-2]: "
if errorlevel 3 goto main
if errorlevel 2 goto export_scope_selected
if errorlevel 1 goto export_scope_all

:export_scope_all
set "export_mode=all"
goto export_format_choose

:export_scope_selected
echo.
for /l %%i in (1,1,!wifi_count!) do set "sel_%%i=0"
set "export_selected=0"
set "sel_input="
set /p "sel_input=!str_input_indices!"
if "!sel_input!"=="" (
    echo.
    echo !str_err_no_selection!
    timeout /t 3 >nul
    goto export_all
)
call :parse_selection "!sel_input!"
if "!export_selected!"=="0" (
    echo.
    echo !str_err_no_selection!
    timeout /t 3 >nul
    goto export_all
)
set "export_mode=selected"
goto export_format_choose

:export_format_choose
echo.
if "!export_mode!"=="selected" if "!current_idx!" neq "0" (
    echo   !str_current_selection! !last_wifi_name!
    echo.
)
echo !str_export_format_title!
echo !str_sep!
echo   1) !str_format_txt!
echo   2) !str_format_csv!
echo   0) !str_format_cancel!
echo !str_sep!
choice /c 120 /n /m "  ^>^> !str_select_option! [0-2]: "
if errorlevel 3 goto main
if errorlevel 2 goto do_export_csv
if errorlevel 1 goto do_export_txt

:do_export_txt
set "export_format=txt"
goto do_export_proceed

:do_export_csv
set "export_format=csv"
goto do_export_proceed

:do_export_proceed
REM Generate timestamped filename using wmic (locale-independent)
REM wmc returns YYYYMMDDHHMMSS.mmmmmm+TZ, avoids %date%/%time% locale issues
set "dt="
for /f "tokens=2 delims==." %%a in ('wmic os get LocalDateTime /value 2^>nul ^| findstr "LocalDateTime"') do set "dt=%%a"
if not "!dt!"=="" (
    set "datestamp=!dt:~0,4!-!dt:~4,2!-!dt:~6,2!"
    set "timestamp=!dt:~8,2!-!dt:~10,2!-!dt:~12,2!"
) else (
    REM Fallback to %date%/%time% if wmic unavailable
    set "datestamp=%date:~0,4%-%date:~5,2%-%date:~8,2%"
    set "timestamp=%time:~0,2%-%time:~3,2%-%time:~6,2%"
    set "timestamp=!timestamp: =0!"
)

REM Count total profiles to export for progress display
set "export_total=0"
if "!export_mode!"=="all" (
    set "export_total=!wifi_count!"
) else (
    for /l %%i in (1,1,!wifi_count!) do (
        if "!sel_%%i!"=="1" set /a export_total+=1
    )
)

if "!export_format!"=="csv" (
    set "outfile=%~dp0!str_export_filename!!datestamp!_!timestamp!.csv"
    REM Init CSV with UTF-8 BOM so Excel opens Chinese correctly
    powershell -Command "[IO.File]::WriteAllBytes('!outfile!', [byte[]](0xEF,0xBB,0xBF))" >nul 2>&1
    echo !str_col_index!,!str_col_name!,!str_col_password!>> "!outfile!"
) else (
    set "outfile=%~dp0!str_export_filename!!datestamp!_!timestamp!.txt"
    REM Write TXT file header
    echo !str_sep! > "!outfile!"
    echo               !str_export_report_title!                          >> "!outfile!"
    echo !str_sep! >> "!outfile!"
    echo.  >> "!outfile!"
    echo !str_export_time!: %date% %time% >> "!outfile!"
    echo !str_tool_version!: !str_title! v3.1 >> "!outfile!"
    echo !str_total_count!: !export_total! >> "!outfile!"
    echo.  >> "!outfile!"
    echo !str_sep! >> "!outfile!"
    echo !str_col_index!   !str_col_name!                             !str_col_password!   >> "!outfile!"
    echo !str_sep! >> "!outfile!"
)

echo.
echo !str_output_file! !outfile!
echo !str_processing! !export_total! !str_profiles_unit!
echo.

set "exported_ok=0"
set "exported_none=0"
set "export_processed=0"
for /l %%n in (1,1,!wifi_count!) do (
    set "skip_export="
    if "!export_mode!"=="selected" if not "!sel_%%n!"=="1" set "skip_export=1"
    if not defined skip_export (
        set "cur_name=!wifi_name_%%n!"
        set "cur_pwd="
        for /f "usebackq tokens=*" %%k in (`netsh wlan show profile name^="!cur_name!" key^=clear 2^>nul`) do (
            set "line=%%k"
            set "is_key="
            if not "!line:Key Content=!"=="!line!" set "is_key=1"
            if not "!line:关键内容=!"=="!line!" set "is_key=1"
            if not "!line:キー コンテンツ=!"=="!line!" set "is_key=1"
            if not "!line:キーコンテンツ=!"=="!line!" set "is_key=1"
            if not "!line:Schlüsselinhalt=!"=="!line!" set "is_key=1"
            if not "!line:Contenu de la clé=!"=="!line!" set "is_key=1"
            if not "!line:Contenido de la clave=!"=="!line!" set "is_key=1"
            if not "!line:Содержимое ключа=!"=="!line!" set "is_key=1"
            if not "!line:Conteúdo da chave=!"=="!line!" set "is_key=1"
            if not "!line:Contenuto della chiave=!"=="!line!" set "is_key=1"
            if not "!line:Zawartosc klucza=!"=="!line!" set "is_key=1"
            if not "!line:Sleutelinhoud=!"=="!line!" set "is_key=1"
            if not "!line:키 콘텐츠=!"=="!line!" set "is_key=1"
            if not "!line:Anahtar Içerigi=!"=="!line!" set "is_key=1"
            if not "!line:Kulcstartalom=!"=="!line!" set "is_key=1"
            if not "!line:Nyckelinnehall=!"=="!line!" set "is_key=1"
            if not "!line:Avaimen sisalto=!"=="!line!" set "is_key=1"
            if not "!line:Nøgleindhold=!"=="!line!" set "is_key=1"
            if not defined is_key (
                echo "!line!"| findstr /i /c:"key" >nul && echo "!line!"| findstr /i /c:"content" >nul && set "is_key=1"
            )
            if defined is_key (
                for /f "tokens=1,* delims=:" %%p in ("!line!") do (
                    set "cur_pwd=%%q"
                    for /f "tokens=* delims= " %%x in ("!cur_pwd!") do set "cur_pwd=%%x"
                )
            )
        )

        set /a export_processed+=1
        call :build_progress_bar !export_processed! !export_total!

        if "!export_format!"=="csv" (
            REM CSV output: index,name,password (with RFC 4180 escaping)
            call :csv_escape "!cur_name!"
            set "csv_name=!csv_field!"
            if "!cur_pwd!"=="" (
                set /a exported_none+=1
                echo %%n,!csv_name!,>> "!outfile!"
                echo !progress_bar! !cur_name!  -^>  ^<!str_no_password!^>
            ) else (
                call :csv_escape "!cur_pwd!"
                set /a exported_ok+=1
                echo %%n,!csv_name!,!csv_field!>> "!outfile!"
                echo !progress_bar! !cur_name!  -^>  !cur_pwd!
            )
        ) else (
            REM TXT output: aligned table format
            set "idx_str=%%n"
            if %%n lss 10 set "idx_str= %%n"
            if %%n lss 100 if %%n geq 10 set "idx_str=%%n"

            set "name_pad=!cur_name!                                                    "
            set "name_pad=!name_pad:~0,36!"

            if "!cur_pwd!"=="" (
                set /a exported_none+=1
                echo !idx_str!.  !name_pad! ^<!str_no_password!^> >> "!outfile!"
                echo !progress_bar! !cur_name!  -^>  ^<!str_no_password!^>
            ) else (
                set /a exported_ok+=1
                echo !idx_str!.  !name_pad! !cur_pwd! >> "!outfile!"
                echo !progress_bar! !cur_name!  -^>  !cur_pwd!
            )
        )
    )
)


REM TXT footer with stats (CSV keeps plain columns)
if not "!export_format!"=="csv" (
    echo. >> "!outfile!"
    echo !str_sep! >> "!outfile!"
    echo !str_export_stats!: !str_stats_success! !exported_ok! / !str_stats_none! !exported_none! / !str_stats_total! !export_total! >> "!outfile!"
    echo !str_sep! >> "!outfile!"
)

echo.
echo !str_sep!
echo   !c_ok![OK]!c_reset! !str_export_complete!
echo !str_sep!
echo   !str_file_location! : !outfile!
echo   !str_success_count!       : !exported_ok!
echo   !str_no_password_count!   : !exported_none!
echo !str_sep!
echo.
pause
goto main

:exit
echo.
echo !str_exiting!
timeout /t 2 >nul
exit /b 0

REM ============================================================
REM Subroutine: Build progress bar string
REM Args: %1 = processed count, %2 = total count
REM Output: progress_bar variable (e.g., "[██████░░░░] 60%")
REM ============================================================
:build_progress_bar
set /a pct=0
if %2 gtr 0 set /a pct=%1*100/%2
set /a bar_filled=pct/10
set /a bar_empty=10-bar_filled
set "progress_bar="
for /l %%i in (1,1,!bar_filled!) do set "progress_bar=!progress_bar!█"
for /l %%i in (1,1,!bar_empty!) do set "progress_bar=!progress_bar!░"
set "progress_bar=!c_bar_fill![!progress_bar!]!c_reset! !pct!%%"
goto :eof

REM ============================================================
REM Subroutine: Detect system language
REM Order: cmdline arg > registry LocaleName > wmic OSLanguage > LANG env > default English
REM ============================================================
:detect_language
set "sys_lang=en"
set "sys_lang_full=en-US"
set "sys_lcid="

REM Method 1: Registry LocaleName (e.g., zh-CN, en-US, ja-JP)
set "locale_name="
for /f "tokens=2,*" %%a in ('reg query "HKCU\Control Panel\International" /v LocaleName 2^>nul ^| findstr /i "LocaleName"') do (
    set "locale_name=%%b"
)
if not "!locale_name!"=="" (
    set "sys_lang_full=!locale_name!"
    set "sys_lang=!locale_name:~0,2!"
    goto :detect_check_override
)

REM Method 2: wmic OSLanguage LCID
for /f "tokens=2 delims==" %%l in ('wmic os get oslanguage /value 2^>nul ^| findstr "OSLanguage"') do (
    set "sys_lcid=%%l"
)
if not "!sys_lcid!"=="" (
    if "!sys_lcid!"=="2052" set "sys_lang=zh"
    if "!sys_lcid!"=="1028" set "sys_lang=zh"
    if "!sys_lcid!"=="1033" set "sys_lang=en"
    if "!sys_lcid!"=="2057" set "sys_lang=en"
    if "!sys_lcid!"=="3081" set "sys_lang=en"
    if "!sys_lcid!"=="4105" set "sys_lang=en"
    if "!sys_lcid!"=="1041" set "sys_lang=ja"
    if "!sys_lcid!"=="1042" set "sys_lang=ko"
    if "!sys_lcid!"=="1031" set "sys_lang=de"
    if "!sys_lcid!"=="1036" set "sys_lang=fr"
    if "!sys_lcid!"=="1049" set "sys_lang=ru"
    if "!sys_lcid!"=="1034" set "sys_lang=es"
    if "!sys_lcid!"=="1040" set "sys_lang=it"
    if "!sys_lcid!"=="2070" set "sys_lang=pt"
    if "!sys_lcid!"=="1045" set "sys_lang=pl"
    if "!sys_lcid!"=="1043" set "sys_lang=nl"
    if "!sys_lcid!"=="1055" set "sys_lang=tr"
    if "!sys_lcid!"=="1025" set "sys_lang=ar"
    if "!sys_lcid!"=="1037" set "sys_lang=he"
    if "!sys_lcid!"=="1029" set "sys_lang=cs"
    if "!sys_lcid!"=="1038" set "sys_lang=hu"
    if "!sys_lcid!"=="1053" set "sys_lang=sv"
    if "!sys_lcid!"=="1035" set "sys_lang=fi"
    if "!sys_lcid!"=="1030" set "sys_lang=da"
    if "!sys_lcid!"=="1044" set "sys_lang=no"
    goto :detect_check_override
)

REM Method 3: LANG environment variable (Git Bash / Cygwin / MSYS2)
if not "%LANG%"=="" (
    set "sys_lang=%LANG:~0,2%"
    goto :detect_check_override
)

:detect_check_override
REM Override with command line argument if provided
if not "%~1"=="" (
    set "arg1=%~1"
    if /i "!arg1!"=="zh" set "sys_lang=zh"
    if /i "!arg1!"=="en" set "sys_lang=en"
    if /i "!arg1!"=="ja" set "sys_lang=ja"
    if /i "!arg1!"=="ko" set "sys_lang=ko"
    if /i "!arg1!"=="de" set "sys_lang=de"
    if /i "!arg1!"=="fr" set "sys_lang=fr"
    if /i "!arg1!"=="ru" set "sys_lang=ru"
    if /i "!arg1!"=="es" set "sys_lang=es"
    if /i "!arg1!"=="it" set "sys_lang=it"
    if /i "!arg1!"=="pt" set "sys_lang=pt"
    if /i "!arg1!"=="pl" set "sys_lang=pl"
    if /i "!arg1!"=="nl" set "sys_lang=nl"
    if /i "!arg1!"=="tr" set "sys_lang=tr"
    if /i "!arg1!"=="ar" set "sys_lang=ar"
    if /i "!arg1!"=="he" set "sys_lang=he"
)
goto :eof

REM ============================================================
REM Subroutine: Load language strings
REM UI text loaded based on detected language (Chinese/English)
REM Other languages default to English UI
REM ============================================================
:load_strings
if /i "!sys_lang!"=="zh" (
    set "str_title=WiFi密码查询工具"
    set "str_lang_info=[已自动识别: 简体中文 / !sys_lang_full!]"
    set "str_profiles_on_interface=接口 WLAN 上的配置文件:"
    set "str_group_policy=组策略配置文件(只读)"
    set "str_user_profiles=用户配置文件"
    set "str_none=无"
    set "str_profile_type=所有用户配置文件"
    set "str_input_prompt=请输入序号或WiFi名称查询密码（e导出，q退出，/关键词模糊搜索）："
    set "str_query_result=WiFi密码查询结果"
    set "str_searching=正在查找密码信息..."
    set "str_search_no_match=无匹配项"
    set "str_search_matches=搜索匹配"
    set "str_search_select=  >> 输入序号选择 (回车返回): "
    set "str_search_invalid=无效选择，已取消"
    set "str_password_strength=密码强度:"
    set "str_strength_empty=无"
    set "str_strength_weak=弱"
    set "str_strength_medium=中等"
    set "str_strength_strong=强"
    set "str_wifi_name=WiFi名称:"
    set "str_wifi_password=WiFi密码:"
    set "str_copied=[密码已复制到剪贴板]"
    set "str_menu_continue=继续查询其他WiFi"
    set "str_menu_export=导出当前WiFi密码"
    set "str_menu_qr=复制WiFi连接字符串（手机扫码）"
    set "str_menu_exit=退出程序"
    set "str_select_option=请选择操作"
    set "str_qr_full=WiFi连接字符串（手机相机扫码即可连接）"
    set "str_qr_copied=[连接字符串已复制到剪贴板]"
    set "str_err_no_wifi=!c_error![ERROR]!c_reset! 请先查询WiFi密码！"
    set "str_csv_file=另存 CSV 文件 -"
    set "str_export_format_title=请选择导出格式："
    set "str_format_txt=导出为 TXT 文本文件"
    set "str_format_csv=导出为 CSV 文件"
    set "str_format_cancel=取消，返回主菜单"
    set "str_export_scope_title=请选择导出范围："
    set "str_scope_all=导出所有 WiFi 配置"
    set "str_scope_selected=导出指定编号的 WiFi 配置"
    set "str_scope_cancel=取消，返回主菜单"
    set "str_input_indices=请输入要导出的编号（多个用逗号分隔，如 1,3,5）："
    set "str_invalid_num=无效编号，已跳过："
    set "str_err_no_selection=!c_error![ERROR]!c_reset! 未选择有效的编号！"
    set "str_current_selection=当前选择:"
    set "str_export_title=批量导出WiFi密码"
    set "str_export_filename=WiFi密码导出_"
    set "str_output_file=导出文件路径 -"
    set "str_processing=正在处理 共"
    set "str_profiles_unit=个WiFi配置..."
    set "str_export_report_title=WiFi密码批量导出报告"
    set "str_export_time=导出时间"
    set "str_tool_version=导出工具"
    set "str_total_count=WiFi总数"
    set "str_col_index=序号"
    set "str_col_name=WiFi名称"
    set "str_col_password=WiFi密码"
    set "str_no_password=无密码或开放网络"
    set "str_export_stats=导出统计"
    set "str_stats_success=成功"
    set "str_stats_none=无密码"
    set "str_stats_total=总计"
    set "str_export_complete=导出完成！"
    set "str_file_location=文件位置"
    set "str_success_count=成功导出"
    set "str_no_password_count=无密码"
    set "str_exiting=正在退出WiFi密码查询工具..."
    set "str_err_admin=!c_error![ERROR]!c_reset! 请以管理员身份运行此脚本！"
    set "str_press_exit=按任意键退出..."
    set "str_err_no_input=!c_error![ERROR]!c_reset! 没有输入WiFi名称！"
    set "str_err_not_found=!c_error![ERROR]!c_reset! 找不到该WiFi配置文件！"
    set "str_err_no_password=!c_error![ERROR]!c_reset! 无法获取密码信息，可能是该WiFi没有保存密码。"
    set "str_err_no_export=!c_error![ERROR]!c_reset! 当前没有可导出的WiFi配置！"
    set "str_menu_toggle=显示/隐藏密码 (R)"
    set "str_password_masked=********（已隐藏，按R切换显示）"
    set "str_menu_history=查看查询历史 (H)"
    set "str_history_title=查询历史记录"
    set "str_history_empty=暂无查询历史"
    set "str_history_prompt=输入序号可快速重新查询（q返回主菜单）："
    set "str_hint_bar=[e]导出  [h]历史  [q]退出  [/关键词]模糊搜索  [序号/名称]查询"
    set "str_progress_done=完成"
) else (
    set "str_title=WiFi Password Query Tool"
    set "str_lang_info=[Auto-detected: English / !sys_lang_full!]"
    set "str_profiles_on_interface=Profiles on interface WLAN:"
    set "str_group_policy=Group policy profiles (read only)"
    set "str_user_profiles=User profiles"
    set "str_none=None"
    set "str_profile_type=All User Profile"
    set "str_input_prompt=Enter index/WiFi name to query (e=export, q=exit, /keyword fuzzy search): "
    set "str_query_result=WiFi Password Query Result"
    set "str_searching=Searching for password information..."
    set "str_search_no_match=No matches"
    set "str_search_matches=Search matches"
    set "str_search_select=  >> Pick a number (Enter to cancel): "
    set "str_search_invalid=Invalid selection, cancelled"
    set "str_password_strength=Password strength:"
    set "str_strength_empty=N/A"
    set "str_strength_weak=Weak"
    set "str_strength_medium=Medium"
    set "str_strength_strong=Strong"
    set "str_wifi_name=WiFi Name:"
    set "str_wifi_password=WiFi Password:"
    set "str_copied=[Password copied to clipboard]"
    set "str_menu_continue=Query another WiFi"
    set "str_menu_export=Export current WiFi password"
    set "str_menu_qr=Copy WiFi connect string"
    set "str_menu_exit=Exit program"
    set "str_select_option=Please select an option"
    set "str_qr_full=WiFi connect string (scan with phone camera to connect)"
    set "str_qr_copied=[Connect string copied to clipboard]"
    set "str_err_no_wifi=!c_error![ERROR]!c_reset! Please query a WiFi password first!"
    set "str_csv_file=CSV file also saved -"
    set "str_export_format_title=Select export format:"
    set "str_format_txt=Export as TXT text file"
    set "str_format_csv=Export as CSV file"
    set "str_format_cancel=Cancel, back to main menu"
    set "str_export_scope_title=Select export scope:"
    set "str_scope_all=Export all WiFi profiles"
    set "str_scope_selected=Export selected WiFi profiles by index"
    set "str_scope_cancel=Cancel, back to main menu"
    set "str_input_indices=Enter indices to export (comma separated, e.g. 1,3,5): "
    set "str_invalid_num=Invalid index, skipped:"
    set "str_err_no_selection=!c_error![ERROR]!c_reset! No valid index selected!"
    set "str_current_selection=Current selection:"
    set "str_export_title=Batch Export WiFi Passwords"
    set "str_export_filename=WiFi_Passwords_Export_"
    set "str_output_file=Output file -"
    set "str_processing=Processing"
    set "str_profiles_unit=WiFi profiles..."
    set "str_export_report_title=WiFi Password Batch Export Report"
    set "str_export_time=Export Time"
    set "str_tool_version=Tool Version"
    set "str_total_count=Total WiFi Count"
    set "str_col_index=No."
    set "str_col_name=WiFi Name"
    set "str_col_password=WiFi Password"
    set "str_no_password=No password or open network"
    set "str_export_stats=Export Stats"
    set "str_stats_success=Success"
    set "str_stats_none=No Password"
    set "str_stats_total=Total"
    set "str_export_complete=Export complete!"
    set "str_file_location=File location"
    set "str_success_count=Success"
    set "str_no_password_count=No password"
    set "str_exiting=Exiting WiFi Password Query Tool..."
    set "str_err_admin=!c_error![ERROR]!c_reset! Please run this script as Administrator!"
    set "str_press_exit=Press any key to exit..."
    set "str_err_no_input=!c_error![ERROR]!c_reset! No WiFi name entered!"
    set "str_err_not_found=!c_error![ERROR]!c_reset! WiFi profile not found!"
    set "str_err_no_password=!c_error![ERROR]!c_reset! Unable to retrieve password information. This WiFi may not have a saved password."
    set "str_err_no_export=!c_error![ERROR]!c_reset! No WiFi configurations available to export!"
    set "str_menu_toggle=Show/Hide password (R)"
    set "str_password_masked=******** (hidden, press R to show)"
    set "str_menu_history=View query history (H)"
    set "str_history_title=Query History"
    set "str_history_empty=No query history yet"
    set "str_history_prompt=Enter index to re-query (q=back to main): "
    set "str_hint_bar=[e]export  [h]history  [q]quit  [/keyword]fuzzy  [index/name]query"
    set "str_progress_done=Done"
)
goto :eof

REM ============================================================
REM Subroutine: Parse a netsh profile line and extract WiFi name
REM Strategy:
REM   1. Exact-match known type keywords (handles ":" in WiFi name)
REM   2. Generic fallback: extract text after last ":" (all languages)
REM Args: %1 = text before first ":", %2 = text after first ":"
REM ============================================================
:parse_profile_line
set "p1=%~1"
set "p2=%~2"

REM Trim leading spaces from p1
for /f "tokens=* delims= " %%x in ("!p1!") do set "p1_trim=%%x"

REM Skip if p1 starts with "<" (e.g., <None>, etc.)
if "!p1_trim:~0,1!"=="<" goto :eof

REM Remove all spaces from p1 for keyword matching
set "p1_nospace=!p1_trim: =!"

REM --- Method 1: Known profile type keywords (exact match) ---
set "is_profile_type=0"
if /i "!p1_nospace!"=="AllUserProfile" set "is_profile_type=1"
if /i "!p1_nospace!"=="CurrentUserProfile" set "is_profile_type=1"
if "!p1_nospace!"=="所有用户配置文件" set "is_profile_type=1"
if "!p1_nospace!"=="当前用户配置" set "is_profile_type=1"
if "!p1_nospace!"=="すべてのユーザープロファイル" set "is_profile_type=1"
if "!p1_nospace!"=="現在のユーザープロファイル" set "is_profile_type=1"
if "!p1_nospace!"=="모든사용자프로필" set "is_profile_type=1"
if "!p1_nospace!"=="현재사용자프로필" set "is_profile_type=1"

if "!is_profile_type!"=="1" (
    set "pname=!p2!"
    for /f "tokens=* delims= " %%x in ("!pname!") do set "pname=%%x"
    if not "!pname!"=="" (
        set /a wifi_count+=1
        call :safe_set_wifi "!wifi_count!" "!pname!"
    )
    goto :eof
)

REM --- Method 2: Generic fallback - extract text after last ":" ---
call :extract_last_segment "!p2!"
if not "!extracted_name!"=="" (
    set "p2_has_colon="
    set "p2_test=!p2:*:=!"
    if not "!p2_test!"=="!p2!" set "p2_has_colon=1"

    set "p1_is_num=0"
    for /f "delims=0123456789" %%d in ("!p1_trim!") do set "p1_is_num=1"
    if "!p1_trim!"=="" set "p1_is_num=1"

    if "!p1_is_num!"=="0" (
        set /a wifi_count+=1
        call :safe_set_wifi "!wifi_count!" "!extracted_name!"
    ) else if "!p2_has_colon!"=="1" (
        set /a wifi_count+=1
        call :safe_set_wifi "!wifi_count!" "!extracted_name!"
    )
)
goto :eof

REM ============================================================
REM Subroutine: Safely set wifi_name_N variable
REM Args: %1 = index, %2 = WiFi name
REM ============================================================
:safe_set_wifi
set "wifi_name_%~1=%~2"
goto :eof

REM ============================================================
REM Subroutine: CSV field escape (RFC 4180)
REM Args: %1 = field value
REM Output: csv_field variable with proper CSV escaping
REM Rules: fields with comma or quote are wrapped in quotes,
REM        quotes inside are doubled ("" -> """")
REM ============================================================
:csv_escape
set "csv_field=%~1"
set "csv_need_escape=0"
if not "!csv_field:,=!"=="!csv_field!" set "csv_need_escape=1"
if not "!csv_field:"=!"=="!csv_field!" set "csv_need_escape=1"
if "!csv_need_escape!"=="1" (
    REM Double all double quotes: " -> ""
    set "csv_field=!csv_field:"=""!"
    REM Wrap field in double quotes
    for /f "delims=" %%q in ('echo "!csv_field!"') do set "csv_field=%%q"
)
goto :eof
REM Marks sel_<n>=1 for each valid index, sets export_selected=1 if any
REM Args: %1 = list like "1,3,5"
REM ============================================================
:parse_selection
set "rest=%~1"
:parse_sel_loop
if "!rest!"=="" goto :parse_sel_done
set "cur_num="
for /f "tokens=1,* delims=," %%a in ("!rest!") do (
    set "cur_num=%%a"
    set "rest=%%b"
)
if not "!cur_num!"=="" (
    for /f "tokens=* delims= " %%t in ("!cur_num!") do set "cur_num=%%t"
    set "is_digit_only=0"
    for /f "delims=0123456789" %%d in ("!cur_num!") do set "is_digit_only=1"
    if "!cur_num!"=="" set "is_digit_only=1"
    if "!is_digit_only!"=="0" (
        if !cur_num! geq 1 if !cur_num! leq !wifi_count! (
            set "sel_!cur_num!=1"
            set "export_selected=1"
        ) else (
            echo     !str_invalid_num! !cur_num!
        )
    ) else (
        echo     !str_invalid_num! !cur_num!
    )
)
goto :parse_sel_loop
:parse_sel_done
goto :eof

REM ============================================================
REM Subroutine: Extract text after the last ":" in a string
REM Loops to remove text up to first ":" until no ":" remains
REM Args: %1 = input string, Output: extracted_name
REM ============================================================
:extract_last_segment
set "seg=%~1"
:extract_loop
set "seg_next=!seg:*:=!"
if "!seg_next!"=="!seg!" goto :extract_done
set "seg=!seg_next!"
goto :extract_loop
:extract_done
for /f "tokens=* delims= " %%x in ("!seg!") do set "extracted_name=%%x"
goto :eof
REM ============================================================
REM Subroutine: Add entry to query history
REM Args: %1 = WiFi name, %2 = password
REM Keeps last 10 entries, skips consecutive duplicates
REM ============================================================
:add_history
set "hist_new_name=%~1"
set "hist_new_pwd=%~2"
REM Skip if same as most recent entry
if !hist_count! gtr 0 (
    call set "hist_last=%%hist_name_!hist_count!%%"
    if /i "!hist_last!"=="!hist_new_name!" goto :eof
)
REM If at max capacity, shift entries (drop oldest)
if !hist_count! geq 10 (
    for /l %%i in (1,1,9) do (
        set /a next=%%i+1
        call set "hist_name_%%i=%%hist_name_!next!%%"
        call set "hist_pwd_%%i=%%hist_pwd_!next!%%"
    )
    set "hist_count=9"
)
set /a hist_count+=1
set "hist_name_!hist_count!=!hist_new_name!"
set "hist_pwd_!hist_count!=!hist_new_pwd!"
goto :eof

REM ============================================================
REM Subroutine: Fuzzy search WiFi profiles (/keyword)
REM Case-insensitive substring, multi-token AND semantics:
REM "/home 5g" matches "HomeWiFi-5G".
REM Inputs:  !input! (already set, starting with "/")
REM          !wifi_count! and wifi_name_!i! arrays
REM Outputs: search_match_count and search_match_N (1-based positions)
REM          wifi_name (set to original SSID on match+select;
REM          cleared on no-match / cancel so caller can detect)
REM ============================================================
:do_fuzzy_search
set "search_term=!input:~1!"
REM Trim leading/trailing spaces from the term
for /f "tokens=*" %%t in ("!search_term!") do set "search_term=%%t"
set "search_match_count=0"
for /l %%i in (1,1,!wifi_count!) do (
    set "match_all=1"
    for %%t in (!search_term!) do (
        if !match_all!==1 (
            echo !wifi_name_%%i!| findstr /i /c:"%%t" >nul 2>&1
            if errorlevel 1 set "match_all=0"
        )
    )
    if !match_all!==1 (
        set /a search_match_count+=1
        set "search_match_!search_match_count!=%%i"
    )
)
if !search_match_count!==0 (
    echo.
    echo   !c_hint!!str_search_no_match!!c_reset!
    timeout /t 2 >nul
    set "wifi_name="
    goto :eof
)
echo.
echo   !c_hint!!str_search_matches!: "!search_term!"!c_reset!
echo   ---------------------------------
for /l %%j in (1,1,!search_match_count!) do (
    call set "orig_idx=%%search_match_%%j%%"
    set "idx_str=%%j"
    if %%j lss 10 set "idx_str=0%%j"
    call echo     !idx_str!. !c_name!%%wifi_name_!orig_idx!%%!c_reset!
)
echo   ---------------------------------
set "sel_input="
set /p "sel_input=!str_search_select!"
if "!sel_input!"=="" (
    set "wifi_name="
    goto :eof
)
REM Validate: must be a positive integer within range
set "sel_is_num=0"
for /f "delims=0123456789" %%d in ("!sel_input!") do set "sel_is_num=1"
if "!sel_is_num!"=="1" (
    echo !str_search_invalid!
    timeout /t 2 >nul
    set "wifi_name="
    goto :eof
)
if !sel_input! lss 1 (
    echo !str_search_invalid!
    timeout /t 2 >nul
    set "wifi_name="
    goto :eof
)
if !sel_input! gtr !search_match_count! (
    echo !str_search_invalid!
    timeout /t 2 >nul
    set "wifi_name="
    goto :eof
)
call set "orig_idx=%%search_match_!sel_input!%%"
call set "wifi_name=%%wifi_name_!orig_idx!%%"
goto :eof

REM ============================================================
REM Subroutine: Password strength scoring (0-5)
REM Inputs:  str_strength_pwd, str_strength_ssid
REM Outputs: str_strength_score (0-5), str_strength_label, str_strength_color
REM Aligned with the Go version's logic.
REM ============================================================
:password_strength
set "pwd=!str_strength_pwd!"
set "ssid=!str_strength_ssid!"
set "score=0"

if "!pwd!"=="" (
    set "str_strength_score=0"
    set "str_strength_label=!str_strength_empty!"
    set "str_strength_color=!c_hint!"
    goto :eof
)

REM --- Length tier (substring existence check, O(32) max) ---
set "pwd_len=0"
for /l %%i in (1,1,32) do (
    if not "!pwd:~%%i,1!"=="" set /a pwd_len=%%i
)
if !pwd_len! geq 12 (
    set /a score+=2
) else if !pwd_len! geq 8 (
    set /a score+=1
) else (
    set /a score-=1
)

REM --- Character classes ---
set "has_lower=0"
set "has_upper=0"
set "has_digit=0"
set "has_special=0"
for /l %%i in (0,1,31) do (
    set "ch=!pwd:~%%i,1!"
    if "!ch!"=="" goto :break_chars
    if "!ch!" geq "a" if "!ch!" leq "z" (
        set "has_lower=1"
    ) else if "!ch!" geq "A" if "!ch!" leq "Z" (
        set "has_upper=1"
    ) else if "!ch!" geq "0" if "!ch!" leq "9" (
        set "has_digit=1"
    ) else (
        set "has_special=1"
    )
)
:break_chars
set /a class_count=has_lower+has_upper+has_digit+has_special
if !class_count! geq 3 (
    set /a score+=2
) else if !class_count! geq 2 (
    set /a score+=1
)

REM --- Common password penalty (matches Go version's list) ---
if /i "!pwd!"=="password" set /a score-=4
if /i "!pwd!"=="passw0rd" set /a score-=4
if /i "!pwd!"=="p@ssw0rd" set /a score-=4
if /i "!pwd!"=="12345678" set /a score-=4
if /i "!pwd!"=="123456789" set /a score-=4
if /i "!pwd!"=="1234567890" set /a score-=4
if /i "!pwd!"=="qwerty" set /a score-=4
if /i "!pwd!"=="qwertyuiop" set /a score-=4
if /i "!pwd!"=="asdfgh" set /a score-=4
if /i "!pwd!"=="zxcvbn" set /a score-=4
if /i "!pwd!"=="abc123" set /a score-=4
if /i "!pwd!"=="111111" set /a score-=4
if /i "!pwd!"=="1234567" set /a score-=4
if /i "!pwd!"=="iloveyou" set /a score-=4
if /i "!pwd!"=="admin" set /a score-=4
if /i "!pwd!"=="welcome" set /a score-=4
if /i "!pwd!"=="monkey" set /a score-=4
if /i "!pwd!"=="letmein" set /a score-=4
if /i "!pwd!"=="dragon" set /a score-=4
if /i "!pwd!"=="master" set /a score-=4
if /i "!pwd!"=="login" set /a score-=4
if /i "!pwd!"=="princess" set /a score-=4
if /i "!pwd!"=="football" set /a score-=4
if /i "!pwd!"=="88888888" set /a score-=4
if /i "!pwd!"=="666666" set /a score-=4
if /i "!pwd!"=="woaini" set /a score-=4
if /i "!pwd!"=="5201314" set /a score-=4
if /i "!pwd!"=="a1b2c3" set /a score-=4
if /i "!pwd!"=="abcd1234" set /a score-=4

REM --- SSID substring penalty (only if SSID >= 3 chars) ---
if not "!ssid!"=="" if not "!ssid:~2,1!"=="" (
    echo !pwd!| findstr /i /c:"!ssid!" >nul 2>&1
    if not errorlevel 1 set /a score-=2
)

REM --- Sequential chars penalty (any 4+ digit/letter run) ---
echo !pwd!| findstr /i /c:"1234" >nul 2>&1
if not errorlevel 1 set /a score-=2
echo !pwd!| findstr /i /c:"2345" >nul 2>&1
if not errorlevel 1 set /a score-=2
echo !pwd!| findstr /i /c:"3456" >nul 2>&1
if not errorlevel 1 set /a score-=2
echo !pwd!| findstr /i /c:"4567" >nul 2>&1
if not errorlevel 1 set /a score-=2
echo !pwd!| findstr /i /c:"5678" >nul 2>&1
if not errorlevel 1 set /a score-=2
echo !pwd!| findstr /i /c:"6789" >nul 2>&1
if not errorlevel 1 set /a score-=2
echo !pwd!| findstr /i /c:"abcd" >nul 2>&1
if not errorlevel 1 set /a score-=2
echo !pwd!| findstr /i /c:"bcde" >nul 2>&1
if not errorlevel 1 set /a score-=2
echo !pwd!| findstr /i /c:"cdef" >nul 2>&1
if not errorlevel 1 set /a score-=2
echo !pwd!| findstr /i /c:"defg" >nul 2>&1
if not errorlevel 1 set /a score-=2
echo !pwd!| findstr /i /c:"wxyz" >nul 2>&1
if not errorlevel 1 set /a score-=2

REM --- Repeated chars penalty (3+ consecutive identical) ---
set "rep_found=0"
for %%c in (a b c d e f g h i j k l m n o p q r s t u v w x y z 0 1 2 3 4 5 6 7 8 9) do (
    if !rep_found!==0 (
        if not "!pwd:%%c%%c%%c=!"=="!pwd!" set "rep_found=1"
    )
)
if !rep_found!==1 set /a score-=1

REM --- Clamp 0-5 ---
if !score! lss 0 set "score=0"
if !score! gtr 5 set "score=5"

REM --- Output ---
set "str_strength_score=!score!"
if !score! leq 1 (
    set "str_strength_label=!str_strength_weak!"
    set "str_strength_color=!c_error!"
) else if !score! leq 3 (
    set "str_strength_label=!str_strength_medium!"
    set "str_strength_color=!c_warn!"
) else (
    set "str_strength_label=!str_strength_strong!"
    set "str_strength_color=!c_ok!"
)
goto :eof

REM ============================================================
REM Subroutine: Build visual strength bar (█ filled / ░ empty)
REM Inputs:  str_strength_score, bar_max
REM Outputs: str_strength_bar (colored bar with reset)
REM ============================================================
:build_strength_bar
set "filled=!str_strength_score!"
if !filled! lss 0 set "filled=0"
if !filled! gtr !bar_max! set "filled=!bar_max!"
set /a empty=bar_max-filled

if !str_strength_score! leq 1 set "bar_color=!c_error!"
if !str_strength_score! gtr 1 if !str_strength_score! leq 3 set "bar_color=!c_warn!"
if !str_strength_score! geq 4 set "bar_color=!c_ok!"

set "str_strength_bar=!bar_color!"
for /l %%i in (1,1,!filled!) do set "str_strength_bar=!str_strength_bar!█"
set "str_strength_bar=!str_strength_bar!!c_bar_empty!"
for /l %%i in (1,1,!empty!) do set "str_strength_bar=!str_strength_bar!░"
set "str_strength_bar=!str_strength_bar!!c_reset!"
goto :eof
