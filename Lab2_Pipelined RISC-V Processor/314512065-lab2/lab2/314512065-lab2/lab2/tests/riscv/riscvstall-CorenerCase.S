        .section .text
        .globl _start
_start:
        j       TESTS_BEGIN

PASS:   li      x31, 1
        j       PASS

FAIL:   li      x31, 0
        j       FAIL

TESTS_BEGIN:
        # A) load-use（stall 核心需 1 個 bubble）
        la      x1, tdata0
        lw      x5, 0(x1)             # x5 = 0x12345678
        add     x6, x5, x0            # 需等 WB 後正確值
        li      t0, 0x12345678
        bne     x6, t0, FAIL

        # B) 連續覆寫後讀（應讀到最新）
        addi    x5, x0, 1
        addi    x5, x5, 2             # x5 = 3
        add     x6, x5, x0
        li      t0, 3
        bne     x6, t0, FAIL

        # C) x0 不能被寫
        addi    x0, x0, 5             # ignored
        addi    x6, x0, 1
        li      t0, 1
        bne     x6, t0, FAIL

        # D) 有號/無號分支比較
        li      x1, -1                # 0xFFFFFFFF
        li      x2, 1
        blt     x1, x2, 1f            # -1 < 1（有號）應跳
        j       FAIL
1:
        bltu    x1, x2, FAIL          # 無號：0xFFFFFFFF < 1 => 不跳

        # E) WAW + 之後讀
        addi    x5, x0, 10
        addi    x5, x5, 20            # x5 = 30
        add     x6, x5, x0
        li      t0, 30
        bne     x6, t0, FAIL

        j       PASS

        .section .data
        .align  2
tdata0: .word   0x12345678
