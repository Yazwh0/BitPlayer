.include "player.asm"

pFRAME_INDEX = $04
pLINE_INDEX = $05
pPATTERN_INDEX = $06
pNEXT_LINE_COUNTER = $07

pMOD_VH = $10
pMOD_VM = $11
pMOD_VL = $12

pINSTRUMENT_DATA_ZP = $a0 ; 2 * 16
pINSTRUMENT_POSITION = $c0  ; 2 * 16
pINSTRUMENT_COMMAND = $e0  ; 2 * 16
pINSTRUMENT_NUMBER = $80 ; 2 * 16
pPLAYER_SCRATCH = $20

.scope
Player_Variables pFRAME_INDEX, pLINE_INDEX, pPATTERN_INDEX, pNEXT_LINE_COUNTER, pMOD_VH, pMOD_VM, pMOD_VL, pINSTRUMENT_DATA_ZP, pINSTRUMENT_COMMAND, pINSTRUMENT_POSITION, pINSTRUMENT_NUMBER, pPLAYER_SCRATCH

.proc player_init
Player_Initialise $01, $00, $00 ; where in vram the pattern data is
.endproc

.proc player_vsync 
Player_Vsync $01, $00, $00 ; where in vram the pattern data is
.endproc

;.segment DATA
Player_Data

.segment "DATA256"
Player_NoteLookup

.export player_init
.export player_vsync
.endscope