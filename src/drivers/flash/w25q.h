#ifndef W25Q_H
#define W25Q_H

#include <stdint.h>
#include <stdbool.h>

// Flash SPI ngoài W25Q16JV (2 MB) trên board, truy cập bằng GPIO bit-bang (SPI mode 0).
// Chân: CS=PIN_61, CLK=PIN_58, DI=PIN_59, DO=PIN_62, HOLD=PIN_57, WP=PIN_2 (khai báo trong rgb.ve, GPIO3_0..5).

#define W25Q_SIZE        (2u * 1024 * 1024)
#define W25Q_BLOCK_SIZE  (64u * 1024)
#define W25Q_PAGE_SIZE   256u

// Khởi tạo chân và đọc JEDEC ID (W25Q16JV = 0xEF4015). Trả về ID, 0 nếu không phản hồi.
uint32_t w25q_init(void);

// Đọc num byte từ addr vào buf.
void w25q_read(uint32_t addr, uint8_t *buf, uint32_t num);

// Đọc nwords từ addr, ghép little-endian từng 4 byte và ghi thẳng vào dst (vd. framebuffer HyperRAM).
void w25q_read_words(uint32_t addr, volatile uint32_t *dst, uint32_t nwords);

// Xoá một khối 64 KB chứa addr. Trả về false nếu quá thời gian.
bool w25q_erase_block(uint32_t addr);

// Ghi num byte (không vượt ranh giới trang 256 byte). Vùng ghi phải đã được xoá.
bool w25q_write_page(uint32_t addr, const uint8_t *data, uint32_t num);

#endif // W25Q_H
