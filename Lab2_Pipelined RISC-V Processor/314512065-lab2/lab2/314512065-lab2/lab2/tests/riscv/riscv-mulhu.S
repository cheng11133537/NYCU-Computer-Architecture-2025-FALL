//=========================================================================
// riscv-mulhu.S  —  tests for MULHU (unsigned × unsigned, high 32 bits)
//=========================================================================

#include "riscv-macros.h"

        TEST_RISCV_BEGIN

        // 0 * 0 -> 0
        li      x1, 0
        li      x2, 0
        mulhu   x3, x1, x2
        TEST_CHECK_EQ( x3, 0 )

        // 2 * 0x80000000 = 0x0000000100000000 (hi = 1)
        li      x1, 2
        li      x2, 0x80000000
        mulhu   x3, x1, x2
        TEST_CHECK_EQ( x3, 1 )

        // 0xFFFFFFFF * 0xFFFFFFFF = 0xFFFFFFFE00000001 (hi = 0xFFFFFFFE)
        li      x1, 0xffffffff
        li      x2, 0xffffffff
        mulhu   x3, x1, x2
        TEST_CHECK_EQ( x3, 0xfffffffe )   // 也可寫成 -2

        // (2^31-1) * (2^31-1) = 0x3FFFFFFF00000001 (hi = 0x3FFFFFFF)
        li      x1, 0x7fffffff
        li      x2, 0x7fffffff
        mulhu   x3, x1, x2
        TEST_CHECK_EQ( x3, 0x3fffffff )

        // 0x80000000 * 0x80000000 = 0x4000000000000000 (hi = 0x40000000)
        li      x1, 0x80000000
        li      x2, 0x80000000
        mulhu   x3, x1, x2
        TEST_CHECK_EQ( x3, 0x40000000 )

        // 0xFFFFFFFF * 1 -> hi = 0
        li      x1, 0xffffffff
        li      x2, 1
        mulhu   x3, x1, x2
        TEST_CHECK_EQ( x3, 0 )

        TEST_RISCV_END
