#ifndef TETRIS_H
#define TETRIS_H

#include <stdint.h>
#include <stdbool.h>

// Khởi tạo trò chơi Tetris (cấu hình màn hình, xóa bộ đệm, sinh tetromino ngẫu nhiên)
void tetris_init(void);

// Vòng lặp chính trò chơi Tetris (xử lý phím bấm vật lý, phím UART, logic rơi, đồ họa)
void tetris_run(void);

#endif // TETRIS_H

