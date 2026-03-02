//=========================================================================
// riscv-mulh.S  —  tests for MULH (signed × signed, return high 32 bits)
//=========================================================================

#include "riscv-macros.h"

        TEST_RISCV_BEGIN

        // 0 * 0  -> 0x0000000000000000
        li      x1, 0
        li      x2, 0
        mulh    x3, x1, x2
        TEST_CHECK_EQ( x3, 0 )

        // 2 * 3  -> 0x0000000000000006  (hi = 0)
        li      x1, 2
        li      x2, 3
        mulh    x3, x1, x2
        TEST_CHECK_EQ( x3, 0 )

        // 0x80000000(-2^31) * 2 -> -4294967296 = 0xFFFFFFFF00000000 (hi = 0xFFFFFFFF)
        li      x1, 0x80000000
        li      x2, 2
        mulh    x3, x1, x2
        TEST_CHECK_EQ( x3, -1 )

        // (-1) * (-1) -> +1 (hi = 0)
        li      x1, -1
        li      x2, -1
        mulh    x3, x1, x2
        TEST_CHECK_EQ( x3, 0 )

        // (2^31-1) * (2^31-1) = 0x3FFFFFFF00000001 (hi = 0x3FFFFFFF)
        li      x1, 0x7fffffff
        li      x2, 0x7fffffff
        mulh    x3, x1, x2
        TEST_CHECK_EQ( x3, 0x3fffffff )

        // (-2^31) * (-2^31) = 2^62 = 0x4000000000000000 (hi = 0x40000000)
        li      x1, 0x80000000
        li      x2, 0x80000000
        mulh    x3, x1, x2
        TEST_CHECK_EQ( x3, 0x40000000 )

        // (-1) * 1 -> -1 = 0xFFFFFFFFFFFFFFFF (hi = 0xFFFFFFFF)
        li      x1, -1
        li      x2, 1
        mulh    x3, x1, x2
        TEST_CHECK_EQ( x3, -1 )

        TEST_RISCV_END
