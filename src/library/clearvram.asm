.macro clearvram dest_vh, dest_vm, dest_vl, size_h, size_l, value
    lda #dest_vh + $10 ; add on 1byte increment
    sta ADDRx_H
    lda #dest_vm
    sta ADDRx_M
    lda #dest_vl
    sta ADDRx_L

    ; y low value
    ; x high value
    ; a what to write
    ldy #size_l
    ldx #size_h+1 ; +1 as we check the end when we reduce x
    lda #value

    jsr clearbitmap
.endmacro

.proc clearbitmap
    sta DATA0
    dey
    bne clearbitmap

    dex
    beq clearbitmap_done
    jmp clearbitmap

clearbitmap_done:
    rts
.endproc
