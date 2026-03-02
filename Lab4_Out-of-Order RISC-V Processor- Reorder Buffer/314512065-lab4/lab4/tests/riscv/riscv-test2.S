    // riscv-test2.S
    .section .text
    .global _start
_start:
    mul   x1, x0, x0
    addi  x5, x0, 7
    addi  x0, x0, 0   // nop
    addi  x0, x0, 0   // nop
    addi  x0, x0, 0   // nop
    add   x6, x5, x0
    addi  x7, x0, 7
    bne   x6, x7, 1f
    addi  a0, x0, 1
    csrw  0x15, a0
    j     2f
1:
    addi  a0, x0, 2
    csrw  0x15, a0
2:
    ebreak