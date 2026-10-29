# Build, Synthesis & Flashing Guide

This guide walks you through compiling the firmware, synthesizing CPLD logic, and programming the **AGM AG32VH407 ("TCX" Board)**.

---

## 1. Prerequisites & Toolchain Setup

### Required Tools
* **Operating System**: Windows 10/11 (64-bit).
* **Python**: Version 3.10 or 3.11 with `pip`.
* **PlatformIO Core**: Installed via PlatformIO extension in VS Code or standalone CLI.
* **AGM AgRV Platform**: The vendor development package for AGM RISC-V devices (`framework-agrv_sdk`, `toolchain-agrv`, `tool-agrv_logic`).
* **Debug Probe**: CMSIS-DAP / DAP-Link (onboard or external USB dongle) or J-Link.

---

## 2. Compiling & Flashing Firmware (C Code)

When modifying game logic, display graphics, or button behavior in `src/`:

### Option A: Using the Provided Batch Scripts (Fastest)
Double-click or run from PowerShell:
```cmd
.\flash_app.bat
```
This runs:
```cmd
pio run --target upload --environment debug
```

### Option B: Using PlatformIO CLI Directly
```powershell
# Build firmware binary only
pio run -e debug

# Build and flash firmware to 0x80000000 via CMSIS-DAP
pio run -e debug -t upload
```

---

## 3. Building & Flashing CPLD Logic (Bitstream)

The CPLD logic controls the pixel clock, HSYNC/VSYNC timing, and HyperRAM circular DMA.

### When changing Pin Assignments (`rgb.ve`):
If you only modify pin constraints in `rgb.ve`:
```powershell
# 1. Clean previous bitstream
pio run -e debug -t logic_clean

# 2. Re-map and generate new bitstream (.pio/logic/rgb.bin)
pio run -e debug -t batch

# 3. Flash the bitstream to flash address 0x80034000
pio run -e debug -t upload_logic
```
*(Or simply run `.\flash_logic.bat`)*

### When modifying Verilog Source Code (`logic/*.v`):
If you modify `logic/fifo2rgb.v`, `logic/hram_ip.v`, or add new hardware IPs:
1. Open PowerShell and navigate to the `logic/` directory:
   ```powershell
   cd logic
   ```
2. Synthesize with **Intel Quartus II Web Edition 13.1**:
   ```powershell
   D:\Tool\Quartus\quartus\bin\quartus_sh.exe -t af_quartus.tcl
   ```
3. Run AGM Supra translation to regenerate `hram_ip/hram_ip.vx`:
   ```powershell
   %USERPROFILE%\.platformio\packages\tool-agrv_logic\bin\af.exe --batch -X "set MODE QUARTUS" -X "set FLOW ALL" -F af_run.tcl
   ```
4. Return to root and rebuild the bitstream:
   ```powershell
   cd ..
   pio run -e debug -t logic_clean
   pio run -e debug -t batch
   ```

---

## 4. Flashing Both Logic & Firmware Together
To program a fresh board from scratch with both CPLD logic and firmware:
```cmd
.\flash_all.bat
```

---

## 5. Serial Debug Logging (UART0)
The board streams boot logs, button transition events, and diagnostic data via **UART0**:
* **Baud Rate**: `115200`
* **Data Bits**: `8`
* **Parity**: `None`
* **Stop Bits**: `1`
* **Port**: Automatically detected on Windows (`COM*` via DAP-Link)

To monitor:
```powershell
pio device monitor -b 115200
```
> [!IMPORTANT]
> Always close the serial monitor before initiating an upload or image flashing session to prevent `Access Denied` port conflict errors.

