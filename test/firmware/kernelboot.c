// SPDX-FileCopyrightText: © 2023-2026 Uri Shaked <uri@wokwi.com>
// SPDX-FileCopyrightText: © 2023-2026 Hirosh Dabui <hirosh@dabui.de>
// SPDX-License-Identifier: MIT

#include <stdatomic.h>
#include <stddef.h>
#include <stdint.h>

#define IO_BASE 0x10000000
#define UART_TX (IO_BASE)
#define UART_RX (IO_BASE)
#define UART_LSR (IO_BASE + 0x5)
#define SPI_DIV (IO_BASE + 0x500010)
#define LSR_THRE 0x20
#define LSR_TEMT 0x40
#define LSR_DR 0x01

#define GPIO_BASE 0x10000700
#define GPIO_UO_EN (GPIO_BASE + 0x0000)
#define GPIO_UO_OUT (GPIO_BASE + 0x0004)
#define GPIO_UI_IN (GPIO_BASE + 0x0008)

#define MTIME (*((volatile uint64_t *)0x0200bff8))

#define PSRAM0_BASE 0x80000000u
#define PSRAM_SEG_SZ 0x00800000u
#define PSRAM1_BASE (PSRAM0_BASE + 1u * PSRAM_SEG_SZ)
#define PSRAM2_BASE (PSRAM0_BASE + 2u * PSRAM_SEG_SZ)
#define PSRAM3_BASE (PSRAM0_BASE + 3u * PSRAM_SEG_SZ)

#define KIANV_QQSPI_CTRL 0x10600000u
#define REG32(a) (*(volatile uint32_t *)(uintptr_t)(a))

volatile char *uart_tx = (char *)UART_TX, *uart_rx = (char *)UART_RX,
              *uart_lsr = (char *)UART_LSR;
volatile uint32_t *gpio_uo_en = (volatile uint32_t *)GPIO_UO_EN,
                  *gpio_uo_out = (volatile uint32_t *)GPIO_UO_OUT,
                  *gpio_ui_in = (volatile uint32_t *)GPIO_UI_IN;
volatile atomic_uint interrupt_occurred = ATOMIC_VAR_INIT(0);

static inline void data_fence(void)
{
  __asm__ volatile("fence rw, rw" ::: "memory");
}

static inline void enable_interrupts(void) { asm volatile("csrsi mstatus, 8"); }
static inline void disable_interrupts(void) { asm volatile("csrci mstatus, 8"); }

void uart_putc(char c)
{
  while (!(*uart_lsr & (LSR_THRE | LSR_TEMT)))
    ;
  *uart_tx = c;
}

char uart_getc(void)
{
  while (!(*uart_lsr & LSR_DR))
    ;
  return *uart_rx;
}

void uart_puts(const char *s)
{
  while (*s)
    uart_putc(*s++);
}

void uart_puthex_byte(uint8_t byte)
{
  const char hex_chars[] = "0123456789ABCDEF";
  uart_putc(hex_chars[byte >> 4]);
  uart_putc(hex_chars[byte & 0xF]);
}

void uart_puthex(const void *data, size_t size)
{
  const uint8_t *bytes = (const uint8_t *)data;
  for (size_t i = 0; i < size; i++) {
    uart_puthex_byte(bytes[i]);
    uart_putc(' ');
  }
}

void setup_timer_interrupt(void)
{
  uint32_t mie;
  asm volatile("csrr %0, mie" : "=r"(mie));
  mie |= (1 << 7);
  asm volatile("csrw mie, %0" ::"r"(mie));
}

__attribute__((naked)) void timer_interrupt_handler(void)
{
  asm volatile(
    "addi sp, sp, -24\n"
    "sw x1, 4(sp)\n"
    "sw x2, 8(sp)\n"
    "sw t0, 12(sp)\n"
    "sw a4, 16(sp)\n"
    "sw a5, 20(sp)\n"
  );
  asm volatile("csrrc t0, mstatus, %0" : : "r"((uint32_t)(1 << 7)) : "t0");
  asm volatile("csrc mstatus, %0" ::"r"((uint32_t)(1 << 3)) : "t0");
  atomic_store(&interrupt_occurred, 1);
  asm volatile(
    "lw x1, 4(sp)\n"
    "lw x2, 8(sp)\n"
    "lw t0, 12(sp)\n"
    "lw a4, 16(sp)\n"
    "lw a5, 20(sp)\n"
    "addi sp, sp, 24\n"
    "mret\n"
  );
}

struct spi_regs {
  volatile uint32_t *ctrl, *data;
} spi = {(volatile uint32_t *)0x10500000, (volatile uint32_t *)0x10500004};

static void spi_set_cs(int cs_n) { *spi.ctrl = cs_n; }

static int spi_xfer(char *tx, char *rx)
{
  while ((*spi.ctrl & 0x80000000) != 0)
    ;
  *spi.data = (tx != NULL) ? *tx : 0;
  while ((*spi.ctrl & 0x80000000) != 0)
    ;
  if (rx)
    *rx = (char)(*spi.data);
  return 0;
}

uint8_t SPI_transfer(char tx)
{
  uint8_t rx;
  spi_xfer(&tx, (char *)&rx);
  return rx;
}

#define CS_ENABLE() spi_set_cs(1)
#define CS_DISABLE() spi_set_cs(0)

static inline uint32_t qqspi_ctrl_r(void)
{
  return REG32(KIANV_QQSPI_CTRL);
}

static inline void qqspi_ctrl_w_raw(uint32_t v)
{
  REG32(KIANV_QQSPI_CTRL) = v;
  data_fence();
  (void)qqspi_ctrl_r();
  data_fence();
}

static int test_psram_segments_verbose(void)
{
  volatile uint32_t *a0 = (volatile uint32_t *)PSRAM0_BASE;
  volatile uint32_t *a1 = (volatile uint32_t *)PSRAM1_BASE;
  volatile uint32_t *a2 = (volatile uint32_t *)PSRAM2_BASE;
  volatile uint32_t *a3 = (volatile uint32_t *)PSRAM3_BASE;

  volatile uint32_t *b0 = (volatile uint32_t *)(PSRAM0_BASE + 0x00001000u);
  volatile uint32_t *b1 = (volatile uint32_t *)(PSRAM1_BASE + 0x00001000u);
  volatile uint32_t *b2 = (volatile uint32_t *)(PSRAM2_BASE + 0x00001000u);
  volatile uint32_t *b3 = (volatile uint32_t *)(PSRAM3_BASE + 0x00001000u);

  uart_puts("RAM-HI START\n");

  *a0 = 0x11111111u;
  *a1 = 0x22222222u;
  *a2 = 0x33333333u;
  *a3 = 0x44444444u;
  data_fence();

  if (*a0 != 0x11111111u) {
    uart_puts("ALIAS FAIL PSRAM0\n");
    uart_puts("RAM-HI FAIL\n");
    return 0;
  }
  uart_puts("PSRAM0 OK\n");

  if (*a1 != 0x22222222u) {
    uart_puts("ALIAS FAIL PSRAM1\n");
    uart_puts("RAM-HI FAIL\n");
    return 0;
  }
  uart_puts("PSRAM1 OK\n");

  if (*a2 != 0x33333333u) {
    uart_puts("ALIAS FAIL PSRAM2\n");
    uart_puts("RAM-HI FAIL\n");
    return 0;
  }
  uart_puts("PSRAM2 OK\n");

  if (*a3 != 0x44444444u) {
    uart_puts("ALIAS FAIL PSRAM3\n");
    uart_puts("RAM-HI FAIL\n");
    return 0;
  }
  uart_puts("PSRAM3 OK\n");

  *b0 = 0xAAAAB000u;
  *b1 = 0xBBBBB111u;
  *b2 = 0xCCCCC222u;
  *b3 = 0xDDDDD333u;
  data_fence();

  if (*b0 != 0xAAAAB000u) {
    uart_puts("OFFSET FAIL PSRAM0\n");
    uart_puts("RAM-HI FAIL\n");
    return 0;
  }

  if (*b1 != 0xBBBBB111u) {
    uart_puts("OFFSET FAIL PSRAM1\n");
    uart_puts("RAM-HI FAIL\n");
    return 0;
  }

  if (*b2 != 0xCCCCC222u) {
    uart_puts("OFFSET FAIL PSRAM2\n");
    uart_puts("RAM-HI FAIL\n");
    return 0;
  }

  if (*b3 != 0xDDDDD333u) {
    uart_puts("OFFSET FAIL PSRAM3\n");
    uart_puts("RAM-HI FAIL\n");
    return 0;
  }

  uart_puts("RAM-HI OK\n");
  return 1;
}

int main(void)
{
  qqspi_ctrl_w_raw(0);
  setup_timer_interrupt();

  uint64_t interval = 2;
  volatile uint64_t *mtime = (volatile uint64_t *)0x0200bff8;
  volatile uint64_t *mtimecmp = (volatile uint64_t *)0x02004000;
  *mtimecmp = *mtime + interval;

  volatile uint32_t *spi_div = (volatile uint32_t *)SPI_DIV;
  (void)spi_div;

  enable_interrupts();

  // Original GPIO test path
  // Note: keep condition exactly as original firmware had it
  if (*gpio_ui_in & 1) {
    *gpio_uo_en = (1 << 9);
    *gpio_uo_out = (1 << 9);
    *gpio_uo_out = 0;
    *gpio_uo_out = (1 << 9);
    *gpio_uo_out = 0;
    *gpio_uo_out = (1 << 9);
    *gpio_uo_en = 0;
  }

  // Original SPI test
  uint8_t rx = 0;
  CS_ENABLE();
  if ((rx = SPI_transfer(0xde)) != (0xde >> 1))
    return 1;
  if ((rx = SPI_transfer(0xad)) != (0xad >> 1))
    return 1;
  if ((rx = SPI_transfer(0xbe)) != (0xdf >> 0))
    return 1;
  if ((rx = SPI_transfer(0xaf)) != (0xaf >> 1))
    return 1;
  CS_DISABLE();

  while (!atomic_load(&interrupt_occurred))
    ;

  // Must remain first UART payload for cocotb
  uart_puts("Hello UART\n");

  // Extended PSRAM segment test
  if (!test_psram_segments_verbose())
    return 1;

  // Original lowercase echo
  while (1) {
    char c = uart_getc();
    uart_putc((c >= 'A' && c <= 'Z') ? (char)(c + 32) : c);
  }

  return 0;
}
