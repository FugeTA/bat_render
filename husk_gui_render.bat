@echo off
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0scripts"
set "PS_GUI=%SCRIPT_DIR%\husk_gui.ps1"
set "PS_LOG=%SCRIPT_DIR%\husk_logger.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_GUI%" -dropFile "%~1"

if %ERRORLEVEL% equ 0 (
    :: 正常終了時はここ。pauseを書かないことで残像を防ぎます。
    powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_LOG%"
    if %ERRORLEVEL% neq 0 pause
) else (
    :: キャンセルやエラー時のみ止める
    echo [INFO] Render Canceled.
)