@echo off
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0scripts"
set "PS_GUI=%SCRIPT_DIR%\husk_gui.ps1"
set "PS_RENDER=%SCRIPT_DIR%\husk_render.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_GUI%" -dropFile "%~1"
set "GUI_EXIT=%ERRORLEVEL%"

if %GUI_EXIT% equ 0 (
    :: 正常終了時はここ。pauseを書かないことで残像を防ぎます。
    powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_RENDER%"
    if %ERRORLEVEL% neq 0 pause
) else if %GUI_EXIT% equ 2 (
    :: ユーザーキャンセル時 (GUIクローズ)
    echo [INFO] Render canceled by user.
) else (
    :: GUI起動エラー
    echo [ERROR] GUI exited with code %GUI_EXIT%.
    pause
)
