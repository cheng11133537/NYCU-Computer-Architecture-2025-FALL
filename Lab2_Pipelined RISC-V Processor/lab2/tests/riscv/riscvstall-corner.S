//=========================================================================
// riscvstall-corner.S 
//=========================================================================
#include "riscv-macros.h"
        TEST_RISCV_BEGIN
        // S1) load-use
        la    x1, tdata_0
        lw    x5, 0(x1)         
        add   x6, x5, x0        
        TEST_CHECK_EQ( x6, 0x000000ff )
        // S2) RAW
        addi  x7,  x0, 1
        addi  x7,  x7, 2       
        add   x8,  x7, x0
        TEST_CHECK_EQ( x8, 3 )
        // S3) Negative sgift base
        la    x9,  tdata_0
        addi  x9,  x9, -32
        lw    x10, 32(x9)
        TEST_CHECK_EQ( x10, 0x000000ff )
        // S4) EX->Store-Data
        la    x9, storebuf
        addi  x5, x0, 0x7f        
        addi  x5, x5, 1           
        sw    x5, 0(x9)           
        lw    x10, 0(x9)          
        TEST_CHECK_EQ( x10, 0x00000080 )
        // S5) EX->EX
        addi  x3, x0, 1          
        addi  x4, x0, 2           
        add   x2, x3, x4          
        add   x6, x2, x0         
        TEST_CHECK_EQ( x6, 3 )
        // S6) Last-writer wins
        addi x1, x0, 5       
        nop                  
        addi x1, x0, 7       
        add  x2, x1, x0      
        TEST_CHECK_EQ(x2, 7)
        //S7)Store -> Load forwarding
        la    x1, storebuf
        li    x2, 0x1234
        sw    x2, 0(x1)      
        lw    x3, 0(x1)     
        TEST_CHECK_EQ(x3, 0x00001234)
        TEST_RISCV_END

        //-----------------------------------------------------------------
        // Test data
        //-----------------------------------------------------------------

        .section .data
        .align 4

tdata_0:  .word 0x000000ff
tdata_1:  .word 0x00007f00
tdata_2:  .word 0x00000ff0
tdata_3:  .word 0x0000700f

// 額外的測試緩衝，不動原本 tdata_* 固定測資
        .align 4
storebuf: .word 0,0,0,0