# Nhật ký Kiểm chứng Bring-up Phần cứng HMI AG32

Dự án: **HMI 5.0" RGB 800x480 trên MCU AGM AG32VH407RCT6 (Board TCX)**  
Cập nhật: **28/10/2026**

---

## 1. Trạng thái Phần Cứng & Build

### A. Định danh phần cứng xác nhận từ mạch thật
- **MCU Chip**: `AG32VH407RCT6` (LQFP-64, RV32IMAFC, 256 KB Flash, tích hợp sẵn SiP 64Mbit / 8MB HyperRAM).
- **Màn hình**: Panel 5.0" RGB 800x480 (`0500A013-S110100` / `IQIKHHQL-A`).
- **Cảm ứng**: 4-wire điện trở (Cáp FPC in rõ thứ tự: `YU`, `XL`, `YD`, `XR` -> nối chân MCU `PIN_9`, `PIN_11`, `PIN_15`, `PIN_17`).
- **3 LED trạng thái thực tế**: `L2` (PIN_54), `L3` (PIN_53), `L4` (PIN_52). Nối song song với bus dữ liệu RGB (B3, B4, G0).
- **Môi trường nạp PlatformIO**: `board = agrv2k_103` (khớp với Flash 256 KB).

### B. Kết quả Tổng hợp & Nạp Logic CPLD
- **Logic Device**: `AGRV2KL64H` (dành riêng cho dòng SiP HyperRAM 64 chân).
- **IP Synthesis**: `hram_ip.vx` (1.3 MB) chứa bộ điều khiển HyperRAM + FIFO + RGB 800x480 (DCLK 33.3 MHz).
- **CPLD Utilization**: **1,222 / 2,112 LUTs (57.9%)**, 103/132 Tiles (78.0%). Tất cả các chân HyperRAM bus và 16-bit RGB bus đã được định tuyến thành công (Route 100%).
- **Nạp Logic CPLD**: Đã nạp file `.pio\logic\rgb.bin` (26,588 bytes) vào Flash logic tại `0x80034000` -> **SUCCESS**.
- **Nạp Firmware**: Đã nạp file `.pio\build\debug\hmi_app.bin` (16,540 bytes) vào Flash chương trình tại `0x80000000` -> **SUCCESS**.

---

## 1b. NGUYÊN NHÂN GỐC (28/10/2026): pin mapping sai

`rgb.ve` của dự án được chép từ ví dụ SDK `HyperRAM/rgb`, vốn dành cho board tham chiếu khác. Gói AGM dành cho board TCX (`agrv2kl64h_example_800x480_touch`) có pin mapping khác hẳn (HSYNC PIN_20, VSYNC PIN_15, DE PIN_16, DCLK PIN_17, dữ liệu PIN_21–41, LED PIN_54/53/52). Tín hiệu video đã đi ra các chân **không nối tới FPC1**, nên màn hình đen dù mọi thứ ở MCU/CPLD chạy đúng (đo VOM trên chân chip vẫn thấy xung; log UART bình thường).

Đã sửa: `rgb.ve` theo AGM; LED = `GPIO4_1..3`; bỏ GPIO1/SPI/EN LCD và chuỗi init (board không có các chân này). Các thử nghiệm `nospi`, `diag_en`, `DCLKPOL` trước đó đều vô nghĩa vì sai chân.

**ĐÃ XÁC NHẬN trên board (28/10/2026): màn hình lên hình, chất lượng tốt** sau khi nạp logic + firmware với `rgb.ve` mới. **Thứ tự màu đã sửa (28/10/2026):** ảnh thật cho thấy R/B bị đảo (da xanh lam); đã hoán đổi nhóm chân trong `rgb.ve`, sau khi nạp lại cổ áo vàng hiện đúng. Còn cần xác nhận: các dải màu test pattern, viền 1 px 4 cạnh, hướng hiển thị.

---

## 1c. Kết quả đo và thử nghiệm trên board (28/10/2026, do người dùng thực hiện)

| Thử nghiệm | Kết quả |
|---|---|
| UART: HyperRAM | `ID0=0x0C86 ID1=0x0001`, đọc/ghi khớp 100%, DMA ~190 MB/s |
| UART: DMA RGB | `running=1`, `rem_chunks` thay đổi liên tục (đang quét) |
| VOM: PIN_27 / DCLK / HSYNC,VSYNC / DE (PIN_58) | ~3.3 V / ~1.6 V / ~3.3 V / ~2.8 V (đúng dự kiến) |
| Bản `debug` (có SPI init, DCLKPOL=0) | màn hình đen, đèn nền sáng |
| Bản `nospi` (bỏ SPI init) | màn hình đen hẳn, đèn nền sáng |
| Bản `diag_en` (nhấp nháy PIN_27) | đèn nền **không** đổi: PIN_27 không phải chân đèn nền |
| VOM FPC1 chân 1–4 (panel rút) | 0 V / "43" V (LED+?) / 0 V / 3.3 V — khớp sơ đồ 40 chân phổ biến (chưa xác nhận) |

Chưa đo: FPC1 chân 29–36 (nhất là chân 31 = DISP nếu theo sơ đồ phổ biến). Chưa có datasheet panel và schematic board.

Nguồn liên hệ (tin Alibaba/Taobao của người bán): Thượng Hải Thiên Thần Tâm Khoa Kỹ (TCX, 上海天晨芯科技有限公司), ông Diêu (姚先生), tuyên bố cung cấp hỗ trợ kỹ thuật chính hãng AGM. Ghi chú của AGM trong tin: các IO khác ở trạng thái **floating** lúc cấp nguồn cho tới khi logic nạp xong.

---

## 2. Điểm Dừng Kiểm chứng: Bước 2 (Màu đơn sắc) & Bước 3 (Pattern 800x480)

> [!IMPORTANT]
> Firmware và Logic CPLD mới đã được nạp trực tiếp vào board qua DAP-Link!  
> Bạn chỉ cần quan sát trực tiếp trên màn hình 5.0" và màn hình UART (115200 8N1). (Nếu MCU đang dừng sau OpenOCD, nhấn nút RESET / rút cắm lại nguồn để MCU chạy).

---

### A. Hiện tượng cần quan sát trên Terminal UART (115200)

```text
======================================================
  DU AN HMI AG32VF407 - MAN HINH TFT 5.0 INCH RGB 800x480
  Kiem tra Buoc 1, 2, 3: Clock, LED, HyperRAM & LCD RGB
======================================================
[TEST] Khoi tao HyperRAM va doc ID...
[HRAM] Doc thanh ghi ID HyperRAM: ID0 = 0x..., ID1 = 0x...
[HRAM] HyperRAM san sang hoat dong tai dia chi 0x60000000 (8MB).
[TEST] Khoi tao LCD RGB 800x480...
[LCD] RGB LCD 800x480 da khoi tao va dang phat tin hieu DMA.

--- [BUOC 2] KIEM TRA MAU DON SAC ---
[LCD] Hien thi mau DO (RED)...
[LCD] Hien thi mau XANH LA (GREEN)...
[LCD] Hien thi mau XANH DUONG (BLUE)...
[LCD] Hien thi mau TRANG (WHITE)...

--- [BUOC 3] KIEM TRA KHUNG VIEN VA TI LE 800x480 ---
[LCD] Ve khung vien 800x480 va 4 goc mau...
[LCD] Ve luoi 50x50 va 8 dai mau RGB chuan...
[SAN SANG] Man hinh dang hien thi Grid & Color Bars.
```

---

### B. Hiện tượng cần quan sát trên Màn hình TFT 5.0"

#### 1. Kiểm tra Bước 2: Màu đơn sắc (Xác nhận thứ tự kênh màu RGB565)
- Đèn nền (Backlight PIN_27) bật sáng.
- Màn hình chuyển đổi tuần tự:
  1. **Màu ĐỎ (RED)** (giữ 2 giây): Kiểm tra xem có đúng màu đỏ tươi không (nếu thành màu xanh dương là bị đảo thứ tự R-B).
  2. **Màu XANH LÁ (GREEN)** (giữ 2 giây): Toàn màn hình xanh lá cây.
  3. **Màu XANH DƯƠNG (BLUE)** (giữ 2 giây): Toàn màn hình xanh dương.
  4. **Màu TRẮNG (WHITE)** (giữ 1 giây): Toàn màn hình sáng trắng đều.

#### 2. Kiểm tra Bước 3: Pattern 800x480 (Xác nhận độ phân giải và căn lề mép)
- **Hình mẫu 1 - Khung viền và 4 góc màu (Border Test)**:
  - Một **khung viền màu trắng dày đúng 1 pixel** bao quanh sát 4 mép cạnh (`y=0`, `y=479`, `x=0`, `x=799`). Viền trắng phải nhìn thấy rõ sát mép, không bị mất nét (co dãn pixel) và không bị lệch khỏi vùng nhìn thấy.
  - **4 khối vuông màu sắc 20x20 pixel** tại 4 góc:
    - Góc Trên - Trái: Màu **ĐỎ**
    - Góc Trên - Phải: Màu **XANH LÁ**
    - Góc Dưới - Trái: Màu **XANH DƯƠNG**
    - Góc Dưới - Phải: Màu **VÀNG**
  - **2 đường chéo màu xám** hình chữ X cắt nhau chính xác tại tâm màn hình (400, 240).
- **Hình mẫu 2 - Lưới ca-rô & Dải màu (Grid & Color Bars)**:
  - Lưới ô vuông 50x50 pixel màu Cyan / Trắng.
  - 8 dải màu chuẩn ở giữa màn hình: Trắng, Vàng, Cyan, Xanh lá, Magenta, Đỏ, Xanh dương, Đen.
- **Tương tác Nút SW2**:
  - Nhấn nút **SW2** (PIN_20) để chuyển qua lại giữa chế độ Border Test và Grid Test.

---

## 3. Danh sách Kiểm tra Xác nhận Từ Người Dùng
Xin bạn quan sát bo mạch thật và phản hồi:
1. Giá trị `ID0` và `ID1` của HyperRAM in ra trên terminal UART là bao nhiêu?
2. 3 màu Đỏ, Xanh lá, Xanh dương hiển thị trên màn hình có đúng màu thực tế không (có bị swap Red - Blue không)?
3. Khung viền 1px màu trắng có hiển thị trọn vẹn 4 cạnh sát mép màn hình không (có bị tràn viền hay lệch vị trí không)?
4. Nhấn nút SW2 có chuyển đổi giữa 2 hình mẫu mượt mà không?

