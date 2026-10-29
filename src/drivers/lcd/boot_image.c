#include "boot_image.h"
#include "lcd_rgb.h"
#include "../flash/w25q.h"
#include "util.h"
#include <stdio.h>
#include <string.h>

#define IMG_ADDR  0x1000u
#define IMG_BYTES (LCD_WIDTH * LCD_HEIGHT * LCD_BYTES)
#define IMG_WORDS (IMG_BYTES / 4)

typedef struct __attribute__((packed)) {
  char     magic[4];   // "HIMG"
  uint16_t width;
  uint16_t height;
  uint32_t length;     // số byte dữ liệu ảnh
  uint32_t checksum;   // tổng các từ 32-bit của ảnh
} boot_hdr_t;

static bool s_flash_ok = false;

static bool flash_ready(void)
{
  if (s_flash_ok) return true;
  uint32_t id = w25q_init();
  if (id == 0) {
    printf("[IMG] Khong doc duoc flash SPI ngoai.\n");
    return false;
  }
  printf("[IMG] Flash SPI ID = 0x%06X\n", (unsigned)id);
  s_flash_ok = true;
  return true;
}

bool boot_image_show(void)
{
  if (!flash_ready()) return false;

  boot_hdr_t h;
  w25q_read(0, (uint8_t *)&h, sizeof(h));
  if (memcmp(h.magic, "HIMG", 4) != 0 || h.width != LCD_WIDTH || h.height != LCD_HEIGHT || h.length != IMG_BYTES) {
    printf("[IMG] Flash chua co anh khoi dong hop le.\n");
    return false;
  }

  uint32_t t0 = UTIL_GetTick();
  w25q_read_words(IMG_ADDR, (volatile uint32_t *)LCD_FRAMEBUFFER_ADDR, IMG_WORDS);
  printf("[IMG] Da nap anh khoi dong tu flash (%u ms).\n", (unsigned)(UTIL_GetTick() - t0));
  return true;
}

bool boot_image_save(void)
{
  if (!flash_ready()) return false;
  volatile uint32_t *fb = (volatile uint32_t *)LCD_FRAMEBUFFER_ADDR;

  printf("[IMG] Xoa flash...\n");
  for (uint32_t addr = 0; addr < IMG_ADDR + IMG_BYTES; addr += W25Q_BLOCK_SIZE) {
    if (!w25q_erase_block(addr)) {
      printf("[IMG] LOI: xoa khoi 0x%06X that bai\n", (unsigned)addr);
      return false;
    }
  }

  printf("[IMG] Ghi anh vao flash...\n");
  uint32_t sum = 0;
  uint32_t buf[W25Q_PAGE_SIZE / 4];
  for (uint32_t off = 0; off < IMG_BYTES; off += W25Q_PAGE_SIZE) {
    for (unsigned i = 0; i < W25Q_PAGE_SIZE / 4; ++i) {
      uint32_t w = fb[(off / 4) + i];
      buf[i] = w;
      sum += w;
    }
    if (!w25q_write_page(IMG_ADDR + off, (const uint8_t *)buf, W25Q_PAGE_SIZE)) {
      printf("[IMG] LOI: ghi trang tai 0x%06X that bai\n", (unsigned)(IMG_ADDR + off));
      return false;
    }
  }

  // Đọc lại từ flash và so checksum trước khi coi ảnh là hợp lệ
  printf("[IMG] Kiem tra lai...\n");
  uint32_t vsum = 0;
  for (uint32_t off = 0; off < IMG_BYTES; off += W25Q_PAGE_SIZE) {
    w25q_read(IMG_ADDR + off, (uint8_t *)buf, W25Q_PAGE_SIZE);
    for (unsigned i = 0; i < W25Q_PAGE_SIZE / 4; ++i) vsum += buf[i];
  }
  if (vsum != sum) {
    printf("[IMG] LOI: checksum khong khop (ghi 0x%08X, doc 0x%08X)\n", (unsigned)sum, (unsigned)vsum);
    return false;
  }

  // Header ghi sau cùng: chỉ khi toàn bộ ảnh đã đúng mới đánh dấu hợp lệ
  boot_hdr_t h = { { 'H', 'I', 'M', 'G' }, LCD_WIDTH, LCD_HEIGHT, IMG_BYTES, sum };
  uint8_t page[W25Q_PAGE_SIZE] __attribute__((aligned(4)));
  memset(page, 0xFF, sizeof(page));
  memcpy(page, &h, sizeof(h));
  if (!w25q_write_page(0, page, W25Q_PAGE_SIZE)) {
    printf("[IMG] LOI: ghi header that bai\n");
    return false;
  }
  printf("[IMG] Da luu anh khoi dong vao flash.\n");
  return true;
}
