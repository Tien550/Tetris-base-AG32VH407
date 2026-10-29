# Bàn giao dự án HMI AG32 (cập nhật 28/10/2026)

Tài liệu này tóm tắt toàn bộ công việc đến thời điểm hiện tại để người/agent tiếp theo làm tiếp mà không phải khảo sát lại.
Chi tiết kỹ thuật: [hardware_notes.md](hardware_notes.md) (pin map, timing, nguồn), [bringup_log.md](bringup_log.md) (nhật ký bring-up).
**Mọi mục đánh dấu "CHƯA XÁC NHẬN" chưa được kiểm chứng trên board thật.**

---

## 1. Mục tiêu
Làm HMI cho board **AGM AG32VH407RCT6 "TCX"** (LQFP-64, RISC-V + CPLD 2K LE + HyperRAM 8 MB) với **màn TFT 5.0" 800×480 RGB** (panel `0500A013-S110100`).
Mục tiêu cuối: giao diện kiểu **máy may công nghiệp** (màn hình chính, danh sách thông số, mã lỗi, cài đặt), nút đủ lớn, phản hồi tốt, giao tiếp UART/RS485. Ngôn ngữ giao tiếp với người dùng: **tiếng Việt**.
Ràng buộc gốc: dùng SDK AgRV (PlatformIO), không sửa SDK gốc, code tách module, comment tiếng Việt ở phần phần cứng, mỗi bước phải build được.

## 2. Đã làm được và đã xác nhận trên board
| Hạng mục | Trạng thái |
|---|---|
| UART0 log (115200, COM17 qua DAP-Link) | OK |
| HyperRAM (ID `0x0C86`), đọc/ghi + DMA ~190 MB/s | OK |
| **Màn hình lên hình**, ảnh đẹp | OK (người dùng xác nhận) |
| Gửi ảnh RGB565 từ PC qua UART, hiển thị | OK |
| Thứ tự màu R/G/B đã đúng sau khi hoán đổi chân trong `rgb.ve` | OK (ảnh thật: cổ áo vàng hiện đúng) |
| Dò chân flash SPI ngoài: `ID=EF4015` (W25Q16JV) | OK, CS=PIN_61 CLK=PIN_58 DI=PIN_59 DO=PIN_62 HOLD=PIN_57 WP=PIN_2 |
| **Game Tetris Arcade 480x800 (Xoay dọc)** | OK, xoay ngược 180 độ (s_portrait_flip=1), ô 28x28 cực lớn, nền đen tuyền 0x0000, chống dội 25ms, đổi hướng 'O' |

## 3. Đã viết và build được nhưng CHƯA XÁC NHẬN trên board
- **Ảnh khởi động trong flash SPI ngoài** (`drivers/flash/w25q.c`, `drivers/lcd/boot_image.c`, lệnh `IMF!`): firmware và logic đã build (firmware 22,8 KB, logic 1103 LUT). Người dùng chưa báo đã nạp và thử `-Save`, cũng chưa thử tắt/bật nguồn.
  Tốc độ đọc/ghi bit-bang là **ước tính** (1–2 s khi khởi động); nếu chậm thì chuyển sang SPI0 phần cứng.
- Test pattern (đơn sắc, viền 1 px, lưới + 8 dải màu): chạy nhưng người dùng chưa xác nhận từng màu, viền 4 cạnh, 4 ô góc. Cần nhắc xác nhận (bấm SW2 để quay lại chu trình test).
- Board hiện nạp gì: **không biết chắc**. Người dùng đã nạp bản `probe`, bản logic ADC thử nghiệm và nhiều bản khác; nên bảo họ chạy `flash_all.bat` để chắc chắn về bản `debug` mới nhất.

## 4. Phần cứng (tóm tắt, nguồn đầy đủ ở hardware_notes.md)
- **Flash chương trình 256 KB**, nhưng logic CPLD nằm từ `0x80034000` nên **firmware chỉ dùng được ~208 KB** (đang dùng ~23 KB). SRAM 128 KB. SDK/platform AgRV **1.8.8**, `board = agrv2k_103`, `logic_device = AGRV2KL64H`, `SYSCLK 150`, **xung HyperRAM 150 MHz** (không phải 200, xem mục 12).
- **HyperRAM** `0x60000000`, 8 MB. Framebuffer RGB565 800×480×2 = 768000 B tại `0x60000000`. DMA vòng của CPLD đọc ra khối RGB (đích `0x70000000`). Ghi trực tiếp từ CPU ~20 MB/s (ghi toàn khung ~40 ms).
- **Panel**: HX Display, driver ST7262, 40 chân, **không có chân reset/DISP/SPI**, đèn nền cấp từ boost 5 V luôn bật (PIN_27 KHÔNG phải đèn nền). Datasheet trong gói AGM là `0500A001` (cùng họ, khác hậu tố với `0500A013`, chưa xác nhận là một).
  Timing panel: DCLK 23/25/27 MHz, Th 816, Tv 496. Logic hiện dùng `DCLK_DIV 6` → 25 MHz, nhưng VBP 25 / VFP 15 / Tv 522 **vượt max của datasheet**; hình vẫn ổn định.
- **Pin map thật** nằm trong [rgb.ve](../rgb.ve) (lấy từ gói AGM). HSYNC PIN_20, VSYNC PIN_15, DE PIN_16, DCLK PIN_17. LED2–4 = `GPIO4_1..3` (PIN_54/53/52, active-low). SW2 = `GPIO6_2` (PIN_51). UART0 PIN_42/43.
  **Dữ liệu RGB đã hoán đổi so với `.ve` gốc của AGM** để RGB565 chuẩn (đỏ = 0xF800) hiện đúng.
- **Flash SPI ngoài W25Q16JV 2 MB**: ảnh khởi động chiếm ~772 KB (header `0x0000`, dữ liệu `0x1000`). Còn ~1,2 MB cho font/biểu tượng/thông số.
- **Cảm ứng**: panel là **điện trở 4 dây** (XR/YD/XL/YU = FPC chân 37–40), nhưng **sơ đồ board: FPC1 chân 35–40 là NC (dấu X)** → 4 dây điện trở **không nối vào MCU**. FPC2 (6 chân) chỉ có `TP_SDA/SCL/RST/INT` → cảm ứng **điện dung I2C** (AGM: SDA PIN_9, SCL PIN_10, INT PIN_14, RST PIN_11). Panel điện trở hiện tại **không dùng được** với FPC2.

## 5. Cấu trúc dự án
```
HMI/
  platformio.ini      env: debug (mặc định), release, lvgl8 (cũ, chưa dùng)
  rgb.ve              pin map + clock (SYSCLK 150, PLL cho HyperRAM)
  flash_all.bat       nạp logic + firmware (env debug)  ← dùng chính
  flash_app.bat / flash_logic.bat / flash_env.bat <env> / flash_all_env.bat <env>
  logic/              IP HyperRAM + RGB (Verilog) và dự án Quartus/af. hram_ip/hram_ip.vx là netlist đã tổng hợp
  src/
    main.c            khởi tạo, boot image, chu trình test pattern, nhận ảnh UART
    board_hw.c/h      LED, SW2
    drivers/lcd/      hram.*, lcd_rgb.* (khởi tạo DMA, vẽ điểm/đường), lcd_image_rx.* (nhận ảnh UART), boot_image.* (flash)
    drivers/flash/    w25q.* (driver W25Q16 bit-bang)
    lv_conf.h         chưa dùng
  tools/
    img2rgb565.py     ảnh → RGB565 800×480 (.raw) + xem trước; --cx --cy --rotate
    send_image.ps1    gửi .raw qua UART; -Save để lưu làm ảnh khởi động
  docs/               hardware_notes.md, bringup_log.md, HANDOFF.md
```
**Chưa có README.md** (yêu cầu gốc) và chưa có thư mục `ui/`, `app/`, `touch/`.

## 6. Cách build và nạp
- PlatformIO không có trong PATH. Dùng `%USERPROFILE%\.platformio\penv\Scripts\pio.exe`.
- Build firmware: `pio run -e debug`.
- **Build logic**: `pio run -e debug -t logic_clean` rồi `pio run -e debug -t batch` (mất ~30–50 s). **Bắt buộc `logic_clean` sau khi đổi `.ve`**, nếu không bản logic cũ được dùng lại. `.pio/logic` dùng chung giữa các env.
- Nạp: `flash_all.bat` (logic + firmware). Chỉ sửa C thì `flash_app.bat` hoặc `flash_env.bat debug`.
- Gửi ảnh (đóng serial monitor trước, COM17):
  `powershell -ExecutionPolicy Bypass -File tools\send_image.ps1 -File tools\anh.raw -Port COM17 [-Save]`
  Chuyển ảnh: `python tools\img2rgb565.py anh_goc.jpg tools\anh.raw [--cy 0.36] [--rotate 90]` (cần Pillow, numpy; có sẵn).
- **Giao thức UART0 (115200 8N1)**: PC gửi `IMG!` (chỉ hiển thị) hoặc `IMF!` (hiển thị + lưu flash) → board trả `K` → 768000 byte RGB565 little-endian → với `IMF!` board xoá/ghi/kiểm tra checksum rồi trả `S` (ok) hoặc `E`. Board bỏ dở nếu 2 s không có byte. Ảnh chỉ bị xoá khỏi flash **sau khi nhận đủ**.
- Bật nguồn: nếu flash có ảnh hợp lệ → hiển thị và giữ; **SW2** để vào chu trình test pattern.

## 7. Bài học và cạm bẫy (QUAN TRỌNG)
1. **Pin map của ví dụ SDK `HyperRAM/rgb` là của board tham chiếu khác.** Màn hình đen nhiều vòng vì dùng nhầm. Pin map đúng nằm trong gói AGM `agrv2kl64h_example_800x480_touch.zip` (xem mục 10). Khi thiết bị "có tín hiệu mà không phản hồi", kiểm tra pin map với tài liệu nhà bán trước khi thử polarity/init.
2. **Sửa RTL của `hram_ip.v` KHÔNG có hiệu lực** nếu chỉ chạy `pio ... -t logic`. Netlist `logic/hram_ip/hram_ip.vx` là bản đã tổng hợp; muốn đổi RTL phải chạy lại Quartus + af (mục 8). Chỉ `rgb.ve` và firmware đổi được nhanh.
3. **Quartus Web Edition 13.1 (có ở `D:\Tool\Quartus\quartus\bin`) không hỗ trợ incremental compilation** → partition giữ lõi cứng `alta_adc` bị gỡ → ADC bị tổng hợp thành mô hình giả → ADC không bao giờ trả EOC. Hướng ADC trong CPLD **bị chặn** trừ khi có Quartus có giấy phép đó, hoặc nhờ AGM build sẵn. Luồng native (Yosys+af) giữ được `alta_adc` nhưng lỗi chân DDR ở cấp chip.
4. **Thứ tự màu**: `.ve` gốc của AGM đặt nhóm đỏ ở `rgb_data[0..4]` (BGR565). Đã hoán đổi. Đừng khôi phục.
5. **Timing logic**: với xung HyperRAM 200 MHz dữ liệu ghi bị sai bit (mục 12). Ở 150 MHz các khe giữa miền xung đã dương; còn lại worst setup ≈ −0,6 ns ở chính SYSCLK 150 MHz (có từ đầu, chưa thấy ảnh hưởng).
6. COM17 thường đang bị serial monitor chiếm → script gửi ảnh/đọc log báo "Access denied". Đừng giành cổng, bảo người dùng đóng monitor.
7. **Khi ghi chuỗi C có `\n` qua heredoc/Python trong shell**, `\n` dễ bị biến thành xuống dòng thật → lỗi biên dịch "missing terminating". Dùng công cụ sửa file trực tiếp (Edit/Write) cho chuỗi C.
8. Flash SPI ngoài và mọi flash đều giới hạn ~100 000 chu kỳ xoá/khối (con số từ trí nhớ về dòng W25Q, chưa đọc datasheet W25Q16JV): **không ghi bộ đếm liên tục** (vd. mỗi mũi may); ghi khi dừng máy/theo chu kỳ dài, hoặc dùng FRAM/EEPROM.
9. Số liệu về ST7262/panel/IC: "ST7262" ban đầu là giả định không nguồn, sau này khớp với datasheet gói AGM. Chuỗi init SPI ST7701 của SDK **không cần** và đã bỏ (board không có chân SPI/RESET cho LCD).

## 8. Tổng hợp lại IP logic bằng Quartus (khi cần sửa RTL)
Chạy trong thư mục `logic/` (mất ~2 phút):
1. `D:\Tool\Quartus\quartus\bin\quartus_sh.exe -t af_quartus.tcl` → tạo `simulation/modelsim/hram_ip.vo`.
2. `%USERPROFILE%\.platformio\packages\tool-agrv_logic\bin\af.exe --batch -X "set MODE QUARTUS" -X "set FLOW ALL" -F af_run.tcl` → ghi `hram_ip/hram_ip.vx`.
3. `pio run -e debug -t logic_clean` + `-t batch`.
Sao lưu `hram_ip/hram_ip.vx` trước. Bản `.vx` gốc đã kiểm chứng hiển thị tốt (1103 LUT).

## 9. Việc tiếp theo (đề xuất, theo thứ tự)
1. Người dùng **nạp lại `flash_all.bat`** rồi thử `-Save`, tắt/bật nguồn, xác nhận ảnh khởi động tự hiện. Báo tốc độ khởi động; nếu chậm → SPI0 phần cứng.
2. Xác nhận test pattern (màu, viền 4 cạnh, 4 ô góc, hướng hiển thị).
3. **Giao diện LVGL 8** (chưa làm). `lib_deps = lvgl/lvgl@^8.4` đã có trong env `lvgl8` và `.pio/libdeps/lvgl8`; ví dụ AGM `lvgl8_test.c` + `lv_conf.h` ở gói AGM làm mẫu. Flush vào HyperRAM bằng `memcpy` từng dòng; buffer vẽ trong SRAM (~HLINES×VLINES/20 trong ví dụ AGM); tick bằng MTIMER; **chế độ vẽ từng phần**.
   Đo flash/RAM thật của LVGL + giao diện (flash chương trình chỉ còn ~185 KB, AGM cũng cảnh báo "flash không đủ").
4. Màn hình kiểu máy may: chính (tốc độ, số mũi, trạng thái), danh sách thông số, mã lỗi, cài đặt. Font có dấu tiếng Việt (`lv_font_conv`) và biểu tượng đặt trong **flash SPI ngoài** (chưa có cơ chế đọc font ngoài).
5. Điều khiển khi chưa có cảm ứng: **SW2 + UART**, rồi **phím vật lý** vào các chân trống PIN_9, 10, 11, 14 (nối xuống GND, kéo lên trong).
6. Giao tiếp UART/RS485 (giao thức chưa chốt; đề xuất ASCII đơn giản để thử rồi Modbus).
7. Lưu thông số máy trong flash SPI với giới hạn ghi/wear leveling.
8. Viết `README.md` (hướng dẫn build/nạp) và danh sách kiểm chứng cuối (yêu cầu gốc).
9. Đã bỏ mục "độ sáng trong màn hình cài đặt": đèn nền luôn bật, không có chân điều khiển.

## 10. Quyết định đang chờ người dùng
- **Cảm ứng** (chưa chọn):
  - **B**: XPT2046 (SPI) + hàn 4 dây từ đuôi panel; không đổi logic. Shop ICDayRoi chỉ bán IC trần TSSOP-16 (7.000 đ); cần module hoặc đế chuyển. Sơ đồ chân XPT2046 trong tài liệu là từ trí nhớ, cần đối chiếu datasheet.
  - **C / mua board VGT6** (LQFP-100, flash 1 MB, cảm ứng điện dung I2C, có ví dụ). AGM trả lời: ví dụ + sơ đồ chỉ gửi **sau khi đặt hàng**, và không khuyến nghị board hiện tại cho cảm ứng. Người dùng đã nhắn họ là "sẽ sớm mua VGT6"; chưa rõ giá có kèm màn hay không (¥15,45 trong tin).
  - **A** (ADC trong CPLD): bị chặn (mục 7.3). Có thể nhờ AGM/TCX build sẵn logic HyperRAM+RGB+ADC.
- Có chuyển hẳn sang VGT6 cho sản phẩm hay không: phần lớn code dùng lại được; **phải đổi `rgb.ve`, `board`, `logic_device`** theo ví dụ họ gửi.
- Số màn hình, ngôn ngữ (Việt/Trung), thao tác bằng phím hay cảm ứng (câu hỏi cuối của tôi chưa được trả lời).
- Công cụ thiết kế UI (SquareLine/EEZ Studio) hay viết LVGL bằng mã: đề xuất viết mã tay để kiểm soát flash.
- Người dùng cũng hỏi "ezz gì đó để vẽ": đã trả lời; chưa rõ họ muốn nói EasyBuilder (chỉ cho HMI thương mại) hay EEZ Studio.

## 11. Tài liệu và liên hệ
- Gói AGM (thư mục Downloads của người dùng, **không nằm trong repo**):
  - `AG32VH407RCT6(AGRV2KL64H)_touch\...\agrv2kl64h_example_800x480_touch.zip` → `64pinH/mcu/HyperRAM/rgb/` (rgb.ve, logic, LVGL, driver cảm ứng I2C) — **nguồn pin map đúng**.
  - `SCH_AGRV2KL64H_2025-02-15（带触摸）.pdf` (sơ đồ board có cảm ứng — đúng board của người dùng), `AG32开发资料汇总（10月27日更新）\...\RGB屏幕资料.pdf` (datasheet panel), `AG32VH407RCT6_V2原理图.pdf` (board V2, không cảm ứng), `MANUAL_AG32VH_HyperRAM.pdf`, tài liệu CPLD/ADC, `agm_rgb_debug_batch(RGB_Test).bin` (logic+firmware nạp sẵn của AGM).
- Người bán: **上海天晨芯科技有限公司 (TCX)**, liên hệ 姚先生 (số trong tin Alibaba người dùng chụp); cung cấp hỗ trợ kỹ thuật chính hãng AGM.
- SDK: `D:\TT\AgRV_pio` (không sửa) và bản cài `C:\Users\User\.platformio\platforms\AgRV` (VERSION 1.8.8, **đây là bản dùng để build**). Người dùng có bản 1.9.2 trên Baidu (chưa tải, chưa cài). Các thư mục `D:\TT\Project_AGM\*` khác là dự án mẫu/RS485 không liên quan (docs RS485/ag32 mô tả **board khác**: VF303 LQFP-48).
- Công cụ: Quartus II 13.1 Web Edition `D:\Tool\Quartus`; Python 3.11 + Pillow + numpy; chưa có pyserial, poppler (dùng pypdf để trích văn bản PDF).

## 12. Lỗi hiển thị nửa màn hình khi chơi Tetris (29/10/2026) — ĐÃ XỬ LÝ
- Triệu chứng: nửa màn dọc bên trái (khoảng 30% khung hình, các hàng vật lý cuối, địa chỉ >= 0x80000) có bản sao rác, chữ "T" của TETRIS biến mất. Lỗi **không phụ thuộc cách vẽ** (ghi 16-bit, ghi 32-bit tuần tự, DMAC từng dòng, CPU đều hỏng giống nhau).
- Chẩn đoán: `env:diag` ghi mẫu theo địa chỉ rồi đọc lại bằng CPU và bằng DMA của CPLD → hai đường cho cùng lỗi (86875 từ sai): bit 7 và bit 23 sai ở mọi khối, khối >= 512 KB sai nặng hơn. Tức dữ liệu **lưu sai trong HyperRAM**.
- Nguyên nhân (người dùng xác nhận đã hết lỗi): **xung HyperRAM 200 MHz quá sát**. Báo cáo định thời của bản 200 MHz có khe hở âm giữa miền SYSCLK và hbus_clk (-3,3 ns / -1,5 ns). Đặt `PLLCLK3`/`PLLCLK4` = **150** trong `rgb.ve` đưa các khe đó thành dương (+2,4 / +1,6 ns). Băng thông vẫn dư (màn cần ~46 MB/s).
- Mọi bản logic dựng với 200 MHz đều có nguy cơ này; test pattern trước đó cũng có thể đã sai nhưng khó thấy. Đã bỏ các thử nghiệm sai hướng: FCB pull-up vẫn giữ mặc định (chỉ tắt bằng `-D HMI_NO_FCB` trong env diag).
- Code vẽ Tetris đã chuyển sang "tile" SRAM + DMAC (`games/tetris/tetris.c`) và chỉ vẽ lại ô thay đổi: không phải nguyên nhân lỗi nhưng làm vòng lặp nhanh hơn (hết lỡ phím); giữ lại.
- Công cụ: `pio run -e diag` + `flash_env.bat diag` chạy kiểm tra bộ nhớ (`[MEM]` trên UART, kỳ vọng "tong so tu sai = 0") rồi 4 mẫu hình. Dùng lại khi đổi logic/xung.
- Bài học: khi hình hỏng ổn định theo vùng địa chỉ, **kiểm tra bộ nhớ bằng đọc lại và so sánh** trước khi sửa mã vẽ; đọc báo cáo định thời (Worst setup giữa các miền xung) của logic.

## 13. Dọn dẹp ngày 29/10/2026 (theo yêu cầu "về dự án gốc, giữ Tetris")
- Đã xoá khỏi dự án: env `adc`, `diag`, `diag150`; `src/diag/` (chương trình kiểm tra bộ nhớ), `src/drivers/adc/`, `logic/adc_variant/`, `rgb150.ve`, các file `hmi_app_*_batch.bin`. Cờ `HMI_NO_FCB` đã gỡ (mã FCB trở lại như ban đầu).
- Còn giữ: Tetris, ảnh khởi động + flash W25Q, nhận ảnh UART, `rgb.ve` với xung HyperRAM 150 MHz, **timing RGB theo datasheet** (HPW/VPW 4, HBP/VBP 4, HFP/VFP 8, Th 816, Tv 496, thay cho 2/25/15/2/43/8 của SDK) trong `logic/hram_ip.v` (đã tổng hợp lại bằng Quartus, 1122 LUT), bộ giám sát DMA quét màn hình trong `tetris_run()` (in `[DMA]` trên UART khi trạng thái đổi).
- Bản sao lưu trước khi dọn: `hmi_before_cleanup.tgz` trong thư mục scratchpad của phiên làm việc (có thể không còn). Các mô tả về hướng ADC và chương trình `diag` ở các mục 7 và 12 giữ lại làm tài liệu lịch sử; mã tương ứng không còn trong repo.
- **Lỗi chập chờn chưa có nguyên nhân (29/10/2026):** màn hình tự đen rồi tự hết đen, không cần reset; khi đen thì LED2 vẫn nháy, đèn nền vẫn sáng. Đã thử: xung HyperRAM 150 MHz (hết lỗi bộ nhớ), timing theo datasheet. Cần quan sát `[DMA]` trên UART lúc màn đen: nếu DMA vẫn chạy thì lỗi ở phía panel/cáp/nguồn; nếu `DMA QUET BI DUNG` thì lỗi ở logic/HyperRAM/nguồn chip.
