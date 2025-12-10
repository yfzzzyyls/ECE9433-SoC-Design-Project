#include <stdint.h>

#define PEU_BASE       0x10000000
#define REG_X          (*(volatile int32_t*)(PEU_BASE + 0x00)) 
#define REG_Y          (*(volatile int32_t*)(PEU_BASE + 0x04))
// 新增寄存器定义
#define REG_ANGLE      (*(volatile int32_t*)(PEU_BASE + 0x08)) // 写这个触发 Sin/Cos
#define REG_RES_COS    (*(volatile int32_t*)(PEU_BASE + 0x10))
#define REG_RES_SIN    (*(volatile int32_t*)(PEU_BASE + 0x14))

// 辅助延时
void delay() { asm volatile ("nop; nop; nop; nop;"); }

void main() {
    int32_t cos_0, sin_0;
    int32_t cos_45, sin_45;

    // ==========================================
    // TEST 1: 0度测试 (Angle = 0)
    // 预期: Cos(0) = 1.0 (65536), Sin(0) = 0
    // ==========================================
    
    // 写入角度 0，这会立即触发硬件计算！
    REG_ANGLE = 0;

    delay(); // 等待 16 周期

    cos_0 = REG_RES_COS;
    sin_0 = REG_RES_SIN;

    // ==========================================
    // TEST 2: 45度测试 (Angle = ~0.785 rad)
    // 45度对应定点数: 0.785398 * 65536 = 51472 (0xC910)
    // 预期 Cos/Sin: 0.7071 * 65536 = 46341 (0xB505)
    // ==========================================
    
    REG_ANGLE = 51472; // 0xC910

    asm volatile ("nop; nop; nop; nop; nop; nop; nop; nop;"); 
    asm volatile ("nop; nop; nop; nop; nop; nop; nop; nop;");

    cos_45 = REG_RES_COS;
    sin_45 = REG_RES_SIN;

    // ==========================================
    // 结果上屏验证 (写回 Y 寄存器以便波形观察)
    // ==========================================

    // --- 第一组 (0度) ---
    REG_Y = cos_0; // 预期: 00010000 (1.0)
    REG_Y = sin_0; // 预期: 00000000 (0.0)

    // --- 第二组 (45度) ---
    // 只要是 B5xx 都算对 (比如 B504, B505)
    REG_Y = cos_45; // 预期: 0000B505 
    REG_Y = sin_45; // 预期: 0000B505 

    while(1);
}