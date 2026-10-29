#include "tetris.h"
#include "tetris_font.h"
#include "board_hw.h"
#include "drivers/lcd/lcd_rgb.h"
#include "util.h"
#include <stdio.h>
#include <string.h>

// Kích thước logic ở chế độ xoay dọc (Portrait Mode)
#define SCREEN_PORT_W 480
#define SCREEN_PORT_H 800

// Kích thước phần cứng quét thực tế của màn hình
#define SCREEN_PHYS_W 800
#define SCREEN_PHYS_H 480

// Hướng xoay dọc: 
// 0 = 90 độ theo chiều kim đồng hồ
// 1 = 270 độ / 90 độ ngược chiều kim đồng hồ (Mặc định: xoay 180 độ theo yêu cầu người dùng)
static int s_portrait_flip = 1;

// Bàn cờ Tetris chuẩn 10 cột x 20 hàng
// Mở rộng bề ngang với lề an toàn chống nhiễu cổng quét: Ô 36x28 px (Khung chơi 360x560 px, lề 60px)
#define BOARD_COLS 10
#define BOARD_ROWS 20
#define CELL_W     36   // Rộng 36 px mỗi ô (360 px tổng bề ngang khung chơi)
#define CELL_H     28   // Cao 28 px mỗi ô (560 px tổng chiều cao khung chơi)

// Tọa độ bàn cờ trên màn hình dọc (360 x 560 px) - Cách lề trái an toàn 60px
#define BOARD_PX_X 60   // Căn giữa: (480 - 360) / 2 = 60 (tránh hoàn toàn vùng nhiễu mép 0..40px)
#define BOARD_PX_Y 172  // Đặt phía dưới HUD (Y: 172..731)
#define BOARD_PX_W (BOARD_COLS * CELL_W) // 360 px
#define BOARD_PX_H (BOARD_ROWS * CELL_H) // 560 px

// Khu vực điểm số và ô xem trước phía trên (Dưới chữ TETRIS, trên khung chơi)
#define STATS_X 56
#define STATS_Y 54
#define STATS_W 176
#define STATS_H 106

#define NEXT_X 248
#define NEXT_Y 54
#define NEXT_W 176
#define NEXT_H 106

// Màu sắc RGB565 chuẩn
#define COLOR_BLACK       0x0000
#define COLOR_WHITE       0xFFFF
#define COLOR_BG          0x0000  // Nền đen tuyền Arcade
#define COLOR_BOARD_BG    0x0000  // Nền bàn chơi đen sâu thẳm
#define COLOR_PANEL_BG    0x0842  // Nền thẻ thông số (Dark Slate)
#define COLOR_BORDER_CYAN 0x07FF  // Viền neon xanh lam
#define COLOR_BORDER_MAG  0xF81F  // Viền neon tím
#define COLOR_GRID_DOT    0x2945  // Chấm lưới xám mờ tinh tế
#define COLOR_TEXT_DIM    0x8410  // Chữ xám mờ
#define COLOR_GOLD        0xFEA0  // Vàng kim

// Màu 7 khối Tetromino (1..7)
static const uint16_t PIECE_COLORS[8] = {
  0x0000, // 0: Trống
  0x07FF, // 1: I - Cyan
  0x29FF, // 2: J - Royal Blue
  0xFD20, // 3: L - Orange
  0xFFE0, // 4: O - Yellow
  0x27E4, // 5: S - Lime Green
  0xD1BF, // 6: T - Purple/Magenta
  0xF9A4  // 7: Z - Bright Red
};

// Con trỏ Framebuffer 16-bit trong HyperRAM
static volatile uint16_t *g_vram = (volatile uint16_t *)LCD_FRAMEBUFFER_ADDR;

// Tọa độ 7 khối x 4 góc xoay x 4 ô x (dx, dy)
static const int8_t SHAPES[7][4][4][2] = {
  // 1: I piece
  {
    { {-1, 0}, {0, 0}, {1, 0}, {2, 0} },
    { { 0,-1}, {0, 0}, {0, 1}, {0, 2} },
    { {-1, 1}, {0, 1}, {1, 1}, {2, 1} },
    { { 1,-1}, {1, 0}, {1, 1}, {1, 2} }
  },
  // 2: J piece
  {
    { {-1,-1}, {-1, 0}, {0, 0}, {1, 0} },
    { { 0,-1}, { 0, 0}, {0, 1}, {1,-1} },
    { {-1, 0}, { 0, 0}, {1, 0}, {1, 1} },
    { {-1, 1}, { 0,-1}, {0, 0}, {0, 1} }
  },
  // 3: L piece
  {
    { {-1, 0}, {0, 0}, {1, 0}, {1,-1} },
    { { 0,-1}, {0, 0}, {0, 1}, {1, 1} },
    { {-1,-1}, {-1, 0}, {0, 0}, {1, 0} },
    { {-1,-1}, { 0,-1}, {0, 0}, {0, 1} }
  },
  // 4: O piece
  {
    { {0, 0}, {1, 0}, {0, 1}, {1, 1} },
    { {0, 0}, {1, 0}, {0, 1}, {1, 1} },
    { {0, 0}, {1, 0}, {0, 1}, {1, 1} },
    { {0, 0}, {1, 0}, {0, 1}, {1, 1} }
  },
  // 5: S piece
  {
    { {-1, 0}, {0, 0}, {0,-1}, {1,-1} },
    { { 0,-1}, {0, 0}, {1, 0}, {1, 1} },
    { {-1, 1}, {0, 1}, {0, 0}, {1, 0} },
    { {-1,-1}, {-1, 0}, {0, 0}, {0, 1} }
  },
  // 6: T piece
  {
    { {-1, 0}, {0, 0}, {1, 0}, {0,-1} },
    { { 0,-1}, {0, 0}, {0, 1}, {1, 0} },
    { {-1, 0}, {0, 0}, {1, 0}, {0, 1} },
    { { 0,-1}, {0, 0}, {0, 1}, {-1, 0} }
  },
  // 7: Z piece
  {
    { {-1,-1}, {0,-1}, {0, 0}, {1, 0} },
    { { 1,-1}, {1, 0}, {0, 0}, {0, 1} },
    { {-1, 0}, {0, 0}, {0, 1}, {1, 1} },
    { { 0,-1}, {0, 0}, {-1, 0}, {-1, 1} }
  }
};

// Trạng thái bàn chơi
static uint8_t s_board[BOARD_ROWS][BOARD_COLS];

// Khối hiện tại và kế tiếp
static int s_cur_type = 1;
static int s_cur_rot  = 0;
static int s_cur_x    = 4;
static int s_cur_y    = 0;
static int s_next_type = 2;

// Điểm số và thống kê
static uint32_t s_score = 0;
static uint32_t s_high_score = 10000;
static uint32_t s_lines = 0;
static uint16_t s_level = 1;
static bool s_game_over = false;
static bool s_paused = false;

// 7-Bag Randomizer
static uint8_t s_bag[7];
static int s_bag_idx = 7;
static uint32_t s_rand_seed = 987654321;

// Tốc độ rơi theo Level (ms)
static const uint16_t LEVEL_SPEED_MS[10] = {
  800, 700, 600, 500, 400, 300, 220, 160, 110, 70
};

// Điều khiển phím vật lý & DAS (Delayed Auto Shift)
static uint32_t s_left_start_tick  = 0;
static uint32_t s_right_start_tick = 0;
static uint32_t s_last_left_repeat  = 0;
static uint32_t s_last_right_repeat = 0;
static uint32_t s_last_drop_tick = 0;

// =========================================================================
// HÀM ĐỒ HỌA XOAY DỌC (PORTRAIT GRAPHICS ENGINE)
// =========================================================================

static inline uint16_t color_lighten(uint16_t c, int percent)
{
  int r = (c >> 11) & 0x1F;
  int g = (c >> 5) & 0x3F;
  int b = c & 0x1F;
  r += (31 - r) * percent / 100;
  g += (63 - g) * percent / 100;
  b += (31 - b) * percent / 100;
  if (r > 31) r = 31;
  if (g > 63) g = 63;
  if (b > 31) b = 31;
  return (uint16_t)((r << 11) | (g << 5) | b);
}

static inline uint16_t color_darken(uint16_t c, int percent)
{
  int r = (c >> 11) & 0x1F;
  int g = (c >> 5) & 0x3F;
  int b = c & 0x1F;
  r -= r * percent / 100;
  g -= g * percent / 100;
  b -= b * percent / 100;
  if (r < 0) r = 0;
  if (g < 0) g = 0;
  if (b < 0) b = 0;
  return (uint16_t)((r << 11) | (g << 5) | b);
}

// HyperRAM trong CPLD lỗi với truy cập ngắn/lẻ (ghi 16-bit, ghi từng đoạn ngắn rời rạc): dữ liệu bị ghi nhầm
// địa chỉ và hiện thành bản sao rác ở chỗ khác. Chỉ có ghi tuần tự dài (lcd_clear, nhận ảnh) và DMAC của MCU
// theo cả dòng (cách ví dụ SDK rgb.c cập nhật khung hình khi đang quét) là đúng.
//
// Vì vậy mọi vùng vẽ nhỏ đều dựng trong "tile" ở SRAM (toạ độ vật lý, 16-bit/điểm) rồi đẩy sang HyperRAM
// bằng DMAC từng dòng (32-bit). Tile KHÔNG đọc HyperRAM: nó được tô sẵn màu nền bg nên vùng tile phải được
// vẽ phủ kín (hoặc nền đúng bằng bg).

#define TILE_MAX_PIXELS 36864          // 72 KB SRAM
static uint16_t s_tile[TILE_MAX_PIXELS] __attribute__((aligned(4)));
static bool s_tile_on = false;
static int s_ty0, s_tx0, s_trows, s_tcols;

// Ghi 1 điểm ảnh trực tiếp vào HyperRAM bằng đọc-sửa-ghi từ 32-bit. Chỉ là phương án dự phòng.
static inline void put16(volatile uint16_t *p, uint16_t color)
{
  volatile uint32_t *w = (volatile uint32_t *)((uintptr_t)p & ~(uintptr_t)3);
  uint32_t v = *w;
  if ((uintptr_t)p & 2) v = (v & 0x0000FFFFu) | ((uint32_t)color << 16);
  else                  v = (v & 0xFFFF0000u) | color;
  *w = v;
}

// Tô count điểm ảnh liên tiếp trực tiếp trong HyperRAM (đầu/cuối lẻ dùng put16, phần giữa ghi 32-bit)
static inline void fill_span(volatile uint16_t *line, int start, int count, uint16_t color)
{
  volatile uint16_t *p = line + start;
  if (count <= 0) return;
  if (((uintptr_t)p & 2) && count > 0) { put16(p, color); ++p; --count; }
  uint32_t c32 = ((uint32_t)color << 16) | color;
  volatile uint32_t *w = (volatile uint32_t *)(void *)p; // p đã căn 4 byte
  for (int n = count / 2; n > 0; --n) *w++ = c32;
  if (count & 1) put16((volatile uint16_t *)(void *)w, color);
}

// Mở tile phủ hình chữ nhật vật lý (hàng py0.., cột px0..), tô nền bg. exact=true: không cho phép nới rộng.
static bool tile_open_phys(int py0, int px0, int rows, int cols, uint16_t bg, bool exact)
{
  if (s_tile_on) return false;
  if ((px0 & 1) || (cols & 1)) {
    if (exact) return false;
    if (px0 & 1) { px0--; cols++; }   // nới rộng cho căn 32-bit: điểm thêm sẽ mang màu nền bg
    if (cols & 1) cols++;
  }
  if (rows <= 0 || cols <= 0 || rows * cols > TILE_MAX_PIXELS) return false;
  if (py0 < 0 || py0 + rows > SCREEN_PHYS_H || px0 < 0 || px0 + cols > SCREEN_PHYS_W) return false;

  uint32_t c32 = ((uint32_t)bg << 16) | bg;
  uint32_t *w = (uint32_t *)(void *)s_tile;
  for (int n = (rows * cols) / 2; n > 0; --n) *w++ = c32;

  s_ty0 = py0; s_tx0 = px0; s_trows = rows; s_tcols = cols;
  s_tile_on = true;
  return true;
}

// Mở tile theo toạ độ màn hình dọc (x: 0..479, y: 0..799)
static bool tile_open_portrait(int x, int y, int w, int h, uint16_t bg, bool exact)
{
  if (x < 0) { w += x; x = 0; }
  if (y < 0) { h += y; y = 0; }
  if (x + w > SCREEN_PORT_W) w = SCREEN_PORT_W - x;
  if (y + h > SCREEN_PORT_H) h = SCREEN_PORT_H - y;
  if (w <= 0 || h <= 0) return false;
  if (s_portrait_flip) return tile_open_phys(479 - (x + w - 1), y, w, h, bg, exact);
  return tile_open_phys(x, 799 - (y + h - 1), w, h, bg, exact);
}

// Đẩy tile sang HyperRAM bằng DMAC của MCU, từng dòng một (kênh 0, mem-to-mem, 32-bit)
static void tile_close(void)
{
  if (!s_tile_on) return;
  s_tile_on = false;
  for (int r = 0; r < s_trows; r++) {
    DMAC_Config(DMAC_CHANNEL0,
                (uint32_t)&s_tile[r * s_tcols],
                (uint32_t)&g_vram[(s_ty0 + r) * SCREEN_PHYS_W + s_tx0],
                DMAC_ADDR_INCR_ON, DMAC_ADDR_INCR_ON, DMAC_WIDTH_32_BIT, DMAC_WIDTH_32_BIT,
                DMAC_BURST_256, DMAC_BURST_256, (uint32_t)(s_tcols / 2), DMAC_MEM_TO_MEM_DMA_CTRL, 0, 0);
    DMAC_WaitChannel(DMAC_CHANNEL0);
  }
}

// Ghi 1 điểm ảnh theo toạ độ vật lý: vào tile nếu đang mở, ngược lại ghi thẳng
static inline void px_put(int py, int px, uint16_t color)
{
  if (px < 0 || px >= SCREEN_PHYS_W || py < 0 || py >= SCREEN_PHYS_H) return;
  if (s_tile_on) {
    int r = py - s_ty0, c = px - s_tx0;
    if (r >= 0 && r < s_trows && c >= 0 && c < s_tcols) s_tile[r * s_tcols + c] = color;
  } else {
    put16(&g_vram[py * SCREEN_PHYS_W + px], color);
  }
}

// Tô một đoạn count điểm ảnh liên tiếp trên hàng vật lý py, bắt đầu từ cột px
static void run_fill(int py, int px, int count, uint16_t color)
{
  if (px < 0) { count += px; px = 0; }
  if (px + count > SCREEN_PHYS_W) count = SCREEN_PHYS_W - px;
  if (count <= 0 || py < 0 || py >= SCREEN_PHYS_H) return;
  if (s_tile_on) {
    int r = py - s_ty0;
    if (r < 0 || r >= s_trows) return;
    int c0 = px - s_tx0, c1 = c0 + count;
    if (c0 < 0) c0 = 0;
    if (c1 > s_tcols) c1 = s_tcols;
    uint16_t *row = &s_tile[r * s_tcols];
    for (int c = c0; c < c1; c++) row[c] = color;
  } else {
    fill_span(&g_vram[py * SCREEN_PHYS_W], px, count, color);
  }
}

// Vẽ điểm ảnh theo tọa độ dọc (x: 0..479, y: 0..799)
static inline void draw_pixel_portrait(int x, int y, uint16_t color)
{
  if (x < 0 || x >= SCREEN_PORT_W || y < 0 || y >= SCREEN_PORT_H) return;
  if (!s_portrait_flip) {
    px_put(x, 799 - y, color);      // 90 độ
  } else {
    px_put(479 - x, y, color);      // 270 độ
  }
}

// Vẽ hình chữ nhật theo tọa độ màn hình dọc.
// Hình ngắn (dòng < 160 điểm) ngoài tile: tự dựng tile vừa khít rồi đẩy bằng DMAC. Dòng dài thì ghi tuần tự trực tiếp.
static void draw_rect(int x, int y, int w, int h, uint16_t color)
{
  if (x < 0) { w += x; x = 0; }
  if (y < 0) { h += y; y = 0; }
  if (x + w > SCREEN_PORT_W) w = SCREEN_PORT_W - x;
  if (y + h > SCREEN_PORT_H) h = SCREEN_PORT_H - y;
  if (w <= 0 || h <= 0) return;

  bool own = false;
  if (!s_tile_on && h < 160 && w * h <= TILE_MAX_PIXELS) {
    own = tile_open_portrait(x, y, w, h, color, true);
  }

  if (!s_portrait_flip) {
    int px_start = 799 - (y + h - 1);
    for (int r = 0; r < w; r++) run_fill(x + r, px_start, h, color);
  } else {
    for (int r = 0; r < w; r++) run_fill(479 - (x + r), y, h, color);
  }

  if (own) tile_close();
}

static void draw_border(int x, int y, int w, int h, uint16_t color, int thickness)
{
  draw_rect(x, y, w, thickness, color);
  draw_rect(x, y + h - thickness, w, thickness, color);
  draw_rect(x, y, thickness, h, color);
  draw_rect(x + w - thickness, y, thickness, h, color);
}

// Vẽ 1 ký tự 8x16: nền bg luôn được vẽ đặc (không còn "trong suốt")
static void draw_char(int x, int y, char c, uint16_t fg, uint16_t bg, int scale)
{
  if (c < FONT_FIRST_CHAR || c > FONT_LAST_CHAR) c = ' ';
  const uint8_t *glyph = g_font_8x16[c - FONT_FIRST_CHAR];

  for (int row = 0; row < 16; row++) {
    uint8_t bits = glyph[row];
    for (int col = 0; col < 8; col++) {
      bool set = (bits & (1 << (7 - col))) != 0;
      uint16_t col_val = set ? fg : bg;
      if (scale == 1) {
        draw_pixel_portrait(x + col, y + row, col_val);
      } else {
        draw_rect(x + col * scale, y + row * scale, scale, scale, col_val);
      }
    }
  }
}

static void draw_text(int x, int y, const char *str, uint16_t fg, uint16_t bg, int scale)
{
  int len = (int)strlen(str);
  bool own = tile_open_portrait(x, y, 8 * scale * len, 16 * scale, bg, false);
  int cx = x;
  while (*str) {
    draw_char(cx, y, *str, fg, bg, scale);
    cx += 8 * scale;
    str++;
  }
  if (own) tile_close();
}

// Vẽ một khối 3D chữ nhật (w x h px) theo chuẩn Arcade
static void draw_block_3d_rect(int px, int py, int w, int h, uint16_t color)
{
  bool own = tile_open_portrait(px, py, w, h, COLOR_BLACK, false);
  uint16_t light = color_lighten(color, 45);
  uint16_t dark  = color_darken(color, 45);

  // Viền ngoài 1px đen
  draw_border(px, py, w, h, COLOR_BLACK, 1);

  // Mép vát trên & trái sáng (2px)
  draw_rect(px + 1, py + 1, w - 2, 2, light);
  draw_rect(px + 1, py + 1, 2, h - 2, light);

  // Mép vát dưới & phải tối (2px)
  draw_rect(px + 1, py + h - 3, w - 2, 2, dark);
  draw_rect(px + w - 3, py + 1, 2, h - 2, dark);

  // Ruột khối màu rực rỡ
  draw_rect(px + 3, py + 3, w - 6, h - 6, color);

  // Điểm phản quang (Glint) ở góc trên bên trái
  draw_rect(px + 4, py + 4, 3, 3, COLOR_WHITE);
  if (own) tile_close();
}

static inline void draw_block_3d(int px, int py, uint16_t color)
{
  draw_block_3d_rect(px, py, CELL_W, CELL_H, color);
}

// Vẽ khối Ghost (bóng mờ định vị nơi khối sẽ rơi)
static void draw_ghost_block(int px, int py, uint16_t color)
{
  bool own = tile_open_portrait(px, py, CELL_W, CELL_H, COLOR_BOARD_BG, false);
  uint16_t ghost_col = color_darken(color, 65);
  draw_border(px + 1, py + 1, CELL_W - 2, CELL_H - 2, ghost_col, 1);
  draw_rect(px + 2, py + 2, CELL_W - 4, CELL_H - 4, COLOR_BOARD_BG);
  if (own) tile_close();
}

// Xóa ô trống trên bàn cờ và vẽ lại chấm tâm
static void draw_empty_cell(int col, int row)
{
  int px = BOARD_PX_X + col * CELL_W;
  int py = BOARD_PX_Y + row * CELL_H;
  bool own = tile_open_portrait(px, py, CELL_W, CELL_H, COLOR_BOARD_BG, false);
  // Chấm tâm mờ 2x2 để căn lưới
  draw_rect(px + CELL_W / 2 - 1, py + CELL_H / 2 - 1, 2, 2, COLOR_GRID_DOT);
  if (own) tile_close();
}

// =========================================================================
// LOGIC TETRIS VÀ RANDOMIZER
// =========================================================================

static uint32_t tetris_rand(void)
{
  s_rand_seed = s_rand_seed * 1103515245 + 12345;
  return (s_rand_seed >> 16) & 0x7FFF;
}

static uint8_t get_next_piece(void)
{
  if (s_bag_idx >= 7) {
    for (int i = 0; i < 7; i++) s_bag[i] = (uint8_t)(i + 1);
    for (int i = 6; i > 0; i--) {
      int j = tetris_rand() % (i + 1);
      uint8_t tmp = s_bag[i];
      s_bag[i] = s_bag[j];
      s_bag[j] = tmp;
    }
    s_bag_idx = 0;
  }
  return s_bag[s_bag_idx++];
}

static bool check_collision(int type, int rot, int bx, int by)
{
  for (int i = 0; i < 4; i++) {
    int x = bx + SHAPES[type - 1][rot][i][0];
    int y = by + SHAPES[type - 1][rot][i][1];
    if (x < 0 || x >= BOARD_COLS || y >= BOARD_ROWS) return true;
    if (y >= 0 && s_board[y][x] != 0) return true;
  }
  return false;
}

static int get_ghost_y(void)
{
  int gy = s_cur_y;
  while (!check_collision(s_cur_type, s_cur_rot, s_cur_x, gy + 1)) {
    gy++;
  }
  return gy;
}

// =========================================================================
// HIỂN THỊ CÁC THÀNH PHẦN GIAO DIỆN DỌC (PORTRAIT HUD)
// =========================================================================

static void render_stats_panel(void)
{
  char buf[32];

  bool own = tile_open_portrait(STATS_X, STATS_Y, STATS_W, STATS_H, COLOR_PANEL_BG, false);
  draw_rect(STATS_X, STATS_Y, STATS_W, STATS_H, COLOR_PANEL_BG);
  draw_border(STATS_X, STATS_Y, STATS_W, STATS_H, COLOR_BORDER_CYAN, 1);

  draw_text(STATS_X + 10, STATS_Y + 12, "SCORE", COLOR_TEXT_DIM, COLOR_PANEL_BG, 1);
  snprintf(buf, sizeof(buf), "%06u", (unsigned)s_score);
  draw_text(STATS_X + 74, STATS_Y + 12, buf, COLOR_GOLD, COLOR_PANEL_BG, 1);

  draw_text(STATS_X + 10, STATS_Y + 36, "HIGH ", COLOR_TEXT_DIM, COLOR_PANEL_BG, 1);
  snprintf(buf, sizeof(buf), "%06u", (unsigned)s_high_score);
  draw_text(STATS_X + 74, STATS_Y + 36, buf, COLOR_WHITE, COLOR_PANEL_BG, 1);

  draw_rect(STATS_X + 10, STATS_Y + 58, STATS_W - 20, 1, COLOR_TEXT_DIM);

  snprintf(buf, sizeof(buf), "LV:%02u  LINES:%03u", (unsigned)s_level, (unsigned)s_lines);
  draw_text(STATS_X + 10, STATS_Y + 74, buf, 0x27E4, COLOR_PANEL_BG, 1);
  if (own) tile_close();
}

static void render_next_piece_box(void)
{
  bool own = tile_open_portrait(NEXT_X, NEXT_Y, NEXT_W, NEXT_H, COLOR_PANEL_BG, false);
  draw_rect(NEXT_X, NEXT_Y, NEXT_W, NEXT_H, COLOR_PANEL_BG);
  draw_border(NEXT_X, NEXT_Y, NEXT_W, NEXT_H, COLOR_BORDER_MAG, 2);
  draw_text(NEXT_X + 48, NEXT_Y + 12, "NEXT PIECE", COLOR_BORDER_CYAN, COLOR_PANEL_BG, 1);

  // Vẽ khối kế tiếp tại tâm ô preview
  int center_px = NEXT_X + NEXT_W / 2;
  int center_py = NEXT_Y + 66;
  uint16_t color = PIECE_COLORS[s_next_type];

  int preview_w = 20;
  int preview_h = 16;
  for (int i = 0; i < 4; i++) {
    int dx = SHAPES[s_next_type - 1][0][i][0];
    int dy = SHAPES[s_next_type - 1][0][i][1];
    int px = center_px + (dx * preview_w) - (preview_w / 2);
    int py = center_py + (dy * preview_h) - (preview_h / 2);
    draw_block_3d_rect(px, py, preview_w, preview_h, color);
  }
  if (own) tile_close();
}

// Đèn báo trạng thái các nút bấm hiển thị trực tiếp lên màn hình
static void render_button_indicators(uint8_t btn_mask)
{
  int hy = 746;
  int bx = 250;
  int by = hy + 10;
  bool own = tile_open_portrait(bx, by, 112, 16, COLOR_PANEL_BG, false);
  draw_text(bx,       by, "9",  (btn_mask & BTN_MASK_LEFT)   ? COLOR_GOLD : 0x4208, COLOR_PANEL_BG, 1);
  draw_text(bx + 18,  by, "10", (btn_mask & BTN_MASK_ROTATE) ? COLOR_GOLD : 0x4208, COLOR_PANEL_BG, 1);
  draw_text(bx + 44,  by, "11", (btn_mask & BTN_MASK_RIGHT)  ? COLOR_GOLD : 0x4208, COLOR_PANEL_BG, 1);
  draw_text(bx + 70,  by, "14", (btn_mask & BTN_MASK_DROP)   ? COLOR_GOLD : 0x4208, COLOR_PANEL_BG, 1);
  draw_text(bx + 96,  by, "SW", (btn_mask & BTN_MASK_SW2)    ? COLOR_GOLD : 0x4208, COLOR_PANEL_BG, 1);
  if (own) tile_close();
}

static void render_controls_help(void)
{
  // Thanh hướng dẫn phím đặt ở đáy màn hình (cách lề trái an toàn 56px)
  int hy = 746;
  bool own = tile_open_portrait(56, hy, 368, 38, COLOR_PANEL_BG, false);
  draw_rect(56, hy, 368, 38, COLOR_PANEL_BG);
  draw_border(56, hy, 368, 38, COLOR_BORDER_CYAN, 1);
  draw_text(64, hy + 10, "P9:< P10:^ P11:> P14:v", COLOR_WHITE, COLOR_PANEL_BG, 1);
  render_button_indicators(0);
  if (own) tile_close();
}

static void render_full_screen(void)
{
  // 1. Phủ màu nền đen toàn màn hình (xóa sạch toàn bộ HyperRAM)
  lcd_clear(COLOR_BG);

  // 2. Banner Game "T E T R I S" ở đầu màn hình (Căn giữa ngang: X = 105..369)
  int tx = 105;
  int ty = 8;
  draw_text(tx,       ty, "T", 0xF800, 0, 3);
  draw_text(tx + 48,  ty, "E", 0xFD20, 0, 3);
  draw_text(tx + 96,  ty, "T", 0xFFE0, 0, 3);
  draw_text(tx + 144, ty, "R", 0x27E0, 0, 3);
  draw_text(tx + 192, ty, "I", 0x07FF, 0, 3);
  draw_text(tx + 240, ty, "S", 0xD1BF, 0, 3);

  // 3. Khung bàn cờ chính giữa màn hình (neon double border, cách lề trái 56px)
  draw_rect(BOARD_PX_X, BOARD_PX_Y, BOARD_PX_W, BOARD_PX_H, COLOR_BOARD_BG);
  {
    const int bx = BOARD_PX_X, by = BOARD_PX_Y, bw = BOARD_PX_W, bh = BOARD_PX_H;
    // Hai dải ngang (đỉnh/đáy) dựng trong tile vì dòng ngắn
    bool t = tile_open_portrait(bx - 4, by - 4, bw + 8, 4, COLOR_BLACK, false);
    draw_rect(bx - 4, by - 4, bw + 8, 2, COLOR_BORDER_CYAN);
    draw_rect(bx - 2, by - 2, bw + 4, 1, COLOR_BORDER_MAG);
    if (t) tile_close();
    t = tile_open_portrait(bx - 4, by + bh, bw + 8, 4, COLOR_BLACK, false);
    draw_rect(bx - 2, by + bh + 1, bw + 4, 1, COLOR_BORDER_MAG);
    draw_rect(bx - 4, by + bh + 2, bw + 8, 2, COLOR_BORDER_CYAN);
    if (t) tile_close();
    // Bốn cạnh dọc dài: ghi tuần tự trực tiếp
    draw_rect(bx - 4, by - 4, 2, bh + 8, COLOR_BORDER_CYAN);
    draw_rect(bx + bw + 2, by - 4, 2, bh + 8, COLOR_BORDER_CYAN);
    draw_rect(bx - 2, by - 2, 1, bh + 4, COLOR_BORDER_MAG);
    draw_rect(bx + bw + 1, by - 2, 1, bh + 4, COLOR_BORDER_MAG);
  }

  // 4. Vẽ các chấm lưới bàn cờ
  for (int r = 0; r < BOARD_ROWS; r++) {
    for (int c = 0; c < BOARD_COLS; c++) {
      draw_empty_cell(c, r);
    }
  }

  // 5. Thẻ thống kê bên trái, ô Next piece bên phải và thanh phím đáy màn hình
  render_stats_panel();
  render_next_piece_box();
  render_controls_help();
}

// Nội dung từng ô ĐANG hiển thị trên màn hình (mã: 0 trống, 1..7 khối cố định,
// 0x10|loại khối đang rơi, 0x20|loại bóng, 0xFF = chưa biết, buộc vẽ lại).
// Chỉ ô nào đổi mới vẽ lại: vẽ cả bàn mỗi lần mất >100 ms và làm lỡ phím bấm.
static uint8_t s_shown[BOARD_ROWS][BOARD_COLS];

static void invalidate_playfield(void)
{
  memset(s_shown, 0xFF, sizeof(s_shown));
}

// Vẽ lại bàn cờ và khối đang rơi (chỉ các ô thay đổi)
static void render_playfield(void)
{
  int ghost_y = get_ghost_y();
  bool live = !s_game_over && !s_paused;
  uint8_t want[BOARD_ROWS][BOARD_COLS];

  for (int r = 0; r < BOARD_ROWS; r++) {
    for (int c = 0; c < BOARD_COLS; c++) {
      want[r][c] = s_board[r][c];
    }
  }
  if (live) {
    for (int i = 0; i < 4; i++) {
      int gx = s_cur_x + SHAPES[s_cur_type - 1][s_cur_rot][i][0];
      int gy = ghost_y + SHAPES[s_cur_type - 1][s_cur_rot][i][1];
      if (gx >= 0 && gx < BOARD_COLS && gy >= 0 && gy < BOARD_ROWS && want[gy][gx] == 0) {
        want[gy][gx] = (uint8_t)(0x20 | s_cur_type);
      }
    }
    for (int i = 0; i < 4; i++) {
      int cx = s_cur_x + SHAPES[s_cur_type - 1][s_cur_rot][i][0];
      int cy = s_cur_y + SHAPES[s_cur_type - 1][s_cur_rot][i][1];
      if (cx >= 0 && cx < BOARD_COLS && cy >= 0 && cy < BOARD_ROWS && s_board[cy][cx] == 0) {
        want[cy][cx] = (uint8_t)(0x10 | s_cur_type);
      }
    }
  }

  for (int r = 0; r < BOARD_ROWS; r++) {
    for (int c = 0; c < BOARD_COLS; c++) {
      uint8_t v = want[r][c];
      if (v == s_shown[r][c]) continue;
      s_shown[r][c] = v;

      int px = BOARD_PX_X + c * CELL_W;
      int py = BOARD_PX_Y + r * CELL_H;
      if (v == 0) {
        draw_empty_cell(c, r);
      } else if (v < 0x10) {
        draw_block_3d(px, py, PIECE_COLORS[v]);
      } else if (v < 0x20) {
        draw_block_3d(px, py, PIECE_COLORS[v & 0x0F]);
      } else {
        draw_ghost_block(px, py, PIECE_COLORS[v & 0x0F]);
      }
    }
  }
}

// =========================================================================
// XỬ LÝ DÒNG ĂN ĐIỂM VÀ HIỆU ỨNG
// =========================================================================

static void clear_lines(void)
{
  int lines_cleared = 0;
  int cleared_rows[4];

  for (int r = BOARD_ROWS - 1; r >= 0; r--) {
    bool full = true;
    for (int c = 0; c < BOARD_COLS; c++) {
      if (s_board[r][c] == 0) { full = false; break; }
    }
    if (full) {
      cleared_rows[lines_cleared++] = r;
    }
  }

  if (lines_cleared == 0) return;

  // Hiệu ứng chớp sáng trắng dòng ăn được (Flash Animation)
  for (int i = 0; i < lines_cleared; i++) {
    int r = cleared_rows[i];
    int py = BOARD_PX_Y + r * CELL_H;
    draw_rect(BOARD_PX_X, py, BOARD_PX_W, CELL_H, COLOR_WHITE);
  }
  board_led_toggle(3);
  UTIL_IdleMs(70);
  invalidate_playfield(); // các hàng chớp trắng đã đè lên bàn cờ

  // Xóa các dòng và dồn bàn cờ xuống
  for (int i = 0; i < lines_cleared; i++) {
    int target_r = cleared_rows[i] + i;
    for (int r = target_r; r > 0; r--) {
      for (int c = 0; c < BOARD_COLS; c++) {
        s_board[r][c] = s_board[r - 1][c];
      }
    }
    for (int c = 0; c < BOARD_COLS; c++) {
      s_board[0][c] = 0;
    }
  }

  // Cộng điểm theo chuẩn Tetris
  uint32_t base_score = 0;
  switch (lines_cleared) {
    case 1: base_score = 100; break;
    case 2: base_score = 300; break;
    case 3: base_score = 500; break;
    case 4: base_score = 800; break; // TETRIS!
  }
  s_score += base_score * s_level;
  if (s_score > s_high_score) {
    s_high_score = s_score;
  }
  s_lines += lines_cleared;

  // Tăng Level mỗi 10 dòng
  s_level = (s_lines / 10) + 1;
  if (s_level > 10) s_level = 10;

  render_stats_panel();
}

static void spawn_piece(void)
{
  s_cur_type = s_next_type;
  s_cur_rot  = 0;
  s_cur_x    = 4;
  s_cur_y    = 0;
  s_next_type = get_next_piece();

  render_next_piece_box();

  // Kiểm tra Game Over khi khối mới xuất hiện đã bị chạm
  if (check_collision(s_cur_type, s_cur_rot, s_cur_x, s_cur_y)) {
    s_game_over = true;
    printf("[TETRIS] GAME OVER! Diem so: %u\n", (unsigned)s_score);
    board_led_set(4, true);

    // Hiển thị hộp Game Over ngay giữa bàn cờ dọc
    int box_w = 280;
    int box_h = 120;
    int box_x = BOARD_PX_X + (BOARD_PX_W - box_w) / 2;
    int box_y = BOARD_PX_Y + (BOARD_PX_H - box_h) / 2;

    bool own = tile_open_portrait(box_x, box_y, box_w, box_h, COLOR_PANEL_BG, false);
    draw_rect(box_x, box_y, box_w, box_h, COLOR_PANEL_BG);
    draw_border(box_x, box_y, box_w, box_h, 0xF800, 2);
    draw_text(box_x + 68, box_y + 20, "GAME OVER", 0xF800, COLOR_PANEL_BG, 2);
    draw_text(box_x + 88, box_y + 64, "Press SW2 / R", COLOR_WHITE, COLOR_PANEL_BG, 1);
    draw_text(box_x + 100, box_y + 86, "To Restart", COLOR_GOLD, COLOR_PANEL_BG, 1);
    if (own) tile_close();
  }
}

static void restart_game(void)
{
  memset(s_board, 0, sizeof(s_board));
  s_score = 0;
  s_lines = 0;
  s_level = 1;
  s_game_over = false;
  s_paused = false;
  s_bag_idx = 7;

  lcd_clear(0);
  s_next_type = get_next_piece();
  spawn_piece();
  render_full_screen();
  invalidate_playfield();
  render_playfield();
  board_led_set_all(0);
  printf("[TETRIS] Tro choi da duoc khoi dong lai o che do xoay doc (Portrait 480x800)!\n");
}

// =========================================================================
// KHỞI TẠO VÀ VÒNG LẶP CHÍNH
// =========================================================================

void tetris_init(void)
{
  printf("\n[TETRIS] Khoi dong dong co Game Tetris Arcade xoay doc 480x800...\n");
  s_rand_seed = UTIL_GetTick() ^ 0x5A5A5A5A;
  if (s_rand_seed == 0) s_rand_seed = 12345;

  lcd_clear(0);
  restart_game();
}

void tetris_run(void)
{
  uint32_t last_gravity_tick = UTIL_GetTick();
  uint32_t last_led_tick = UTIL_GetTick();
  uint32_t last_dma_tick = UTIL_GetTick();
  int dma_alive_prev = -1;   // -1: chưa biết; 1: DMA quét đang chạy; 0: DMA bị đứng
  unsigned dma_stall_count = 0;
  uint32_t now;

  while (1) {
    now = UTIL_GetTick();

    // Giám sát DMA quét màn hình mỗi 1 s: số khối còn lại (bit 31..16 của CTRL) phải thay đổi liên tục.
    // Nếu đứng yên thì CPLD/HyperRAM đã ngừng xuất hình; nếu vẫn chạy mà màn đen thì lỗi ở phía panel/cáp/nguồn.
    if (now - last_dma_tick >= 1000) {
      last_dma_tick = now;
      uint32_t a = RD_REG(HRAM_DMA_CTRL);
      UTIL_IdleUs(300);
      uint32_t b = RD_REG(HRAM_DMA_CTRL);
      int alive = ((a >> 16) != (b >> 16)) && (a & 1);
      if (!alive) dma_stall_count++;
      if (alive != dma_alive_prev) {
        printf("[DMA] %s (CTRL 0x%08X -> 0x%08X, lan dung: %u)\n",
               alive ? "QUET MAN HINH DANG CHAY" : "!!! DMA QUET BI DUNG !!!",
               (unsigned)a, (unsigned)b, dma_stall_count);
        dma_alive_prev = alive;
      }
    }

    // Nhấp nháy LED trạng thái Heartbeat mỗi 500 ms
    if (now - last_led_tick > 500) {
      board_led_toggle(2);
      last_led_tick = now;
    }

    // ---------------------------------------------------------------------
    // 1. ĐỌC PHÍM NHẤN (Bộ lọc chống dội 35ms Lockout + UART0 Console)
    // ---------------------------------------------------------------------
    board_buttons_update();
    uint8_t btn_held    = board_buttons_get_state();
    uint8_t btn_pressed = board_buttons_get_pressed();

    // Cập nhật đèn báo nút bấm trực tiếp lên màn hình và UART
    static uint8_t s_last_btn_held = 0xFF;
    if (btn_held != s_last_btn_held) {
      render_button_indicators(btn_held);
      s_last_btn_held = btn_held;
      if (btn_held != 0) {
        printf("[BTN] Giu nut: %s%s%s%s%s (GPIO=0x%02X)\n",
               (btn_held & BTN_MASK_LEFT)   ? "PIN9 "  : "",
               (btn_held & BTN_MASK_ROTATE) ? "PIN10 " : "",
               (btn_held & BTN_MASK_RIGHT)  ? "PIN11 " : "",
               (btn_held & BTN_MASK_DROP)   ? "PIN14 " : "",
               (btn_held & BTN_MASK_SW2)    ? "SW2 "   : "",
               board_buttons_get_raw_gpio());
      }
    }

    if (btn_pressed != 0) {
      printf("[BTN] Bam nut: %s%s%s%s%s\n",
             (btn_pressed & BTN_MASK_LEFT)   ? "LEFT(P9) "    : "",
             (btn_pressed & BTN_MASK_ROTATE) ? "ROTATE(P10) " : "",
             (btn_pressed & BTN_MASK_RIGHT)  ? "RIGHT(P11) "  : "",
             (btn_pressed & BTN_MASK_DROP)   ? "DROP(P14) "   : "",
             (btn_pressed & BTN_MASK_SW2)    ? "SW2 "         : "");
    }

    char uart_ch = 0;
    while (!UART_IsRxFifoEmpty(UART0)) {
      uart_ch = (char)UART_ReceiveData(UART0);
    }

    bool act_left_press  = (btn_pressed & BTN_MASK_LEFT)  || (uart_ch == 'a' || uart_ch == 'A');
    bool act_left_hold   = (btn_held & BTN_MASK_LEFT)     || (uart_ch == 'a' || uart_ch == 'A');
    bool act_right_press = (btn_pressed & BTN_MASK_RIGHT) || (uart_ch == 'd' || uart_ch == 'D');
    bool act_right_hold  = (btn_held & BTN_MASK_RIGHT)    || (uart_ch == 'd' || uart_ch == 'D');
    bool act_rotate      = (btn_pressed & BTN_MASK_ROTATE)|| (uart_ch == 'w' || uart_ch == 'W');
    bool act_drop        = (btn_held & BTN_MASK_DROP)     || (uart_ch == 's' || uart_ch == 'S');
    bool act_hard        = (uart_ch == ' ');
    bool act_pause       = (btn_pressed & BTN_MASK_SW2)   || (uart_ch == 'p' || uart_ch == 'P');
    bool act_restart     = ((btn_pressed & BTN_MASK_SW2) && s_game_over) || (uart_ch == 'r' || uart_ch == 'R');
    bool act_flip        = (uart_ch == 'o' || uart_ch == 'O' || uart_ch == 'f' || uart_ch == 'F');

    // Phím đổi hướng xoay 180 độ (nếu cầm ngược chiều)
    if (act_flip) {
      s_portrait_flip = !s_portrait_flip;
      lcd_clear(0);
      render_full_screen();
      invalidate_playfield();
      render_playfield();
      printf("[TETRIS] Da dao chieu man hinh doc: %s (Bam 'O' de dao nguoc)\n", 
             s_portrait_flip ? "270 do" : "90 do");
      continue;
    }

    // Xử lý Restart
    if (act_restart) {
      restart_game();
      last_gravity_tick = now;
      continue;
    }

    // Xử lý Pause
    if (act_pause && !s_game_over) {
      s_paused = !s_paused;
      if (s_paused) {
        printf("[TETRIS] TAM DUNG (PAUSED). Bam SW2 hoac P de tiep tuc.\n");
        int box_w = 240;
        int box_h = 80;
        int box_x = BOARD_PX_X + (BOARD_PX_W - box_w) / 2;
        int box_y = BOARD_PX_Y + (BOARD_PX_H - box_h) / 2;
        bool own = tile_open_portrait(box_x, box_y, box_w, box_h, COLOR_PANEL_BG, false);
        draw_rect(box_x, box_y, box_w, box_h, COLOR_PANEL_BG);
        draw_border(box_x, box_y, box_w, box_h, COLOR_GOLD, 2);
        draw_text(box_x + 72, box_y + 28, "PAUSED", COLOR_GOLD, COLOR_PANEL_BG, 2);
        if (own) tile_close();
      } else {
        printf("[TETRIS] TIEP TUC CHOI (RESUMED).\n");
        invalidate_playfield(); // hộp PAUSED đã đè lên bàn cờ
        render_playfield();
      }
      UTIL_IdleMs(100);
      continue;
    }

    if (s_game_over || s_paused) {
      UTIL_IdleMs(10);
      continue;
    }

    bool field_changed = false;

    // ---------------------------------------------------------------------
    // 2. XỬ LÝ DI CHUYỂN SANG TRÁI (DAS - Delayed Auto Shift)
    // ---------------------------------------------------------------------
    if (act_left_press) {
      s_left_start_tick = now;
      s_last_left_repeat = now;
      if (!check_collision(s_cur_type, s_cur_rot, s_cur_x - 1, s_cur_y)) {
        s_cur_x--;
        field_changed = true;
      }
    } else if (act_left_hold) {
      if (s_left_start_tick != 0 && (now - s_left_start_tick > 160) && (now - s_last_left_repeat > 50)) {
        s_last_left_repeat = now;
        if (!check_collision(s_cur_type, s_cur_rot, s_cur_x - 1, s_cur_y)) {
          s_cur_x--;
          field_changed = true;
        }
      }
    } else {
      s_left_start_tick = 0;
    }

    // ---------------------------------------------------------------------
    // 3. XỬ LÝ DI CHUYỂN SANG PHẢI (DAS)
    // ---------------------------------------------------------------------
    if (act_right_press) {
      s_right_start_tick = now;
      s_last_right_repeat = now;
      if (!check_collision(s_cur_type, s_cur_rot, s_cur_x + 1, s_cur_y)) {
        s_cur_x++;
        field_changed = true;
      }
    } else if (act_right_hold) {
      if (s_right_start_tick != 0 && (now - s_right_start_tick > 160) && (now - s_last_right_repeat > 50)) {
        s_last_right_repeat = now;
        if (!check_collision(s_cur_type, s_cur_rot, s_cur_x + 1, s_cur_y)) {
          s_cur_x++;
          field_changed = true;
        }
      }
    } else {
      s_right_start_tick = 0;
    }

    // ---------------------------------------------------------------------
    // 4. XỬ LÝ XOAY KHỐI (Có Wall-Kick thông minh, chống dội 100%)
    // ---------------------------------------------------------------------
    if (act_rotate) {
      int next_rot = (s_cur_rot + 1) % 4;

      if (!check_collision(s_cur_type, next_rot, s_cur_x, s_cur_y)) {
        s_cur_rot = next_rot;
        field_changed = true;
      } else if (!check_collision(s_cur_type, next_rot, s_cur_x - 1, s_cur_y)) {
        // Wall kick sang trái
        s_cur_x -= 1;
        s_cur_rot = next_rot;
        field_changed = true;
      } else if (!check_collision(s_cur_type, next_rot, s_cur_x + 1, s_cur_y)) {
        // Wall kick sang phải
        s_cur_x += 1;
        s_cur_rot = next_rot;
        field_changed = true;
      }
    }

    // ---------------------------------------------------------------------
    // 5. XỬ LÝ RƠI NHANH (Soft Drop) VÀ THẢ RƠI (Hard Drop)
    // ---------------------------------------------------------------------
    if (act_hard) {
      // Hard drop: Thả thẳng xuống bóng
      int gy = get_ghost_y();
      s_score += (gy - s_cur_y) * 2;
      s_cur_y = gy;

      for (int i = 0; i < 4; i++) {
        int x = s_cur_x + SHAPES[s_cur_type - 1][s_cur_rot][i][0];
        int y = s_cur_y + SHAPES[s_cur_type - 1][s_cur_rot][i][1];
        if (y >= 0 && y < BOARD_ROWS && x >= 0 && x < BOARD_COLS) {
          s_board[y][x] = (uint8_t)s_cur_type;
        }
      }
      clear_lines();
      spawn_piece();
      field_changed = true;
      last_gravity_tick = now;
    } else if (act_drop) {
      // Soft drop: rơi mỗi 50 ms
      if (now - s_last_drop_tick > 50) {
        s_last_drop_tick = now;
        if (!check_collision(s_cur_type, s_cur_rot, s_cur_x, s_cur_y + 1)) {
          s_cur_y++;
          s_score += 1;
          field_changed = true;
          last_gravity_tick = now;
        }
      }
    }

    // ---------------------------------------------------------------------
    // 6. TRỌNG LỰC TỰ NHIÊN (Gravity Step)
    // ---------------------------------------------------------------------
    uint16_t gravity_interval = LEVEL_SPEED_MS[(s_level > 10 ? 10 : s_level) - 1];
    if (now - last_gravity_tick >= gravity_interval) {
      last_gravity_tick = now;
      if (!check_collision(s_cur_type, s_cur_rot, s_cur_x, s_cur_y + 1)) {
        s_cur_y++;
        field_changed = true;
      } else {
        // Chạm đáy hoặc chạm khối khác: Cố định khối vào bàn cờ
        for (int i = 0; i < 4; i++) {
          int x = s_cur_x + SHAPES[s_cur_type - 1][s_cur_rot][i][0];
          int y = s_cur_y + SHAPES[s_cur_type - 1][s_cur_rot][i][1];
          if (y >= 0 && y < BOARD_ROWS && x >= 0 && x < BOARD_COLS) {
            s_board[y][x] = (uint8_t)s_cur_type;
          }
        }
        clear_lines();
        spawn_piece();
        field_changed = true;
      }
    }

    // ---------------------------------------------------------------------
    // 7. CẬP NHẬT HIỂN THỊ
    // ---------------------------------------------------------------------
    if (field_changed && !s_game_over) {
      render_playfield();
    }

    UTIL_IdleMs(8);
  }
}
