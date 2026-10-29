#ifndef BOOT_IMAGE_H
#define BOOT_IMAGE_H

#include <stdbool.h>

// Ảnh khởi động lưu trong flash SPI ngoài W25Q16 (xem drivers/flash/w25q.c).
// Bố cục: 0x0000 = header 16 byte (ghi SAU CÙNG, nên ghi dở không làm ảnh hỏng), 0x1000 = dữ liệu RGB565 800x480.

// Đọc ảnh từ flash vào framebuffer nếu header hợp lệ. Trả về true nếu đã hiển thị ảnh.
bool boot_image_show(void);

// Lưu nội dung framebuffer hiện tại vào flash (xoá, ghi, kiểm tra lại). Trả về true nếu thành công.
bool boot_image_save(void);

#endif // BOOT_IMAGE_H
