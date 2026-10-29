#ifndef LCD_IMAGE_RX_H
#define LCD_IMAGE_RX_H

#include <stdbool.h>

// Nhận ảnh RGB565 800x480 từ máy tính qua UART0 và ghi thẳng vào framebuffer (HyperRAM).
// Giao thức: PC gửi "IMG!" -> board trả 'K' -> PC gửi 768000 byte (little-endian, từng điểm ảnh 16-bit).
// Gọi thường xuyên (vd. mỗi 1 ms). Trả về true khi vừa nhận xong một ảnh.
bool image_rx_poll(void);

#endif // LCD_IMAGE_RX_H
