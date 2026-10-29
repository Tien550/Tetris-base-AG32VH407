#ifndef LCD_RGB_H
#define LCD_RGB_H

#include "board.h"
#include "hram.h"
#include <stdint.h>
#include <stdbool.h>

// Kích thước chuẩn màn hình TFT 5.0"
#define LCD_WIDTH   800
#define LCD_HEIGHT  480
#define LCD_BITS    16
#define LCD_BYTES   2

// Địa chỉ framebuffer trong HyperRAM (0x60000000)
#define LCD_FRAMEBUFFER_ADDR HRAM_DATA

// Địa chỉ thanh ghi logic RGB DMA (0x70000000)
#define LCD_RGB_DMA_SYS_ADDR (HRAM_DATA + 0x10000000)

// Kích thước DMA theo khối 64 bytes: 800 * 480 * 2 / 64 = 12000
#define LCD_DMA_FRAME_CHUNKS (LCD_WIDTH * LCD_HEIGHT * LCD_BYTES / HRAM_DMA_XFER_BYTES)

// Màu sắc RGB565 thông dụng
#define COLOR_BLACK   0x0000
#define COLOR_WHITE   0xFFFF
#define COLOR_RED     0xF800
#define COLOR_GREEN   0x07E0
#define COLOR_BLUE    0x001F
#define COLOR_YELLOW  0xFFE0
#define COLOR_CYAN    0x07FF
#define COLOR_MAGENTA 0xF81F
#define COLOR_GRAY    0x8410

// Board này không có chân reset/DISP/SPI/EN cho LCD; đèn nền cấp trực tiếp từ 5V (xem rgb.ve).

// Hàm khởi tạo bộ điều khiển LCD RGB và HyperRAM
bool lcd_rgb_init(void);

// Lấy số khung hình DMA đã phát ra màn hình
uint32_t lcd_get_frame_count(void);

// Đổ màu toàn bộ màn hình 800x480
void lcd_clear(uint16_t color);

// Vẽ một điểm ảnh tại (x, y)
static inline void lcd_draw_pixel(uint16_t x, uint16_t y, uint16_t color)
{
  if (x < LCD_WIDTH && y < LCD_HEIGHT) {
    *(volatile uint16_t *)(LCD_FRAMEBUFFER_ADDR + (y * LCD_WIDTH + x) * LCD_BYTES) = color;
  }
}

// Vẽ một đường thẳng ngang
void lcd_draw_hline(uint16_t x, uint16_t y, uint16_t len, uint16_t color);

// Vẽ một đường thẳng dọc
void lcd_draw_vline(uint16_t x, uint16_t y, uint16_t len, uint16_t color);

// Vẽ khung viền 1 pixel quanh 4 mép cạnh (kiểm tra căn viền 800x480)
void lcd_draw_border_test(void);

// Vẽ lưới ca-rô và dải màu kiểm tra
void lcd_draw_grid_test(void);

#endif // LCD_RGB_H

