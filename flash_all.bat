@echo off
set "PIO_EXE=%USERPROFILE%\.platformio\penv\Scripts\pio.exe"
if not exist "%PIO_EXE%" (
    echo [ERROR] Khong tim thay pio.exe tai %PIO_EXE%
    pause
    exit /b 1
)

echo ========================================================
echo [1/2] Dang nap Logic CPLD...
echo ========================================================
"%PIO_EXE%" run -d "%~dp0." -e debug -t logic
if %ERRORLEVEL% neq 0 (
    echo [FAIL] Nap Logic CPLD that bai!
    pause
    exit /b 1
)

echo ========================================================
echo [2/2] Dang nap Firmware chuong trinh...
echo ========================================================
"%PIO_EXE%" run -d "%~dp0." -e debug -t upload
if %ERRORLEVEL% neq 0 (
    echo [FAIL] Nap Firmware that bai!
    pause
    exit /b 1
)

echo ========================================================
echo [THANH CONG] Da nap xong Logic va Firmware!
echo ========================================================

