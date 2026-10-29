#include "board_hw.h"
#include "fcb.h"
#include "util.h"

static uint8_t s_led_state = 0;

// Các biến phục vụ chống dội phím (Leading-Edge Lockout Debounce)
#define DEBOUNCE_LOCKOUT_MS 35  // Thời gian khóa chống dội (35 ms)

static uint8_t  s_idle_state = 0xFF;         // Trạng thái nghỉ đo lúc khởi động
static uint8_t  s_debounced_state = 0;      // Trạng thái nút đã lọc ổn định (1 = đang nhấn)
static uint8_t  s_just_pressed_events = 0;  // Sự kiện vừa bấm mới (Single-shot edge trigger)
static uint32_t s_last_press_time[5] = {0}; // Mốc thời gian kích hoạt phím
static uint32_t s_last_release_time[5] = {0};

void board_hw_init(void)
{
  board_init();

  // 1. Cấu hình GPIO cho 3 LED (L2=PIN_54, L3=PIN_53, L4=PIN_52) trên PORT4
  SYS_EnableAPBClock(APB_MASK_GPIO4);
  GPIO_SetOutput(LED_GPIO, LED_ALL_BITS);
  // Mặc định tắt (Active-Low)
  GPIO_SetHigh(LED_GPIO, LED_ALL_BITS);
  s_led_state = 0;

  // 2. Cấu hình nút nhấn SW2 trên PORT6
  SYS_EnableAPBClock(APB_MASK_GPIO6);
  GPIO_SetInput(SW2_GPIO, SW2_BIT);

  // 3. Cấu hình 4 nút nhấn mở rộng trên header H1 (PORT2)
  SYS_EnableAPBClock(APB_MASK_GPIO2);
  GPIO_SetInput(BTN_GPIO, BTN_ALL_BITS);

  // Kéo trở nội PULL_UP cho các chân nút bấm (PIN_9, 10, 11, 14)
  FCB_IO_TypeDef io_cfg;
  FCB_PIN_TypeDef pin_cfg;
  FCB_ReadIOConfig(&io_cfg);

  const int btn_pins[] = {
    AGRV2KL64_PIN_9_ID,
    AGRV2KL64_PIN_10_ID,
    AGRV2KL64_PIN_11_ID,
    AGRV2KL64_PIN_14_ID
  };

  for (int i = 0; i < 4; i++) {
    FCB_GetPinConfig(&io_cfg, btn_pins[i], &pin_cfg);
    FCB_PIN_SetPullMode(&pin_cfg, FCB_PIN_PULL_UP);
    FCB_PIN_SetInputEnabled(&pin_cfg, true);
    FCB_SetPinConfig(&io_cfg, btn_pins[i], &pin_cfg);
  }
  FCB_WriteIOConfig(&io_cfg);


  // Chờ 50ms cho các chân ổn định điện áp
  UTIL_IdleMs(50);

  // Đọc mẫu trạng thái chân ban đầu (Baseline) để hỗ trợ cả Pull-Up lẫn Pull-Down
  s_idle_state = GPIO_GetValue(BTN_GPIO, BTN_ALL_BITS);

  printf("\n[BSP] Bo mach AG32VF407 khoi tao thanh cong.\n");
  printf("[BSP] SysClk: %d MHz, PClk: %d MHz\n", 
         SYS_GetSysClkFreq() / 1000000, 
         SYS_GetPclkFreq() / 1000000);
  printf("[BSP] 3 LED da cau hinh: PIN_54 (L2), PIN_53 (L3), PIN_52 (L4).\n");
  printf("[BSP] Trang thai chan nut bam luc khoi dong (Idle Baseline): 0x%02X\n", s_idle_state);
  printf("[BSP]   PIN_9  (Trai) : %s\n", (s_idle_state & BTN_LEFT_BIT)   ? "HIGH (bam keo GND)" : "LOW (bam noi 3.3V)");
  printf("[BSP]   PIN_10 (Xoay) : %s\n", (s_idle_state & BTN_ROTATE_BIT) ? "HIGH (bam keo GND)" : "LOW (bam noi 3.3V)");
  printf("[BSP]   PIN_11 (Phai) : %s\n", (s_idle_state & BTN_RIGHT_BIT)  ? "HIGH (bam keo GND)" : "LOW (bam noi 3.3V)");
  printf("[BSP]   PIN_14 (Roi)  : %s\n", (s_idle_state & BTN_DROP_BIT)   ? "HIGH (bam keo GND)" : "LOW (bam noi 3.3V)");
  printf("[BSP] Bo loc phím chong doi tuc thi (Instant Lockout 35ms) san sang.\n");
}

void board_led_set(uint8_t num, bool state)
{
  uint8_t bit_mask = 0;
  switch (num) {
    case 2: bit_mask = LED_L2_BIT; break;
    case 3: bit_mask = LED_L3_BIT; break;
    case 4: bit_mask = LED_L4_BIT; break;
    default: return;
  }

  if (state) {
    GPIO_SetLow(LED_GPIO, bit_mask); // Bật LED (Active-Low)
    s_led_state |= (1 << (num - 1));
  } else {
    GPIO_SetHigh(LED_GPIO, bit_mask); // Tắt LED
    s_led_state &= ~(1 << (num - 1));
  }
}

void board_led_toggle(uint8_t num)
{
  if (num >= 2 && num <= 4) {
    bool current = (s_led_state & (1 << (num - 1))) != 0;
    board_led_set(num, !current);
  }
}

void board_led_set_all(uint8_t mask)
{
  for (uint8_t i = 2; i <= 4; i++) {
    board_led_set(i, (mask & (1 << (i - 1))) != 0);
  }
}

bool board_button_is_pressed(void)
{
  // Nút SW2 nối xuống GND khi bấm (Active-Low)
  return (GPIO_GetValue(SW2_GPIO, SW2_BIT) == 0);
}

uint8_t board_buttons_get_raw_gpio(void)
{
  return GPIO_GetValue(BTN_GPIO, BTN_ALL_BITS);
}

uint8_t board_buttons_read_raw(void)
{
  uint8_t val = GPIO_GetValue(BTN_GPIO, BTN_ALL_BITS);
  // Tự động nhận diện thay đổi so với trạng thái nghỉ ban đầu (s_idle_state)
  // Hỗ trợ cả mạch nối GND (Pull-Up) lẫn mạch nối 3.3V (Pull-Down)
  uint8_t changed = (val ^ s_idle_state) & BTN_ALL_BITS;

  uint8_t res = 0;
  if (changed & BTN_LEFT_BIT)   res |= BTN_MASK_LEFT;
  if (changed & BTN_ROTATE_BIT) res |= BTN_MASK_ROTATE;
  if (changed & BTN_RIGHT_BIT)  res |= BTN_MASK_RIGHT;
  if (changed & BTN_DROP_BIT)   res |= BTN_MASK_DROP;

  if (board_button_is_pressed()) {
    res |= BTN_MASK_SW2;
  }

  return res;
}

void board_buttons_update(void)
{
  uint32_t now = UTIL_GetTick();
  uint8_t raw = board_buttons_read_raw();

  for (int i = 0; i < 5; i++) {
    uint8_t mask = (1 << i);
    bool raw_pressed = (raw & mask) != 0;
    bool curr_pressed = (s_debounced_state & mask) != 0;

    if (raw_pressed && !curr_pressed) {
      // Sườn lên (Vừa nhấn): Kích hoạt tức thì nếu đã qua thời gian lockout
      if (now - s_last_release_time[i] >= DEBOUNCE_LOCKOUT_MS) {
        s_debounced_state |= mask;
        s_just_pressed_events |= mask;
        s_last_press_time[i] = now;
      }
    } else if (!raw_pressed && curr_pressed) {
      // Sườn xuống (Nhả ra): Tắt trạng thái giữ sau lockout
      if (now - s_last_press_time[i] >= DEBOUNCE_LOCKOUT_MS) {
        s_debounced_state &= ~mask;
        s_last_release_time[i] = now;
      }
    }
  }
}

uint8_t board_buttons_get_state(void)
{
  return s_debounced_state;
}

uint8_t board_buttons_get_pressed(void)
{
  uint8_t evt = s_just_pressed_events;
  s_just_pressed_events = 0; // Xóa sau khi đọc (Single-shot edge trigger)
  return evt;
}

uint8_t board_buttons_read(void)
{
  board_buttons_update();
  return board_buttons_get_state();
}
