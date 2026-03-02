    // riscv-test3.S
    .section .text
    .global _start
_start:
    addi  x2, x0, 1        // x2 = 1
    addi  x3, x0, 2        // x3 = 2
    addi  x5, x0, 1        // x5 = 1 
    mul   x5, x2, x3       // x5 = 2 
    addi  x0, x0, 0        // nop
    addi  x0, x0, 0        // nop
    addi  x6, x0, 2
    bne   x5, x6, 1f
    addi  a0, x0, 1
    csrw  0x15, a0
    j     2f
1:
    addi  a0, x0, 2
    csrw  0x15, a0
2:
    ebreak