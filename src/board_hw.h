#ifndef BOARD_HW_H
#define BOARD_HW_H

#include "board.h"
#include <stdio.h>
#include <stdbool.h>

// Định nghĩa 3 LED thực tế trên bo mạch TCX (PIN_54, PIN_53, PIN_52):
// L2 -> PIN_54 (GPIO4_1)
// L3 -> PIN_53 (GPIO4_2)
// L4 -> PIN_52 (GPIO4_3)
#define LED_GPIO      GPIO4
#define LED_L2_BIT    GPIO_BIT1  // PIN_54
#define LED_L3_BIT    GPIO_BIT2  // PIN_53
#define LED_L4_BIT    GPIO_BIT3  // PIN_52
#define LED_ALL_BITS  (LED_L2_BIT | LED_L3_BIT | LED_L4_BIT)

// Nút nhấn người dùng SW2 trên bo mạch (PIN_51 / GPIO6_2)
#define SW2_GPIO      GPIO6
#define SW2_BIT       GPIO_BIT2

// 4 nút nhấn mở rộng trên header H1 (kết nối Active-Low: nhấn = nối GND)
// H1 Pin 1 (PIN_9)  -> BTN_LEFT   (Sang trái)
// H1 Pin 2 (PIN_10) -> BTN_ROTATE (Xoay khối)
// H1 Pin 3 (PIN_11) -> BTN_RIGHT  (Sang phải)
// H1 Pin 4 (PIN_14) -> BTN_DROP   (Rơi nhanh)
#define BTN_GPIO        GPIO2
#define BTN_LEFT_BIT    GPIO_BIT0 // PIN_9  (H1 Pin 1)
#define BTN_ROTATE_BIT  GPIO_BIT1 // PIN_10 (H1 Pin 2)
#define BTN_RIGHT_BIT   GPIO_BIT2 // PIN_11 (H1 Pin 3)
#define BTN_DROP_BIT    GPIO_BIT3 // PIN_14 (H1 Pin 4)
#define BTN_ALL_BITS    (BTN_LEFT_BIT | BTN_ROTATE_BIT | BTN_RIGHT_BIT | BTN_DROP_BIT)

// Bitmask tiện ích cho các nút
#define BTN_MASK_LEFT    (1 << 0)
#define BTN_MASK_ROTATE  (1 << 1)
#define BTN_MASK_RIGHT   (1 << 2)
#define BTN_MASK_DROP    (1 << 3)
#define BTN_MASK_SW2     (1 << 4)

void board_hw_init(void);

// Điều khiển LED: num = 2 (L2), 3 (L3), 4 (L4)
void board_led_set(uint8_t num, bool state);
void board_led_toggle(uint8_t num);
void board_led_set_all(uint8_t mask);

// Đọc nút SW2 trên bo mạch (true = đang nhấn)
bool board_button_is_pressed(void);

// Đọc trạng thái thô chưa lọc của tất cả nút
uint8_t board_buttons_read_raw(void);

// Hàm cập nhật bộ lọc chống dội (chạy mỗi chu kỳ lặp)
void board_buttons_update(void);

// Đọc trạng thái giữ ổn định sau khi đã chống dội (1 = đang giữ)
uint8_t board_buttons_get_state(void);

// Đọc sự kiện vừa nhấn (chỉ 1 xung duy nhất tại sườn xuống, tự xóa sau khi đọc)
uint8_t board_buttons_get_pressed(void);

// Đọc trực tiếp mức logic chân GPIO (PIN_9, 10, 11, 14)
uint8_t board_buttons_get_raw_gpio(void);

// Đọc nút (tương thích ngược)
uint8_t board_buttons_read(void);

#endif // BOARD_HW_H
