// Minimal PEU sanity test: write operands, start, poll, and compare to SW ref.
#include <stdint.h>

#define PEU_BASE    0x10000000u
#define PEU_SRC0    (*(volatile uint32_t *)(PEU_BASE + 0x00))
#define PEU_SRC1    (*(volatile uint32_t *)(PEU_BASE + 0x04))
#define PEU_CTRL    (*(volatile uint32_t *)(PEU_BASE + 0x08))
#define PEU_STATUS  (*(volatile uint32_t *)(PEU_BASE + 0x0C))
#define PEU_RESULT  (*(volatile uint32_t *)(PEU_BASE + 0x10))

static void trap_success(void) __attribute__((noreturn));
static void trap_fail(void) __attribute__((noreturn));

static void trap_success(void) { asm volatile("ebreak"); for(;;); }
static void trap_fail(void) { for(;;); } // spin forever so testbench times out

int main(void) {
    uint32_t a = 0x12345678;
    uint32_t b = 0x0000abcd;
    uint32_t expected = a + b; // matches PEU stub behavior

    PEU_SRC0 = a;
    PEU_SRC1 = b;
    PEU_CTRL = 0x1; // start

    while ((PEU_STATUS & 0x1) == 0) {
        // spin
    }

    uint32_t got = PEU_RESULT;
    if (got == expected) {
        trap_success();
    } else {
        trap_fail();
    }
}
