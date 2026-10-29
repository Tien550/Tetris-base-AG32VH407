#include "w25q.h"
#include "board.h"
#include "util.h"

// GPIO3 bit tương ứng với rgb.ve
#define PIN_HOLD GPIO_BIT0
#define PIN_CLK  GPIO_BIT1
#define PIN_MOSI GPIO_BIT2
#define PIN_CS   GPIO_BIT3
#define PIN_MISO GPIO_BIT4
#define PIN_WP   GPIO_BIT5

#define CMD_WRITE_ENABLE 0x06
#define CMD_READ_STATUS1 0x05
#define CMD_READ_DATA    0x03
#define CMD_PAGE_PROGRAM 0x02
#define CMD_BLOCK_ERASE  0xD8
#define CMD_JEDEC_ID     0x9F

#define PORT GPIO3

static inline void cs_low(void)  { GPIO_SetLow(PORT, PIN_CS); }
static inline void cs_high(void) { GPIO_SetHigh(PORT, PIN_CS); }

// Gửi 1 byte (MSB trước). MOSI và CLK=0 được đặt bằng một lần ghi.
static void spi_write(uint8_t v)
{
  for (int i = 0; i < 8; ++i) {
    GPIO_SetValue(PORT, PIN_MOSI | PIN_CLK, (v & 0x80) ? PIN_MOSI : 0);
    v <<= 1;
    GPIO_SetHigh(PORT, PIN_CLK);
  }
  GPIO_SetLow(PORT, PIN_CLK);
}

static uint8_t spi_read(void)
{
  uint8_t v = 0;
  for (int i = 0; i < 8; ++i) {
    GPIO_SetHigh(PORT, PIN_CLK);
    v = (uint8_t)((v << 1) | (GPIO_GetValue(PORT, PIN_MISO) ? 1 : 0));
    GPIO_SetLow(PORT, PIN_CLK);
  }
  return v;
}

static void send_cmd_addr(uint8_t cmd, uint32_t addr)
{
  spi_write(cmd);
  spi_write((uint8_t)(addr >> 16));
  spi_write((uint8_t)(addr >> 8));
  spi_write((uint8_t)addr);
}

static void write_enable(void)
{
  cs_low();
  spi_write(CMD_WRITE_ENABLE);
  cs_high();
}

// Chờ bit BUSY (WIP) về 0. timeout_ms tính bằng ms.
static bool wait_ready(uint32_t timeout_ms)
{
  uint32_t t0 = UTIL_GetTick();
  while (1) {
    cs_low();
    spi_write(CMD_READ_STATUS1);
    uint8_t st = spi_read();
    cs_high();
    if (!(st & 0x01)) return true;
    if (UTIL_GetTick() - t0 > timeout_ms) return false;
  }
}

uint32_t w25q_init(void)
{
  SYS_EnableAPBClock(APB_MASK_GPIO3);
  GPIO_SetOutput(PORT, PIN_HOLD | PIN_CLK | PIN_MOSI | PIN_CS | PIN_WP);
  GPIO_SetInput(PORT, PIN_MISO);
  // Mức nghỉ: CS=1, CLK=0, HOLD và WP kéo lên cao (không khoá flash)
  GPIO_SetHigh(PORT, PIN_HOLD | PIN_CS | PIN_WP);
  GPIO_SetLow(PORT, PIN_CLK | PIN_MOSI);
  UTIL_IdleMs(2);

  cs_low();
  spi_write(CMD_JEDEC_ID);
  uint32_t id = 0;
  for (int i = 0; i < 3; ++i) id = (id << 8) | spi_read();
  cs_high();
  return (id == 0x000000 || id == 0xFFFFFF) ? 0 : id;
}

void w25q_read(uint32_t addr, uint8_t *buf, uint32_t num)
{
  cs_low();
  send_cmd_addr(CMD_READ_DATA, addr);
  for (uint32_t i = 0; i < num; ++i) buf[i] = spi_read();
  cs_high();
}

void w25q_read_words(uint32_t addr, volatile uint32_t *dst, uint32_t nwords)
{
  cs_low();
  send_cmd_addr(CMD_READ_DATA, addr);
  for (uint32_t i = 0; i < nwords; ++i) {
    uint32_t w = spi_read();
    w |= (uint32_t)spi_read() << 8;
    w |= (uint32_t)spi_read() << 16;
    w |= (uint32_t)spi_read() << 24;
    dst[i] = w;
  }
  cs_high();
}

bool w25q_erase_block(uint32_t addr)
{
  write_enable();
  cs_low();
  send_cmd_addr(CMD_BLOCK_ERASE, addr);
  cs_high();
  return wait_ready(3000); // xoá khối 64 KB: thường ~150 ms, tối đa ~2 s
}

bool w25q_write_page(uint32_t addr, const uint8_t *data, uint32_t num)
{
  write_enable();
  cs_low();
  send_cmd_addr(CMD_PAGE_PROGRAM, addr);
  for (uint32_t i = 0; i < num; ++i) spi_write(data[i]);
  cs_high();
  return wait_ready(50); // ghi trang: thường <1 ms, tối đa 3 ms
}
