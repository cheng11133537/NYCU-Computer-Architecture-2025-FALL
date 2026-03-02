#include "riscv-macros.h"

        TEST_RISCV_BEGIN

        # Cache-directed test suite (I- and D-cache paths)
        jal x1, test_clean_hits
        jal x1, test_dirty_hits
        jal x1, test_refill_and_eviction
        jal x1, test_conflict_lru
        jal x1, test_stride_stress
        jal x1, test_same_set_conflict
        jal x1, test_full_cache_sweep
        jal x1, test_edge_misaligned
        jal x1, test_random_mixed

        TEST_RISCV_END

#=====================================================================
# PASS / FAIL Macro Helpers
#=====================================================================
# x20 = expected, x21 = actual

check_equal:
        bne   x20, x21, fail
        ret

pass:
        li    x3, 1
        ret

fail:
        li    x3, 0
        ret

#---------------------------------------------------------------------
# T1: Read/write clean hit paths within a line
#---------------------------------------------------------------------
test_clean_hits:
        addi  x31, x1, 0
        la    x10, data_region       # base

        li    x11, 0x11223344
        sw    x11, 0(x10)            # cold miss then clean line
        lw    x12, 0(x10)            # hit
        mv    x21, x12
        mv    x20, x11
        jal   x1, check_equal

        li    x13, 0x55667788
        sw    x13, 4(x10)            # same line hit
        lw    x14, 4(x10)
        mv    x21, x14
        mv    x20, x13
        jal   x1, check_equal

        addi  x1, x31, 0
        ret

#---------------------------------------------------------------------
# T2: Read/write dirty hits (update in-place)
#---------------------------------------------------------------------
test_dirty_hits:
        addi  x31, x1, 0
        la    x10, data_region
        addi  x10, x10, 64           # different line

        li    x11, 0xAAAABBBB
        sw    x11, 0(x10)            # fill

        li    x12, 0xCCCCDDDD
        sw    x12, 0(x10)            # dirty hit overwrite
        lw    x13, 0(x10)            # hit should return x12
        mv    x21, x13
        mv    x20, x12
        jal   x1, check_equal

        addi  x1, x31, 0
        ret

#---------------------------------------------------------------------
# T3: Read/write misses with refill (clean) and with eviction
#---------------------------------------------------------------------
test_refill_and_eviction:
        addi  x31, x1, 0
        la    x10, data_region       # A
        li    x11, 2048
        add   x12, x10, x11          # B (same set, new tag)

        # Clean refill then read/write
        lw    x13, 0(x10)            # miss, BSS is zero
        li    x20, 0
        mv    x21, x13
        jal   x1, check_equal

        li    x14, 0x1234ABCD
        sw    x14, 0(x10)
        lw    x15, 0(x10)
        mv    x21, x15
        mv    x20, x14
        jal   x1, check_equal

        # Eviction path: touch B to evict A (direct-mapped)
        li    x16, 0xCAFEBABE
        sw    x16, 0(x12)

        # Access A again -> miss+refill must retrieve stored value
        lw    x17, 0(x10)
        mv    x21, x17
        mv    x20, x14
        jal   x1, check_equal

        addi  x1, x31, 0
        ret

#---------------------------------------------------------------------
# T4: Conflict/capacity misses and LRU verification (same set thrash)
#---------------------------------------------------------------------
test_conflict_lru:
        addi  x31, x1, 0
        la    x10, data_region       # A
        li    x11, 2048
        add   x12, x10, x11          # B
        li    x11, 4096
        add   x13, x10, x11          # C

        li    x14, 0xDEAD0001        # A data
        li    x15, 0xBEEF0002        # B data
        li    x16, 0xFEED0003        # C data

        sw    x14, 0(x10)            # fill A
        sw    x15, 0(x12)            # fill B (evicts A)
        sw    x16, 0(x13)            # fill C (evicts B)

        # Bring A back (evict C), then B back; ensure data preserved
        lw    x17, 0(x10)
        mv    x21, x17
        mv    x20, x14
        jal   x1, check_equal

        lw    x18, 0(x12)
        mv    x21, x18
        mv    x20, x15
        jal   x1, check_equal

        addi  x1, x31, 0
        ret

#---------------------------------------------------------------------
# T5: Stride stress over many sets (unit stride of 64B)
#---------------------------------------------------------------------
test_stride_stress:
        addi  x31, x1, 0
        la    x10, data_region
        li    x11, 0                  # i
        li    x12, 16                 # iterations

1:      slli  x13, x11, 6             # offset = i * 64
        add   x14, x10, x13
        addi  x15, x11, 0x20          # pattern
        sw    x15, 0(x14)
        lw    x16, 0(x14)
        mv    x21, x16
        mv    x20, x15
        jal   x1, check_equal

        addi  x11, x11, 1
        blt   x11, x12, 1b

        addi  x1, x31, 0
        ret

#---------------------------------------------------------------------
# T6: Repeated accesses to same set to force conflicts (stress)
#---------------------------------------------------------------------
test_same_set_conflict:
        addi  x31, x1, 0
        la    x10, data_region        # base A
        li    x11, 2048
        add   x12, x10, x11           # base B (same set)

        li    x13, 0
        li    x14, 8                  # iterations

1:      addi  x15, x13, 0x55
        sw    x15, 0(x10)             # write A
        lw    x16, 0(x10)
        mv    x21, x16
        mv    x20, x15
        jal   x1, check_equal

        addi  x15, x13, 0xAA
        sw    x15, 0(x12)             # write B -> evict A
        lw    x17, 0(x12)
        mv    x21, x17
        mv    x20, x15
        jal   x1, check_equal

        # Re-read A (miss/refill) and confirm value survives
        lw    x18, 0(x10)
        mv    x21, x18
        addi  x20, x13, 0x55
        jal   x1, check_equal

        addi  x13, x13, 1
        blt   x13, x14, 1b

        addi  x1, x31, 0
        ret

#---------------------------------------------------------------------
# T7: Sweep across many lines to exercise full cache footprint
#---------------------------------------------------------------------
test_full_cache_sweep:
        addi  x31, x1, 0
        la    x10, data_region
        li    x11, 0                  # line index
        li    x12, 64                 # number of lines (64 * 64B = 4KB)

1:      slli  x13, x11, 6             # offset = idx * 64
        add   x14, x10, x13
        addi  x15, x11, 0x123         # pattern
        sw    x15, 0(x14)
        lw    x16, 0(x14)
        mv    x21, x16
        mv    x20, x15
        jal   x1, check_equal

        addi  x11, x11, 1
        blt   x11, x12, 1b

        addi  x1, x31, 0
        ret

#---------------------------------------------------------------------
# T8: Edge/corner cases with misaligned subword accesses
#---------------------------------------------------------------------
test_edge_misaligned:
        addi  x31, x1, 0
        la    x10, data_region
        addi  x10, x10, 128           # keep away from other tests

        li    x11, 0xAABBCCDD
        sw    x11, 0(x10)

        # Byte overwrite at offset 1 and 3
        li    x12, 0x11
        sb    x12, 1(x10)             # -> AABB11DD
        li    x13, 0x22
        sb    x13, 3(x10)             # -> 22BB11DD

        lw    x14, 0(x10)
        li    x15, 0x22BB11DD
        mv    x21, x14
        mv    x20, x15
        jal   x1, check_equal

        # Halfword overwrite crossing previous bytes
        li    x16, 0x3344
        sh    x16, 1(x10)             # -> 22 44 33 DD (endian aware)
        lw    x17, 0(x10)
        li    x18, 0x224433DD
        mv    x21, x17
        mv    x20, x18
        jal   x1, check_equal

        # Unaligned load/store (lb/lh) sanity
        lb    x19, 1(x10)             # should be 0x44 sign-extended
        li    x20, 0x00000044
        mv    x21, x19
        jal   x1, check_equal

        lhu   x19, 2(x10)             # should read 0x33DD
        li    x20, 0x000033DD
        mv    x21, x19
        jal   x1, check_equal

        addi  x1, x31, 0
        ret

#---------------------------------------------------------------------
# T9: Randomized mixed read/write sequence within a window
#      (deterministic LFSR for reproducibility)
#---------------------------------------------------------------------
test_random_mixed:
        addi  x31, x1, 0
        la    x10, data_region
        li    x11, 0xACE1            # lfsr state
        li    x12, 0                 # loop counter
        li    x13, 32                # iterations

1:      # LFSR update: x^16 + x^14 + x^13 + x^11 + 1 taps
        slli  x14, x11, 1
        srli  x15, x11, 15
        xor   x14, x14, x15
        srli  x15, x11, 13
        xor   x14, x14, x15
        srli  x15, x11, 12
        xor   x14, x14, x15
        srli  x15, x11, 10
        xor   x14, x14, x15
        # keep LFSR to 16 bits
        slli  x14, x14, 16
        srli  x14, x14, 16
        addi  x11, x14, 0            # new lfsr

        # Derive offset within 4KB window and data pattern
        andi  x15, x11, 0x3F          # choose line within 4KB (64 lines)
        slli  x15, x15, 6             # line offset * 64
        add   x16, x10, x15
        slli  x17, x11, 8
        ori   x17, x17, 0x5A          # data pattern

        # Alternate store/load based on lsb of lfsr
        andi  x18, x11, 1
        beqz  x18, 2f
        sw    x17, 0(x16)
        j     3f
2:      lw    x19, 0(x16)             # likely hit/miss depending on history
        # No strict check; just consume value to avoid X
        add   x0, x0, x19
3:
        addi  x12, x12, 1
        blt   x12, x13, 1b

        # Spot-check one of the lines we wrote last
        lw    x20, 0(x16)
        mv    x21, x20
        mv    x20, x17
        jal   x1, check_equal

        addi  x1, x31, 0
        ret

#=====================================================================
# Private data region for cache testing in this program
#=====================================================================
        .section .bss
        .align 7                  # align to 128 bytes for clean set mapping
data_region:
        .space 8192               # 8KB region
