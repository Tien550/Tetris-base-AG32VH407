#include "lcd_rgb.h"
#include "util.h"

static volatile uint32_t s_frame_count = 0;

uint32_t lcd_get_frame_count(void)
{
  return s_frame_count;
}

bool lcd_rgb_init(void)
{
  // Panel ST7262 (800x480, RGB565) chỉ cần tín hiệu DCLK/HSYNC/VSYNC/DE + dữ liệu,
  // không có chân reset/SPI. Khối RGB trong CPLD tự phát tín hiệu khi DMA chạy.

  // 1. Kiểm tra HyperRAM (framebuffer 768 KB nằm ở đây)
  bool hram_ok = hram_init();
  if (!hram_ok) {
    printf("[LCD] CANH BAO: HyperRAM khong phan hoi - van chay tiep de chan doan.\n");
  }

  // 2. Nạp trước Framebuffer màu đen (tránh nháy màu khác trước khi ảnh khởi động hiện)
  uint32_t red32 = 0;
  uint32_t total_words = (LCD_WIDTH * LCD_HEIGHT) / 2;
  volatile uint32_t *dst = (volatile uint32_t *)LCD_FRAMEBUFFER_ADDR;
  for (uint32_t i = 0; i < total_words; ++i) {
    dst[i] = red32;
  }
  printf("[LCD] Framebuffer san sang (768 KB nap mau DO).\n");

  // 3. Bật DMA vòng: CPLD đọc HyperRAM và quét ra LCD liên tục
  INT_DisableIntLocal(LOCAL_INT0_IRQn);
  HRAM_SetDmaHramAddr(LCD_FRAMEBUFFER_ADDR);
  HRAM_SetDmaSysAddr(LCD_RGB_DMA_SYS_ADDR);
  HRAM_StartDmaReadCircular(LCD_DMA_FRAME_CHUNKS);

  // Chờ ~6 khung hình cho DCLK/HSYNC/VSYNC/DE ổn định
  UTIL_IdleMs(100);

  printf("[LCD] Khoi tao xong! DMA CTRL: 0x%08X (running=%d, en=%d)\n",
         RD_REG(HRAM_DMA_CTRL), (RD_REG(HRAM_DMA_CTRL) & 1), HRAM_IsDmaEnabled());

  return hram_ok;
}

void lcd_clear(uint16_t color)
{
  uint32_t color32 = ((uint32_t)color << 16) | (uint32_t)color;
  uint32_t total_words = (LCD_WIDTH * LCD_HEIGHT) / 2;
  volatile uint32_t *dst = (volatile uint32_t *)LCD_FRAMEBUFFER_ADDR;
  for (uint32_t i = 0; i < total_words; ++i) {
    dst[i] = color32;
  }
}

void lcd_draw_hline(uint16_t x, uint16_t y, uint16_t len, uint16_t color)
{
  if (y >= LCD_HEIGHT) return;
  for (uint16_t i = 0; i < len; i++) {
    if (x + i < LCD_WIDTH) {
      lcd_draw_pixel(x + i, y, color);
    }
  }
}

void lcd_draw_vline(uint16_t x, uint16_t y, uint16_t len, uint16_t color)
{
  if (x >= LCD_WIDTH) return;
  for (uint16_t i = 0; i < len; i++) {
    if (y + i < LCD_HEIGHT) {
      lcd_draw_pixel(x, y + i, color);
    }
  }
}

void lcd_draw_border_test(void)
{
  // Nền đen
  uint32_t total_words = (LCD_WIDTH * LCD_HEIGHT) / 2;
  volatile uint32_t *dst = (volatile uint32_t *)LCD_FRAMEBUFFER_ADDR;
  for (uint32_t i = 0; i < total_words; ++i) dst[i] = 0;

  // Khung viền 4 mép cạnh (Màu Trắng)
  lcd_draw_hline(0, 0, LCD_WIDTH, COLOR_WHITE);
  lcd_draw_hline(0, LCD_HEIGHT - 1, LCD_WIDTH, COLOR_WHITE);
  lcd_draw_vline(0, 0, LCD_HEIGHT, COLOR_WHITE);
  lcd_draw_vline(LCD_WIDTH - 1, 0, LCD_HEIGHT, COLOR_WHITE);

  // 4 khối vuông 20x20 tại 4 góc
  for (int y = 2; y < 22; y++) {
    for (int x = 2; x < 22; x++) lcd_draw_pixel(x, y, COLOR_RED);
  }
  for (int y = 2; y < 22; y++) {
    for (int x = LCD_WIDTH - 22; x < LCD_WIDTH - 2; x++) lcd_draw_pixel(x, y, COLOR_GREEN);
  }
  for (int y = LCD_HEIGHT - 22; y < LCD_HEIGHT - 2; y++) {
    for (int x = 2; x < 22; x++) lcd_draw_pixel(x, y, COLOR_BLUE);
  }
  for (int y = LCD_HEIGHT - 22; y < LCD_HEIGHT - 2; y++) {
    for (int x = LCD_WIDTH - 22; x < LCD_WIDTH - 2; x++) lcd_draw_pixel(x, y, COLOR_YELLOW);
  }

  // 2 đường chéo chữ X
  for (int x = 0; x < LCD_WIDTH; x++) {
    int y1 = (x * LCD_HEIGHT) / LCD_WIDTH;
    int y2 = LCD_HEIGHT - 1 - y1;
    lcd_draw_pixel(x, y1, COLOR_GRAY);
    lcd_draw_pixel(x, y2, COLOR_GRAY);
  }
}

void lcd_draw_grid_test(void)
{
  // Nền đen
  uint32_t total_words = (LCD_WIDTH * LCD_HEIGHT) / 2;
  volatile uint32_t *dst = (volatile uint32_t *)LCD_FRAMEBUFFER_ADDR;
  for (uint32_t i = 0; i < total_words; ++i) dst[i] = 0;

  for (int x = 0; x < LCD_WIDTH; x += 50) {
    lcd_draw_vline(x, 0, LCD_HEIGHT, (x % 100 == 0) ? COLOR_WHITE : COLOR_CYAN);
  }
  for (int y = 0; y < LCD_HEIGHT; y += 50) {
    lcd_draw_hline(0, y, LCD_WIDTH, (y % 100 == 0) ? COLOR_WHITE : COLOR_CYAN);
  }

  uint16_t bar_colors[] = { COLOR_WHITE, COLOR_YELLOW, COLOR_CYAN, COLOR_GREEN, 
                            COLOR_MAGENTA, COLOR_RED, COLOR_BLUE, COLOR_BLACK };
  int bar_width = LCD_WIDTH / 8;
  for (int b = 0; b < 8; b++) {
    for (int y = 190; y < 290; y++) {
      for (int x = b * bar_width; x < (b + 1) * bar_width; x++) {
        lcd_draw_pixel(x, y, bar_colors[b]);
      }
    }
  }
}
