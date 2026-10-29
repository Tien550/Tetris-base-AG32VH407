@echo off
rem Nap firmware cho mot moi truong bat ky: flash_env.bat <ten_env>   (vd: flash_env.bat diag_en)
set "PIO_EXE=%USERPROFILE%\.platformio\penv\Scripts\pio.exe"
if "%~1"=="" (
    echo Cach dung: flash_env.bat ^<ten_env^>   vi du: flash_env.bat diag_en
    pause
    exit /b 1
)
if not exist "%PIO_EXE%" (
    echo [ERROR] Khong tim thay pio.exe tai %PIO_EXE%
    pause
    exit /b 1
)
"%PIO_EXE%" run -d "%~dp0." -e %~1 -t upload
if %ERRORLEVEL% equ 0 (
    echo [OK] Nap xong moi truong %~1. Nhan RESET va xem UART.
) else (
    echo [FAIL] Nap that bai. Kiem tra ket noi DAP-Link!
)
pause
