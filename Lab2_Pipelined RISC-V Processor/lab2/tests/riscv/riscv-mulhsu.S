//=========================================================================
// riscv-mulhsu.S  —  tests for MULHSU (signed × unsigned, high 32 bits)
//=========================================================================

#include "riscv-macros.h"

        TEST_RISCV_BEGIN

        // (-1) * 0xFFFFFFFF(u) = -4294967295 = 0xFFFFFFFF00000001 (hi = 0xFFFFFFFF)
        li      x1, -1
        li      x2, 0xffffffff
        mulhsu  x3, x1, x2
        TEST_CHECK_EQ( x3, -1 )

        // (-2^31) * 2u = -4294967296 = 0xFFFFFFFF00000000 (hi = 0xFFFFFFFF)
        li      x1, 0x80000000
        li      x2, 2
        mulhsu  x3, x1, x2
        TEST_CHECK_EQ( x3, -1 )

        // (-2^31) * 0x80000000u = -2^62 = 0xC000000000000000 (hi = 0xC0000000)
        li      x1, 0x80000000
        li      x2, 0x80000000
        mulhsu  x3, x1, x2
        TEST_CHECK_EQ( x3, 0xC0000000 )

        // (-1) * 0x80000000u = -2147483648 = 0xFFFFFFFF80000000 (hi = 0xFFFFFFFF)
        li      x1, -1
        li      x2, 0x80000000
        mulhsu  x3, x1, x2
        TEST_CHECK_EQ( x3, -1 )

        // (2^31-1) * 2u = 4294967294 = 0x00000000FFFFFFFE (hi = 0)
        li      x1, 0x7fffffff
        li      x2, 2
        mulhsu  x3, x1, x2
        TEST_CHECK_EQ( x3, 0 )

        // (-1) * 0u -> 0 (hi = 0)
        li      x1, -1
        li      x2, 0
        mulhsu  x3, x1, x2
        TEST_CHECK_EQ( x3, 0 )

        TEST_RISCV_END
