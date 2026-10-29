#include "lcd_image_rx.h"
#include "boot_image.h"
#include "lcd_rgb.h"
#include "util.h"
#include <stdio.h>

#define IMG_BYTES (LCD_WIDTH * LCD_HEIGHT * LCD_BYTES)
#define RX_TIMEOUT_MS 2000   // quá thời gian này không có byte nào thì bỏ dở

// 4 byte gần nhất. "IMG!" = chỉ hiển thị, "IMF!" = hiển thị rồi lưu vào flash làm ảnh khởi động.
#define MAGIC(a, b, c, d) (((uint32_t)(a) << 24) | ((uint32_t)(b) << 16) | ((uint32_t)(c) << 8) | (uint32_t)(d))
#define MAGIC_SHOW MAGIC('I', 'M', 'G', '!')
#define MAGIC_SAVE MAGIC('I', 'M', 'F', '!')
static uint32_t s_last4 = 0;

// Nhận toàn bộ payload vào framebuffer. FIFO UART0 chỉ 16 byte nên phải đọc liên tục.
static bool receive_image(void)
{
  volatile uint32_t *dst = (volatile uint32_t *)LCD_FRAMEBUFFER_ADDR;
  uint32_t word = 0;
  unsigned shift = 0;
  uint32_t got = 0;
  uint32_t last_tick = UTIL_GetTick();

  while (got < IMG_BYTES) {
    if (UART_IsRxFifoEmpty(UART0)) {
      if (UTIL_GetTick() - last_tick > RX_TIMEOUT_MS) {
        printf("[IMG] Het thoi gian cho, da nhan %u/%u byte\n", (unsigned)got, (unsigned)IMG_BYTES);
        return false;
      }
      continue;
    }
    word |= (uint32_t)UART_ReceiveData(UART0) << shift;
    shift += 8;
    ++got;
    last_tick = UTIL_GetTick();
    if (shift == 32) {
      *dst++ = word;   // 2 điểm ảnh/lần ghi 32-bit
      word = 0;
      shift = 0;
    }
  }
  return true;
}

bool image_rx_poll(void)
{
  while (!UART_IsRxFifoEmpty(UART0)) {
    s_last4 = (s_last4 << 8) | UART_ReceiveData(UART0);
    if (s_last4 != MAGIC_SHOW && s_last4 != MAGIC_SAVE) continue;

    bool save = (s_last4 == MAGIC_SAVE);
    s_last4 = 0;
    UART_SendCh(UART0, 'K');             // bắt tay: báo PC có thể gửi dữ liệu
    if (!receive_image()) return false;
    printf("[IMG] Nhan xong anh.\n");
    if (save) {
      bool ok = boot_image_save();
      UART_SendCh(UART0, ok ? 'S' : 'E'); // 'S' = đã lưu, 'E' = lỗi
    }
    return true;
  }
  return false;
}
