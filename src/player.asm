
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
.macro Player_Variables frameIndex, lineIndex, patternIndex, nextLineCounter, vhPos, vmPos, vlPos, instrumentDataZP, instrumentCommandData, instrumentPosition, instrumentNumber, playerScratch, commandVariables
; Memory locations for variables
FRAME_INDEX = frameIndex
LINE_INDEX = lineIndex
PATTERN_INDEX = patternIndex
NEXT_LINE_COUNTER = nextLineCounter

PATTERN_POS_H = vhPos
PATTERN_POS_M = vmPos
PATTERN_POS_L = vlPos

; instrument pointers
; Needs 2 * 4 bytes. 
; .word instrument address
INSTRUMENT_START = instrumentDataZP
INSTRUMENT_ADDR = instrumentDataZP

; Needs 2 * 4 bytes. 
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

COMMAND_VARIABLES0 = commandVariables
COMMAND_VARIABLES1 = COMMAND_VARIABLES0 + 1

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

    ldx #(2 * 4)
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
    copytovram vh, vm, vl, $1356, pattern_data

    rts
.endmacro

.macro Play_Instrument offset
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
    .local instrument_copy_loop

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

.repeat 4, I
Play_Instrument I
.endrepeat

; if there are less than 8 tracks, double up for better volume.
.if 4 <= 1

    lda #1
    sta CTRL

    ; PSG start
    lda #$11
    sta ADDRx_L
    lda #$f9
    sta ADDRx_M
    lda #$c0
    sta ADDRx_L

    stz CTRL

.if 4 <= 3
    ldx #4 * 4
.elseif 4 <= 4 
    ldx #4 * 3
.else
    ldx #4 
.endif

instrument_copy_loop:
    lda DATA1
    sta DATA0
    lda DATA1
    sta DATA0
    lda DATA1
    sta DATA0
    lda DATA1
    sta DATA0

    dex
    bne instrument_copy_loop

.endif

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

    ; add check for PCM

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

pattern_0_init:
	lda #(^(vh * $10000 + vm * $100 + vl + 0)) + $10
	sta PATTERN_POS_H
	lda #>(vh * $10000 + vm * $100 + vl + 0)
	sta PATTERN_POS_M
	lda #<(vh * $10000 + vm * $100 + vl + 0)
	sta PATTERN_POS_L
	lda #$01 ; first line is 1
	sta NEXT_LINE_COUNTER
	lda #$40 ; this pattern is 64 lines long
	sta LINE_INDEX
	lda #$05 ; tempo
	sta next_line+1 ; modify reset code
	sta FRAME_INDEX
	jmp play_next

pattern_1_init:
	lda #(^(vh * $10000 + vm * $100 + vl + 453)) + $10
	sta PATTERN_POS_H
	lda #>(vh * $10000 + vm * $100 + vl + 453)
	sta PATTERN_POS_M
	lda #<(vh * $10000 + vm * $100 + vl + 453)
	sta PATTERN_POS_L
	lda #$01 ; first line is 1
	sta NEXT_LINE_COUNTER
	lda #$40 ; this pattern is 64 lines long
	sta LINE_INDEX
	lda #$05 ; tempo
	sta next_line+1 ; modify reset code
	sta FRAME_INDEX
	jmp play_next

pattern_2_init:
	lda #(^(vh * $10000 + vm * $100 + vl + 898)) + $10
	sta PATTERN_POS_H
	lda #>(vh * $10000 + vm * $100 + vl + 898)
	sta PATTERN_POS_M
	lda #<(vh * $10000 + vm * $100 + vl + 898)
	sta PATTERN_POS_L
	lda #$01 ; first line is 1
	sta NEXT_LINE_COUNTER
	lda #$40 ; this pattern is 64 lines long
	sta LINE_INDEX
	lda #$05 ; tempo
	sta next_line+1 ; modify reset code
	sta FRAME_INDEX
	jmp play_next

pattern_3_init:
	lda #(^(vh * $10000 + vm * $100 + vl + 1382)) + $10
	sta PATTERN_POS_H
	lda #>(vh * $10000 + vm * $100 + vl + 1382)
	sta PATTERN_POS_M
	lda #<(vh * $10000 + vm * $100 + vl + 1382)
	sta PATTERN_POS_L
	lda #$01 ; first line is 1
	sta NEXT_LINE_COUNTER
	lda #$40 ; this pattern is 64 lines long
	sta LINE_INDEX
	lda #$05 ; tempo
	sta next_line+1 ; modify reset code
	sta FRAME_INDEX
	jmp play_next

pattern_4_init:
	lda #(^(vh * $10000 + vm * $100 + vl + 1858)) + $10
	sta PATTERN_POS_H
	lda #>(vh * $10000 + vm * $100 + vl + 1858)
	sta PATTERN_POS_M
	lda #<(vh * $10000 + vm * $100 + vl + 1858)
	sta PATTERN_POS_L
	lda #$01 ; first line is 1
	sta NEXT_LINE_COUNTER
	lda #$40 ; this pattern is 64 lines long
	sta LINE_INDEX
	lda #$05 ; tempo
	sta next_line+1 ; modify reset code
	sta FRAME_INDEX
	jmp play_next

pattern_5_init:
	lda #(^(vh * $10000 + vm * $100 + vl + 2426)) + $10
	sta PATTERN_POS_H
	lda #>(vh * $10000 + vm * $100 + vl + 2426)
	sta PATTERN_POS_M
	lda #<(vh * $10000 + vm * $100 + vl + 2426)
	sta PATTERN_POS_L
	lda #$01 ; first line is 1
	sta NEXT_LINE_COUNTER
	lda #$40 ; this pattern is 64 lines long
	sta LINE_INDEX
	lda #$05 ; tempo
	sta next_line+1 ; modify reset code
	sta FRAME_INDEX
	jmp play_next

pattern_6_init:
	lda #(^(vh * $10000 + vm * $100 + vl + 2970)) + $10
	sta PATTERN_POS_H
	lda #>(vh * $10000 + vm * $100 + vl + 2970)
	sta PATTERN_POS_M
	lda #<(vh * $10000 + vm * $100 + vl + 2970)
	sta PATTERN_POS_L
	lda #$01 ; first line is 1
	sta NEXT_LINE_COUNTER
	lda #$40 ; this pattern is 64 lines long
	sta LINE_INDEX
	lda #$05 ; tempo
	sta next_line+1 ; modify reset code
	sta FRAME_INDEX
	jmp play_next

pattern_7_init:
	lda #(^(vh * $10000 + vm * $100 + vl + 3494)) + $10
	sta PATTERN_POS_H
	lda #>(vh * $10000 + vm * $100 + vl + 3494)
	sta PATTERN_POS_M
	lda #<(vh * $10000 + vm * $100 + vl + 3494)
	sta PATTERN_POS_L
	lda #$01 ; first line is 1
	sta NEXT_LINE_COUNTER
	lda #$40 ; this pattern is 64 lines long
	sta LINE_INDEX
	lda #$05 ; tempo
	sta next_line+1 ; modify reset code
	sta FRAME_INDEX
	jmp play_next

pattern_8_init:
	lda #(^(vh * $10000 + vm * $100 + vl + 4222)) + $10
	sta PATTERN_POS_H
	lda #>(vh * $10000 + vm * $100 + vl + 4222)
	sta PATTERN_POS_M
	lda #<(vh * $10000 + vm * $100 + vl + 4222)
	sta PATTERN_POS_L
	lda #$01 ; first line is 1
	sta NEXT_LINE_COUNTER
	lda #$40 ; this pattern is 64 lines long
	sta LINE_INDEX
	lda #$05 ; tempo
	sta next_line+1 ; modify reset code
	sta FRAME_INDEX
	jmp play_next

    stp ; should never reach here

restart:
    lda #$0B ; playlist length
    sta PATTERN_INDEX

    tax
    dex
    jmp play_next_pattern

command_jump_table:
	.word command_silence
	.word command_songevent
	.word command_frequencyslidedown
	.word command_pitchshiftdown
	.word command_setnote
	.word command_pitchshiftup


.proc command_songevent
    lda INSTRUMENT_COMMAND_PARAM1, y
    beq setflag

    stz INSTRUMENT_DATA_COMMAND, x
    rts

setflag:
    lda #$01
    sta INSTRUMENT_COMMAND_PARAM1, y
    rts
.endproc

.proc command_setnote
    ldx INSTRUMENT_COMMAND_PARAM0, y
    dex
    txa
    clc
    rol
    sta INSTRUMENT_NUMBER, y

    tay

    lda player_notelookup, y
    sta PLAYER_SCRATCH_FREQL
    lda player_notelookup+1, y
    sta PLAYER_SCRATCH_FREQH

    rts
.endproc

.proc command_pitchshiftup
   ; number of steps, 1-3.
    lda INSTRUMENT_COMMAND_PARAM0, y
    clc
    rol ; multiply by 2 for the jump table.
    tax

    ; y now has the instrument number.
    lda INSTRUMENT_NUMBER, y
    tay

    jmp (jumptable, x)
jumptable:
    .word normal
    .word low
    .word mid
    .word high

normal:
    lda player_notelookup, y
    sta PLAYER_SCRATCH_FREQL
    lda player_notelookup+1, y
    sta PLAYER_SCRATCH_FREQH
    rts
low:
    lda player_slide_low, y
    sta PLAYER_SCRATCH_FREQL
    lda player_slide_low+1, y
    sta PLAYER_SCRATCH_FREQH
    rts
mid:
    lda player_slide_mid, y
    sta PLAYER_SCRATCH_FREQL
    lda player_slide_mid+1, y
    sta PLAYER_SCRATCH_FREQH
    rts
high:
    lda player_slide_high, y
    sta PLAYER_SCRATCH_FREQL
    lda player_slide_high+1, y
    sta PLAYER_SCRATCH_FREQH
    rts
.endproc

.proc command_pitchshiftdown
    ; number of steps, 1-3.
    lda INSTRUMENT_COMMAND_PARAM0, y
    clc
    rol ; multiply by 2 for the jump table.
    tax

    ; y now has the instrument number.
    lda INSTRUMENT_NUMBER, y
    tay
    dey
    dey

    jmp (jumptable, x)
jumptable:
    .word normal
    .word high
    .word mid
    .word low

normal:
    lda player_notelookup, y
    sta PLAYER_SCRATCH_FREQL
    lda player_notelookup+1, y
    sta PLAYER_SCRATCH_FREQH
    rts
low:
    lda player_slide_low, y
    sta PLAYER_SCRATCH_FREQL
    lda player_slide_low+1, y
    sta PLAYER_SCRATCH_FREQH
    rts
mid:
    lda player_slide_mid, y
    sta PLAYER_SCRATCH_FREQL
    lda player_slide_mid+1, y
    sta PLAYER_SCRATCH_FREQH
    rts
high:
    lda player_slide_high, y
    sta PLAYER_SCRATCH_FREQL
    lda player_slide_high+1, y
    sta PLAYER_SCRATCH_FREQH
    rts
.endproc

.proc command_frequencyslideup
    ; number of shifts
    ldx INSTRUMENT_COMMAND_PARAM1, y
    beq slide_done
    dex 
    stx INSTRUMENT_COMMAND_PARAM1, y

    ; change in frequency
    clc
    lda PLAYER_SCRATCH_FREQL
    adc INSTRUMENT_COMMAND_PARAM0, y
    sta PLAYER_SCRATCH_FREQL

    lda PLAYER_SCRATCH_FREQH
    adc #$00
    sta PLAYER_SCRATCH_FREQH

    clc
    rts
slide_done:
    stx INSTRUMENT_DATA_COMMAND, y ; stop this being applied again
    rts
.endproc

.proc command_frequencyslidedown
    ; number of shifts
    ldx INSTRUMENT_COMMAND_PARAM1, y
    beq slide_done
    dex 
    stx INSTRUMENT_COMMAND_PARAM1, y

    ; change in frequency
    sec
    lda PLAYER_SCRATCH_FREQL
    sbc INSTRUMENT_COMMAND_PARAM0, y
    sta PLAYER_SCRATCH_FREQL

    lda PLAYER_SCRATCH_FREQH
    sbc #00
    sta PLAYER_SCRATCH_FREQH
    clc
    rts        
slide_done:
    stx INSTRUMENT_DATA_COMMAND, y
    rts
.endproc

.proc command_commandstop
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
    sec
    lda PLAYER_SCRATCH_FREQL
    sbc player_slidelookup, y
    sta PLAYER_SCRATCH_FREQL
    lda PLAYER_SCRATCH_FREQH
    sbc player_slidelookup+1, y
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
	.word instrument_14
	.word instrument_15
	.word instrument_16

instrument_length:
	.byte $0B, $00 ; 4 steps, -1 repeat
	.byte $05, $02 ; 2 steps, 1 repeat
	.byte $05, $02 ; 2 steps, 1 repeat
	.byte $05, $02 ; 2 steps, 1 repeat
	.byte $0E, $08 ; 5 steps, 2 repeat
	.byte $0E, $08 ; 5 steps, 2 repeat
	.byte $17, $02 ; 8 steps, 7 repeat
	.byte $0E, $08 ; 5 steps, 2 repeat
	.byte $08, $08 ; 3 steps, 0 repeat
	.byte $08, $08 ; 3 steps, 0 repeat
	.byte $08, $08 ; 3 steps, 0 repeat
	.byte $08, $00 ; 3 steps, -1 repeat
	.byte $08, $08 ; 3 steps, 0 repeat
	.byte $08, $00 ; 3 steps, -1 repeat
	.byte $11, $00 ; 6 steps, -1 repeat
	.byte $1A, $00 ; 9 steps, -1 repeat
	.byte $14, $00 ; 7 steps, -1 repeat

instrument_0:
	.byte $3F, $C0, $00; Width 63 + Wave Pulse, Volume 0, NoteAdj 0
	.byte $3F, $E8, $00; Width 63 + Wave Pulse, Volume 40, NoteAdj 0
	.byte $3F, $FF, $00; Width 20 + Wave Pulse, Volume 63, NoteAdj 0
	.byte $3F, $FF, $00; Width 30 + Wave Pulse, Volume 63, NoteAdj 0
instrument_1:
	.byte $3F, $F2, $00; Width 63 + Wave Pulse, Volume 50, NoteAdj 0
	.byte $3F, $F2, $00; Width 63 + Wave Pulse, Volume 50, NoteAdj 0
instrument_2:
	.byte $3F, $F2, $00; Width 31 + Wave Pulse, Volume 50, NoteAdj 0
	.byte $3F, $F2, $00; Width 31 + Wave Pulse, Volume 50, NoteAdj 0
instrument_3:
	.byte $3F, $F2, $00; Width 2 + Wave Pulse, Volume 50, NoteAdj 0
	.byte $3F, $F2, $00; Width 2 + Wave Pulse, Volume 50, NoteAdj 0
instrument_4:
	.byte $3F, $E8, $00; Width 63 + Wave Pulse, Volume 40, NoteAdj 0
	.byte $3F, $E8, $06; Width 63 + Wave Pulse, Volume 40, NoteAdj 3
	.byte $3F, $E8, $00; Width 63 + Wave Pulse, Volume 40, NoteAdj 0
	.byte $3F, $FF, $06; Width 20 + Wave Pulse, Volume 63, NoteAdj 3
	.byte $3F, $FF, $00; Width 30 + Wave Pulse, Volume 63, NoteAdj 0
instrument_5:
	.byte $3F, $E8, $00; Width 30 + Wave Pulse, Volume 40, NoteAdj 0
	.byte $3F, $E8, $0A; Width 35 + Wave Pulse, Volume 40, NoteAdj 5
	.byte $3F, $E8, $00; Width 40 + Wave Pulse, Volume 40, NoteAdj 0
	.byte $3F, $FF, $0A; Width 63 + Wave Pulse, Volume 63, NoteAdj 5
	.byte $3F, $FF, $00; Width 63 + Wave Pulse, Volume 63, NoteAdj 0
instrument_6:
	.byte $3F, $ED, $00; Width 63 + Wave Pulse, Volume 45, NoteAdj 0
	.byte $3F, $F0, $00; Width 63 + Wave Pulse, Volume 48, NoteAdj 0
	.byte $3F, $F3, $00; Width 63 + Wave Pulse, Volume 51, NoteAdj 0
	.byte $3F, $F6, $00; Width 63 + Wave Pulse, Volume 54, NoteAdj 0
	.byte $3F, $F9, $00; Width 63 + Wave Pulse, Volume 57, NoteAdj 0
	.byte $3F, $FC, $00; Width 63 + Wave Pulse, Volume 60, NoteAdj 0
	.byte $3F, $E6, $00; Width 63 + Wave Pulse, Volume 38, NoteAdj 0
	.byte $3F, $D0, $00; Width 63 + Wave Pulse, Volume 16, NoteAdj 0
instrument_7:
	.byte $3F, $E8, $00; Width 63 + Wave Pulse, Volume 40, NoteAdj 0
	.byte $3F, $E8, $08; Width 63 + Wave Pulse, Volume 40, NoteAdj 4
	.byte $3F, $E8, $00; Width 63 + Wave Pulse, Volume 40, NoteAdj 0
	.byte $3F, $FF, $08; Width 20 + Wave Pulse, Volume 63, NoteAdj 4
	.byte $3F, $FF, $00; Width 30 + Wave Pulse, Volume 63, NoteAdj 0
instrument_8:
	.byte $3F, $FA, $0E; Width 63 + Wave Pulse, Volume 58, NoteAdj 7
	.byte $3F, $FA, $06; Width 63 + Wave Pulse, Volume 58, NoteAdj 3
	.byte $3F, $FA, $00; Width 63 + Wave Pulse, Volume 58, NoteAdj 0
instrument_9:
	.byte $3F, $D4, $0E; Width 63 + Wave Pulse, Volume 20, NoteAdj 7
	.byte $3F, $D4, $06; Width 63 + Wave Pulse, Volume 20, NoteAdj 3
	.byte $3F, $D4, $00; Width 63 + Wave Pulse, Volume 20, NoteAdj 0
instrument_10:
	.byte $3F, $FA, $0A; Width 63 + Wave Pulse, Volume 58, NoteAdj 5
	.byte $3F, $FA, $06; Width 63 + Wave Pulse, Volume 58, NoteAdj 3
	.byte $3F, $FA, $00; Width 63 + Wave Pulse, Volume 58, NoteAdj 0
instrument_11:
	.byte $3F, $D4, $0A; Width 63 + Wave Pulse, Volume 20, NoteAdj 5
	.byte $3F, $D4, $06; Width 63 + Wave Pulse, Volume 20, NoteAdj 3
	.byte $3F, $D4, $00; Width 63 + Wave Pulse, Volume 20, NoteAdj 0
instrument_12:
	.byte $3F, $FA, $14; Width 63 + Wave Pulse, Volume 58, NoteAdj 10
	.byte $3F, $FA, $06; Width 63 + Wave Pulse, Volume 58, NoteAdj 3
	.byte $3F, $FA, $00; Width 63 + Wave Pulse, Volume 58, NoteAdj 0
instrument_13:
	.byte $3F, $D4, $14; Width 63 + Wave Pulse, Volume 20, NoteAdj 10
	.byte $3F, $D4, $06; Width 63 + Wave Pulse, Volume 20, NoteAdj 3
	.byte $3F, $D4, $00; Width 63 + Wave Pulse, Volume 20, NoteAdj 0
instrument_14:
	.byte $BF, $C0, $00; Width 63 + Wave Triangle, Volume 0, NoteAdj 0
	.byte $BF, $DE, $00; Width 63 + Wave Triangle, Volume 30, NoteAdj 0
	.byte $BF, $E6, $00; Width 63 + Wave Triangle, Volume 38, NoteAdj 0
	.byte $BF, $EE, $00; Width 63 + Wave Triangle, Volume 46, NoteAdj 0
	.byte $BF, $F6, $00; Width 63 + Wave Triangle, Volume 54, NoteAdj 0
	.byte $BF, $FF, $00; Width 63 + Wave Triangle, Volume 63, NoteAdj 0
instrument_15:
	.byte $FF, $C0, $00; Width 63 + Wave Noise, Volume 0, NoteAdj 0
	.byte $FF, $E8, $00; Width 63 + Wave Noise, Volume 40, NoteAdj 0
	.byte $FF, $E8, $00; Width 63 + Wave Noise, Volume 40, NoteAdj 0
	.byte $FF, $E8, $00; Width 63 + Wave Noise, Volume 40, NoteAdj 0
	.byte $FF, $E8, $00; Width 63 + Wave Noise, Volume 40, NoteAdj 0
	.byte $FF, $E8, $00; Width 63 + Wave Noise, Volume 40, NoteAdj 0
	.byte $FF, $EF, $06; Width 63 + Wave Noise, Volume 47, NoteAdj 3
	.byte $FF, $F7, $0C; Width 63 + Wave Noise, Volume 55, NoteAdj 6
	.byte $FF, $FF, $12; Width 63 + Wave Noise, Volume 63, NoteAdj 9
instrument_16:
	.byte $FF, $C0, $00; Width 63 + Wave Noise, Volume 0, NoteAdj 0
	.byte $FF, $D0, $00; Width 63 + Wave Noise, Volume 16, NoteAdj 0
	.byte $FF, $E1, $00; Width 63 + Wave Noise, Volume 33, NoteAdj 0
	.byte $FF, $F2, $00; Width 63 + Wave Noise, Volume 50, NoteAdj 0
	.byte $FF, $F2, $00; Width 63 + Wave Noise, Volume 50, NoteAdj 0
	.byte $FF, $F2, $00; Width 63 + Wave Noise, Volume 50, NoteAdj 0
	.byte $FF, $F2, $00; Width 63 + Wave Noise, Volume 50, NoteAdj 0

pattern_data:
pattern_0:

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $02	; Silence
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $54	; Note 43 (-1*2) G-3 - Vera 0107
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $4A	; Note 38 (-1*2) D-3 - Vera 00C5
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $08	; Instrument 4
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $50	; Note 41 (-1*2) F-3 - Vera 00EA
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $54	; Note 43 (-1*2) G-3 - Vera 0107
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $70	; Note 57 (-1*2) A-4 - Vera 024E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $54	; Note 43 (-1*2) G-3 - Vera 0107
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $50	; Note 41 (-1*2) F-3 - Vera 00EA
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $54	; Note 43 (-1*2) G-3 - Vera 0107
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $0A	; Instrument 5
	.byte $04	; SongEvent
	.word $0000	;
	.byte $01	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $4A	; Note 38 (-1*2) D-3 - Vera 00C5
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $08	; Instrument 4
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $50	; Note 41 (-1*2) F-3 - Vera 00EA
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $54	; Note 43 (-1*2) G-3 - Vera 0107
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $70	; Note 57 (-1*2) A-4 - Vera 024E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $5A	; Note 46 (-1*2) A#3 - Vera 0138
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $50	; Note 41 (-1*2) F-3 - Vera 00EA
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $54	; Note 43 (-1*2) G-3 - Vera 0107
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $4A	; Note 38 (-1*2) D-3 - Vera 00C5
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $08	; Instrument 4
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $50	; Note 41 (-1*2) F-3 - Vera 00EA
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $54	; Note 43 (-1*2) G-3 - Vera 0107
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $70	; Note 57 (-1*2) A-4 - Vera 024E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $54	; Note 43 (-1*2) G-3 - Vera 0107
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $50	; Note 41 (-1*2) F-3 - Vera 00EA
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $54	; Note 43 (-1*2) G-3 - Vera 0107
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $0A	; Instrument 5
	.byte $04	; SongEvent
	.word $0000	;
	.byte $01	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $4A	; Note 38 (-1*2) D-3 - Vera 00C5
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $08	; Instrument 4
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $50	; Note 41 (-1*2) F-3 - Vera 00EA
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $54	; Note 43 (-1*2) G-3 - Vera 0107
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $70	; Note 57 (-1*2) A-4 - Vera 024E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $5A	; Note 46 (-1*2) A#3 - Vera 0138
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $5C	; Note 47 (-1*2) B-3 - Vera 014B
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 453 bytes.
pattern_1:

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $02	; Silence
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $8E	; Note 72 (-1*2) C-6 - Vera 057C
	.byte $08	; Instrument 4
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $0A	; Instrument 5
	.byte $04	; SongEvent
	.word $0000	;
	.byte $01	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $8E	; Note 72 (-1*2) C-6 - Vera 057C
	.byte $08	; Instrument 4
	.byte $04	; SongEvent
	.word $0000	;
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $4C	; Note 39 (-1*2) D#3 - Vera 00D0
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $8E	; Note 72 (-1*2) C-6 - Vera 057C
	.byte $08	; Instrument 4
	.byte $04	; SongEvent
	.word $0000	;
	.byte $01	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $0A	; Instrument 5
	.byte $04	; SongEvent
	.word $0000	;
	.byte $01	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $8E	; Note 72 (-1*2) C-6 - Vera 057C
	.byte $08	; Instrument 4
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $4C	; Note 39 (-1*2) D#3 - Vera 00D0
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 445 bytes.
pattern_2:

	.byte $00	; first voice is 0
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $8E	; Note 72 (-1*2) C-6 - Vera 057C
	.byte $08	; Instrument 4
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $00	; first voice is 0
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $08	; Instrument 4
	.byte $04	; SongEvent
	.word $0000	;
	.byte $01	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8E	; Note 72 (-1*2) C-6 - Vera 057C
	.byte $0A	; Instrument 5
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $4C	; Note 39 (-1*2) D#3 - Vera 00D0
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $00	; first voice is 0
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $32	; Note 26 (-1*2) D-2 - Vera 0062
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $08	; Instrument 4
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $70	; Note 57 (-1*2) A-4 - Vera 024E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $08	; Instrument 4
	.byte $04	; SongEvent
	.word $0000	;
	.byte $01	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $32	; Note 26 (-1*2) D-2 - Vera 0062
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $0A	; Instrument 5
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $70	; Note 57 (-1*2) A-4 - Vera 024E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $44	; Note 35 (-1*2) B-2 - Vera 00A5
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 484 bytes.
pattern_3:

	.byte $00	; first voice is 0
	.byte $68	; Note 53 (-1*2) F-4 - Vera 01D4
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $00	; first voice is 0
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0E	; Instrument 7
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $3E	; Note 32 (-1*2) G#2 - Vera 008B
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3E	; Note 32 (-1*2) G#2 - Vera 008B
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $00	; first voice is 0
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $0A	; Instrument 5
	.byte $04	; SongEvent
	.word $0000	;
	.byte $01	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0E	; Instrument 7
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $3E	; Note 32 (-1*2) G#2 - Vera 008B
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3E	; Note 32 (-1*2) G#2 - Vera 008B
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $68	; Note 53 (-1*2) F-4 - Vera 01D4
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $70	; Note 57 (-1*2) A-4 - Vera 024E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $70	; Note 57 (-1*2) A-4 - Vera 024E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $2E	; Note 24 (-1*2) C-2 - Vera 0057
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $0E	; Instrument 7
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $34	; Note 27 (-1*2) D#2 - Vera 0068
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $68	; Note 53 (-1*2) F-4 - Vera 01D4
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $70	; Note 57 (-1*2) A-4 - Vera 024E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $34	; Note 27 (-1*2) D#2 - Vera 0068
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $68	; Note 53 (-1*2) F-4 - Vera 01D4
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $70	; Note 57 (-1*2) A-4 - Vera 024E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $0A	; Instrument 5
	.byte $04	; SongEvent
	.word $0000	;
	.byte $01	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $70	; Note 57 (-1*2) A-4 - Vera 024E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $2E	; Note 24 (-1*2) C-2 - Vera 0057
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $00	; first voice is 0
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $08	; Instrument 4
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $34	; Note 27 (-1*2) D#2 - Vera 0068
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $68	; Note 53 (-1*2) F-4 - Vera 01D4
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $70	; Note 57 (-1*2) A-4 - Vera 024E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $40	; Note 33 (-1*2) A-2 - Vera 0093
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 476 bytes.
pattern_4:

	.byte $00	; first voice is 0
	.byte $68	; Note 53 (-1*2) F-4 - Vera 01D4
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $00	; first voice is 0
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0E	; Instrument 7
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $3E	; Note 32 (-1*2) G#2 - Vera 008B
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3E	; Note 32 (-1*2) G#2 - Vera 008B
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $00	; first voice is 0
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $0A	; Instrument 5
	.byte $04	; SongEvent
	.word $0000	;
	.byte $01	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $8A	; Note 70 (-1*2) A#5 - Vera 04E3
	.byte $0E	; Instrument 7
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $3E	; Note 32 (-1*2) G#2 - Vera 008B
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3E	; Note 32 (-1*2) G#2 - Vera 008B
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $00	; first voice is 0
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $68	; Note 53 (-1*2) F-4 - Vera 01D4
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $70	; Note 57 (-1*2) A-4 - Vera 024E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $70	; Note 57 (-1*2) A-4 - Vera 024E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $2E	; Note 24 (-1*2) C-2 - Vera 0057
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $0E	; Instrument 7
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $34	; Note 27 (-1*2) D#2 - Vera 0068
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $68	; Note 53 (-1*2) F-4 - Vera 01D4
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $70	; Note 57 (-1*2) A-4 - Vera 024E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $34	; Note 27 (-1*2) D#2 - Vera 0068
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $08	; PitchShiftDown
	.word $0001	;
	.byte $00	; steps to next voice
	.byte $68	; Note 53 (-1*2) F-4 - Vera 01D4
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $08	; PitchShiftDown
	.word $0002	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $08	; PitchShiftDown
	.word $0003	;
	.byte $00	; steps to next voice
	.byte $6E	; Note 56 (-1*2) G#4 - Vera 022D
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $0A	; SetNote
	.word $003B	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $08	; PitchShiftDown
	.word $0001	;
	.byte $00	; steps to next voice
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $2E	; Note 24 (-1*2) C-2 - Vera 0057
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $08	; PitchShiftDown
	.word $0002	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $08	; PitchShiftDown
	.word $0003	;
	.byte $00	; steps to next voice
	.byte $6E	; Note 56 (-1*2) G#4 - Vera 022D
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $0A	; SetNote
	.word $003A	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $08	; PitchShiftDown
	.word $0001	;
	.byte $00	; steps to next voice
	.byte $80	; Note 65 (-1*2) F-5 - Vera 03A9
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $08	; PitchShiftDown
	.word $0002	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $08	; PitchShiftDown
	.word $0003	;
	.byte $00	; steps to next voice
	.byte $68	; Note 53 (-1*2) F-4 - Vera 01D4
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $2E	; Note 24 (-1*2) C-2 - Vera 0057
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $0A	; SetNote
	.word $0039	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $08	; PitchShiftDown
	.word $0001	;
	.byte $00	; steps to next voice
	.byte $6E	; Note 56 (-1*2) G#4 - Vera 022D
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $08	; PitchShiftDown
	.word $0002	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $08	; PitchShiftDown
	.word $0003	;
	.byte $00	; steps to next voice
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $0A	; SetNote
	.word $0038	;
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 568 bytes.
pattern_5:

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $08	; PitchShiftDown
	.word $0001	;
	.byte $00	; steps to next voice
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $08	; PitchShiftDown
	.word $0002	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $08	; PitchShiftDown
	.word $0003	;
	.byte $00	; steps to next voice
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $0A	; SetNote
	.word $0037	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $01	; first voice is 1
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $32	; Note 26 (-1*2) D-2 - Vera 0062
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $08	; Instrument 4
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $70	; Note 57 (-1*2) A-4 - Vera 024E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $0A	; Instrument 5
	.byte $04	; SongEvent
	.word $0000	;
	.byte $01	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $32	; Note 26 (-1*2) D-2 - Vera 0062
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $08	; Instrument 4
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $0C	; PitchShiftUp
	.word $0001	;
	.byte $00	; steps to next voice
	.byte $70	; Note 57 (-1*2) A-4 - Vera 024E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $0C	; PitchShiftUp
	.word $0002	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $0C	; PitchShiftUp
	.word $0003	;
	.byte $00	; steps to next voice
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $0A	; SetNote
	.word $0038	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $0C	; PitchShiftUp
	.word $0001	;
	.byte $00	; steps to next voice
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $0C	; PitchShiftUp
	.word $0002	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $0C	; PitchShiftUp
	.word $0003	;
	.byte $00	; steps to next voice
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $0A	; SetNote
	.word $0039	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $01	; first voice is 1
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $32	; Note 26 (-1*2) D-2 - Vera 0062
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $08	; Instrument 4
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $70	; Note 57 (-1*2) A-4 - Vera 024E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $0A	; Instrument 5
	.byte $04	; SongEvent
	.word $0000	;
	.byte $01	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $32	; Note 26 (-1*2) D-2 - Vera 0062
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $08	; Instrument 4
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $0C	; PitchShiftUp
	.word $0001	;
	.byte $00	; steps to next voice
	.byte $70	; Note 57 (-1*2) A-4 - Vera 024E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $0C	; PitchShiftUp
	.word $0002	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $0C	; PitchShiftUp
	.word $0003	;
	.byte $00	; steps to next voice
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $44	; Note 35 (-1*2) B-2 - Vera 00A5
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $0A	; SetNote
	.word $003A	;
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 544 bytes.
pattern_6:

	.byte $00	; first voice is 0
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $0C	; Instrument 6
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $32	; Note 26 (-1*2) D-2 - Vera 0062
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $08	; Instrument 4
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $70	; Note 57 (-1*2) A-4 - Vera 024E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $0A	; Instrument 5
	.byte $04	; SongEvent
	.word $0000	;
	.byte $01	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $32	; Note 26 (-1*2) D-2 - Vera 0062
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $08	; Instrument 4
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $0C	; PitchShiftUp
	.word $0001	;
	.byte $00	; steps to next voice
	.byte $70	; Note 57 (-1*2) A-4 - Vera 024E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $0C	; PitchShiftUp
	.word $0002	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $0C	; PitchShiftUp
	.word $0003	;
	.byte $00	; steps to next voice
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $0A	; SetNote
	.word $003B	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $0C	; PitchShiftUp
	.word $0001	;
	.byte $00	; steps to next voice
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $0C	; PitchShiftUp
	.word $0002	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $0C	; PitchShiftUp
	.word $0003	;
	.byte $00	; steps to next voice
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $0A	; SetNote
	.word $003C	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $01	; first voice is 1
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $32	; Note 26 (-1*2) D-2 - Vera 0062
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $08	; Instrument 4
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $70	; Note 57 (-1*2) A-4 - Vera 024E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $0A	; Instrument 5
	.byte $04	; SongEvent
	.word $0000	;
	.byte $01	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $32	; Note 26 (-1*2) D-2 - Vera 0062
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $08	; Instrument 4
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $0A	; SetNote
	.word $003B	;
	.byte $00	; steps to next voice
	.byte $70	; Note 57 (-1*2) A-4 - Vera 024E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $0A	; SetNote
	.word $003A	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $0A	; SetNote
	.word $0039	;
	.byte $00	; steps to next voice
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $44	; Note 35 (-1*2) B-2 - Vera 00A5
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $00	; no note
	.byte $0A	; SetNote
	.word $0038	;
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 524 bytes.
pattern_7:

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $8E	; Note 72 (-1*2) C-6 - Vera 057C
	.byte $08	; Instrument 4
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $16	; Instrument 11
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $0A	; Instrument 5
	.byte $04	; SongEvent
	.word $0000	;
	.byte $01	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $8E	; Note 72 (-1*2) C-6 - Vera 057C
	.byte $08	; Instrument 4
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $4C	; Note 39 (-1*2) D#3 - Vera 00D0
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $18	; Instrument 12
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $1A	; Instrument 13
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $16	; Instrument 11
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $8E	; Note 72 (-1*2) C-6 - Vera 057C
	.byte $08	; Instrument 4
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $16	; Instrument 11
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $16	; Instrument 11
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $08	; Instrument 4
	.byte $04	; SongEvent
	.word $0000	;
	.byte $01	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $8E	; Note 72 (-1*2) C-6 - Vera 057C
	.byte $0A	; Instrument 5
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $18	; Instrument 12
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $46	; Note 36 (-1*2) C-3 - Vera 00AF
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $1A	; Instrument 13
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $18	; Instrument 12
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $4C	; Note 39 (-1*2) D#3 - Vera 00D0
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $1A	; Instrument 13
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7C	; Note 63 (-1*2) D#5 - Vera 0343
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $76	; Note 60 (-1*2) C-5 - Vera 02BE
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 728 bytes.
pattern_8:

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $32	; Note 26 (-1*2) D-2 - Vera 0062
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $08	; Instrument 4
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $70	; Note 57 (-1*2) A-4 - Vera 024E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $16	; Instrument 11
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $0A	; Instrument 5
	.byte $04	; SongEvent
	.word $0000	;
	.byte $01	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $32	; Note 26 (-1*2) D-2 - Vera 0062
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $08	; Instrument 4
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $70	; Note 57 (-1*2) A-4 - Vera 024E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $18	; Instrument 12
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $1A	; Instrument 13
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $32	; Note 26 (-1*2) D-2 - Vera 0062
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $08	; Instrument 4
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $70	; Note 57 (-1*2) A-4 - Vera 024E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $C8	; Note 101 (-1*2) F-8 - Vera 1D4B
	.byte $1E	; Instrument 15
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $16	; Instrument 11
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $14	; Instrument 10
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $01	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $16	; Instrument 11
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $7A	; Note 62 (-1*2) D-5 - Vera 0314
	.byte $0A	; Instrument 5
	.byte $04	; SongEvent
	.word $0000	;
	.byte $01	; steps to next voice
	.byte $58	; Note 45 (-1*2) A-3 - Vera 0127
	.byte $1C	; Instrument 14
	.byte $06	; FrequencySlideDown
	.word $0504	;
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $10	; Instrument 8
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $32	; Note 26 (-1*2) D-2 - Vera 0062
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $02	; next line count

	.byte $01	; first voice is 1
	.byte $84	; Note 67 (-1*2) G-5 - Vera 041C
	.byte $08	; Instrument 4
	.byte $04	; SongEvent
	.word $0000	;
	.byte $00	; steps to next voice
	.byte $38	; Note 29 (-1*2) F-2 - Vera 0075
	.byte $02	; Instrument 1
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $18	; Instrument 12
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $3C	; Note 31 (-1*2) G-2 - Vera 0083
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $1A	; Instrument 13
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $18	; Instrument 12
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $70	; Note 57 (-1*2) A-4 - Vera 024E
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $42	; Note 34 (-1*2) A#2 - Vera 009C
	.byte $06	; Instrument 3
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $1A	; Instrument 13
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $72	; Note 58 (-1*2) A#4 - Vera 0271
	.byte $00	; Instrument 0
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $44	; Note 35 (-1*2) B-2 - Vera 00A5
	.byte $04	; Instrument 2
	.byte $00	; No command
	.byte $00	; steps to next voice
	.byte $E0	; Note 113 (-1*2) F-9 - Vera 3A97
	.byte $20	; Instrument 16
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $01	; next line count

	.byte $00	; first voice is 0
	.byte $6C	; Note 55 (-1*2) G-4 - Vera 020E
	.byte $12	; Instrument 9
	.byte $00	; No command
	.byte $ff	; no more for this line.
	.byte $ff	; pattern done.
; -- size: 728 bytes.
; -- total size: 4950 bytes.

pattern_playlist:
	.byte $08
	.byte $07
	.byte $06
	.byte $05
	.byte $04
	.byte $02
	.byte $03
	.byte $02
	.byte $00
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

player_slide_low:
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
	.word $004F
	.word $0054
	.word $0059
	.word $005E
	.word $0063
	.word $0069
	.word $0070
	.word $0076
	.word $007D
	.word $0085
	.word $008D
	.word $0095
	.word $009E
	.word $00A8
	.word $00B2
	.word $00BC
	.word $00C7
	.word $00D3
	.word $00E0
	.word $00ED
	.word $00FB
	.word $010A
	.word $011A
	.word $012B
	.word $013D
	.word $0150
	.word $0164
	.word $0179
	.word $018F
	.word $01A7
	.word $01C0
	.word $01DB
	.word $01F7
	.word $0215
	.word $0235
	.word $0257
	.word $027A
	.word $02A0
	.word $02C8
	.word $02F2
	.word $031F
	.word $034F
	.word $0381
	.word $03B7
	.word $03EF
	.word $042B
	.word $046B
	.word $04AE
	.word $04F5
	.word $0541
	.word $0591
	.word $05E5
	.word $063F
	.word $069E
	.word $0703
	.word $076E
	.word $07DF
	.word $0857
	.word $08D6
	.word $095C
	.word $09EB
	.word $0A82
	.word $0B22
	.word $0BCB
	.word $0C7F
	.word $0D3D
	.word $0E06
	.word $0EDC
	.word $0FBE
	.word $10AE
	.word $11AC
	.word $12B9
	.word $13D6
	.word $1504
	.word $1644
	.word $1797
	.word $18FE
	.word $1A7A
	.word $1C0D
	.word $1DB8
	.word $1F7D
	.word $215C
	.word $2358
	.word $2572
	.word $27AC
	.word $2A08
	.word $2C88
	.word $2F2E
	.word $31FC
	.word $34F5
	.word $381B
	.word $3B71
	.word $3EFA
	.word $42B8
	.word $46B0
	.word $4AE4
	.word $4F58
	.word $5410
	.word $5910
	.word $5E5C
	.word $63F8
	.word $69EA
	.word $7036
	.word $76E2
	.word $7DF4
	.word $8571
	.word $8D61

player_slide_mid:
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
	.word $0050
	.word $0055
	.word $005A
	.word $005F
	.word $0065
	.word $006B
	.word $0071
	.word $0078
	.word $007F
	.word $0087
	.word $008F
	.word $0097
	.word $00A1
	.word $00AA
	.word $00B4
	.word $00BF
	.word $00CA
	.word $00D6
	.word $00E3
	.word $00F1
	.word $00FF
	.word $010E
	.word $011E
	.word $012F
	.word $0142
	.word $0155
	.word $0169
	.word $017E
	.word $0195
	.word $01AD
	.word $01C7
	.word $01E2
	.word $01FF
	.word $021D
	.word $023D
	.word $025F
	.word $0284
	.word $02AA
	.word $02D2
	.word $02FD
	.word $032B
	.word $035B
	.word $038E
	.word $03C4
	.word $03FE
	.word $043B
	.word $047B
	.word $04BF
	.word $0508
	.word $0554
	.word $05A5
	.word $05FB
	.word $0656
	.word $06B7
	.word $071D
	.word $0789
	.word $07FC
	.word $0876
	.word $08F6
	.word $097F
	.word $0A10
	.word $0AA9
	.word $0B4B
	.word $0BF7
	.word $0CAD
	.word $0D6E
	.word $0E3B
	.word $0F13
	.word $0FF9
	.word $10EC
	.word $11ED
	.word $12FE
	.word $1420
	.word $1552
	.word $1696
	.word $17EE
	.word $195B
	.word $1ADD
	.word $1C76
	.word $1E27
	.word $1FF2
	.word $21D8
	.word $23DB
	.word $25FD
	.word $2840
	.word $2AA4
	.word $2D2D
	.word $2FDD
	.word $32B6
	.word $35BA
	.word $38EC
	.word $3C4E
	.word $3FE4
	.word $43B1
	.word $47B7
	.word $4BFB
	.word $5080
	.word $5549
	.word $5A5B
	.word $5FBB
	.word $656C
	.word $6B74
	.word $71D8
	.word $789D
	.word $7FC9
	.word $8762
	.word $8F6F

player_slide_high:
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
	.word $0051
	.word $0056
	.word $005B
	.word $0061
	.word $0066
	.word $006D
	.word $0073
	.word $007A
	.word $0081
	.word $0089
	.word $0091
	.word $009A
	.word $00A3
	.word $00AD
	.word $00B7
	.word $00C2
	.word $00CD
	.word $00DA
	.word $00E7
	.word $00F4
	.word $0103
	.word $0112
	.word $0123
	.word $0134
	.word $0146
	.word $015A
	.word $016E
	.word $0184
	.word $019B
	.word $01B4
	.word $01CE
	.word $01E9
	.word $0206
	.word $0225
	.word $0246
	.word $0268
	.word $028D
	.word $02B4
	.word $02DD
	.word $0308
	.word $0337
	.word $0368
	.word $039C
	.word $03D2
	.word $040D
	.word $044A
	.word $048C
	.word $04D1
	.word $051A
	.word $0568
	.word $05BA
	.word $0611
	.word $066E
	.word $06D0
	.word $0738
	.word $07A5
	.word $081A
	.word $0895
	.word $0918
	.word $09A2
	.word $0A35
	.word $0AD0
	.word $0B75
	.word $0C23
	.word $0CDC
	.word $0DA0
	.word $0E70
	.word $0F4B
	.word $1034
	.word $112B
	.word $1230
	.word $1345
	.word $146B
	.word $15A1
	.word $16EB
	.word $1847
	.word $19B9
	.word $1B41
	.word $1CE0
	.word $1E97
	.word $2069
	.word $2256
	.word $2461
	.word $268B
	.word $28D6
	.word $2B43
	.word $2DD6
	.word $308F
	.word $3373
	.word $3682
	.word $39C0
	.word $3D2F
	.word $40D2
	.word $44AD
	.word $48C2
	.word $4D16
	.word $51AC
	.word $5687
	.word $5BAC
	.word $611F
	.word $66E6
	.word $6D04
	.word $7380
	.word $7A5E
	.word $81A5
	.word $895A
	.word $9185

.endmacro



.endscope
