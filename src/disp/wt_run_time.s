#include "sys/asm.h"
#include "sys/regdef.h"

LEAF(wt_run_time)
        .set noreorder
        .set noat
        lw      v0, 0x218(a0)
        li      a2, -10000
        addiu   a0, v0, 0x50
1:      lld     v1, 0(a0)
        daddu   AT, v1, a2
        move    v1, AT
        scd     AT, 0(a0)
        beqzl   AT, 1b
        nop
        lw      AT, 0(v0)
        addiu   sp, sp, -32
        bne     AT, v0, 2f
        sd      v0, 0(sp)
        sd      ra, 8(sp)
        lui     a0, 0
        jal     nested_spinlock
        addiu   a0, a0, 0
        ld      AT, 0(sp)
        lw      a2, 0(AT)
        beq     a2, AT, 3f
        lui     a0, 0
4:      jal     nested_spinunlock
        addiu   a0, a0, 0
        ld      ra, 8(sp)
2:      jr      ra
        addiu   sp, sp, 32
3:      ld      a1, 0(sp)
        lui     a0, 0
        addiu   a0, a0, 0
        jal     pushq
        addiu   a0, a0, 4
        b       4b
        lui     a0, 0
        .set reorder
        .set at
        END(wt_run_time)
