#include "board_hw.h"
#include "drivers/lcd/lcd_rgb.h"
#include "drivers/lcd/boot_image.h"
#include "games/tetris/tetris.h"
#include "util.h"

// Trap handler để bắt và thông báo mọi ngoại lệ nếu có
void exception_handler(void)
{
  uint32_t mcause = read_csr(mcause);
  uint32_t mepc   = read_csr(mepc);
  printf("\n[PANIC] EXCEPTION TRAP! mcause = 0x%08X, mepc = 0x%08X\n", mcause, mepc);
  while (1) {
    board_led_toggle(2);
    UTIL_IdleMs(100);
  }
}

int main(void)
{
  // 1. Khởi tạo BSP bo mạch (Clock 150MHz, 3 LED, 4 nút nhấn H1, nút SW2, UART0)
  board_hw_init();

  printf("\n======================================================\n");
  printf("  DU AN HMI AG32VF407 - MAN HINH TFT 5.0 INCH RGB 800x480\n");
  printf("  ARCADE GAME: TETRIS 800x480 VOI 4 NUT BAM NGOAI H1\n");
  printf("======================================================\n");

  // 2. Khởi tạo LCD RGB (DMA quét liên tục 60 FPS từ HyperRAM)
  printf("[TEST] Khoi tao LCD RGB 800x480...\n");
  if (!lcd_rgb_init()) {
    printf("[LOI] Khoi tao LCD that bai!\n");
  }

  // 3. Khởi động trò chơi Tetris Arcade xoay dọc (Portrait 480x800)
  tetris_init();
  tetris_run();

  return 0;
}
