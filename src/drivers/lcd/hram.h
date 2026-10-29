#ifndef HRAM_H
#define HRAM_H

#include "board.h"
#include <stdio.h>
#include <stdbool.h>
#include <string.h>

#define HRAM_BASE MMIO_BASE
#define HRAM_DATA HRAM_BASE
#define HRAM_REG  (HRAM_BASE | (1 << 23))
#define HRAM_DMA  (HRAM_BASE | (3 << 22))

#define HRAM_ID0  0x0
#define HRAM_ID1  0x1
#define HRAM_CR0  0x800
#define HRAM_CR1  0x801

#define HRAM_CR0_LATENCY          2
#define HRAM_CR0_DRIVE_STRENGTH   0
#define HRAM_CR0_FIXED_LATENCY    (1 << 3)
#define HRAM_CR0_VARIABLE_LATENCY (0 << 3)

#define HRAM_DMA_CTRL (HRAM_DMA + 0)
#define HRAM_DMA_HRAM (HRAM_DMA + 4)
#define HRAM_DMA_SYS  (HRAM_DMA + 8)

#define HRAM_DMA_EN      (1 << 0)
#define HRAM_DMA_WRITE   (1 << 1)
#define HRAM_DMA_READ    (0 << 1)
#define HRAM_DMA_CIRC    (1 << 3)
#define HRAM_DMA_BURST16 (3 << 4)
#define HRAM_DMA_SIZE(__size) ((__size) << 16)

#define HRAM_DMA_XFER_BYTES 64

static inline void HRAM_WriteReg(uint32_t addr, uint16_t data)
{
  *(uint16_t *)(HRAM_REG | (addr << 1)) = data;
}

static inline uint16_t HRAM_ReadReg(uint32_t addr)
{
  return *(uint16_t *)(HRAM_REG | (addr << 1));
}

static inline void HRAM_SetDmaHramAddr(uint32_t addr)
{
  WR_REG(HRAM_DMA_HRAM, addr);
}

static inline void HRAM_SetDmaSysAddr(uint32_t addr)
{
  WR_REG(HRAM_DMA_SYS, addr);
}

static inline void HRAM_StartDmaWrite(uint32_t xfer_size)
{
  WR_REG(HRAM_DMA_CTRL, HRAM_DMA_EN | HRAM_DMA_WRITE | HRAM_DMA_BURST16 | HRAM_DMA_SIZE(xfer_size));
}

static inline void HRAM_StartDmaRead(uint32_t xfer_size)
{
  WR_REG(HRAM_DMA_CTRL, HRAM_DMA_EN | HRAM_DMA_READ | HRAM_DMA_BURST16 | HRAM_DMA_SIZE(xfer_size));
}

static inline void HRAM_StartDmaReadCircular(uint32_t xfer_size)
{
  WR_REG(HRAM_DMA_CTRL, HRAM_DMA_EN | HRAM_DMA_READ | HRAM_DMA_BURST16 | HRAM_DMA_CIRC | HRAM_DMA_SIZE(xfer_size));
}

static inline bool HRAM_IsDmaEnabled(void)
{
  return (RD_REG(HRAM_DMA_CTRL) & HRAM_DMA_EN) != 0;
}

static inline void HRAM_StopDma(void)
{
  WR_REG(HRAM_DMA_CTRL, 0);
  while (HRAM_IsDmaEnabled());
}

bool hram_init(void);
void test_hram(int latency_type, bool loop, bool use_interrupt);

#endif // HRAM_H
