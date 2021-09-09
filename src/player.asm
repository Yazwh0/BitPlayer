;.include "./library/copytovram.asm"

;.export Player_Variables
;.export Player_Initialise
;.export Player_Vsync

.scope

; need to run this maco to define where to keep the data.
.macro Player_Variables frameIndex, lineIndex, patternIndex, nextLineCounter, vhPos, vmPos, vlPos, instrumentDataZP, instrumentCommandData, instrumentPosition, instrumentNumber
; Memory locations for variables
FRAME_INDEX = frameIndex
LINE_INDEX = lineIndex
PATTERN_INDEX = patternIndex
NEXT_LINE_COUNTER = nextLineCounter

PATTERN_POS_H = vhPos
PATTERN_POS_M = vmPos
PATTERN_POS_L = vlPos

; instrument pointers
; Needs 2 * 7 bytes. 
; .word instrument address
INSTRUMENT_START = instrumentDataZP
INSTRUMENT_ADDR = $00

; Needs 2 * 7 bytes. 
; .word command parameters
INSTRUMENT_COMMAND_START = instrumentCommandData
INSTRUMENT_COMMAND_PARAM0 = $00
INSTRUMENT_COMMAND_PARAM1 = $01

; instrument data 
; .byte position (decreases)
; .byte current command 
INSTRUMENT_DATA_START = instrumentPosition
INSTRUMENT_DATA_POSITION = $00
INSTRUMENT_DATA_COMMAND = $01

; instrument number
; .byte number
INSTRUMENT_NUMBER = instrumentNumber

.endmacro

; call this once
; vh, vm, vl are where in vram to store the pattern data.
.macro Player_Initialise vh, vm, vl
    .local clear_loop
    .local clear_psg_loop

    ; load in 1 so we init on first call
    lda #1
    sta FRAME_INDEX
    sta LINE_INDEX
    sta PATTERN_INDEX
    sta NEXT_LINE_COUNTER

    ldx #(2 * 7)
    ldx #32 ; debuging
    
clear_loop:
    stz INSTRUMENT_DATA_START - 1, x
    stz INSTRUMENT_START - 1, x
    stz INSTRUMENT_COMMAND_START - 1, x
    stz INSTRUMENT_NUMBER - 1, x
    dex
    bne clear_loop

    ; usful for debugging
    lda #$11
    sta ADDRx_H
    lda #$f9
    sta ADDRx_M
    lda #$c0
    sta ADDRx_L

    ldx #16 * 4 ; use 16 not the width so we clear everything

clear_psg_loop:
    stz DATA0
    dex
    bne clear_psg_loop

    ; we store the pattern data in vram as we pull it in serial. the data0/1 makes this considerably easier.
    copytovram vh, vm, vl, $0EA4, pattern_data

    rts
.endmacro

.macro Play_Instrument offset
    .local instrument_not_playing
    .local instrument_done
    .local instrument_played
    .local no_note_adjust
    .local note_adjust_done
    .local skipinstr

    lda INSTRUMENT_DATA_START + INSTRUMENT_DATA_POSITION + (offset * 2)
    beq instrument_not_playing
    tay
;stp
    ; adjust note
    lda (INSTRUMENT_START + INSTRUMENT_ADDR + (offset * 2)), y
    clc
    adc INSTRUMENT_NUMBER + (offset * 2)

    tax
;stp
    lda player_notelookup, x
    sta DATA0

    lda player_notelookup+1, x
    sta DATA0

    dey

    ; volume
    lda (INSTRUMENT_START + INSTRUMENT_ADDR + (offset * 2)), y
    sta DATA0
    dey
    beq instrument_played

    ; width
    lda (INSTRUMENT_START + INSTRUMENT_ADDR + (offset * 2)), y
    sta DATA0
    dey
    
    tya
    sta INSTRUMENT_DATA_START + INSTRUMENT_DATA_POSITION + (offset * 2)

    jmp instrument_done

instrument_played:
    lda (INSTRUMENT_START + INSTRUMENT_ADDR + (offset * 2))
    sta DATA0

    ; get repeat position (0 will stop)
    lda INSTRUMENT_NUMBER + 1 + (offset * 2)
    sta INSTRUMENT_DATA_START + INSTRUMENT_DATA_POSITION + (offset * 2)

    jmp instrument_done

instrument_not_playing:
    stz DATA0
    stz DATA0
    stz DATA0
    stz DATA0
instrument_done:
.endmacro

; call this once per frame, at the same frame time 
.macro Player_Vsync vh, vm, vl
    .local play_instruments
    .local next_line
    .local play_next
    .local play_line
    .local next_voice_loop
    .local move_to_start
    .local no_voice_skip
    .local no_command
    .local next_voice
    .local next_pattern
    .local play_next_pattern
    .local pattern_jump_table
    .local restart

	dec FRAME_INDEX
	bne play_instruments  
    jmp next_line

play_instruments:
    ; PLAY INSTRUMENTS
;stp
    ; PSG Start.
    lda #$11
    sta ADDRx_L
    lda #$f9
    sta ADDRx_M
    lda #$c0
    sta ADDRx_L

;stp
.repeat 7, I
Play_Instrument I
.endrepeat

    rts

next_line: ; !label is important!
    lda #$ff ; Tempo - gets modified in new pattern init
    sta FRAME_INDEX

	dec LINE_INDEX
	bne play_next
	jmp next_pattern

play_next:
    dec NEXT_LINE_COUNTER ; lines till there is a line with notes to play.
    beq play_line
    jmp play_instruments

play_line:
    ; setup DATA0
    lda PATTERN_POS_H
    sta ADDRx_H
    lda PATTERN_POS_M
    sta ADDRx_M
    lda PATTERN_POS_L
    sta ADDRx_L

    ldy #0 ; y is the position in the output

;stp
    lda DATA0 ; number of voices till next action.
    beq no_voice_skip

next_voice_loop:
    tax      ; arrive here with steps in A, need to use X.

move_to_start:
    iny
    iny

    dex
    bne move_to_start

no_voice_skip:
    lda DATA0   ; load note number
    sta INSTRUMENT_NUMBER, y ; store instrument number

    ldx DATA0   ; instrument number, already *2 for the lookup.

    ; store instrment address and pos. (instrument data is reversed)

    lda instruments_play, x
    sta INSTRUMENT_START + INSTRUMENT_ADDR, y
    lda instruments_play + 1, x
    sta INSTRUMENT_START + INSTRUMENT_ADDR + 1, y

    lda instrument_length, x
    sta INSTRUMENT_DATA_START + INSTRUMENT_DATA_POSITION, y

    lda instrument_length + 1, x
    sta INSTRUMENT_NUMBER + 1, y

    lda DATA0   ; command
    beq no_command

    sta INSTRUMENT_DATA_START + INSTRUMENT_DATA_COMMAND, y

    lda DATA0   ; command data
    sta INSTRUMENT_COMMAND_START + INSTRUMENT_COMMAND_PARAM0, y
    lda DATA0
    sta INSTRUMENT_COMMAND_START + INSTRUMENT_COMMAND_PARAM1, y

    jmp next_voice
no_command:
    lda #0
    sta INSTRUMENT_DATA_START + INSTRUMENT_DATA_COMMAND, y

next_voice:
    iny
    iny

    lda DATA0   ; steps till next
    beq no_voice_skip

    cmp #$ff    ; done.
    bne next_voice_loop

    lda DATA0
    sta NEXT_LINE_COUNTER ; store in next frame counter

    lda ADDRx_H         ; store our position for later.
    sta PATTERN_POS_H
    lda ADDRx_M
    sta PATTERN_POS_M
    lda ADDRx_L
    sta PATTERN_POS_L

    jmp play_instruments

next_pattern:
	dec PATTERN_INDEX
	beq restart_near

    ldx PATTERN_INDEX
    dex

play_next_pattern:
    lda pattern_playlist, x
     
    asl ; x is the pattern, so *2 for the offset. assume < 128 patterns
    tax

    jmp (pattern_jump_table, x)

restart_near:
    jmp restart
    
pattern_jump_table:
	.word pattern_0_init
	.word pattern_1_init
	.word pattern_2_init
	.word pattern_3_init
	.word pattern_4_init
	.word pattern_5_init
	.word pattern_6_init
	.word pattern_7_init
	.word pattern_8_init
	.word pattern_9_init
	.word pattern_10_init

pattern_0_init:
	lda #(^(vh * $10000 + vm * $100 + vl + 0)) + $10
	sta PATTERN_POS_H
	lda #>(vh * $10000 + vm * $100 + vl + 0)
	sta PATTERN_POS_M
	lda #<(vh * $10000 + vm * $100 + vl + 0)
	sta PATTERN_POS_L
	lda #$01 ; first line is 1
	sta NEXT_LINE_COUNTER
	lda #$18 ; this pattern is 24 lines long
	sta LINE_INDEX
	lda #$0A ; tempo
	sta next_line+1 ; modify reset code
	sta FRAME_INDEX
	jmp play_next

pattern_1_init:
	lda #(^(vh * $10000 + vm * $100 + vl + 244)) + $10
	sta PATTERN_POS_H
	lda #>(vh * $10000 + vm * $100 + vl + 244)
	sta PATTERN_POS_M
	lda #<(vh * $10000 + vm * $100 + vl + 244)
	sta PATTERN_POS_L
	lda #$01 ; first line is 1
	sta NEXT_LINE_COUNTER
	lda #$18 ; this pattern is 24 lines long
	sta LINE_INDEX
	lda #$0A ; tempo
	sta next_line+1 ; modify reset code
	sta FRAME_INDEX
	jmp play_next

pattern_2_init:
	lda #(^(vh * $10000 + vm * $100 + vl + 500)) + $10
	sta PATTERN_POS_H
	lda #>(vh * $10000 + vm * $100 + vl + 500)
	sta PATTERN_POS_M
	lda #<(vh * $10000 + vm * $100 + vl + 500)
	sta PATTERN_POS_L
	lda #$01 ; first line is 1
	sta NEXT_LINE_COUNTER
	lda #$18 ; this pattern is 24 lines long
	sta LINE_INDEX
	lda #$0A ; tempo
	sta next_line+1 ; modify reset code
	sta FRAME_INDEX
	jmp play_next

pattern_3_init:
	lda #(^(vh * $10000 + vm * $100 + vl + 796)) + $10
	sta PATTERN_POS_H
	lda #>(vh * $10000 + vm * $100 + vl + 796)
	sta PATTERN_POS_M
	lda #<(vh * $10000 + vm * $100 + vl + 796)
	sta PATTERN_POS_L
	lda #$01 ; first line is 1
	sta NEXT_LINE_COUNTER
	lda #$18 ; this pattern is 24 lines long
	sta LINE_INDEX
	lda #$0A ; tempo
	sta next_line+1 ; modify reset code
	sta FRAME_INDEX
	jmp play_next

pattern_4_init:
	lda #(^(vh * $10000 + vm * $100 + vl + 1064)) + $10
	sta PATTERN_POS_H
	lda #>(vh * $10000 + vm * $100 + vl + 1064)
	sta PATTERN_POS_M
	lda #<(vh * $10000 + vm * $100 + vl + 1064)
	sta PATTERN_POS_L
	lda #$01 ; first line is 1
	sta NEXT_LINE_COUNTER
	lda #$18 ; this pattern is 24 lines long
	sta LINE_INDEX
	lda #$0A ; tempo
	sta next_line+1 ; modify reset code
	sta FRAME_INDEX
	jmp play_next

pattern_5_init:
	lda #(^(vh * $10000 + vm * $100 + vl + 1352)) + $10
	sta PATTERN_POS_H
	lda #>(vh * $10000 + vm * $100 + vl + 1352)
	sta PATTERN_POS_M
	lda #<(vh * $10000 + vm * $100 + vl + 1352)
	sta PATTERN_POS_L
	lda #$01 ; first line is 1
	sta NEXT_LINE_COUNTER
	lda #$18 ; this pattern is 24 lines long
	sta LINE_INDEX
	lda #$0A ; tempo
	sta next_line+1 ; modify reset code
	sta FRAME_INDEX
	jmp play_next

pattern_6_init:
	lda #(^(vh * $10000 + vm * $100 + vl + 1612)) + $10
	sta PATTERN_POS_H
	lda #>(vh * $10000 + vm * $100 + vl + 1612)
	sta PATTERN_POS_M
	lda #<(vh * $10000 + vm * $100 + vl + 1612)
	sta PATTERN_POS_L
	lda #$01 ; first line is 1
	sta NEXT_LINE_COUNTER
	lda #$18 ; this pattern is 24 lines long
	sta LINE_INDEX
	lda #$0A ; tempo
	sta next_line+1 ; modify reset code
	sta FRAME_INDEX
	jmp play_next

pattern_7_init:
	lda #(^(vh * $10000 + vm * $100 + vl + 1916)) + $10
	sta PATTERN_POS_H
	lda #>(vh * $10000 + vm * $100 + vl + 1916)
	sta PATTERN_POS_M
	lda #<(vh * $10000 + vm * $100 + vl + 1916)
	sta PATTERN_POS_L
	lda #$01 ; first line is 1
	sta NEXT_LINE_COUNTER
	lda #$18 ; this pattern is 24 lines long
	sta LINE_INDEX
	lda #$0A ; tempo
	sta next_line+1 ; modify reset code
	sta FRAME_INDEX
	jmp play_next

pattern_8_init:
	lda #(^(vh * $10000 + vm * $100 + vl + 2212)) + $10
	sta PATTERN_POS_H
	lda #>(vh * $10000 + vm * $100 + vl + 2212)
	sta PATTERN_POS_M
	lda #<(vh * $10000 + vm * $100 + vl + 2212)
	sta PATTERN_POS_L
	lda #$01 ; first line is 1
	sta NEXT_LINE_COUNTER
	lda #$18 ; this pattern is 24 lines long
	sta LINE_INDEX
	lda #$0A ; tempo
	sta next_line+1 ; modify reset code
	sta FRAME_INDEX
	jmp play_next

pattern_9_init:
	lda #(^(vh * $10000 + vm * $100 + vl + 2724)) + $10
	sta PATTERN_POS_H
	lda #>(vh * $10000 + vm * $100 + vl + 2724)
	sta PATTERN_POS_M
	lda #<(vh * $10000 + vm * $100 + vl + 2724)
	sta PATTERN_POS_L
	lda #$01 ; first line is 1
	sta NEXT_LINE_COUNTER
	lda #$18 ; this pattern is 24 lines long
	sta LINE_INDEX
	lda #$0A ; tempo
	sta next_line+1 ; modify reset code
	sta FRAME_INDEX
	jmp play_next

pattern_10_init:
	lda #(^(vh * $10000 + vm * $100 + vl + 3236)) + $10
	sta PATTERN_POS_H
	lda #>(vh * $10000 + vm * $100 + vl + 3236)
	sta PATTERN_POS_M
	lda #<(vh * $10000 + vm * $100 + vl + 3236)
	sta PATTERN_POS_L
	lda #$01 ; first line is 1
	sta NEXT_LINE_COUNTER
	lda #$18 ; this pattern is 24 lines long
	sta LINE_INDEX
	lda #$0A ; tempo
	sta next_line+1 ; modify reset code
	sta FRAME_INDEX
	jmp play_next

    stp ; should never reach here

restart:

    lda #$0E ; playlist length
    sta PATTERN_INDEX

    tax
    dex
    jmp play_next_pattern
.endmacro


.macro Player_Data
patterns:
	.word pattern_0
	.word pattern_1
	.word pattern_2
	.word pattern_3
	.word pattern_4
	.word pattern_5
	.word pattern_6
	.word pattern_7
	.word pattern_8
	.word pattern_9
	.word pattern_10

instruments_play:
	.word instrument_0
	.word instrument_1
	.word instrument_2
	.word instrument_3
	.word instrument_4
	.word instrument_5
	.word instrument_6
	.word instrument_7
	.word instrument_8
	.word instrument_9
	.word instrument_10
	.word instrument_11
	.word instrument_12

instrument_length:
	.byte $3E, $08 ; 21 steps, 18 repeat
	.byte $3E, $08 ; 21 steps, 18 repeat
	.byte $3E, $08 ; 21 steps, 18 repeat
	.byte $3E, $08 ; 21 steps, 18 repeat
	.byte $11, $00 ; 6 steps, -1 repeat
	.byte $0B, $00 ; 4 steps, -1 repeat
	.byte $0B, $00 ; 4 steps, -1 repeat
	.byte $5C, $08 ; 31 steps, 28 repeat
	.byte $2C, $00 ; 15 steps, -1 repeat
	.byte $14, $00 ; 7 steps, -1 repeat
	.byte $11, $00 ; 6 steps, -1 repeat
	.byte $2F, $00 ; 16 steps, -1 repeat
	.byte $14, $00 ; 7 steps, -1 repeat

instrument_0:
	.byte $7F, $C3, $0E; Width 63 + Wave Sawtooth, Volume 3, NoteAdj 7
	.byte $7F, $C3, $06; Width 63 + Wave Sawtooth, Volume 3, NoteAdj 3
	.byte $7F, $C3, $00; Width 63 + Wave Sawtooth, Volume 3, NoteAdj 0
	.byte $7F, $C4, $0E; Width 63 + Wave Sawtooth, Volume 4, NoteAdj 7
	.byte $7F, $C6, $06; Width 63 + Wave Sawtooth, Volume 6, NoteAdj 3
	.byte $7F, $C7, $00; Width 63 + Wave Sawtooth, Volume 7, NoteAdj 0
	.byte $7F, $C9, $0E; Width 63 + Wave Sawtooth, Volume 9, NoteAdj 7
	.byte $7F, $CA, $06; Width 63 + Wave Sawtooth, Volume 10, NoteAdj 3
	.byte $7F, $CC, $00; Width 63 + Wave Sawtooth, Volume 12, NoteAdj 0
	.byte $7F, $CD, $0E; Width 63 + Wave Sawtooth, Volume 13, NoteAdj 7
	.byte $7F, $CF, $06; Width 63 + Wave Sawtooth, Volume 15, NoteAdj 3
	.byte $7F, $D0, $00; Width 63 + Wave Sawtooth, Volume 16, NoteAdj 0
	.byte $7F, $D2, $0E; Width 63 + Wave Sawtooth, Volume 18, NoteAdj 7
	.byte $7F, $D3, $06; Width 63 + Wave Sawtooth, Volume 19, NoteAdj 3
	.byte $7F, $D5, $00; Width 63 + Wave Sawtooth, Volume 21, NoteAdj 0
	.byte $7F, $D6, $0E; Width 63 + Wave Sawtooth, Volume 22, NoteAdj 7
	.byte $7F, $D8, $06; Width 63 + Wave Sawtooth, Volume 24, NoteAdj 3
	.byte $7F, $D9, $00; Width 63 + Wave Sawtooth, Volume 25, NoteAdj 0
	.byte $7F, $DB, $0E; Width 63 + Wave Sawtooth, Volume 27, NoteAdj 7
	.byte $7F, $DC, $06; Width 63 + Wave Sawtooth, Volume 28, NoteAdj 3
	.byte $7F, $DE, $00; Width 63 + Wave Sawtooth, Volume 30, NoteAdj 0
instrument_1:
	.byte $7F, $C3, $10; Width 63 + Wave Sawtooth, Volume 3, NoteAdj 8
	.byte $7F, $C3, $06; Width 63 + Wave Sawtooth, Volume 3, NoteAdj 3
	.byte $7F, $C3, $00; Width 63 + Wave Sawtooth, Volume 3, NoteAdj 0
	.byte $7F, $C4, $10; Width 63 + Wave Sawtooth, Volume 4, NoteAdj 8
	.byte $7F, $C6, $06; Width 63 + Wave Sawtooth, Volume 6, NoteAdj 3
	.byte $7F, $C7, $00; Width 63 + Wave Sawtooth, Volume 7, NoteAdj 0
	.byte $7F, $C9, $10; Width 63 + Wave Sawtooth, Volume 9, NoteAdj 8
	.byte $7F, $CA, $06; Width 63 + Wave Sawtooth, Volume 10, NoteAdj 3
	.byte $7F, $CC, $00; Width 63 + Wave Sawtooth, Volume 12, NoteAdj 0
	.byte $7F, $CD, $10; Width 63 + Wave Sawtooth, Volume 13, NoteAdj 8
	.byte $7F, $CF, $06; Width 63 + Wave Sawtooth, Volume 15, NoteAdj 3
	.byte $7F, $D0, $00; Width 63 + Wave Sawtooth, Volume 16, NoteAdj 0
	.byte $7F, $D2, $10; Width 63 + Wave Sawtooth, Volume 18, NoteAdj 8
	.byte $7F, $D3, $06; Width 63 + Wave Sawtooth, Volume 19, NoteAdj 3
	.byte $7F, $D5, $00; Width 63 + Wave Sawtooth, Volume 21, NoteAdj 0
	.byte $7F, $D6, $10; Width 63 + Wave Sawtooth, Volume 22, NoteAdj 8
	.byte $7F, $D8, $06; Width 63 + Wave Sawtooth, Volume 24, NoteAdj 3
	.byte $7F, $D9, $00; Width 63 + Wave Sawtooth, Volume 25, NoteAdj 0
	.byte $7F, $DB, $10; Width 63 + Wave Sawtooth, Volume 27, NoteAdj 8
	.byte $7F, $DC, $06; Width 63 + Wave Sawtooth, Volume 28, NoteAdj 3
	.byte $7F, $DE, $00; Width 63 + Wave Sawtooth, Volume 30, NoteAdj 0
instrument_2:
	.byte $7F, $C3, $14; Width 63 + Wave Sawtooth, Volume 3, NoteAdj 10
	.byte $7F, $C3, $0A; Width 63 + Wave Sawtooth, Volume 3, NoteAdj 5
	.byte $7F, $C3, $00; Width 63 + Wave Sawtooth, Volume 3, NoteAdj 0
	.byte $7F, $C4, $14; Width 63 + Wave Sawtooth, Volume 4, NoteAdj 10
	.byte $7F, $C6, $0A; Width 63 + Wave Sawtooth, Volume 6, NoteAdj 5
	.byte $7F, $C7, $00; Width 63 + Wave Sawtooth, Volume 7, NoteAdj 0
	.byte $7F, $C9, $14; Width 63 + Wave Sawtooth, Volume 9, NoteAdj 10
	.byte $7F, $CA, $0A; Width 63 + Wave Sawtooth, Volume 10, NoteAdj 5
	.byte $7F, $CC, $00; Width 63 + Wave Sawtooth, Volume 12, NoteAdj 0
	.byte $7F, $CD, $14; Width 63 + Wave Sawtooth, Volume 13, NoteAdj 10
	.byte $7F, $CF, $0A; Width 63 + Wave Sawtooth, Volume 15, NoteAdj 5
	.byte $7F, $D0, $00; Width 63 + Wave Sawtooth, Volume 16, NoteAdj 0
	.byte $7F, $D2, $14; Width 63 + Wave Sawtooth, Volume 18, NoteAdj 10
	.byte $7F, $D3, $0A; Width 63 + Wave Sawtooth, Volume 19, NoteAdj 5
	.byte $7F, $D5, $00; Width 63 + Wave Sawtooth, Volume 21, NoteAdj 0
	.byte $7F, $D6, $14; Width 63 + Wave Sawtooth, Volume 22, NoteAdj 10
	.byte $7F, $D8, $0A; Width 63 + Wave Sawtooth, Volume 24, NoteAdj 5
	.byte $7F, $D9, $00; Width 63 + Wave Sawtooth, Volume 25, NoteAdj 0
	.byte $7F, $DB, $14; Width 63 + Wave Sawtooth, Volume 27, NoteAdj 10
	.byte $7F, $DC, $0A; Width 63 + Wave Sawtooth, Volume 28, NoteAdj 5
	.byte $7F, $DE, $00; Width 63 + Wave Sawtooth, Volume 30, NoteAdj 0
instrument_3:
	.byte $7F, $C3, $12; Width 63 + Wave Sawtooth, Volume 3, NoteAdj 9
	.byte $7F, $C3, $0A; Width 63 + Wave Sawtooth, Volume 3, NoteAdj 5
	.byte $7F, $C3, $00; Width 63 + Wave Sawtooth, Volume 3, NoteAdj 0
	.byte $7F, $C4, $12; Width 63 + Wave Sawtooth, Volume 4, NoteAdj 9
	.byte $7F, $C6, $0A; Width 63 + Wave Sawtooth, Volume 6, NoteAdj 5
	.byte $7F, $C7, $00; Width 63 + Wave Sawtooth, Volume 7, NoteAdj 0
	.byte $7F, $C9, $12; Width 63 + Wave Sawtooth, Volume 9, NoteAdj 9
	.byte $7F, $CA, $0A; Width 63 + Wave Sawtooth, Volume 10, NoteAdj 5
	.byte $7F, $CC, $00; Width 63 + Wave Sawtooth, Volume 12, NoteAdj 0
	.byte $7F, $CD, $12; Width 63 + Wave Sawtooth, Volume 13, NoteAdj 9
	.byte $7F, $CF, $0A; Width 63 + Wave Sawtooth, Volume 15, NoteAdj 5
	.byte $7F, $D0, $00; Width 63 + Wave Sawtooth, Volume 16, NoteAdj 0
	.byte $7F, $D2, $12; Width 63 + Wave Sawtooth, Volume 18, NoteAdj 9
	.byte $7F, $D3, $0A; Width 63 + Wave Sawtooth, Volume 19, NoteAdj 5
	.byte $7F, $D5, $00; Width 63 + Wave Sawtooth, Volume 21, NoteAdj 0
	.byte $7F, $D6, $12; Width 63 + Wave Sawtooth, Volume 22, NoteAdj 9
	.byte $7F, $D8, $0A; Width 63 + Wave Sawtooth, Volume 24, NoteAdj 5
	.byte $7F, $D9, $00; Width 63 + Wave Sawtooth, Volume 25, NoteAdj 0
	.byte $7F, $DB, $12; Width 63 + Wave Sawtooth, Volume 27, NoteAdj 9
	.byte $7F, $DC, $0A; Width 63 + Wave Sawtooth, Volume 28, NoteAdj 5
	.byte $7F, $DE, $00; Width 63 + Wave Sawtooth, Volume 30, NoteAdj 0
instrument_4:
	.byte $3F, $C0, $00; Width 63 + Wave Pulse, Volume 0, NoteAdj 0
	.byte $3F, $C6, $18; Width 63 + Wave Pulse, Volume 6, NoteAdj 12
	.byte $1E, $CC, $00; Width 30 + Wave Pulse, Volume 12, NoteAdj 0
	.byte $1E, $D2, $00; Width 30 + Wave Pulse, Volume 18, NoteAdj 0
	.byte $3F, $D8, $00; Width 63 + Wave Pulse, Volume 24, NoteAdj 0
	.byte $3F, $DE, $00; Width 63 + Wave Pulse, Volume 30, NoteAdj 0
instrument_5:
	.byte $00, $C0, $00; Width 0 + Wave Pulse, Volume 0, NoteAdj 0
	.byte $28, $DE, $00; Width 40 + Wave Pulse, Volume 30, NoteAdj 0
	.byte $00, $DE, $E8; Width 0 + Wave Pulse, Volume 30, NoteAdj -12
	.byte $3F, $DE, $00; Width 63 + Wave Pulse, Volume 30, NoteAdj 0
instrument_6:
	.byte $28, $C0, $00; Width 40 + Wave Pulse, Volume 0, NoteAdj 0
	.byte $28, $D4, $00; Width 40 + Wave Pulse, Volume 20, NoteAdj 0
	.byte $28, $D4, $00; Width 40 + Wave Pulse, Volume 20, NoteAdj 0
	.byte $28, $D4, $18; Width 40 + Wave Pulse, Volume 20, NoteAdj 12
instrument_7:
	.byte $7F, $D4, $00; Width 63 + Wave Sawtooth, Volume 20, NoteAdj 0
	.byte $7F, $D3, $12; Width 63 + Wave Sawtooth, Volume 19, NoteAdj 9
	.byte $7F, $D2, $0A; Width 63 + Wave Sawtooth, Volume 18, NoteAdj 5
	.byte $7F, $D1, $00; Width 63 + Wave Sawtooth, Volume 17, NoteAdj 0
	.byte $7F, $D1, $12; Width 63 + Wave Sawtooth, Volume 17, NoteAdj 9
	.byte $7F, $D0, $0A; Width 63 + Wave Sawtooth, Volume 16, NoteAdj 5
	.byte $7F, $CF, $00; Width 63 + Wave Sawtooth, Volume 15, NoteAdj 0
	.byte $7F, $CF, $12; Width 63 + Wave Sawtooth, Volume 15, NoteAdj 9
	.byte $7F, $CE, $0A; Width 63 + Wave Sawtooth, Volume 14, NoteAdj 5
	.byte $7F, $CD, $00; Width 63 + Wave Sawtooth, Volume 13, NoteAdj 0
	.byte $7F, $CD, $12; Width 63 + Wave Sawtooth, Volume 13, NoteAdj 9
	.byte $7F, $CC, $0A; Width 63 + Wave Sawtooth, Volume 12, NoteAdj 5
	.byte $7F, $CB, $00; Width 63 + Wave Sawtooth, Volume 11, NoteAdj 0
	.byte $7F, $CB, $12; Width 63 + Wave Sawtooth, Volume 11, NoteAdj 9
	.byte $7F, $CA, $0A; Width 63 + Wave Sawtooth, Volume 10, NoteAdj 5
	.byte $7F, $C9, $00; Width 63 + Wave Sawtooth, Volume 9, NoteAdj 0
	.byte $7F, $C9, $12; Width 63 + Wave Sawtooth, Volume 9, NoteAdj 9
	.byte $7F, $C8, $0A; Width 63 + Wave Sawtooth, Volume 8, NoteAdj 5
	.byte $7F, $C8, $00; Width 63 + Wave Sawtooth, Volume 8, NoteAdj 0
	.byte $7F, $C7, $12; Width 63 + Wave Sawtooth, Volume 7, NoteAdj 9
	.byte $7F, $C6, $0A; Width 63 + Wave Sawtooth, Volume 6, NoteAdj 5
	.byte $7F, $C6, $00; Width 63 + Wave Sawtooth, Volume 6, NoteAdj 0
	.byte $7F, $C5, $12; Width 63 + Wave Sawtooth, Volume 5, NoteAdj 9
	.byte $7F, $C4, $0A; Width 63 + Wave Sawtooth, Volume 4, NoteAdj 5
	.byte $7F, $C3, $00; Width 63 + Wave Sawtooth, Volume 3, NoteAdj 0
	.byte $7F, $C3, $12; Width 63 + Wave Sawtooth, Volume 3, NoteAdj 9
	.byte $7F, $C2, $0A; Width 63 + Wave Sawtooth, Volume 2, NoteAdj 5
	.byte $7F, $C2, $00; Width 63 + Wave Sawtooth, Volume 2, NoteAdj 0
	.byte $7F, $C1, $12; Width 63 + Wave Sawtooth, Volume 1, NoteAdj 9
	.byte $7F, $C0, $0A; Width 63 + Wave Sawtooth, Volume 0, NoteAdj 5
	.byte $7F, $C0, $00; Width 63 + Wave Sawtooth, Volume 0, NoteAdj 0
instrument_8:
	.byte $BF, $C0, $00; Width 63 + Wave Triangle, Volume 0, NoteAdj 0
	.byte $BF, $CA, $00; Width 63 + Wave Triangle, Volume 10, NoteAdj 0
	.byte $BF, $D4, $00; Width 63 + Wave Triangle, Volume 20, NoteAdj 0
	.byte $BF, $DE, $00; Width 63 + Wave Triangle, Volume 30, NoteAdj 0
	.byte $BF, $E8, $00; Width 63 + Wave Triangle, Volume 40, NoteAdj 0
	.byte $BF, $F2, $00; Width 63 + Wave Triangle, Volume 50, NoteAdj 0
	.byte $BF, $FC, $00; Width 63 + Wave Triangle, Volume 60, NoteAdj 0
	.byte $BF, $FC, $00; Width 63 + Wave Triangle, Volume 60, NoteAdj 0
	.byte $BF, $FC, $00; Width 63 + Wave Triangle, Volume 60, NoteAdj 0
	.byte $BF, $FC, $00; Width 63 + Wave Triangle, Volume 60, NoteAdj 0
	.byte $BF, $FC, $00; Width 63 + Wave Triangle, Volume 60, NoteAdj 0
	.byte $BF, $F2, $00; Width 63 + Wave Triangle, Volume 50, NoteAdj 0
	.byte $BF, $E8, $00; Width 63 + Wave Triangle, Volume 40, NoteAdj 0
	.byte $BF, $DE, $00; Width 63 + Wave Triangle, Volume 30, NoteAdj 0
	.byte $BF, $D4, $00; Width 63 + Wave Triangle, Volume 20, NoteAdj 0
instrument_9:
	.byte $FF, $C0, $00; Width 63 + Wave Noise, Volume 0, NoteAdj 0
	.byte $FF, $D4, $FC; Width 63 + Wave Noise, Volume 20, NoteAdj -2
	.byte $FF, $D8, $00; Width 63 + Wave Noise, Volume 24, NoteAdj 0
	.byte $FF, $DC, $FC; Width 63 + Wave Noise, Volume 28, NoteAdj -2
	.byte $FF, $E0, $00; Width 63 + Wave Noise, Volume 32, NoteAdj 0
	.byte $FF, $E4, $FC; Width 63 + Wave Noise, Volume 36, NoteAdj -2
	.byte $FF, $E8, $00; Width 63 + Wave Noise, Volume 40, NoteAdj 0
instrument_10:
	.byte $FF, $C0, $00; Width 63 + Wave Noise, Volume 0, NoteAdj 0
	.byte $FF, $CA, $00; Width 63 + Wave Noise, Volume 10, NoteAdj 0
	.byte $FF, $D4, $00; Width 63 + Wave Noise, Volume 20, NoteAdj 0
	.byte $FF, $E8, $00; Width 63 + Wave Noise, Volume 40, NoteAdj 0
	.byte $FF, $DE, $00; Width 63 + Wave Noise, Volume 30, NoteAdj 0
	.byte $FF, $D4, $00; Width 63 + Wave Noise, Volume 20, NoteAdj 0
instrument_11:
	.byte $FF, $C0, $FE; Width 63 + Wave Noise, Volume 0, NoteAdj -1
	.byte $FF, $C4, $FC; Width 63 + Wave Noise, Volume 4, NoteAdj -2
	.byte $FF, $C8, $F0; Width 63 + Wave Noise, Volume 8, NoteAdj -8
	.byte $FF, $CC, $00; Width 63 + Wave Noise, Volume 12, NoteAdj 0
	.byte $FF, $D0, $FE; Width 63 + Wave Noise, Volume 16, NoteAdj -1
	.byte $FF, $D4, $FC; Width 63 + Wave Noise, Volume 20, NoteAdj -2
	.byte $FF, $D6, $F0; Width 63 + Wave Noise, Volume 22, NoteAdj -8
	.byte $FF, $D8, $00; Width 63 + Wave Noise, Volume 24, NoteAdj 0
	.byte $FF, $DA, $FE; Width 63 + Wave Noise, Volume 26, NoteAdj -1
	.byte $FF, $DC, $FC; Width 63 + Wave Noise, Volume 28, NoteAdj -2
	.byte $FF, $DE, $F0; Width 63 + Wave Noise, Volume 30, NoteAdj -8
	.byte $FF, $E0, $00; Width 63 + Wave Noise, Volume 32, NoteAdj 0
	.byte $FF, $E2, $FE; Width 63 + Wave Noise, Volume 34, NoteAdj -1
	.byte $FF, $E4, $FC; Width 63 + Wave Noise, Volume 36, NoteAdj -2
	.byte $FF, $E6, $F0; Width 63 + Wave Noise, Volume 38, NoteAdj -8
	.byte $FF, $E8, $00; Width 63 + Wave Noise, Volume 40, NoteAdj 0
instrument_12:
	.byte $FF, $C0, $00; Width 63 + Wave Noise, Volume 0, NoteAdj 0
	.byte $FF, $C5, $02; Width 63 + Wave Noise, Volume 5, NoteAdj 1
	.byte $FF, $CA, $00; Width 63 + Wave Noise, Volume 10, NoteAdj 0
	.byte $FF, $CF, $02; Width 63 + Wave Noise, Volume 15, NoteAdj 1
	.byte $FF, $D4, $00; Width 63 + Wave Noise, Volume 20, NoteAdj 0
	.byte $FF, $D9, $02; Width 63 + Wave Noise, Volume 25, NoteAdj 1
	.byte $FF, $DE, $00; Width 63 + Wave Noise, Volume 30, NoteAdj 0

pattern_data:
pattern_0:

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0E	; Instrument 7
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 244 bytes.
pattern_1:

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 256 bytes.
pattern_2:

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $48	; Note 37 (*2) C#3 - Vera 00BA
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $4C	; Note 39 (*2) D#3 - Vera 00D0
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $50	; Note 41 (*2) F-3 - Vera 00EA
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $52	; Note 42 (*2) F#3 - Vera 00F8
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $4C	; Note 39 (*2) D#3 - Vera 00D0
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $4C	; Note 39 (*2) D#3 - Vera 00D0
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $4C	; Note 39 (*2) D#3 - Vera 00D0
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $48	; Note 37 (*2) C#3 - Vera 00BA
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $46	; Note 36 (*2) C-3 - Vera 00AF
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 296 bytes.
pattern_3:

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $48	; Note 37 (*2) C#3 - Vera 00BA
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $46	; Note 36 (*2) C-3 - Vera 00AF
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 268 bytes.
pattern_4:

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $48	; Note 37 (*2) C#3 - Vera 00BA
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $4C	; Note 39 (*2) D#3 - Vera 00D0
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $50	; Note 41 (*2) F-3 - Vera 00EA
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $52	; Note 42 (*2) F#3 - Vera 00F8
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $56	; Note 44 (*2) G#3 - Vera 0116
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $48	; Note 37 (*2) C#3 - Vera 00BA
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 288 bytes.
pattern_5:

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 260 bytes.
pattern_6:

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $50	; Note 41 (*2) F-3 - Vera 00EA
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $52	; Note 42 (*2) F#3 - Vera 00F8
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $4C	; Note 39 (*2) D#3 - Vera 00D0
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $4C	; Note 39 (*2) D#3 - Vera 00D0
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $4C	; Note 39 (*2) D#3 - Vera 00D0
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $48	; Note 37 (*2) C#3 - Vera 00BA
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $46	; Note 36 (*2) C-3 - Vera 00AF
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 304 bytes.
pattern_7:

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $50	; Note 41 (*2) F-3 - Vera 00EA
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $52	; Note 42 (*2) F#3 - Vera 00F8
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $56	; Note 44 (*2) G#3 - Vera 0116
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $46	; Note 36 (*2) C-3 - Vera 00AF
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 296 bytes.
pattern_8:

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $A2	; Note 82 (*2) A#6 - Vera 09C6
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $5A	; Note 46 (*2) A#3 - Vera 0138
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $98	; Note 77 (*2) F-6 - Vera 0752
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $50	; Note 41 (*2) F-3 - Vera 00EA
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $9A	; Note 78 (*2) F#6 - Vera 07C2
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $52	; Note 42 (*2) F#3 - Vera 00F8
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3A	; Note 30 (*2) F#2 - Vera 007C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $9A	; Note 78 (*2) F#6 - Vera 07C2
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $52	; Note 42 (*2) F#3 - Vera 00F8
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3A	; Note 30 (*2) F#2 - Vera 007C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $9A	; Note 78 (*2) F#6 - Vera 07C2
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $52	; Note 42 (*2) F#3 - Vera 00F8
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3A	; Note 30 (*2) F#2 - Vera 007C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3E	; Note 32 (*2) G#2 - Vera 008B
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3E	; Note 32 (*2) G#2 - Vera 008B
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3E	; Note 32 (*2) G#2 - Vera 008B
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $9E	; Note 80 (*2) G#6 - Vera 08B5
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $56	; Note 44 (*2) G#3 - Vera 0116
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3E	; Note 32 (*2) G#2 - Vera 008B
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $9E	; Note 80 (*2) G#6 - Vera 08B5
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $56	; Note 44 (*2) G#3 - Vera 0116
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $94	; Note 75 (*2) D#6 - Vera 0686
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $4C	; Note 39 (*2) D#3 - Vera 00D0
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $94	; Note 75 (*2) D#6 - Vera 0686
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $4C	; Note 39 (*2) D#3 - Vera 00D0
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $34	; Note 27 (*2) D#2 - Vera 0068
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $94	; Note 75 (*2) D#6 - Vera 0686
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $4C	; Note 39 (*2) D#3 - Vera 00D0
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $34	; Note 27 (*2) D#2 - Vera 0068
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $94	; Note 75 (*2) D#6 - Vera 0686
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $4C	; Note 39 (*2) D#3 - Vera 00D0
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 512 bytes.
pattern_9:

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $A2	; Note 82 (*2) A#6 - Vera 09C6
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $5A	; Note 46 (*2) A#3 - Vera 0138
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $A2	; Note 82 (*2) A#6 - Vera 09C6
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $5A	; Note 46 (*2) A#3 - Vera 0138
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $9E	; Note 80 (*2) G#6 - Vera 08B5
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $56	; Note 44 (*2) G#3 - Vera 0116
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $A2	; Note 82 (*2) A#6 - Vera 09C6
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $5A	; Note 46 (*2) A#3 - Vera 0138
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $A2	; Note 82 (*2) A#6 - Vera 09C6
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $5A	; Note 46 (*2) A#3 - Vera 0138
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $A2	; Note 82 (*2) A#6 - Vera 09C6
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $5A	; Note 46 (*2) A#3 - Vera 0138
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $9E	; Note 80 (*2) G#6 - Vera 08B5
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $56	; Note 44 (*2) G#3 - Vera 0116
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $A2	; Note 82 (*2) A#6 - Vera 09C6
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $5A	; Note 46 (*2) A#3 - Vera 0138
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 512 bytes.
pattern_10:

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $A2	; Note 82 (*2) A#6 - Vera 09C6
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $5A	; Note 46 (*2) A#3 - Vera 0138
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $A2	; Note 82 (*2) A#6 - Vera 09C6
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $5A	; Note 46 (*2) A#3 - Vera 0138
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $78	; Note 61 (*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $9E	; Note 80 (*2) G#6 - Vera 08B5
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $56	; Note 44 (*2) G#3 - Vera 0116
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $A2	; Note 82 (*2) A#6 - Vera 09C6
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $5A	; Note 46 (*2) A#3 - Vera 0138
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $A2	; Note 82 (*2) A#6 - Vera 09C6
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $5A	; Note 46 (*2) A#3 - Vera 0138
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $A2	; Note 82 (*2) A#6 - Vera 09C6
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $5A	; Note 46 (*2) A#3 - Vera 0138
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $9E	; Note 80 (*2) G#6 - Vera 08B5
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $52	; Note 42 (*2) F#3 - Vera 00F8
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C4	; Note 99 (*2) D#8 - Vera 1A19
	.byte $16	; Instrument 11
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $46	; Note 36 (*2) C-3 - Vera 00AF
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C4	; Note 99 (*2) D#8 - Vera 1A19
	.byte $18	; Instrument 12
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $A2	; Note 82 (*2) A#6 - Vera 09C6
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $52	; Note 42 (*2) F#3 - Vera 00F8
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C4	; Note 99 (*2) D#8 - Vera 1A19
	.byte $16	; Instrument 11
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 512 bytes.
; -- total size: 3748 bytes.

pattern_playlist:
	.byte $0A
	.byte $09
	.byte $08
	.byte $08
	.byte $05
	.byte $07
	.byte $03
	.byte $06
	.byte $05
	.byte $04
	.byte $03
	.byte $02
	.byte $01
	.byte $00

.endmacro

.macro Player_NoteLookup
player_notelookup:
	.word $0000
	.word $0000
	.word $0000
	.word $0000
	.word $0000
	.word $0000
	.word $0000
	.word $0000
	.word $0000
	.word $0000
	.word $0000
	.word $0000
	.word $0000
	.word $0000
	.word $0000
	.word $0000
	.word $0000
	.word $0000
	.word $0000
	.word $0000
	.word $0049
	.word $004E
	.word $0052
	.word $0057
	.word $005D
	.word $0062
	.word $0068
	.word $006E
	.word $0075
	.word $007C
	.word $0083
	.word $008B
	.word $0093
	.word $009C
	.word $00A5
	.word $00AF
	.word $00BA
	.word $00C5
	.word $00D0
	.word $00DD
	.word $00EA
	.word $00F8
	.word $0107
	.word $0116
	.word $0127
	.word $0138
	.word $014B
	.word $015F
	.word $0174
	.word $018A
	.word $01A1
	.word $01BA
	.word $01D4
	.word $01F0
	.word $020E
	.word $022D
	.word $024E
	.word $0271
	.word $0296
	.word $02BE
	.word $02E8
	.word $0314
	.word $0343
	.word $0374
	.word $03A9
	.word $03E1
	.word $041C
	.word $045A
	.word $049D
	.word $04E3
	.word $052D
	.word $057C
	.word $05D0
	.word $0628
	.word $0686
	.word $06E9
	.word $0752
	.word $07C2
	.word $0838
	.word $08B5
	.word $093A
	.word $09C6
	.word $0A5B
	.word $0AF9
	.word $0BA0
	.word $0C51
	.word $0D0C
	.word $0DD3
	.word $0EA5
	.word $0F84
	.word $1071
	.word $116B
	.word $1274
	.word $138D
	.word $14B7
	.word $15F2
	.word $1740
	.word $18A2
	.word $1A19
	.word $1BA6
	.word $1D4B
	.word $1F09
	.word $20E2
	.word $22D6
	.word $24E8
	.word $271A
	.word $296E
	.word $2BE4
	.word $2E80
	.word $3144
	.word $3432
	.word $374D
	.word $3A97
	.word $3E13
	.word $41C4
	.word $45AD
	.word $49D1
	.word $4E35
	.word $52DC
	.word $57C9
	.word $5D01
	.word $6289
	.word $6865
	.word $6E9A
	.word $752E
	.word $7C26
	.word $8388
	.word $8B5A

.endmacro

.endscope
