@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

title CABM-ED 卸载程序
mode con cols=70 lines=25

:menu
cls
echo ==========================================================
echo                    CABM-ED 卸载程序
echo ==========================================================
echo.
echo  1. 仅删除游戏文件（当前目录下的 CABM-ED.exe 和 addons\）
echo  2. 仅删除存档文件（Godot 存档目录）
echo  3. 删除游戏文件和存档文件（完全卸载）
echo  4. 退出
echo.
set /p choice="请选择操作 (1/2/3/4): "

if "%choice%"=="1" goto delete_game
if "%choice%"=="2" goto delete_save
if "%choice%"=="3" goto delete_all
if "%choice%"=="4" exit /b
goto menu

:delete_game
cls
echo ==========================================================
echo                   删除游戏文件
echo ==========================================================
echo.

if exist "CABM-ED.exe" (
    del /f /q "CABM-ED.exe" >nul 2>&1
    echo [✓] 已删除：CABM-ED.exe
) else (
    echo [ ] CABM-ED.exe 不存在
)

if exist "addons\" (
    rmdir /s /q "addons" >nul 2>&1
    echo [✓] 已删除：addons\ 文件夹
) else (
    echo [ ] addons\ 文件夹不存在
)

echo.
echo 游戏文件删除完成！
goto end_prompt

:delete_save
cls
echo ==========================================================
echo                   删除存档文件
echo ==========================================================
echo.

set SAVE_PATH=%APPDATA%\Godot\app_userdata\CABM-ED

if exist "!SAVE_PATH!" (
    rmdir /s /q "!SAVE_PATH!" >nul 2>&1
    echo [✓] 已删除存档：!SAVE_PATH!
) else (
    echo [ ] 存档目录不存在：!SAVE_PATH!
)

echo.
echo 存档删除完成！
goto end_prompt

:delete_all
cls
echo ==========================================================
echo                   完全卸载
echo ==========================================================
echo.

REM 删除游戏文件
echo 正在删除游戏文件...
if exist "CABM-ED.exe" (
    del /f /q "CABM-ED.exe" >nul 2>&1
    echo [✓] 已删除：CABM-ED.exe
)
if exist "addons\" (
    rmdir /s /q "addons" >nul 2>&1
    echo [✓] 已删除：addons\ 文件夹
)

echo.
REM 删除存档
echo 正在删除存档文件...
set SAVE_PATH=%APPDATA%\Godot\app_userdata\CABM-ED
if exist "!SAVE_PATH!" (
    rmdir /s /q "!SAVE_PATH!" >nul 2>&1
    echo [✓] 已删除存档：!SAVE_PATH!
)

echo.
echo 完全卸载完成！

:end_prompt
echo.
echo 按任意键返回主菜单...
pause >nul
goto menu