@echo off
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0scripts"
set "PS_GUI=%SCRIPT_DIR%\husk_gui.ps1"
set "PS_REN=%SCRIPT_DIR%\husk_render.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_GUI%" -dropFile "%~1"
set "GUI_EXIT=%ERRORLEVEL%"

if %GUI_EXIT% equ 0 (
    :: 正常終了時はここ。pauseを書かないことで残像を防ぎます。
    powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_REN%"
    if %ERRORLEVEL% neq 0 pause
) else if %GUI_EXIT% equ 2 (
    :: レンダリングがユーザーによってキャンセルされた場合
    echo [INFO] Render canceled by user.
) else (
    :: GUI異常終了時
    echo [ERROR] GUI exited with code %GUI_EXIT%.
    pause
)