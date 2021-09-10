.scope

.charmap 48, 0
.charmap 49, 1
.charmap 50, 2
.charmap 51, 3
.charmap 52, 4
.charmap 53, 5
.charmap 54, 6
.charmap 55, 7
.charmap 56, 8
.charmap 57, 9
.charmap 97, 10
.charmap 98, 11
.charmap 99, 12
.charmap 100, 13
.charmap 101, 14
.charmap 102, 15
.charmap 103, 16
.charmap 104, 17
.charmap 105, 18
.charmap 106, 19
.charmap 107, 20
.charmap 108, 21
.charmap 109, 22
.charmap 110, 23
.charmap 111, 24
.charmap 112, 25
.charmap 113, 26
.charmap 114, 27
.charmap 115, 28
.charmap 116, 29
.charmap 117, 30
.charmap 118, 31
.charmap 119, 32
.charmap 120, 33
.charmap 121, 34
.charmap 122, 35
.charmap 46, 36
.charmap 33, 37
.charmap 44, 38
.charmap 36, 39
.charmap 63, 40
.charmap 32, 41


.import player_init
.import player_vsync

VSYNC_LATCH = $02

.export display

.include "../library/clearvram.asm"
.include "../library/copytovram.asm"

.macro display_a_hex
    .local showzero
    .local done
    tay ; store
    beq showzero

    and #$f0 
    ror
    ror
    ror
    ror
    sta DATA0
    lda #$01
    sta DATA0

    tya
    and #$0f
    sta DATA0
    lda #$01
    sta DATA0
    jmp done
showzero:
    stz DATA0
    lda #$02
    sta DATA0
    stz DATA0
    lda #$02
    sta DATA0
done:
.endmacro

.macro display_output_line vh, vm, vl, linenumber
    .local vera_loop

    lda #1
    sta CTRL
    
    ; data 1 is the registers
    lda #$11
    sta ADDRx_H
    lda #$f9
    sta ADDRx_M
    lda #$c0
    sta ADDRx_L

    stz CTRL

    ; data 0 is the output
    ; start at $vhvmvl + linenumber * 64 * 2
    START_ADDR = vh * $10000 + vm * $100 + vl + (linenumber * 64 * 2)

    lda #^START_ADDR + $10
    sta ADDRx_H

    .repeat 16, I
        lda #>(START_ADDR + (I * 64 * 2))
        sta ADDRx_M
        lda #<(START_ADDR + (I * 64 * 2))
        sta ADDRx_L

        ldx #I * 2
        jsr display_vera
    .endrepeat
.endmacro

.macro display_output_counter vh, vm, vl, xpos, ypos, refvalue

    lda #^(vh * $10000 + vm * $100 + vl + (ypos * 64 * 2) + xpos * 2) + $10
    sta ADDRx_H
    lda #>(vh * $10000 + vm * $100 + vl + (ypos * 64 * 2) + xpos * 2)
    sta ADDRx_M
    lda #<(vh * $10000 + vm * $100 + vl + (ypos * 64 * 2) + xpos * 2)
    sta ADDRx_L

    lda refvalue
    display_a_hex

.endmacro

.macro display_text vh, vm, vl, xpos, ypos, refText
    .local loop
    .local done

    lda #^(vh * $10000 + vm * $100 + vl + (ypos * 64 * 2) + xpos * 2) + $10
    sta ADDRx_H
    lda #>(vh * $10000 + vm * $100 + vl + (ypos * 64 * 2) + xpos * 2)
    sta ADDRx_M
    lda #<(vh * $10000 + vm * $100 + vl + (ypos * 64 * 2) + xpos * 2)
    sta ADDRx_L

    ldx #0
loop:
    lda refText, x
    cmp #$ff ; zeros are valid
    beq done

    sta DATA0
    lda #1
    sta DATA0
    inx
    jmp loop
done:
.endmacro

.proc display
    sei

    clearvram $00, $00, $00,   $40, $00,  $00
    clearvram $00, $60, $00,   $20, $00,  $00

    jsr player_init

    ; enable interupt
    lda #<vsync
    sta $0314
    lda #>vsync
    sta $0315
    ;     i   aslv l=line interupt, v=vsync
    lda #%00000010
    sta IEN
    lda #10
    sta IRQLINE_L


    stz CTRL
    ;     FS10-Cmm
    lda #%01010001
    sta DC_VIDEO

    lda #64         ; 2:1 scale
    sta DC_HSCALE
    sta DC_VSCALE

    ;     hhwwtbcc
    lda #%01010000 ; tiles 1bp
    sta L0_CONFIG

    ;     aaaaaahw
	lda #%00000000 
	sta L0_MAPBASE ; map at $0000 - 0000 0000 0000 0000

    ;     aaaaaahw
    lda #%00110000 ; tiles at $6000 - 0110 0000 0000 0000, 8px x 8px tiles
    sta L0_TILEBASE    

    copytovram $00, $60, $00,  (42*8),  font_tiles
    copytovram $00, $80, $00,  $100,    yazwhosprite

    cli

    display_text $00, $00, $00, 0,  9, table_heading
    display_text $00, $00, $00, 1,  3, frame_heading
    display_text $00, $00, $00, 1,  4, line_heading
    display_text $00, $00, $00, 1,  5, pattern_heading
    display_text $00, $00, $00, 1,  6, next_heading
    display_text $00, $00, $00, 16, 3, vera_heading

    jsr initYazWhoSprite
    jsr initColours

loop:
    lda VSYNC_LATCH
    beq newframe
    jmp loop

newframe:
    lda #1
    sta VSYNC_LATCH

    lda #$11
    sta ADDRx_H
    lda #$fa
    sta ADDRx_M
    stz ADDRx_L
    lda #$0f
    sta DATA0
    sta DATA0

    jsr player_vsync

    lda #$11
    sta ADDRx_H
    lda #$fa
    sta ADDRx_M
    stz ADDRx_L

    lda #$03
    sta DATA0
    stz DATA0
    
    display_output_line $00, $00, $00, 10

                        ;  address      , x , y , source
    display_output_counter $00, $00, $00, 07, 03, pFRAME_INDEX
    display_output_counter $00, $00, $00, 07, 04, pLINE_INDEX
    display_output_counter $00, $00, $00, 07, 05, pPATTERN_INDEX
    display_output_counter $00, $00, $00, 07, 06, pNEXT_LINE_COUNTER

    display_output_counter $00, $00, $00, 16, 04, pMOD_VH
    display_output_counter $00, $00, $00, 18, 04, pMOD_VM
    display_output_counter $00, $00, $00, 20, 04, pMOD_VL


    jmp loop

vsync:
    lda ISR
    and #$02
    beq vsync_handler

line_hander:

    stz VSYNC_LATCH

    lda #$02    ; clear vera line interupt signal as we dont use the kernal
    sta ISR

    ply
    plx
    pla
    rti

vsync_handler:

    lda ISR
    and #$01
    beq no_interupt


    lda #$01 ; reset flag
    sta ISR   

no_interupt:
    ply
    plx
    pla
    rti
.endproc

.proc display_vera
    stz DATA0
    stz DATA0

    ; number    
    txa
    and #%11111110
    ror
    sta DATA0
    lda #$01
    sta DATA0

    stz DATA0
    stz DATA0

    lda #'$'
    sta DATA0
    lda #$01
    sta DATA0

    ; frequency
    lda DATA1
    pha
    lda DATA1
    display_a_hex
    pla
    display_a_hex

    stz DATA0
    stz DATA0
    
    lda DATA1
    display_a_hex

    stz DATA0
    stz DATA0

    lda DATA1
    display_a_hex

    stz DATA0
    stz DATA0

    lda #'$'
    sta DATA0
    lda #$01
    sta DATA0

    lda pINSTRUMENT_DATA_ZP, x
    pha
    lda pINSTRUMENT_DATA_ZP + 1, x
    display_a_hex
    pla
    display_a_hex


    stz DATA0
    stz DATA0

    lda pINSTRUMENT_POSITION, x
    display_a_hex

    stz DATA0
    stz DATA0

    lda pINSTRUMENT_POSITION + 1, x
    display_a_hex

    stz DATA0
    stz DATA0

    lda pINSTRUMENT_NUMBER, x
    display_a_hex

    stz DATA0
    stz DATA0

    lda pINSTRUMENT_NUMBER + 1, x
    display_a_hex

    stz DATA0
    stz DATA0

    lda pINSTRUMENT_COMMAND, x
    display_a_hex

    stz DATA0
    stz DATA0

    lda pINSTRUMENT_COMMAND + 1, x
    display_a_hex

    rts
.endproc

.proc initYazWhoSprite

    lda #$11
    sta ADDRx_H
    lda #$fc
    sta ADDRx_M
    stz ADDRx_L

    lda #%00000000 ; 12:5 $08000 or 0100 |0 0000 000|0 0000
    sta DATA0

    lda #%00000100 ; first bit, 4bpp
    sta DATA0

    lda #6
	sta DATA0 ; X1
	stz DATA0 ; X2
	lda #222
	sta DATA0 ; Y1
	stz DATA0 ; y2

	;     cccczzvh
	lda #%00001100 ; in front of everything
	sta DATA0 
	;     hhwwpppp
	lda #%01101001 ; 16 high, 32 width, $09 palette offset
	sta DATA0

	; set sprite colour
	lda #$11
    sta ADDRx_H 
	lda #$fb
    sta ADDRx_M
	lda #$22 
    sta ADDRx_L

	lda #$ff
	sta DATA0
	lda #$0f
	sta DATA0

	lda #$00
	sta DATA0
	lda #$00
	sta DATA0

	lda #$00
	sta DATA0
	lda #$0f
	sta DATA0

    rts

.endproc

.proc initColours
	lda #$11
    sta ADDRx_H 
	lda #$fa
    sta ADDRx_M
    stz ADDRx_L

    ; blue background
    lda #$02
    sta DATA0
    stz DATA0

    ; white text
    lda #$ff
    sta DATA0
    lda #$0f
    sta DATA0

    ; grey text for zeros
    lda #$55
    sta DATA0
    lda #$05
    sta DATA0

    rts
.endproc

.include "../library/vera.asm"
.include "modplayer.asm"
.include "modplayer/font.asm"
.include "../library/yazwhosprite.asm"

table_heading:
.byte "    vera        addr ps cm nm rp c1 c2"
.byte $ff
frame_heading:
.byte "frame", $ff
line_heading:
.byte "line          $", $ff
pattern_heading:
.byte "patt", $ff
next_heading:
.byte "next", $ff
vera_heading:
.byte "source", $ff

.endscope