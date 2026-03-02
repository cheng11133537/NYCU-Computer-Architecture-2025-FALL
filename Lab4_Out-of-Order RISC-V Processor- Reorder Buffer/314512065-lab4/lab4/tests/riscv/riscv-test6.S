    .section .text
    .global _start

// riscv-test6.S  (fixed: no x32+ registers)
// Single-file ROB test suite constrained to Lab4(3) capabilities.
// - Uses only registers x0..x31
// - CSR 0x15 = 1 -> PASS, 2 -> FAIL
// - CSR 0x16 = first failing subtest index (0 = none)
// - x30 = fail mask, x31 = first_fail_idx

_start:
    addi x30, x0, 0      // fail_mask = 0
    addi x31, x0, 0      // first_fail_idx = 0

// SUBTEST 1: Out-of-order completion vs in-order commit (classic)
sub1:
    addi x2, x0, 1
    addi x3, x0, 1
    mul  x5, x2, x3      // long-latency
    addi x5, x0, 2       // later short -> expected final 2
    addi x6, x0, 2
    bne  x5, x6, sub1_fail
    j sub1_done
sub1_fail:
    ori x30, x30, 1
    beq x31, x0, sub1_setfirst
    j sub1_done
sub1_setfirst:
    addi x31, x0, 1
    j sub1_done
sub1_done:

// SUBTEST 2: WAW (older long, later short)
sub2:
    addi x2, x0, 2
    mul  x5, x2, x2      // produces 4 late
    addi x5, x0, 9       // later short -> expected 9
    addi x6, x0, 9
    bne x5, x6, sub2_fail
    j sub2_done
sub2_fail:
    ori x30, x30, 2
    beq x31, x0, sub2_setfirst
    j sub2_done
sub2_setfirst:
    addi x31, x0, 2
    j sub2_done
sub2_done:

// SUBTEST 3: ROB bypass — dependent ALU reads before commit
sub3:
    addi x2, x0, 7
    addi x3, x0, 3
    mul x10, x2, x3      // long
    add  x11, x10, x0    // should bypass and get 21
    addi x12, x0, 21
    bne x11, x12, sub3_fail
    j sub3_done
sub3_fail:
    ori x30, x30, 4
    beq x31, x0, sub3_setfirst
    j sub3_done
sub3_setfirst:
    addi x31, x0, 3
    j sub3_done
sub3_done:

// SUBTEST 4: Store then immediate Load to same address (ordering)
sub4:
    addi x4, x0, 0x100     // base address (adjust if simulator forbids)
    addi x5, x0, 77
    sw   x5, 0(x4)
    lw   x6, 0(x4)
    addi x7, x0, 77
    bne x6, x7, sub4_fail
    j sub4_done
sub4_fail:
    ori x30, x30, 8
    beq x31, x0, sub4_setfirst
    j sub4_done
sub4_setfirst:
    addi x31, x0, 4
    j sub4_done
sub4_done:

// SUBTEST 5: Load-use hazard (load must forward)
sub5:
    addi x8, x0, 0x200
    addi x9, x0, 123
    sw x9, 0(x8)
    lw x10, 0(x8)        // load latency
    add x11, x10, x0     // dependent
    addi x12, x0, 123
    bne x11, x12, sub5_fail
    j sub5_done
sub5_fail:
    ori x30, x30, 16
    beq x31, x0, sub5_setfirst
    j sub5_done
sub5_setfirst:
    addi x31, x0, 5
    j sub5_done
sub5_done:

// SUBTEST 6: Branch mispredict + in-flight store squash
sub6:
    addi x1, x0, 0x300
    addi x2, x0, 9
    beq x0, x0, sub6_taken   // always taken -> filler store should be squashed
    sw x2, 0(x1)
    j sub6_after
sub6_taken:
    addi x3, x0, 1
sub6_after:
    lw x4, 0(x1)
    addi x5, x0, 9
    beq x4, x5, sub6_fail   // if memory equals 9 -> store wrongly committed
    j sub6_done
sub6_fail:
    ori x30, x30, 32
    beq x31, x0, sub6_setfirst
    j sub6_done
sub6_setfirst:
    addi x31, x0, 6
    j sub6_done
sub6_done:

// SUBTEST 7: ROB wrap-around / circulation stress
sub7:
    addi x13, x0, 1
    addi x14, x0, 2
    mul x15, x13, x14
    add x16, x13, x14
    mul x17, x13, x14
    // Use the mul result in the sum so final result reaches 8
    add x18, x16, x15
    addi x19, x0, 3
    add x20, x18, x19
    addi x21, x0, 8
    bne x20, x21, sub7_fail
    j sub7_done
sub7_fail:
    ori x30, x30, 64
    beq x31, x0, sub7_setfirst
    j sub7_done
sub7_setfirst:
    addi x31, x0, 7
    j sub7_done
sub7_done:

// SUBTEST 8: ROB-full stress — use only registers <= x31
// mapped original x40..x46 -> x22..x28 (all legal)
sub8:
    addi x22, x0, 3
    mul x23, x22, x22
    mul x24, x22, x22
    mul x25, x22, x22
    mul x26, x22, x22
    mul x27, x22, x22
    // verify each produces 9
    addi x28, x0, 9
    bne x23, x28, sub8_fail
    bne x24, x28, sub8_fail
    bne x25, x28, sub8_fail
    bne x26, x28, sub8_fail
    bne x27, x28, sub8_fail
    j sub8_done
sub8_fail:
    ori x30, x30, 128
    beq x31, x0, sub8_setfirst
    j sub8_done
sub8_setfirst:
    addi x31, x0, 8
    j sub8_done
sub8_done:

// SUBTEST 9: Rename alias check (logical regs independent)
sub9:
    addi x1, x0, 5
    addi x2, x0, 7
    add x3, x1, x0
    add x4, x2, x0
    addi x5, x0, 5
    addi x6, x0, 7
    bne x3, x5, sub9_fail
    bne x4, x6, sub9_fail
    j sub9_done
sub9_fail:
    ori x30, x30, 256
    beq x31, x0, sub9_setfirst
    j sub9_done
sub9_setfirst:
    addi x31, x0, 9
    j sub9_done
sub9_done:

// SUBTEST 10: Basic functionality smoke test (simple in-order sequence)
sub10:
    addi x1, x0, 10
    addi x2, x0, 20
    add x3, x1, x2
    addi x4, x0, 30
    bne x3, x4, sub10_fail
    j sub10_done
sub10_fail:
    ori x30, x30, 512
    beq x31, x0, sub10_setfirst
    j sub10_done
sub10_setfirst:
    addi x31, x0, 10
    j sub10_done
sub10_done:

// SUBTEST 11: Dual-source ROB bypass (both srcs from ROB before commit)
sub11:
    // Head blocker keeps commit at head while producers reach W/ROB
    mul  x1, x0, x0          // long-lat; result 0 but multi-cycle
    addi x5, x0, 11          // producer A
    addi x6, x0, 22          // producer B
    addi x0, x0, 0           // nop spacing
    addi x0, x0, 0           // nop spacing
    add  x7, x5, x6          // consumer must bypass both from ROB -> 33
    addi x8, x0, 33
    bne  x7, x8, sub11_fail
    j sub11_done
sub11_fail:
    ori  x30, x30, 1024
    beq  x31, x0, sub11_setfirst
    j sub11_done
sub11_setfirst:
    addi x31, x0, 11
    j sub11_done
sub11_done:

// SUBTEST 12: x0 special-case (writes ignored, reads always 0)
sub12:
    addi x1, x0, 123
    add  x0, x1, x1          // attempt to write x0; must remain 0
    addi x2, x0, 0
    bne  x0, x2, sub12_fail  // x0 must be 0
    j sub12_done
sub12_fail:
    // Set fail bit 2048 (1<<11) without out-of-range immediate
    addi x28, x0, 1
    slli x28, x28, 11
    or   x30, x30, x28
    beq  x31, x0, sub12_setfirst
    j sub12_done
sub12_setfirst:
    addi x31, x0, 12
    j sub12_done
sub12_done:

// SUBTEST 13: ROB-full backpressure (head blocked + many allocs)
// Functional check: ensure later independent ADDI still executes → progress
sub13:
    mul  x3, x0, x0          // head blocker
    addi x9,  x0, 1
    addi x10, x0, 2
    addi x11, x0, 3
    addi x12, x0, 4
    addi x13, x0, 5
    addi x14, x0, 6
    addi x15, x0, 7
    addi x16, x0, 8
    addi x17, x0, 9
    addi x18, x0, 10
    addi x19, x0, 11
    addi x20, x0, 12
    addi x21, x0, 13
    addi x22, x0, 14
    addi x23, x0, 15
    addi x24, x0, 16
    // Check that a deep instruction executed (progress under backpressure)
    addi x25, x0, 16
    bne  x24, x25, sub13_fail
    j sub13_done
sub13_fail:
    // Set fail bit 4096 (1<<12) without out-of-range immediate
    addi x28, x0, 1
    slli x28, x28, 12
    or   x30, x30, x28
    beq  x31, x0, sub13_setfirst
    j sub13_done
sub13_setfirst:
    addi x31, x0, 13
    j sub13_done
sub13_done:

// SUBTEST 14: Wrong-path ALU writeback must be squashed
sub14:
    // Baseline value in x4
    addi x4, x0, 55
    // Always-taken branch; the following ADDI to x4 is on the wrong path
    beq  x0, x0, sub14_taken
    addi x4, x0, 99      // wrong path; must NOT commit
    j    sub14_after
sub14_taken:
    addi x0, x0, 0       // nop
sub14_after:
    addi x5, x0, 55
    bne  x4, x5, sub14_fail
    j sub14_done
sub14_fail:
    // Set fail bit 8192 (1<<13) without out-of-range immediate
    addi x28, x0, 1
    slli x28, x28, 13
    or   x30, x30, x28
    beq  x31, x0, sub14_setfirst
    j sub14_done
sub14_setfirst:
    addi x31, x0, 14
    j sub14_done
sub14_done:

// FINALIZE: write first fail index to CSR 0x16, overall PASS/FAIL to CSR 0x15
    csrw 0x16, x31
    beq x30, x0, all_pass
    addi a0, x0, 2
    csrw 0x15, a0
    ebreak

all_pass:
    addi a0, x0, 1
    csrw 0x15, a0
    ebreak
