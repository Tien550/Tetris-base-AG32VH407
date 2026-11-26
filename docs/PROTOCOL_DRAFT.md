# Giao thức STM32 → AG32 (SPI) — BẢN NHÁP v0.1

Trạng thái: **nháp, chưa kiểm chứng** với STM32 thật và driver động cơ. Mục "Cần chốt" ở cuối còn bỏ ngỏ.
Nguyên tắc (đã chốt): STM32 tính toàn bộ đường tốc độ (tăng tốc, giữ tốc, giảm tốc). **AG32 chỉ chạy theo**: mỗi gói mang tần số tức thời cho từng động cơ và AG32 áp dụng đúng giá trị đó, không tự tính đường tốc độ.

## 1. Lớp vật lý
- STM32 là SPI master, AG32 là SPI slave (cài bằng logic CPLD, ví dụ SDK `spi/slave_spi`).
- 8 bit, MSB trước, **mode 0** (CPOL=0, CPHA=0). CS tích cực thấp, giữ thấp suốt một gói.
- Tốc độ đề xuất 1 đến 10 MHz (chưa chốt). Chỉ cần chân SCK, MOSI, CS (MISO không dùng ở v0.1).

## 2. Khung gói (cố định 36 byte)
| Offset | Kích thước | Trường | Ghi chú |
|---|---|---|---|
| 0 | 1 | SOF | luôn `0xA5` |
| 1 | 1 | VER | `0x01` |
| 2 | 1 | SEQ | tăng dần mỗi gói, quay vòng 0..255 |
| 3 | 1 | MASK | bit0..bit4 = động cơ 1..5 được phép chạy |
| 4 + 6·i | 6 | khối động cơ i (i = 0..4) | xem dưới |
| 34 | 2 | CRC16 | CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF) tính trên byte 1..33, gửi little-endian |

Khối động cơ (6 byte, little-endian):
| Byte | Trường | Nội dung |
|---|---|---|
| 0 | MODE | 0 STOP, 1 START (đang tăng tốc), 2 RUN (giữ tốc), 3 STOP_RAMP (đang giảm tốc), 4 ESTOP |
| 1 | FLAGS | bit0 DIR (0 thuận, 1 nghịch), bit1 EN |
| 2..5 | FREQ | tần số xung STEP, đơn vị **0,1 Hz**, kiểu uint32 |

Ý nghĩa:
- **FREQ là tần số tức thời cần phát ở thời điểm gói này.** AG32 áp dụng đúng giá trị đó. MODE chỉ là nhãn để HMI hiển thị, riêng `ESTOP` ép dừng xung ngay.
- STM32 phải gửi gói **liên tục** (cả khi tốc độ không đổi). Mỗi gói đồng thời là tín hiệu "còn sống".

## 3. Phía AG32
- Gói hợp lệ (SOF, VER, CRC đúng) được ghi vào **thanh ghi đệm** của FPGA rồi áp dụng cho cả 5 động cơ cùng một thời điểm.
- **Gói sai CRC/SOF bị bỏ**, tăng bộ đếm lỗi (hiển thị trên HMI), vẫn giữ giá trị trước đó trong thời gian chờ.
- Tần số vượt giới hạn cấu hình (`FREQ_MAX`) bị **kẹp** về giới hạn và đếm là cảnh báo.
- Đổi chiều (DIR): FPGA chèn thời gian bảo vệ (mặc định 20 µs, chỉnh theo datasheet driver) không phát STEP trước và sau cạnh DIR.
- Độ rộng xung STEP tối thiểu theo driver (cấu hình, mặc định 2,5 µs).

## 4. Mất kết nối (mặc định an toàn, đổi được)
- Quá `LINK_TIMEOUT` (mặc định **20 ms**) không có gói hợp lệ: **dừng xung và tắt EN cả 5 động cơ**, HMI hiện "LINK LOST".
- Chạy lại khi nhận lại gói hợp lệ có MODE = STOP trong 3 gói liên tiếp, rồi mới nhận lệnh chạy.

## 5. Đã đưa vào HMI
Mỗi động cơ: trạng thái (chạy/dừng/lỗi), MODE, chiều, tần số (xung/giây) và vòng/phút (cần cấu hình số bước mỗi vòng), tổng số xung đã phát, thời gian chạy. Chung: kết nối SPI, số gói lỗi, tuổi gói cuối, SEQ.

## 6. Cần chốt
1. Tần số xung tối đa (`FREQ_MAX`) và tốc độ SPI thật của STM32.
2. Chu kỳ gửi gói của STM32 (đề xuất 1 đến 10 ms) và độ nhạy `LINK_TIMEOUT` tương ứng.
3. Chân driver: STEP + DIR + EN riêng (15 chân) hay EN dùng chung.
4. Có cần MISO để AG32 trả trạng thái lại STM32 không (hiện không).
5. Thời gian bảo vệ DIR và độ rộng xung tối thiểu theo driver thật.
