
;https://opensource.org/licenses/BSD-3-Clause

;Copyright 2021 Yazwho

;Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

;1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

;2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

;3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

;THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.



; uncomment if you're not including this elsewhere.
;.include "./library/copytovram.asm"


.scope

; need to run this maco to define where to keep the data.
.macro Player_Variables frameIndex, lineIndex, patternIndex, nextLineCounter, vhPos, vmPos, vlPos, instrumentDataZP, instrumentCommandData, instrumentPosition, instrumentNumber, playerScratch
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
INSTRUMENT_ADDR = instrumentDataZP

; Needs 2 * 7 bytes. 
; .word command parameters
INSTRUMENT_COMMAND_START = instrumentCommandData
INSTRUMENT_COMMAND_PARAM0 = instrumentCommandData
INSTRUMENT_COMMAND_PARAM1 = instrumentCommandData + 1

; instrument data 
; .byte position (decreases)
; .byte current command 
INSTRUMENT_DATA_START = instrumentPosition
INSTRUMENT_DATA_POSITION = instrumentPosition
INSTRUMENT_DATA_COMMAND = instrumentPosition + 1

; instrument number
; .byte number
; .byte repeat position
INSTRUMENT_NUMBER_START = instrumentNumber
INSTRUMENT_NUMBER = instrumentNumber
INSTRUMENT_NUMBER_REPEAT = instrumentNumber + 1

; 4 bytes of scrach space for the player
PLAYER_SCRATCH = playerScratch
PLAYER_SCRATCH_FREQL = PLAYER_SCRATCH
PLAYER_SCRATCH_FREQH = PLAYER_SCRATCH + 1
PLAYER_SCRATCH_VOLUME = PLAYER_SCRATCH + 2
PLAYER_SCRATCH_WIDTH = PLAYER_SCRATCH + 3

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
    stz INSTRUMENT_NUMBER_START - 1, x
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
    copytovram vh, vm, vl, $10E0, pattern_data

    rts
.endmacro

.macro Play_Instrument offset, hasCommands
    .local instrument_not_playing
    .local instrument_done
    .local instrument_played
    .local no_note_adjust
    .local note_adjust_done
    .local skipinstr
    .local check_command
    .local command_done

    lda INSTRUMENT_DATA_POSITION + (offset * 2)
    beq instrument_not_playing
    tay

    ; adjust note
    lda (INSTRUMENT_ADDR + (offset * 2)), y
    clc
    adc INSTRUMENT_NUMBER + (offset * 2)

    tax

    lda player_notelookup, x
    sta PLAYER_SCRATCH_FREQL

    lda player_notelookup+1, x
    sta PLAYER_SCRATCH_FREQH

    dey

    ; volume
    lda (INSTRUMENT_ADDR + (offset * 2)), y
    sta PLAYER_SCRATCH_VOLUME

    dey
    beq instrument_played

    ; width
    lda (INSTRUMENT_ADDR + (offset * 2)), y
    sta PLAYER_SCRATCH_WIDTH

    dey
    
    tya
    sta INSTRUMENT_DATA_POSITION + (offset * 2)

    jmp check_command

instrument_played:
    lda (INSTRUMENT_ADDR + (offset * 2))
    sta PLAYER_SCRATCH_WIDTH

    ; get repeat position (0 will stop)
    lda INSTRUMENT_NUMBER_REPEAT + (offset * 2)
    sta INSTRUMENT_DATA_POSITION + (offset * 2)

check_command:
    .if 1 = 1

    lda INSTRUMENT_DATA_COMMAND + (offset * 2)
    beq command_done

    tax ; x is now the command

    ; set return address on the stack as the commands can't jump into a macro

    lda #>(command_done-1)
    pha
    lda #<(command_done-1)
    pha

    ldy #(offset * 2) ; pass y as the offset
    dex
    dex

    jmp (command_jump_table, x)

    .endif

command_done:
    lda PLAYER_SCRATCH_FREQL
    sta DATA0
    lda PLAYER_SCRATCH_FREQH
    sta DATA0
    lda PLAYER_SCRATCH_VOLUME
    sta DATA0
    lda PLAYER_SCRATCH_WIDTH
    sta DATA0

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
    .local no_note_change

	dec FRAME_INDEX
	bne play_instruments  
    jmp next_line

play_instruments:
    ; PLAY INSTRUMENTS
    ; PSG Start.
    lda #$11
    sta ADDRx_L
    lda #$f9
    sta ADDRx_M
    lda #$c0
    sta ADDRx_L

.repeat 7, I
Play_Instrument I, 1
.endrepeat

    rts

; commands


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
    beq no_note_change ; if the note number is zero, there is only a command.
    sta INSTRUMENT_NUMBER, y ; store instrument number

    ldx DATA0   ; instrument number, already *2 for the lookup.

    ; store instrment address and pos. (instrument data is reversed)
    lda instruments_play, x
    sta INSTRUMENT_ADDR, y
    lda instruments_play + 1, x
    sta INSTRUMENT_ADDR + 1, y

    lda instrument_length, x
    sta INSTRUMENT_DATA_POSITION, y

    lda instrument_length + 1, x
    sta INSTRUMENT_NUMBER_REPEAT, y

no_note_change:
    lda DATA0   ; command
    beq no_command

    sta INSTRUMENT_DATA_COMMAND, y

    lda DATA0   ; command data
    sta INSTRUMENT_COMMAND_PARAM0, y
    lda DATA0
    sta INSTRUMENT_COMMAND_PARAM1, y

    jmp next_voice
no_command:
    lda #0
    sta INSTRUMENT_DATA_COMMAND, y

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
	.word pattern_11_init

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
	lda #(^(vh * $10000 + vm * $100 + vl + 510)) + $10
	sta PATTERN_POS_H
	lda #>(vh * $10000 + vm * $100 + vl + 510)
	sta PATTERN_POS_M
	lda #<(vh * $10000 + vm * $100 + vl + 510)
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
	lda #(^(vh * $10000 + vm * $100 + vl + 806)) + $10
	sta PATTERN_POS_H
	lda #>(vh * $10000 + vm * $100 + vl + 806)
	sta PATTERN_POS_M
	lda #<(vh * $10000 + vm * $100 + vl + 806)
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
	lda #(^(vh * $10000 + vm * $100 + vl + 1074)) + $10
	sta PATTERN_POS_H
	lda #>(vh * $10000 + vm * $100 + vl + 1074)
	sta PATTERN_POS_M
	lda #<(vh * $10000 + vm * $100 + vl + 1074)
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
	lda #(^(vh * $10000 + vm * $100 + vl + 1362)) + $10
	sta PATTERN_POS_H
	lda #>(vh * $10000 + vm * $100 + vl + 1362)
	sta PATTERN_POS_M
	lda #<(vh * $10000 + vm * $100 + vl + 1362)
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
	lda #(^(vh * $10000 + vm * $100 + vl + 1622)) + $10
	sta PATTERN_POS_H
	lda #>(vh * $10000 + vm * $100 + vl + 1622)
	sta PATTERN_POS_M
	lda #<(vh * $10000 + vm * $100 + vl + 1622)
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
	lda #(^(vh * $10000 + vm * $100 + vl + 1926)) + $10
	sta PATTERN_POS_H
	lda #>(vh * $10000 + vm * $100 + vl + 1926)
	sta PATTERN_POS_M
	lda #<(vh * $10000 + vm * $100 + vl + 1926)
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
	lda #(^(vh * $10000 + vm * $100 + vl + 2222)) + $10
	sta PATTERN_POS_H
	lda #>(vh * $10000 + vm * $100 + vl + 2222)
	sta PATTERN_POS_M
	lda #<(vh * $10000 + vm * $100 + vl + 2222)
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
	lda #(^(vh * $10000 + vm * $100 + vl + 2734)) + $10
	sta PATTERN_POS_H
	lda #>(vh * $10000 + vm * $100 + vl + 2734)
	sta PATTERN_POS_M
	lda #<(vh * $10000 + vm * $100 + vl + 2734)
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
	lda #(^(vh * $10000 + vm * $100 + vl + 3246)) + $10
	sta PATTERN_POS_H
	lda #>(vh * $10000 + vm * $100 + vl + 3246)
	sta PATTERN_POS_M
	lda #<(vh * $10000 + vm * $100 + vl + 3246)
	sta PATTERN_POS_L
	lda #$01 ; first line is 1
	sta NEXT_LINE_COUNTER
	lda #$18 ; this pattern is 24 lines long
	sta LINE_INDEX
	lda #$0A ; tempo
	sta next_line+1 ; modify reset code
	sta FRAME_INDEX
	jmp play_next

pattern_11_init:
	lda #(^(vh * $10000 + vm * $100 + vl + 3758)) + $10
	sta PATTERN_POS_H
	lda #>(vh * $10000 + vm * $100 + vl + 3758)
	sta PATTERN_POS_M
	lda #<(vh * $10000 + vm * $100 + vl + 3758)
	sta PATTERN_POS_L
	lda #$01 ; first line is 1
	sta NEXT_LINE_COUNTER
	lda #$30 ; this pattern is 48 lines long
	sta LINE_INDEX
	lda #$05 ; tempo
	sta next_line+1 ; modify reset code
	sta FRAME_INDEX
	jmp play_next

    stp ; should never reach here

restart:
    lda #$0F ; playlist length
    sta PATTERN_INDEX

    tax
    dex
    jmp play_next_pattern

command_jump_table:
	.word command_silence
	.word command_slidedowntonote
	.word command_pitchshiftup


.proc command_pitchshiftup
    ; number of shifts
    ldx INSTRUMENT_COMMAND_PARAM0, y

    lda INSTRUMENT_NUMBER, y
    tay ; y now is the note number
loop:
    clc
    lda player_slidelookup, y
    adc PLAYER_SCRATCH_FREQL
    sta PLAYER_SCRATCH_FREQL
    lda player_slidelookup+1, y
    adc PLAYER_SCRATCH_FREQH
    sta PLAYER_SCRATCH_FREQH

    dex
    bne loop

    rts
.endproc

.proc command_silence
    ldx INSTRUMENT_COMMAND_PARAM0, y ; total counter
    beq command_done

    dex
    txa ; could use stx, if we enforce this on zp?
    sta INSTRUMENT_COMMAND_PARAM0, y
    rts
command_done:
    stz PLAYER_SCRATCH_VOLUME
    rts
.endproc

.proc command_slideuptonote
    tya
    tax
    dec INSTRUMENT_COMMAND_PARAM1, x ; total counter
    beq command_done

    ldx INSTRUMENT_COMMAND_PARAM0, y ; steps per frame

    lda INSTRUMENT_NUMBER, y
    tay ; y now is the note number
loop:
    clc
    lda player_slidelookup, y
    adc PLAYER_SCRATCH_FREQL
    sta PLAYER_SCRATCH_FREQL
    lda player_slidelookup+1, y
    adc PLAYER_SCRATCH_FREQH
    sta PLAYER_SCRATCH_FREQH

    dex
    bne loop

    rts

    command_done:
    stz INSTRUMENT_DATA_COMMAND, x
    rts
.endproc

.proc command_slidedowntonote
    tya
    tax
    dec INSTRUMENT_COMMAND_PARAM1, x ; total counter
    beq command_done

    ldx INSTRUMENT_COMMAND_PARAM0, y ; steps per frame

    lda INSTRUMENT_NUMBER, y
    tay ; y now is the note number
loop:
    clc
    lda player_slidelookup, y
    sbc PLAYER_SCRATCH_FREQL
    sta PLAYER_SCRATCH_FREQL
    lda player_slidelookup+1, y
    sbc PLAYER_SCRATCH_FREQH
    sta PLAYER_SCRATCH_FREQH

    dex
    bne loop

    rts

    command_done:
    stz INSTRUMENT_DATA_COMMAND, x
    rts
.endproc

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
	.word pattern_11

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
	.word instrument_13
	.word $0000

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
	.byte $08, $08 ; 3 steps, 0 repeat
	.byte $00, $00

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
instrument_13:
	.byte $28, $D0, $00; Width 40 + Wave Pulse, Volume 16, NoteAdj 0
	.byte $28, $D2, $00; Width 40 + Wave Pulse, Volume 18, NoteAdj 0
	.byte $28, $D4, $00; Width 40 + Wave Pulse, Volume 20, NoteAdj 0

pattern_data:
pattern_0:

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0E	; Instrument 7
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 244 bytes.
pattern_1:

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $00	; Note 1 (-1*2) --- - Vera 0000
	.byte $02	; Silence
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $00	; Note 1 (-1*2) --- - Vera 0000
	.byte $02	; Silence
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 266 bytes.
pattern_2:

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $48	; Note 37 (-1*2) C#3 - Vera 00BA
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $4C	; Note 39 (-1*2) D#3 - Vera 00D0
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $50	; Note 41 (-1*2) F-3 - Vera 00EA
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $52	; Note 42 (-1*2) F#3 - Vera 00F8
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $4C	; Note 39 (-1*2) D#3 - Vera 00D0
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $4C	; Note 39 (-1*2) D#3 - Vera 00D0
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $4C	; Note 39 (-1*2) D#3 - Vera 00D0
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $48	; Note 37 (-1*2) C#3 - Vera 00BA
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 296 bytes.
pattern_3:

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $48	; Note 37 (-1*2) C#3 - Vera 00BA
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 268 bytes.
pattern_4:

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $48	; Note 37 (-1*2) C#3 - Vera 00BA
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $4C	; Note 39 (-1*2) D#3 - Vera 00D0
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $50	; Note 41 (-1*2) F-3 - Vera 00EA
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $52	; Note 42 (-1*2) F#3 - Vera 00F8
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $56	; Note 44 (-1*2) G#3 - Vera 0116
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $48	; Note 37 (-1*2) C#3 - Vera 00BA
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 288 bytes.
pattern_5:

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 260 bytes.
pattern_6:

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $50	; Note 41 (-1*2) F-3 - Vera 00EA
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $52	; Note 42 (-1*2) F#3 - Vera 00F8
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $4C	; Note 39 (-1*2) D#3 - Vera 00D0
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $4C	; Note 39 (-1*2) D#3 - Vera 00D0
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $4C	; Note 39 (-1*2) D#3 - Vera 00D0
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $48	; Note 37 (-1*2) C#3 - Vera 00BA
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 304 bytes.
pattern_7:

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $50	; Note 41 (-1*2) F-3 - Vera 00EA
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $52	; Note 42 (-1*2) F#3 - Vera 00F8
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $02	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $56	; Note 44 (-1*2) G#3 - Vera 0116
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 296 bytes.
pattern_8:

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $A2	; Note 82 (-1*2) A#6 - Vera 09C6
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $5A	; Note 46 (-1*2) A#3 - Vera 0138
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $98	; Note 77 (-1*2) F-6 - Vera 0752
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $50	; Note 41 (-1*2) F-3 - Vera 00EA
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $9A	; Note 78 (-1*2) F#6 - Vera 07C2
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $52	; Note 42 (-1*2) F#3 - Vera 00F8
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3A	; Note 30 (-1*2) F#2 - Vera 007C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $9A	; Note 78 (-1*2) F#6 - Vera 07C2
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $52	; Note 42 (-1*2) F#3 - Vera 00F8
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3A	; Note 30 (-1*2) F#2 - Vera 007C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $9A	; Note 78 (-1*2) F#6 - Vera 07C2
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $52	; Note 42 (-1*2) F#3 - Vera 00F8
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3A	; Note 30 (-1*2) F#2 - Vera 007C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3E	; Note 32 (-1*2) G#2 - Vera 008B
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3E	; Note 32 (-1*2) G#2 - Vera 008B
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3E	; Note 32 (-1*2) G#2 - Vera 008B
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $9E	; Note 80 (-1*2) G#6 - Vera 08B5
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $56	; Note 44 (-1*2) G#3 - Vera 0116
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3E	; Note 32 (-1*2) G#2 - Vera 008B
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $9E	; Note 80 (-1*2) G#6 - Vera 08B5
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $56	; Note 44 (-1*2) G#3 - Vera 0116
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $94	; Note 75 (-1*2) D#6 - Vera 0686
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $4C	; Note 39 (-1*2) D#3 - Vera 00D0
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $94	; Note 75 (-1*2) D#6 - Vera 0686
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $4C	; Note 39 (-1*2) D#3 - Vera 00D0
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $34	; Note 27 (-1*2) D#2 - Vera 0068
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $94	; Note 75 (-1*2) D#6 - Vera 0686
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $4C	; Note 39 (-1*2) D#3 - Vera 00D0
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $34	; Note 27 (-1*2) D#2 - Vera 0068
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $94	; Note 75 (-1*2) D#6 - Vera 0686
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $4C	; Note 39 (-1*2) D#3 - Vera 00D0
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 512 bytes.
pattern_9:

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $A2	; Note 82 (-1*2) A#6 - Vera 09C6
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $5A	; Note 46 (-1*2) A#3 - Vera 0138
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $A2	; Note 82 (-1*2) A#6 - Vera 09C6
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $5A	; Note 46 (-1*2) A#3 - Vera 0138
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $9E	; Note 80 (-1*2) G#6 - Vera 08B5
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $56	; Note 44 (-1*2) G#3 - Vera 0116
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $A2	; Note 82 (-1*2) A#6 - Vera 09C6
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $5A	; Note 46 (-1*2) A#3 - Vera 0138
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $A2	; Note 82 (-1*2) A#6 - Vera 09C6
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $5A	; Note 46 (-1*2) A#3 - Vera 0138
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $A2	; Note 82 (-1*2) A#6 - Vera 09C6
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $5A	; Note 46 (-1*2) A#3 - Vera 0138
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $9E	; Note 80 (-1*2) G#6 - Vera 08B5
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $56	; Note 44 (-1*2) G#3 - Vera 0116
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $A2	; Note 82 (-1*2) A#6 - Vera 09C6
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $5A	; Note 46 (-1*2) A#3 - Vera 0138
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 512 bytes.
pattern_10:

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $A2	; Note 82 (-1*2) A#6 - Vera 09C6
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $5A	; Note 46 (-1*2) A#3 - Vera 0138
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $A2	; Note 82 (-1*2) A#6 - Vera 09C6
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $5A	; Note 46 (-1*2) A#3 - Vera 0138
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $78	; Note 61 (-1*2) C#5 - Vera 02E8
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $9E	; Note 80 (-1*2) G#6 - Vera 08B5
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $56	; Note 44 (-1*2) G#3 - Vera 0116
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $A2	; Note 82 (-1*2) A#6 - Vera 09C6
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $5A	; Note 46 (-1*2) A#3 - Vera 0138
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $A2	; Note 82 (-1*2) A#6 - Vera 09C6
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $5A	; Note 46 (-1*2) A#3 - Vera 0138
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $A2	; Note 82 (-1*2) A#6 - Vera 09C6
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $5A	; Note 46 (-1*2) A#3 - Vera 0138
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DC	; Note 111 (-1*2) D#9 - Vera 3432
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $9E	; Note 80 (-1*2) G#6 - Vera 08B5
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $52	; Note 42 (-1*2) F#3 - Vera 00F8
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C4	; Note 99 (-1*2) D#8 - Vera 1A19
	.byte $16	; Instrument 11
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C4	; Note 99 (-1*2) D#8 - Vera 1A19
	.byte $18	; Instrument 12
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $08	; Instrument 4
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $A2	; Note 82 (-1*2) A#6 - Vera 09C6
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $52	; Note 42 (-1*2) F#3 - Vera 00F8
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C4	; Note 99 (-1*2) D#8 - Vera 1A19
	.byte $16	; Instrument 11
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 512 bytes.
pattern_11:

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $DA	; Note 110 (-1*2) D-9 - Vera 3144
	.byte $18	; Instrument 12
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $1A	; Instrument 13
	.byte $04	; SlideDownToNote
	.word $0501	;
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $1A	; Instrument 13
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $88	; Note 69 (-1*2) A-5 - Vera 049D
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DA	; Note 110 (-1*2) D-9 - Vera 3144
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $04	; first voice is 4
	.byte $00	; Note 1 (-1*2) --- - Vera 0000
	.byte $02	; Silence
	.word $0004	;
	.byte $00	; steps to next voice
	.byte $00	; Note 1 (-1*2) --- - Vera 0000
	.byte $02	; Silence
	.word $0004	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DA	; Note 110 (-1*2) D-9 - Vera 3144
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $1A	; Instrument 13
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $1A	; Instrument 13
	.byte $06	; PitchShiftUp
	.word $0001	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DA	; Note 110 (-1*2) D-9 - Vera 3144
	.byte $16	; Instrument 11
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $90	; Note 73 (-1*2) C#6 - Vera 05D0
	.byte $1A	; Instrument 13
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $90	; Note 73 (-1*2) C#6 - Vera 05D0
	.byte $1A	; Instrument 13
	.byte $06	; PitchShiftUp
	.word $0001	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $50	; Note 41 (-1*2) F-3 - Vera 00EA
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DA	; Note 110 (-1*2) D-9 - Vera 3144
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $1A	; Instrument 13
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $1A	; Instrument 13
	.byte $06	; PitchShiftUp
	.word $0001	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $DA	; Note 110 (-1*2) D-9 - Vera 3144
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $1A	; Instrument 13
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $1A	; Instrument 13
	.byte $06	; PitchShiftUp
	.word $0001	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $52	; Note 42 (-1*2) F#3 - Vera 00F8
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DA	; Note 110 (-1*2) D-9 - Vera 3144
	.byte $18	; Instrument 12
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $96	; Note 76 (-1*2) E-6 - Vera 06E9
	.byte $1A	; Instrument 13
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $96	; Note 76 (-1*2) E-6 - Vera 06E9
	.byte $1A	; Instrument 13
	.byte $06	; PitchShiftUp
	.word $0001	;
	.byte $00	; steps to next voice
	.byte $88	; Note 69 (-1*2) A-5 - Vera 049D
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $6A	; Note 54 (-1*2) F#4 - Vera 01F0
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $DA	; Note 110 (-1*2) D-9 - Vera 3144
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $DA	; Note 110 (-1*2) D-9 - Vera 3144
	.byte $18	; Instrument 12
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $94	; Note 75 (-1*2) D#6 - Vera 0686
	.byte $1A	; Instrument 13
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $94	; Note 75 (-1*2) D#6 - Vera 0686
	.byte $1A	; Instrument 13
	.byte $06	; PitchShiftUp
	.word $0001	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $6A	; Note 54 (-1*2) F#4 - Vera 01F0
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $DA	; Note 110 (-1*2) D-9 - Vera 3144
	.byte $16	; Instrument 11
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $52	; Note 42 (-1*2) F#3 - Vera 00F8
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DA	; Note 110 (-1*2) D-9 - Vera 3144
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $90	; Note 73 (-1*2) C#6 - Vera 05D0
	.byte $1A	; Instrument 13
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $90	; Note 73 (-1*2) C#6 - Vera 05D0
	.byte $1A	; Instrument 13
	.byte $06	; PitchShiftUp
	.word $0001	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $6A	; Note 54 (-1*2) F#4 - Vera 01F0
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3A	; Note 30 (-1*2) F#2 - Vera 007C
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DA	; Note 110 (-1*2) D-9 - Vera 3144
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $1A	; Instrument 13
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $1A	; Instrument 13
	.byte $06	; PitchShiftUp
	.word $0001	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $04	; first voice is 4
	.byte $00	; Note 1 (-1*2) --- - Vera 0000
	.byte $02	; Silence
	.word $0004	;
	.byte $00	; steps to next voice
	.byte $00	; Note 1 (-1*2) --- - Vera 0000
	.byte $02	; Silence
	.word $0004	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $01	; first voice is 1
	.byte $6E	; Note 56 (-1*2) G#4 - Vera 022D
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $DA	; Note 110 (-1*2) D-9 - Vera 3144
	.byte $18	; Instrument 12
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8E	; Note 72 (-1*2) C-6 - Vera 057C
	.byte $1A	; Instrument 13
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8E	; Note 72 (-1*2) C-6 - Vera 057C
	.byte $1A	; Instrument 13
	.byte $06	; PitchShiftUp
	.word $0001	;
	.byte $00	; steps to next voice
	.byte $88	; Note 69 (-1*2) A-5 - Vera 049D
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $04	; first voice is 4
	.byte $00	; Note 1 (-1*2) --- - Vera 0000
	.byte $02	; Silence
	.word $0004	;
	.byte $00	; steps to next voice
	.byte $00	; Note 1 (-1*2) --- - Vera 0000
	.byte $02	; Silence
	.word $0004	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $01	; first voice is 1
	.byte $6E	; Note 56 (-1*2) G#4 - Vera 022D
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $56	; Note 44 (-1*2) G#3 - Vera 0116
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DA	; Note 110 (-1*2) D-9 - Vera 3144
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8E	; Note 72 (-1*2) C-6 - Vera 057C
	.byte $1A	; Instrument 13
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8E	; Note 72 (-1*2) C-6 - Vera 057C
	.byte $1A	; Instrument 13
	.byte $06	; PitchShiftUp
	.word $0001	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $04	; first voice is 4
	.byte $00	; Note 1 (-1*2) --- - Vera 0000
	.byte $02	; Silence
	.word $0004	;
	.byte $00	; steps to next voice
	.byte $00	; Note 1 (-1*2) --- - Vera 0000
	.byte $02	; Silence
	.word $0004	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $01	; first voice is 1
	.byte $6E	; Note 56 (-1*2) G#4 - Vera 022D
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $56	; Note 44 (-1*2) G#3 - Vera 0116
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DA	; Note 110 (-1*2) D-9 - Vera 3144
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8E	; Note 72 (-1*2) C-6 - Vera 057C
	.byte $1A	; Instrument 13
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8E	; Note 72 (-1*2) C-6 - Vera 057C
	.byte $1A	; Instrument 13
	.byte $06	; PitchShiftUp
	.word $0001	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $04	; first voice is 4
	.byte $00	; Note 1 (-1*2) --- - Vera 0000
	.byte $02	; Silence
	.word $0004	;
	.byte $00	; steps to next voice
	.byte $00	; Note 1 (-1*2) --- - Vera 0000
	.byte $02	; Silence
	.word $0004	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $01	; first voice is 1
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $DA	; Note 110 (-1*2) D-9 - Vera 3144
	.byte $16	; Instrument 11
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8E	; Note 72 (-1*2) C-6 - Vera 057C
	.byte $1A	; Instrument 13
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8E	; Note 72 (-1*2) C-6 - Vera 057C
	.byte $1A	; Instrument 13
	.byte $06	; PitchShiftUp
	.word $0001	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $6E	; Note 56 (-1*2) G#4 - Vera 022D
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $56	; Note 44 (-1*2) G#3 - Vera 0116
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DA	; Note 110 (-1*2) D-9 - Vera 3144
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $1A	; Instrument 13
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $1A	; Instrument 13
	.byte $06	; PitchShiftUp
	.word $0001	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $DA	; Note 110 (-1*2) D-9 - Vera 3144
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $1A	; Instrument 13
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $86	; Note 68 (-1*2) G#5 - Vera 045A
	.byte $1A	; Instrument 13
	.byte $06	; PitchShiftUp
	.word $0001	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $DA	; Note 110 (-1*2) D-9 - Vera 3144
	.byte $18	; Instrument 12
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $1A	; Instrument 13
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $1A	; Instrument 13
	.byte $06	; PitchShiftUp
	.word $0001	;
	.byte $00	; steps to next voice
	.byte $88	; Note 69 (-1*2) A-5 - Vera 049D
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $4C	; Note 39 (-1*2) D#3 - Vera 00D0
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $DA	; Note 110 (-1*2) D-9 - Vera 3144
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $64	; Note 51 (-1*2) D#4 - Vera 01A1
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $DA	; Note 110 (-1*2) D-9 - Vera 3144
	.byte $18	; Instrument 12
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $04	; first voice is 4
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $1A	; Instrument 13
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $82	; Note 66 (-1*2) F#5 - Vera 03E1
	.byte $1A	; Instrument 13
	.byte $06	; PitchShiftUp
	.word $0001	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $01	; first voice is 1
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $DA	; Note 110 (-1*2) D-9 - Vera 3144
	.byte $16	; Instrument 11
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $1A	; Instrument 13
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $1A	; Instrument 13
	.byte $06	; PitchShiftUp
	.word $0001	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $64	; Note 51 (-1*2) D#4 - Vera 01A1
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $DA	; Note 110 (-1*2) D-9 - Vera 3144
	.byte $18	; Instrument 12
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $1A	; Instrument 13
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $1A	; Instrument 13
	.byte $06	; PitchShiftUp
	.word $0001	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0A	; Instrument 5
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $DA	; Note 110 (-1*2) D-9 - Vera 3144
	.byte $16	; Instrument 11
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $94	; Note 75 (-1*2) D#6 - Vera 0686
	.byte $1A	; Instrument 13
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $94	; Note 75 (-1*2) D#6 - Vera 0686
	.byte $1A	; Instrument 13
	.byte $06	; PitchShiftUp
	.word $0001	;
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 562 bytes.
; -- total size: 4320 bytes.

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
	.byte $0B

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

player_slidelookup:
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
	.word $0000
	.word $0001
	.word $0001
	.word $0001
	.word $0001
	.word $0001
	.word $0001
	.word $0001
	.word $0001
	.word $0001
	.word $0001
	.word $0001
	.word $0002
	.word $0002
	.word $0002
	.word $0002
	.word $0002
	.word $0002
	.word $0002
	.word $0003
	.word $0003
	.word $0003
	.word $0003
	.word $0003
	.word $0004
	.word $0004
	.word $0004
	.word $0004
	.word $0005
	.word $0005
	.word $0005
	.word $0006
	.word $0006
	.word $0006
	.word $0007
	.word $0007
	.word $0008
	.word $0008
	.word $0009
	.word $0009
	.word $000A
	.word $000B
	.word $000B
	.word $000C
	.word $000D
	.word $000D
	.word $000E
	.word $000F
	.word $0010
	.word $0011
	.word $0012
	.word $0013
	.word $0014
	.word $0016
	.word $0017
	.word $0018
	.word $001A
	.word $001B
	.word $001D
	.word $001F
	.word $0021
	.word $0023
	.word $0025
	.word $0027
	.word $0029
	.word $002C
	.word $002E
	.word $0031
	.word $0034
	.word $0037
	.word $003B
	.word $003E
	.word $0042
	.word $0046
	.word $004A
	.word $004E
	.word $0053
	.word $0058
	.word $005D
	.word $0063
	.word $0069
	.word $006F
	.word $0076
	.word $007D
	.word $0084
	.word $008C
	.word $0094
	.word $009D
	.word $00A7
	.word $00B0
	.word $00BB
	.word $00C6
	.word $00D2
	.word $00DE
	.word $00EC
	.word $00FA
	.word $0109
	.word $0118
	.word $0129
	.word $013B
	.word $014E
	.word $0161
	.word $0176
	.word $018D
	.word $01A4
	.word $01BD
	.word $01D8
	.word $01F4

.endmacro



.endscope
