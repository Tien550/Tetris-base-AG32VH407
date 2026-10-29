#include "hram.h"
#include <stdlib.h>

#define BUF_WORDS 0x1000 // 16 KB test buffer
#define DMA_SIZE  (BUF_WORDS * 4 / HRAM_DMA_XFER_BYTES)

__attribute__((aligned(HRAM_DMA_XFER_BYTES))) static uint32_t wr_buf[BUF_WORDS];
__attribute__((aligned(HRAM_DMA_XFER_BYTES))) static uint32_t rd_buf[BUF_WORDS];

static void check_data(uint32_t addr)
{
  for (int i = 0; i < BUF_WORDS; ++i) {
    if (rd_buf[i] != wr_buf[i]) {
      printf("[HRAM LOI] Tai addr 0x%08X: doc duoc 0x%08X, ky vong 0x%08X\n", addr + i * 4, rd_buf[i], wr_buf[i]);
      return;
    }
  }
  printf("[HRAM OK] Kiem tra du lieu doc/ghi trung khop 100%%.\n");
  memset(rd_buf, 0, BUF_WORDS * 4);
}

static void print_info(const char *msg, int bytes, uint32_t time_us)
{
  if (time_us == 0) time_us = 1;
  float data_rate = 1e6f / time_us * bytes / 1024 / 1024;
  printf("[HRAM SPEED] %s %d KB trong %.1f ms (%.1f MB/s)\n", msg, bytes / 1024, time_us / 1000.0f, data_rate);
}

static volatile bool dma_int = false;
void LOCAL_INT0_isr(void)
{
  WR_REG(HRAM_DMA_CTRL, 0);
  dma_int = true;
}

void test_direct(void)
{
  uint32_t hram_addr = HRAM_DATA;

  uint32_t time_us = UTIL_GetUSec();
  for (int i = 0; i < BUF_WORDS; ++i) {
    WR_REG(hram_addr, wr_buf[i]);
    hram_addr += 4;
  }
  time_us = UTIL_GetUSec() - time_us;
  print_info("Ghi truc tiep 32-bit", BUF_WORDS * 4, time_us);

  hram_addr = HRAM_DATA;
  time_us = UTIL_GetUSec();
  for (int i = 0; i < BUF_WORDS; ++i) {
    rd_buf[i] = RD_REG(hram_addr);
    hram_addr += 4;
  }
  time_us = UTIL_GetUSec() - time_us;
  check_data(HRAM_DATA);
  print_info("Doc truc tiep 32-bit", BUF_WORDS * 4, time_us);
}

void test_hram_dma(bool loop, bool use_interrupt)
{
  if (use_interrupt) {
    clint_isr[LOCAL_INT0_IRQn] = LOCAL_INT0_isr;
    INT_EnableIntLocal(LOCAL_INT0_IRQn);
  } else {
    INT_DisableIntLocal(LOCAL_INT0_IRQn);
  }

  uint32_t hram_addr = HRAM_DATA;
  uint32_t time_us = UTIL_GetUSec();
  dma_int = false;
  HRAM_SetDmaHramAddr(hram_addr);
  HRAM_SetDmaSysAddr((uint32_t)wr_buf);
  HRAM_StartDmaWrite(DMA_SIZE);
  if (use_interrupt) {
    uint32_t t0 = UTIL_GetTick();
    while (!dma_int && (UTIL_GetTick() - t0 < 500));
  } else {
    while (HRAM_IsDmaEnabled());
  }
  time_us = UTIL_GetUSec() - time_us;
  print_info("CPLD DMA Ghi", BUF_WORDS * 4, time_us);

  hram_addr = HRAM_DATA;
  time_us = UTIL_GetUSec();
  dma_int = false;
  HRAM_SetDmaHramAddr(hram_addr);
  HRAM_SetDmaSysAddr((uint32_t)rd_buf);
  HRAM_StartDmaRead(DMA_SIZE);
  if (use_interrupt) {
    uint32_t t0 = UTIL_GetTick();
    while (!dma_int && (UTIL_GetTick() - t0 < 500));
  } else {
    while (HRAM_IsDmaEnabled());
  }
  time_us = UTIL_GetUSec() - time_us;
  check_data(HRAM_DATA);
  print_info("CPLD DMA Doc", BUF_WORDS * 4, time_us);

  INT_DisableIntLocal(LOCAL_INT0_IRQn);
}

void test_hram(int latency_type, bool loop, bool use_interrupt)
{
  printf("\n[HRAM] Kiem tra HyperRAM voi che do %s latency...\n", 
         latency_type == HRAM_CR0_FIXED_LATENCY ? "FIXED" : "VARIABLE");
  uint32_t cr0 = 0x8f07 | latency_type | (HRAM_CR0_LATENCY << 4) | (HRAM_CR0_DRIVE_STRENGTH << 12);
  HRAM_WriteReg(HRAM_CR0, cr0);

  uint16_t id0 = HRAM_ReadReg(HRAM_ID0);
  uint16_t id1 = HRAM_ReadReg(HRAM_ID1);
  uint16_t r_cr0 = HRAM_ReadReg(HRAM_CR0);
  uint16_t r_cr1 = HRAM_ReadReg(HRAM_CR1);
  printf("[HRAM] ID0 = 0x%04X, ID1 = 0x%04X, CR0 = 0x%04X, CR1 = 0x%04X\n", id0, id1, r_cr0, r_cr1);

  for (int i = 0; i < BUF_WORDS; ++i) {
    wr_buf[i] = 0xA5A50000 | (i & 0xFFFF);
  }

  test_direct();
  test_hram_dma(loop, use_interrupt);
}

bool hram_init(void)
{
  // Cấu hình HyperRAM thanh ghi CR0 theo chuẩn SDK (Variable Latency)
  uint32_t cr0 = 0x8f07 | HRAM_CR0_VARIABLE_LATENCY | (HRAM_CR0_LATENCY << 4) | (HRAM_CR0_DRIVE_STRENGTH << 12);
  HRAM_WriteReg(HRAM_CR0, cr0);

  uint16_t id0 = HRAM_ReadReg(HRAM_ID0);
  uint16_t id1 = HRAM_ReadReg(HRAM_ID1);

  printf("[HRAM] Doc thanh ghi ID HyperRAM: ID0 = 0x%04X, ID1 = 0x%04X\n", id0, id1);

  if ((id0 == 0x0000 && id1 == 0x0000) || (id0 == 0xFFFF && id1 == 0xFFFF)) {
    printf("[HRAM] CANH BAO: Khong phat hien chip HyperRAM tren bus!\n");
    return false;
  }

  printf("[HRAM] HyperRAM san sang hoat dong tai dia chi 0x%08X (8MB).\n", HRAM_DATA);
  return true;
}
