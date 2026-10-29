# Hardware Pinout & Wiring Specification

This document provides the hardware pin connections for the **AG32VH407RCT6 / AGRV2KL64H ("TCX" Board)** driving the **5.0" RGB 800×480 TFT LCD (ST7262)** and external arcade control buttons.

---

## 1. External Pushbutton Controls (Header H1)

The control buttons are wired to the first 4 pins of **Header H1 (2.0mm pitch 2x12 header)** on the TCX board.

| Button Function | Header H1 Pin | AGM Physical Pin | GPIO Mapping | Pad ID (`agrv2k_pins.h`) | Internal Pull Mode | Description |
|---|---|---|---|---|---|---|
| **MOVE LEFT** | **Pin 1** | `PIN_9` | `GPIO2_0` | `AGRV2KL64_PIN_9_ID` (52) | Pull-Up (50 kΩ) + Auto-Polarity | Move falling tetromino left |
| **ROTATE** | **Pin 2** | `PIN_10` | `GPIO2_1` | `AGRV2KL64_PIN_10_ID` (53) | Pull-Up (50 kΩ) + Auto-Polarity | Rotate clockwise (Single-shot) |
| **MOVE RIGHT** | **Pin 3** | `PIN_11` | `GPIO2_2` | `AGRV2KL64_PIN_11_ID` (54) | Pull-Up (50 kΩ) + Auto-Polarity | Move falling tetromino right |
| **HARD DROP** | **Pin 4** | `PIN_14` | `GPIO2_3` | `AGRV2KL64_PIN_14_ID` (57) | Pull-Up (50 kΩ) + Auto-Polarity | Instantly drop tetromino |
| **GND** | **Header H1 Pin 23/24** or Board GND | — | GND | — | Reference Ground | Common ground for pushbuttons |

> [!TIP]
> **Auto-Polarity Feature**: You can wire buttons either:
> 1. Between the signal pin and **GND** (Active-Low, default recommended).
> 2. Between the signal pin and **3.3V** with a pull-down resistor (Active-High).
> 
> The firmware measures the idle voltage baseline at boot and automatically configures the trigger logic!

---

## 2. Onboard User Controls & Indicators

| Component | Physical Pin | Port / Bit | Active State | Description |
|---|---|---|---|---|
| **SW2 (Button)** | `PIN_51` | `GPIO6_2` | Low (GND) | Pause / Resume / Restart Game |
| **LED L2** | `PIN_54` | `GPIO4_1` | Low (GND) | Hardware Trap / Panic Indicator |
| **LED L3** | `PIN_53` | `GPIO4_2` | Low (GND) | General Status / Heartbeat |
| **LED L4** | `PIN_52` | `GPIO4_3` | Low (GND) | DMA Active Indicator |
| **UART0 TX** | `PIN_43` | `USART0_TX` | — | Serial Debug Log (115200 8N1) |
| **UART0 RX** | `PIN_42` | `USART0_RX` | — | Serial Command / Image Upload |

---

## 3. 5.0" RGB LCD (40-Pin FPC) Pinout

The 5.0" TFT LCD panel (`0500A013-S110100` with ST7262 driver IC) connects to the onboard 40-pin 0.5mm FPC connector (`FPC1`).

### Control Lines
| Signal | LCD FPC Pin | AGM Physical Pin | Direction | Description |
|---|---|---|---|---|
| **DCLK** | Pin 30 | `PIN_17` | Output (CPLD) | Pixel Clock (~25 MHz) |
| **DE** | Pin 34 | `PIN_16` | Output (CPLD) | Data Enable |
| **HSYNC** | Pin 32 | `PIN_20` | Output (CPLD) | Horizontal Synchronization |
| **VSYNC** | Pin 33 | `PIN_15` | Output (CPLD) | Vertical Synchronization |
| **DISP** | Pin 31 | — | N/C | Internally pulled high on panel |
| **RESET** | Pin 4 | — | N/C | Handled by internal power-on circuit |
| **BACKLIGHT +** | Pins 1, 2 | 5V Boost Rail | Power | Always-on LED backlight anode |
| **BACKLIGHT -** | Pins 3, 4 | Boost Return | Power | LED backlight cathode |

### RGB565 / RGB888 Color Bus Mapping (`rgb.ve`)
```
Red   (5 bits): R[4:0] -> PIN_37, PIN_38, PIN_39, PIN_40, PIN_41
Green (6 bits): G[5:0] -> PIN_29, PIN_30, PIN_31, PIN_32, PIN_35, PIN_36
Blue  (5 bits): B[4:0] -> PIN_21, PIN_22, PIN_25, PIN_26, PIN_28
```

---

## 4. Header H1 Pin Map (Physical Layout)

```
        +----------------------------------------+
 Pin 1  | [O] PIN_9  (BTN_LEFT)   | PIN_10 [O]   | Pin 2  (BTN_ROTATE)
 Pin 3  | [O] PIN_11 (BTN_RIGHT)  | PIN_14 [O]   | Pin 4  (BTN_DROP)
 Pin 5  | [O] TFT_VS (PIN_15)     | TFT_DE [O]   | Pin 6  (PIN_16)
 Pin 7  | [O] TFT_CLK(PIN_17)     | TFT_HS [O]   | Pin 8  (PIN_20)
 Pin 9  | [O] LCD_B0 (PIN_21)     | LCD_B1 [O]   | Pin 10 (PIN_22)
 Pin 11 | [O] LCD_B2 (PIN_25)     | LCD_B3 [O]   | Pin 12 (PIN_26)
 Pin 13 | [O] LCD_B4 (PIN_28)     | LCD_G0 [O]   | Pin 14 (PIN_29)
 Pin 15 | [O] LCD_G1 (PIN_30)     | LCD_G2 [O]   | Pin 16 (PIN_31)
 Pin 17 | [O] LCD_G3 (PIN_32)     | LCD_G4 [O]   | Pin 18 (PIN_35)
 Pin 19 | [O] LCD_G5 (PIN_36)     | LCD_R0 [O]   | Pin 20 (PIN_37)
 Pin 21 | [O] LCD_R1 (PIN_38)     | LCD_R2 [O]   | Pin 22 (PIN_39)
 Pin 23 | [O] LCD_R3 (PIN_40)     | LCD_R4 [O]   | Pin 24 (PIN_41)
        +----------------------------------------+
```

> [!WARNING]
> Pins 5 through 24 on Header H1 are directly wired in parallel to the high-speed LCD RGB bus. **Do NOT connect pushbuttons or external pull resistors to Pins 5–24**, as this will cause video display corruption or bus contention.

