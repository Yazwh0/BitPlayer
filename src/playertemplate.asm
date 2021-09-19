
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
; Needs 2 * ###PatternWidth bytes. 
; .word instrument address
INSTRUMENT_START = instrumentDataZP
INSTRUMENT_ADDR = instrumentDataZP

; Needs 2 * ###PatternWidth bytes. 
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

    ldx #(2 * ###PatternWidth)
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
    copytovram vh, vm, vl, ###PatternSize, pattern_data

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
    .if ###HasCommands = 1

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

.repeat ###PatternWidth, I
Play_Instrument I
.endrepeat

; if there are less than 8 tracks, double up for better volume.
.if ###PatternWidth <= 8

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

    ldx ####PatternWidth + 1
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
###PatternJumpTable
    stp ; should never reach here

restart:
    lda ####PlayListLength ; playlist length
    sta PATTERN_INDEX

    tax
    dex
    jmp play_next_pattern

command_jump_table:
###CommandJumpTable

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

.proc command_pitchshiftdown
    ; number of shifts
    ldx INSTRUMENT_COMMAND_PARAM0, y

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
.endproc

.proc command_frequencyslideup
    ; number of shifts
    ldx INSTRUMENT_COMMAND_PARAM1, y
    beq slide_done

slide_done:
    rts
.endproc

.proc command_frequencyslidedown
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
###PatternInit
###InstrumentSwitch
###InstrumentLength
###Instruments
###Patterns
###PatternPlayList
.endmacro

.macro Player_NoteLookup
player_notelookup:
###NoteNumLookup
player_slidelookup:
###NoteSlideLookup
.endmacro



.endscope
