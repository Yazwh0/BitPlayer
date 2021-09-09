.macro copytovram dest_vh, dest_vm, dest_vl,  size,   source_label
    lda #dest_vh + $10 ; add on 1byte increment
    sta ADDRx_H
    lda #dest_vm
    sta ADDRx_M
    lda #dest_vl
    sta ADDRx_L

    ; y low value
    ; x high value
    ldy #<size
    ldx #>size+1 ; +1 as we check the end when we reduce x

    lda #<source_label
    sta copydata::copydata_src + 1
    lda #>source_label
    sta copydata::copydata_src + 2

    jsr copydata    
.endmacro

.proc copydata
copydata_src:
    lda $1234 ; gets modified
    sta DATA0

    inc copydata::copydata_src + 1
    bne noinc

    inc copydata::copydata_src + 2

noinc:

    dey
    bne copydata_src

    dex
    beq copydata_done
    jmp copydata_src

copydata_done:
    rts
.endproc
