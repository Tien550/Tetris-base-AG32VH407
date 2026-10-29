@echo off
set "PIO_EXE=%USERPROFILE%\.platformio\penv\Scripts\pio.exe"
if not exist "%PIO_EXE%" (
    echo [ERROR] Khong tim thay pio.exe tai %PIO_EXE%
    pause
    exit /b 1
)
echo [1/1] Dang nap Firmware chuong trinh...
"%PIO_EXE%" run -d "%~dp0." -e debug -t upload
if %ERRORLEVEL% equ 0 (
    echo [OK] Nap Firmware thanh cong!
) else (
    echo [FAIL] Nap Firmware that bai. Kiem tra ket noi DAP-Link!
)

