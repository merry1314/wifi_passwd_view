# BAT 脚本陷阱全集

## 1. 中文 REM 注释导致编码问题

**症状**：脚本在某些系统上乱码或闪退

**解决**：REM 注释必须用英文

```bat
REM This is a comment  ✅
REM 这是一个注释      ❌
```

## 2. for 循环内 setlocal/endlocal

**症状**：变量永远为空，功能失效

**原因**：`setlocal enabledelayedexpansion` + `endlocal &` 模式在 for 循环内会使变量赋值丢失

```bat
REM ❌ 禁止在 for 循环内使用
for /f %%a in (...) do (
    setlocal enabledelayedexpansion
    set var=%%a
    endlocal & set result=!var!
)
REM result 永远为空

REM ✅ 在循环外 setlocal
setlocal enabledelayedexpansion
for /f %%a in (...) do (
    set var=%%a
    set result=!var!
)
endlocal
```

## 3. 延迟展开中 `!var:!=!` 检测感叹号

**症状**：解析歧义或闪退

**原因**：`!` 是延迟展开的触发字符，`!var:!=!` 语法会导致解析器混乱

**解决**：禁用 `!var:!=!`，改用其他方式检测感叹号（如临时关闭延迟展开）

## 4. 临时文件首行缺 `@` 前缀

**症状**：`cmd /c` 执行临时 bat 且输出被 `for /f` 捕获时，首行命令回显被当作数据

```bat
REM ❌ 临时文件首行无 @
echo %ssid%

REM ✅ 首行加 @ 抑制回显
@echo %ssid%
```

## 5. 编码处理

```bat
REM 切换到 UTF-8 代码页
chcp 65001 >nul

REM 调用 netsh
for /f "tokens=2 delims=:" %%a in ('netsh wlan show profiles ^| findstr /C:"All User Profile"') do (
    set ssid=%%a
    set ssid=!ssid: =!
)
```

## 6. 延迟展开时变量赋值

```bat
setlocal enabledelayedexpansion

REM 在 for 循环内读取/修改变量必须用 !var! 而非 %var%
for /f %%a in ('netsh wlan show profiles') do (
    set line=%%a
    echo !line!          ✅ 延迟展开
    echo %line%          ❌ 只展开循环前的值
)

endlocal
```