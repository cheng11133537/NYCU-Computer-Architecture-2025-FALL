    // riscv-test1.S
    .section .text
    .global _start
_start:
    addi x2, x0, 1    // x2 = 1
    addi x3, x0, 1    // x3 = 1
    mul  x5, x2, x3   
    addi x5, x0, 2    
    addi x6, x0, 2     // x6 = expected
    bne  x5, x6, 1f    // if x5 != 2 -> FAIL
    // PASS: csr_status = 1
    addi a0, x0, 1
    csrw 0x15, a0
    j    2f
1:
    addi a0, x0, 2
    csrw 0x15, a0
2:
    ebreak

