# Ghi chú phần cứng HMI AG32VH407RCT6 + TFT 5.0" 800×480

Cập nhật: 28/10/2026. Mọi số liệu dưới đây có nguồn; mục nào chưa kiểm chứng được ghi rõ.

## 1. Nguồn tài liệu (do TCX/AGM cung cấp, thư mục Downloads của người dùng)
| Ký hiệu | Tài liệu |
|---|---|
| [A] | `AG32VH407RCT6(AGRV2KL64H)_touch/agrv2kl64h_example_800x480_touch.zip` → `64pinH/mcu/HyperRAM/rgb/` (`rgb.ve`, `logic/`, `src/`) |
| [B] | `AG32开发资料汇总/.../AG32VH407RCT6_V2_64pin/RGB屏幕资料.pdf` (datasheet HX Display) |
| [C] | `.../AG32VH407RCT6_V2原理图.pdf` (board V2, **không** cảm ứng) |
| [D] | `AG32VH407RCT6(AGRV2KL64H)_touch/SCH_AGRV2KL64H_2025-02-15（带触摸）.pdf` — đúng board của bạn, **chưa đọc được** (PDF vector) |

## 2. Board
- MCU AG32VH407RCT6 (LQFP-64, RISC-V + CPLD 2K LE + HyperRAM 64 Mbit = 8 MB). SDK/platform AgRV **1.8.8**; board PlatformIO `agrv2k_103`, `logic_device = AGRV2KL64H`. `SYSCLK 150` MHz, `HSECLK 8`.
- Framebuffer RGB565 800×480×2 = 768000 B nằm ở HyperRAM `0x60000000`; DMA vòng của CPLD đọc ra khối RGB (đích `0x70000000`).
- **Đèn nền cấp từ boost trên board (5 V), luôn bật, không có chân điều khiển** [B][C].
- **Board không có chân reset / DISP / SPI / EN cho LCD** [A][C]. (Dự án cũ gán GPIO1_0..3,7 theo ví dụ SDK: sai.)

## 3. Panel
Datasheet [B] là của **HX Display (Hongxian) `0500A001-S1I0100`**, driver **ST7262**. Panel của bạn là `0500A013-S110100`: **cùng họ nhưng khác hậu tố — chưa xác nhận hai mã là một**.
- 5.0", 800(RGB)×480, 40 chân, đầu vào 24-bit RGB (board nối RGB565), VCC 3.3 V, IOVCC 1.8–3.3 V.
- Đèn nền 12 LED, 40 mA, Vf 18 V (nên ~16.8–19.2 V).
- Chân FPC (40): 1 LEDK, 2 LEDA, 3 GND, 4 VCC, 5–12 R0–R7, 13–20 G0–G7, 21–28 B0–B7, 29 GND, 30 PCLK, **31 NC**, 32 HS, 33 VS, 34 DE, 35 NC, 36 GND, 37–40 XR/YD/XL/YU (NC).
- Timing đầu vào [B] (typ; trong ngoặc là max):

| | Fclk | Th | Thw | Thbp | Thfp | Tv | Tvw | Tvbp | Tvfp |
|---|---|---|---|---|---|---|---|---|---|
| Giá trị | 25 MHz (23–27) | 816 (≤896) | 4 (≤8) | 8 (≤48) | 8 (≤48) | 496 (≤504) | 4 (≤8) | 8 (≤12) | 8 (≤12) |

- Xung HyperRAM: **150 MHz** (đã xác nhận trên board; 200 MHz làm sai bit dữ liệu, xem HANDOFF mục 12). Logic hiện dùng (từ [A], giống ví dụ SDK): `DCLK_DIV 6` → **25 MHz** (đúng), HPW 2 / HBP 43 / HFP 8 → Th 853, VPW 2 / VBP 25 / VFP 15 → Tv 522, sync âm, `DCLKPOL 0`. **Tv, VBP, VFP vượt giới hạn max của datasheet**; AGM dùng chính bộ này trong demo của họ. Nếu panel đã sáng hình mà không ổn định, thử `HPW 4 / HBP 4 / HFP 8, VPW 4 / VBP 4 / VFP 8` (Th 816, Tv 496, 61.8 Hz) và thử `DCLKPOL 1`.
- Cạnh chốt DCLK mặc định của ST7262 trong datasheet: chưa xác định được từ biểu đồ.

## 4. Pin mapping (từ [A] `rgb.ve`)
| Chức năng | Chân MCU |
|---|---|
| HSYNC / VSYNC / DE / DCLK | PIN_20 / PIN_15 / PIN_16 / PIN_17 |
| R3..R7 (`rgb_data[11..15]`) | PIN_40, 41, 38, 39, 36 |
| G2..G7 (`rgb_data[5..10]`) | PIN_37, 34, 35, 29, 33, 27 |
| B3..B7 (`rgb_data[0..4]`) | PIN_28, 24, 26, 21, 23 |
| LED2 / LED3 / LED4 (`GPIO4_1..3`, active-low) | PIN_54 / 53 / 52 |
| Nút SW2 (`GPIO6_2`) | PIN_51 |
| UART0 TX / RX | PIN_42 / PIN_43 |
| Flash SPI ngoài W25Q16JV 2 MB (ĐÃ ĐO bằng chương trình dò, ID EF4015) | CS = PIN_61, CLK = PIN_58, DI = PIN_59, DO = PIN_62, HOLD = PIN_57, WP = PIN_2 (GPIO3_0..5 trong `rgb.ve`) |
| 4 Nút nhấn ngoài Header H1 (Tetris Controls, Active-Low) | PIN_9 (Trái), PIN_10 (Xoay), PIN_11 (Phải), PIN_14 (Rơi nhanh) -> GPIO2_0..3 trong rgb.ve |
| Cảm ứng FPC2 (điện dung, theo [A]) | I2C0 SDA PIN_9, SCL PIN_10, INT PIN_14, RST PIN_11 |

> **Thứ tự màu (28/10/2026):** `rgb.ve` gốc của AGM đặt nhóm đỏ ở `rgb_data[0..4]` (BGR565): ảnh RGB565 chuẩn hiện sai màu (da thành xanh lam, xác nhận bằng ảnh thật). Đã hoán đổi hai nhóm chân trong `rgb.ve` để dùng RGB565 chuẩn (đỏ = 0xF800). Cần nạp lại logic.

### 4b. Ảnh khởi động (flash SPI ngoài)
- Bố cục: `0x0000` header 16 byte (`HIMG`, 800, 480, 768000, checksum) ghi **sau cùng**; `0x1000` dữ liệu RGB565 800x480 (768000 byte). Dùng khối 64 KB 0..11.
- Khi bật nguồn: `boot_image_show()` đọc ảnh vào framebuffer (bit-bang GPIO, ước tính 1-2 s) rồi giữ ảnh; SW2 để xem test pattern.
- Nạp từ máy tính (UART0 115200): `tools\send_image.ps1 -File toolsnh.raw -Save`. Giao thức: `IMF!` -> board trả `K` -> 768000 byte -> board xoá/ghi/kiểm tra checksum -> trả `S` (ok) hoặc `E`. `IMG!` chỉ hiển thị, không lưu.

## 5. Cảm ứng — ĐÃ XÁC NHẬN: board không nối cảm ứng điện trở
- Sơ đồ [D] (ảnh người dùng chụp, 28/10/2026): FPC1 chân **35–40 là no-connect (dấu X)**. Cảm ứng điện trở của panel (37 XR, 38 YD, 39 XL, 40 YU, khớp datasheet [B]) **không tới MCU**. Chân 31 nối 3.3 V.
- FPC2 (6 chân, AFA07-S06ECA) = `TP_SDA, TP_SCL, TP_RST, TP_INT`, 3.3 V, GND (+ kéo lên 4.7 kΩ cho SDA/SCL): chỉ dành cho cảm ứng **điện dung** I2C. AGM gán I2C0 SDA/SCL = PIN_9/PIN_10, INT = PIN_14, RST = PIN_11.
- Để dùng cảm ứng điện trở phải hàn 4 dây từ đuôi cảm ứng của panel ra ngoài:
  - Hướng A: vào PIN_9/10/11/14 (đều có kênh ADC) và thêm khối ADC (`analog_ip`) vào logic (ADC là IP trong CPLD, mặc định `0x60000000` trùng HyperRAM, cần đổi địa chỉ; CPLD hiện 58% LE).
  - Hướng B: module XPT2046 (SPI).
- Hướng còn lại: panel cảm ứng điện dung cắm FPC2 (driver I2C có sẵn trong gói AGM).

### 5b. Hướng A (ADC trong CPLD) — CHƯA DÙNG ĐƯỢC (28/10/2026)
- ADC của AG32 là IP trong CPLD (`analog_ip.v`, +~300 LE) và phải là lõi cứng `alta_adc`. Đã viết bản `hram_ip` có ADC0 ở `0x61010000`; firmware ở `src/drivers/adc/` (bật bằng `-D HMI_ADC_TEST`, env `adc`). (Mã thử nghiệm đã bị xoá khỏi repo ngày 29/10/2026; logic đang dùng là bản KHÔNG có ADC.)
- Quartus II 13.1 Web Edition có ở `D:\Tool\Quartus\quartusin`. Tổng hợp lại IP: `quartus_sh -t af_quartus.tcl` rồi `af.exe --batch -X "set MODE QUARTUS" -X "set FLOW ALL" -F af_run.tcl`. Mọi sửa RTL của `hram_ip` đều phải làm vậy (FIFO `dcfifo_mixed_widths`); chỉ sửa `rgb.ve`/firmware thì không cần.
- **Vì sao ADC không chạy:** Quartus ghi "Current license file does not support incremental compilation… removes all user-specified partitions". Quy trình AGM dựa vào partition để giữ `alta_adc` thành lõi cứng; không có nó, `alta_adc` bị tổng hợp thành mô hình giả (`eoc = sclk`, `db = const`). Trên board: ghi/đọc thanh ghi ADC đúng (`CHNL=0x0503`) nhưng EOC không bao giờ lên (`TIMEOUT`).
- Đã thử: black box `syn_black_box` (không hiệu quả); luồng native Yosys+af giữ được `alta_adc` nhưng ở cấp chip lỗi `Failed to find ddio logic tile` / `Exhaust all IO resources` ở chân `hbus_adq`.
- Còn lại: (a) Quartus có incremental compilation; (b) nhờ AGM/TCX build sẵn logic gồm HyperRAM + RGB + ADC; (c) cảm ứng bằng XPT2046 (không cần đổi logic).

## 6. Chưa kiểm chứng
- Hai mã panel A001 và A013 có giống nhau không.
- Thứ tự bit R/G/B và hướng hiển thị trên màn hình thật.
