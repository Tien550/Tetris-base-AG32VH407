@echo off
rem Nap LOGIC roi FIRMWARE cho mot moi truong: flash_all_env.bat <ten_env>   (vd: flash_all_env.bat adc)
set "PIO_EXE=%USERPROFILE%\.platformio\penv\Scripts\pio.exe"
if "%~1"=="" (
    echo Cach dung: flash_all_env.bat ^<ten_env^>   vi du: flash_all_env.bat adc
    pause
    exit /b 1
)
if not exist "%PIO_EXE%" (
    echo [ERROR] Khong tim thay pio.exe tai %PIO_EXE%
    pause
    exit /b 1
)
echo [1/2] Nap Logic CPLD...
"%PIO_EXE%" run -d "%~dp0." -e %~1 -t logic
if %ERRORLEVEL% neq 0 (
    echo [FAIL] Nap Logic that bai!
    pause
    exit /b 1
)
echo [2/2] Nap Firmware...
"%PIO_EXE%" run -d "%~dp0." -e %~1 -t upload
if %ERRORLEVEL% neq 0 (
    echo [FAIL] Nap Firmware that bai!
    pause
    exit /b 1
)
echo [OK] Nap xong moi truong %~1. Nhan RESET va xem UART.
pause
