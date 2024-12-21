;
; codybros.asm
; A scrolling game demo inspired by Super Mario Bros and Great Giana Sisters.
;
; Copyright 2024 Frederick John Milens III, The Cody Computer Developers.
;
; This program is free software; you can redistribute it and/or
; modify it under the terms of the GNU General Public License
; as published by the Free Software Foundation; either version 3
; of the License, or (at your option) any later version.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License
; along with this program; if not, write to the Free Software
; Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
;
; This is not a full game, but it showcases many of the Cody Computer's game
; features. A Pomeranian (in sprite form) can smoothly walk back and forth in
; a game world when the joystick is moved left or right. When the joystick is
; moved up, the Pomeranian barks. When the joystick is moved down, the Pomeranian
; changes outfits. The fire button exits the demo.
;
; To assemble using 64TASS run the following:
;
;   64tass --mw65c02 --nostart -o codybros.bin codybros.asm
;
ADDR      = $0300               ; The actual loading address of the program

SCRRAM1   = $A000               ; Screen memory locations for double-buffering
SCRRAM2   = $A400

COLRAM1   = $A800               ; Color memory locations for double-buffering
COLRAM2   = $AC00

SPRITES   = $B000               ; Sprite memory locations

VIA_BASE  = $9F00               ; VIA base address and register locations
VIA_IORB  = VIA_BASE+$0
VIA_IORA  = VIA_BASE+$1
VIA_DDRB  = VIA_BASE+$2
VIA_DDRA  = VIA_BASE+$3
VIA_T1CL  = VIA_BASE+$4
VIA_T1CH  = VIA_BASE+$5
VIA_SR    = VIA_BASE+$A
VIA_ACR   = VIA_BASE+$B
VIA_PCR   = VIA_BASE+$C
VIA_IFR   = VIA_BASE+$D
VIA_IER   = VIA_BASE+$E

VID_BLNK  = $D000               ; Video blanking status register
VID_CNTL  = $D001               ; Video control register
VID_COLR  = $D002               ; Video color register
VID_BPTR  = $D003               ; Video base pointer register
VID_SCRL  = $D004               ; Video scroll register
VID_SCRC  = $D005               ; Video screen common colors register
VID_SPRC  = $D006               ; Video sprite control register

SPR0_X    = $D080               ; Sprite X coordinate
SPR0_Y    = $D081               ; Sprite Y coordinate
SPR0_COL  = $D082               ; Sprite color
SPR0_PTR  = $D083               ; Sprite base pointer

SID_BASE  = $D400               ; SID registers (mostly for voice 1)
SID_V1FL  = SID_BASE+0
SID_V1FH  = SID_BASE+1
SID_V1PL  = SID_BASE+2
SID_V1PH  = SID_BASE+3
SID_V1CT  = SID_BASE+4
SID_V1AD  = SID_BASE+5
SID_V1SR  = SID_BASE+6
SID_FVOL  = SID_BASE+24

PLAYERX   = $D0                 ; Player coordinates
PLAYERY   = $D1

CORNERX   = $D2                 ; Screen top-left corner coordinates
CORNERY   = $D3

MAPPTR    = $D4                 ; Memory pointers for drawing the screen
SCRPTR    = $D6
COLPTR    = $D8

BUFFLAG   = $DA                 ; Flag indicating what buffer is being used
FWDREV    = $DB                 ; Flag indicating player direction (forward or reverse)

TEMP      = $DC                 ; Temporary variable

; Program header for Cody Basic's loader (needs to be first)

.WORD ADDR                      ; Starting address (just like KIM-1, Commodore, etc.)
.WORD (ADDR + LAST - MAIN - 1)  ; Ending address (so we know when we're done loading)

; The actual program goes below here

.LOGICAL    ADDR                ; The actual program gets loaded at ADDR

;
; MAIN
;
; The starting point of the demo. Performs the necessary setup before the demo runs.
;
MAIN        STZ PLAYERX         ; Reset player position
            LDA #183
            STA PLAYERY

            STZ FWDREV          ; Player moving forward by default
            
            STZ BUFFLAG         ; Clear double buffer flag
            
            LDA #$07            ; Set VIA data direction register A to 00000111 (pins 0-2 outputs, pins 3-7 inputs)     
            STA VIA_DDRA

            LDA #$06            ; Set VIA to read joystick 1
            STA VIA_IORA

            LDA #$01            ; Sprite bank 0, white as common color
            STA VID_SPRC
            
            LDA VID_COLR        ; Set border color to black
            AND #$F0
            STA VID_COLR

            LDA #$E0            ; Store shared colors (light blue and black)
            STA VID_SCRC
  
            LDA #$04            ; Enable horizontal scrolling
            STA VID_CNTL

            LDX #0              ; Copy game map tiles into character memory
_COPYCHAR   LDA CHARDATA,X
            STA $C800,X
            INX
            CPX #80
            BNE _COPYCHAR

            LDX #0              ; Copy sprite data into video memory
_COPYSPRT   LDA SPRITEDATA,X
            STA SPRITES,X
            INX
            CPX #255
            BNE _COPYSPRT
            
            LDA #$D8            ; Initial sprite color
            STA SPR0_COL

;
; LOOP
;
; Main loop of the CODYBROS demo. Control drops through here after setup
; and jumps back here at the end of every game loop.
;
LOOP        LDA PLAYERX         ; Calculate coarse scroll position
            LSR A
            LSR A
            
            CMP #21
            BCC _TOOLO
            
            CMP #46
            BCS _TOOHI
            
            SEC
            SBC #21
            STA CORNERX
            
            BRA _DRAW
            
_TOOLO      STZ CORNERX
            BRA _DRAW
            
_TOOHI      LDA #25
            STA CORNERX
            BRA _DRAW
            
_DRAW       JSR DRAWSCRN        ; Draw the screen and sprite
            JSR DRAWSPRT
            
            LDA VIA_IORA        ; Read joystick
            LSR A
            LSR A
            LSR A
            
            BIT #16             ; Fire button?
            BEQ _FIRE
            
            BIT #8              ; Joystick right?
            BEQ _RIGHT
            
            BIT #4              ; Joystick left?
            BEQ _LEFT

            BIT #2              ; Joystick down to swap colors?
            BEQ SWAPCOLOR
            
            BIT #1              ; Joystick up to bark?
            BEQ BARK
            
            BRA LOOP
            
_FIRE       RTS                 ; Exit on fire button

_LEFT       LDA #1              ; Move left
            STA FWDREV
            
            LDA PLAYERX
            BEQ _NEXT
            
            DEC PLAYERX
            BRA _NEXT
            
_RIGHT      STZ FWDREV          ; Move right

            LDA PLAYERX
            CMP #232
            BEQ _NEXT
            
            INC PLAYERX
            
_NEXT       JMP LOOP

;
; BARK
;
; Handles a barking sound/animation for the sprite, then jumps back to the
; main loop.
;
BARK        LDA #$0F            ; Set main volume
            STA SID_FVOL
            
            LDA #<2400          ; Set starting frequency
            STA SID_V1FL
            LDA #>2400
            STA SID_V1FH
            
            LDA #$50            ; Attack/decay
            STA SID_V1AD
            
            LDA #$F0            ; Sustain/release
            STA SID_V1SR

            LDA #$21            ; Begin playing
            STA SID_V1CT
            
            LDX #0              ; Loop counter

_WOOF       JSR WAITBLANK       ; Wait for the next frame

            DEC SPR0_Y          ; Decrement sprite Y for dog hop
            
            CLC                 ; Increment frequency for next loop
            LDA SID_V1FL
            ADC #100
            STA SID_V1FL
            
            LDA SID_V1FH
            ADC #0
            STA SID_V1FH
            
            INX                 ; Increment for next loop
            CPX #10
            BNE _WOOF
            
            LDA #0              ; Stop playing
            STA SID_V1CT
            
            LDA PLAYERY         ; Move sprite back to original y
            STA SPR0_Y
            
            JMP LOOP

;
; SWAPCOLOR
;
; Swaps the sprite color (red/green or green/red) and jumps back to the main
; loop.
;
SWAPCOLOR   LDA SPR0_COL        ; Check current sprite colors
            CMP #$D8
            BEQ _RED
            
_GRN        LDA #$D8            ; Make sprite wear green
            STA SPR0_COL 
            BRA _WAITJOY
            
_RED        LDA #$28            ; Make sprite wear red
            STA SPR0_COL 
            BRA _WAITJOY

_WAITJOY    LDA VIA_IORA        ; Read joystick
            LSR A
            LSR A
            LSR A
            
            BIT #2              ; Wait for joystick release
            BEQ _WAITJOY
            
            JMP LOOP            ; All done

;
; DRAWSCRN
;
; Draws the current visible of the screen. This routine uses double-buffering
; so that the new screen and colors are drawn to a different location, and the
; screens/colors are switched out during the vertical blanking interval.
;
; In a real application the screen may need to be drawn (offscreen) in sections
; to keep up with a high game frame rate. For an example this works well enough
; to avoid glitches or tearing during scrolling.
;
DRAWSCRN    LDA #<MAPDATA       ; Start map pointer at beginning of map
            STA MAPPTR+0
            LDA #>MAPDATA
            STA MAPPTR+1  

            CLC                 ; Adjust map position based on player position
            LDA MAPPTR+0
            ADC CORNERX
            STA MAPPTR+0
            LDA MAPPTR+1
            ADC #0
            STA MAPPTR+1
            
            LDA BUFFLAG         ; Determine what buffer to draw to
            TAX
            
            LDA SCRRAMS_L,X     ; Start screen pointer at beginning of buffer
            STA SCRPTR+0
            LDA SCRRAMS_H,X
            STA SCRPTR+1
            
            LDA COLRAMS_L,X     ; Start color pointer at beginning of buffer
            STA COLPTR+0
            LDA COLRAMS_H,X
            STA COLPTR+1
            
            LDX #25             ; For now, try drawing everything
            JSR COPYROWS
            
            JSR WAITBLANK       ; Wait for the blanking interval to make changes

            LDA BUFFLAG         ; Determine what buffer to flip to
            TAX
            
            LDA BASEREGS,X      ; Update base register for screen memory
            STA VID_BPTR
            
            LDA COLREGS,X       ; Update color register for color memory
            STA VID_COLR
            
            LDA BUFFLAG         ; Toggle buffer flag
            EOR #$01
            STA BUFFLAG
            
            LDA PLAYERX         ; Update fine scroll position if needed
            
            CMP #(4*21)
            BCC _DONE
            
            CMP #(4*46)
            BCS _DONE
            
            AND #$03
            ASL A
            ASL A
            ASL A
            ASL A
            STA VID_SCRL
            
_DONE       RTS                 ; All done

;
; COPYROWS
;
; Copies a number of rows from the game map into the screen and color memory. The
; number of rows to copy is stored in the X register.
;  
COPYROWS    

_XLOOP      PHX
            LDY #0
            
_YLOOP      LDA (MAPPTR),Y      ; Copy the character (game tile) into screen memory 
            STA (SCRPTR),Y
            
            TAX                 ; Copy the color into color memory
            LDA COLORDATA,X
            STA (COLPTR),Y
            
            INY                 ; Next loop for Y
            CPY #40
            BNE _YLOOP
            
            CLC                 ; Increment map pointer to next row
            LDA MAPPTR+0
            ADC #64
            STA MAPPTR+0
            LDA MAPPTR+1
            ADC #0
            STA MAPPTR+1
            
            CLC                 ; Increment screen pointer to next row
            LDA SCRPTR+0
            ADC #40
            STA SCRPTR+0
            LDA SCRPTR+1
            ADC #0
            STA SCRPTR+1
            
            CLC                 ; Increment color pointer to next row
            LDA COLPTR+0
            ADC #40
            STA COLPTR+0
            LDA COLPTR+1
            ADC #0
            STA COLPTR+1
            
            PLX                 ; Next loop for X
            DEX
            BNE _XLOOP
            
            RTS                 ; All done

;
; DRAWSPRT
;
; Draws the sprite in the correct location for this frame. Note that the sprite
; isn't "drawn" so much as its registers updated so that it appears correctly.
; This should be called after drawing the screen because we want to sneak in 
; during the vertical blank.
;
DRAWSPRT    LDA PLAYERX         ; Calculate new sprite location
            CMP #(21*4)
            BCC _LO
            
            CMP #(46*4)
            BCS _HI
            
            LDA #(21*4)
            BRA _SPRX
            
_LO         BRA _SPRX

_HI         SEC
            SBC #((46*4)-84)
            BRA _SPRX

_SPRX       ADC #12             ; Update sprite X
            STA SPR0_X
            
            LDA PLAYERY         ; Update sprite Y
            STA SPR0_Y
            
            LDA FWDREV          ; Update sprite base pointer (different frames)
            ASL A
            STA TEMP
            CLC
            LDA PLAYERX
            AND #$02
            LSR A
            ADC TEMP
            ADC #(4096/64)
            STA SPR0_PTR
            
            RTS

;
; WAITBLANK
;
; Waits for the vertical blank signal to transition from drawing to not drawing, then
; returns. Used to sync up screen/register updates so they don't occur in the middle
; of the screen.
;
WAITBLANK

_WAITVIS    LDA VID_BLNK        ; Wait until the blanking is zero (drawing the screen)
            BNE _WAITVIS
            
_WAITBLANK  LDA VID_BLNK        ; Wait until the blanking is one (not drawing the screen)
            BEQ _WAITBLANK
            
            RTS

;
; The game map.
;
; 0 = Sky
; 1 = Brick
; 2 = Cloud left
; 3 = Cloud middle
; 4 = Cloud right
; 5 = Hills left
; 6 = Hills middle
; 7 = Hills right
; 8 = ?
; 9 = ?
;
MAPDATA

  .BYTE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,3,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
  .BYTE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,3,3,3,3,3,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
  .BYTE 0,0,0,2,3,3,4,0,0,0,0,0,0,0,0,0,0,0,2,3,3,3,3,3,4,0,0,0,0,0,2,3,3,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,3,3,4,0,0,0,0,0,0,0,0
  .BYTE 0,0,2,3,3,3,3,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
  .BYTE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,3,3,3,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
  .BYTE 0,0,0,0,0,0,0,0,0,0,0,0,0,2,3,3,3,3,3,4,0,0,0,0,0,0,0,0,0,0,0,2,3,4,0,0,0,0,2,3,3,3,3,3,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
  .BYTE 0,0,0,0,0,0,0,0,0,0,0,0,2,3,3,3,3,3,3,3,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,3,3,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
  .BYTE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,3,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,3,4,0,0,0,0,0,0
  .BYTE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
  .BYTE 0,0,0,2,3,3,4,0,0,0,0,0,0,0,0,0,0,0,2,3,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,3,4,0,0,0,0
  .BYTE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,0,0,1,1,0,0,0,0,0,0,0,0,2,3,3,3,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0
  .BYTE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,3,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
  .BYTE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
  .BYTE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
  .BYTE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0
  .BYTE 0,0,0,0,0,0,0,1,1,1,1,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,5
  .BYTE 0,0,0,0,0,0,0,1,1,1,1,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0,5,6,7,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,5,6
  .BYTE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,5,6,6,6,7,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,5,7,0,0,5,6,6
  .BYTE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,5,6,6,6,6,6,7,0,0,0,0,0,0,0,0,0,0,0,0,5,7,0,0,0,0,0,0,0,0,0,0,0,5,6,6,7,5,6,6,6
  .BYTE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,5,6,7,0,0,5,6,6,6,6,6,6,6,7,0,0,0,0,0,0,0,0,0,0,5,6,6,7,0,0,0,0,0,0,0,0,0,5,6,6,6,6,6,6,6,6
  .BYTE 0,0,0,0,0,5,7,0,0,0,0,0,0,0,0,0,0,5,6,6,6,7,5,6,6,6,6,6,6,6,6,6,7,0,0,0,0,0,0,0,0,5,6,6,6,6,7,0,0,0,0,0,0,0,5,6,6,6,6,6,6,6,6,6
  .BYTE 0,0,0,0,5,6,6,7,0,0,0,0,0,0,0,0,5,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,7,0,0,0,0,0,0,5,6,6,6,6,6,6,7,0,0,0,0,0,5,6,6,6,6,6,6,6,6,1,1
  .BYTE 0,0,0,5,6,6,6,6,7,0,0,0,0,0,0,5,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,7,0,0,0,0,5,6,6,6,6,6,6,6,6,7,0,0,0,5,6,6,6,6,6,6,6,6,6,1,1
  .BYTE 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
  .BYTE 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1

;
; The game's character tiles (used to draw the map).
;
CHARDATA

  .BYTE %11111111   ; Sky
  .BYTE %11111111
  .BYTE %11111111
  .BYTE %11111111
  .BYTE %11111111
  .BYTE %11111111
  .BYTE %11111111
  .BYTE %11111111

  .BYTE %01010101   ; Brick
  .BYTE %01000000
  .BYTE %01000000
  .BYTE %01000000
  .BYTE %01010101
  .BYTE %00000001
  .BYTE %00000001
  .BYTE %00000001

  .BYTE %11111100   ; Cloud left
  .BYTE %11000000
  .BYTE %00000000
  .BYTE %00000000
  .BYTE %00000000
  .BYTE %00000000
  .BYTE %11000000
  .BYTE %11111100

  .BYTE %00000000   ; Cloud middle
  .BYTE %00000000
  .BYTE %00000000
  .BYTE %00000000
  .BYTE %00000000
  .BYTE %00000000
  .BYTE %00000000
  .BYTE %00000000

  .BYTE %00111111   ; Cloud right
  .BYTE %00000011
  .BYTE %00000000
  .BYTE %00000000
  .BYTE %00000000
  .BYTE %00000000
  .BYTE %00000011
  .BYTE %00111111

  .BYTE %11111100   ; Hills left
  .BYTE %11111100
  .BYTE %11110001
  .BYTE %11110000
  .BYTE %11000100
  .BYTE %11000000
  .BYTE %00010000
  .BYTE %00000001

  .BYTE %00000000   ; Hills middle
  .BYTE %00010000
  .BYTE %00000000
  .BYTE %01000000
  .BYTE %00000100
  .BYTE %00000000
  .BYTE %01000000
  .BYTE %00000001

  .BYTE %00111111   ; Hills right
  .BYTE %00111111
  .BYTE %00001111
  .BYTE %01001111
  .BYTE %00000011
  .BYTE %00010011
  .BYTE %00000000
  .BYTE %01000100

  .BYTE %00000000   ; Unused
  .BYTE %00000000
  .BYTE %00000000
  .BYTE %00000000
  .BYTE %00000000
  .BYTE %00000000
  .BYTE %00000000
  .BYTE %00000000

  .BYTE %00000000   ; Unused
  .BYTE %00000000
  .BYTE %00000000
  .BYTE %00000000
  .BYTE %00000000
  .BYTE %00000000
  .BYTE %00000000
  .BYTE %00000000

;
; The color date to copy for each tile type.
;
COLORDATA

  .BYTE   $00       ; Sky (no colors)
  .BYTE   $09       ; Brick (black and brown)
  .BYTE   $F1       ; Clouds (gray and white)
  .BYTE   $F1       ; Clouds (gray and white)
  .BYTE   $F1       ; Clouds (gray and white)
  .BYTE   $D5       ; Hills (light green and green)
  .BYTE   $D5       ; Hills (light green and green)
  .BYTE   $D5       ; Hills (light green and green)
  .BYTE   $00       ; Unused
  .BYTE   $00       ; Unused

;
; The sprite data for the Pomeranian sprite on the screen.
;
SPRITEDATA

  .BYTE %00000000,%00000001,%01000000   ; Pomeranian forward 0
  .BYTE %00010000,%00001101,%11110000
  .BYTE %00010000,%00001101,%01111111
  .BYTE %01010100,%00000101,%01010000
  .BYTE %01010100,%00110101,%01110000
  .BYTE %01010100,%10110101,%01010101
  .BYTE %01010100,%10111001,%01010111
  .BYTE %01010111,%10101110,%01010100
  .BYTE %01010111,%10101110,%01010000
  .BYTE %01010111,%10101110,%10100000
  .BYTE %00010110,%11101110,%10100000
  .BYTE %00011010,%11101110,%10100000
  .BYTE %00001010,%11101110,%10000000
  .BYTE %00001010,%10111010,%10000000
  .BYTE %00010110,%10111001,%01010000
  .BYTE %00010101,%01000001,%01010000
  .BYTE %01010101,%00000000,%01010000
  .BYTE %01010000,%00000000,%01010000
  .BYTE %01010000,%00000000,%01010000
  .BYTE %00010100,%00000000,%00010100
  .BYTE %00010100,%00000000,%00010100
  .BYTE %00000000

  .BYTE %00000000,%00000001,%01000000 ; Pomeranian forward 1
  .BYTE %00010000,%00001101,%11110000
  .BYTE %00010000,%00001101,%01111111
  .BYTE %01010100,%00000101,%01010000
  .BYTE %01010100,%00110101,%01110000
  .BYTE %01010100,%10110101,%01010101
  .BYTE %01010100,%10111001,%01010111
  .BYTE %01010111,%10101110,%01010100
  .BYTE %01010111,%10101110,%01010000
  .BYTE %01010111,%10101110,%10100000
  .BYTE %00010110,%11101110,%10100000
  .BYTE %00011010,%11101110,%10100000
  .BYTE %00001010,%11101110,%10000000
  .BYTE %00001010,%10111010,%10000000
  .BYTE %00000110,%10111001,%01000000
  .BYTE %00010101,%01000001,%01000000
  .BYTE %00010101,%00000101,%00000000
  .BYTE %00000101,%00000101,%00000000
  .BYTE %00010101,%00000101,%00000000
  .BYTE %01010100,%00000001,%01000000
  .BYTE %01010000,%00000001,%01000000
  .BYTE %00000000

  .BYTE %00000001,%01000000,%00000000   ; Pomeranian reverse 0
  .BYTE %00001111,%01110000,%00000100
  .BYTE %11111101,%01110000,%00000100
  .BYTE %00000101,%01010000,%00010101
  .BYTE %00001101,%01011100,%00010101
  .BYTE %01010101,%01011110,%00010101
  .BYTE %11010101,%01101110,%00010101
  .BYTE %00010101,%10111010,%11010101
  .BYTE %00000101,%10111010,%11010101
  .BYTE %00001010,%10111010,%11010101
  .BYTE %00001010,%10111011,%10010100
  .BYTE %00001010,%10111011,%10100100
  .BYTE %00000010,%10111011,%10100000
  .BYTE %00000010,%10101110,%10100000
  .BYTE %00000101,%01101110,%10010100
  .BYTE %00000101,%01000001,%01010100
  .BYTE %00000101,%00000000,%01010101
  .BYTE %00000101,%00000000,%00000101
  .BYTE %00000101,%00000000,%00000101
  .BYTE %00010100,%00000000,%00010100
  .BYTE %00010100,%00000000,%00010100
  .BYTE %00000000

  .BYTE %00000001,%01000000,%00000000   ; Pomeranian reverse 1
  .BYTE %00001111,%01110000,%00000100
  .BYTE %11111101,%01110000,%00000100
  .BYTE %00000101,%01010000,%00010101
  .BYTE %00001101,%01011100,%00010101
  .BYTE %01010101,%01011110,%00010101
  .BYTE %11010101,%01101110,%00010101
  .BYTE %00010101,%10111010,%11010101
  .BYTE %00000101,%10111010,%11010101
  .BYTE %00001010,%10111010,%11010101
  .BYTE %00001010,%10111011,%10010100
  .BYTE %00001010,%10111011,%10100100
  .BYTE %00000010,%10111011,%10100000
  .BYTE %00000010,%10101110,%10100000
  .BYTE %00000001,%01101110,%10010000
  .BYTE %00000001,%01000001,%01010100
  .BYTE %00000000,%01010000,%01010100
  .BYTE %00000000,%01010000,%01010000
  .BYTE %00000000,%01010000,%01010100
  .BYTE %00000001,%01000000,%00010101
  .BYTE %00000001,%01000000,%00000101
  .BYTE %00000000

;
; Lookup tables for screen and color memory locations. Used to quickly
; switch between the double buffer during an update.
;
SCRRAMS_L

  .BYTE <SCRRAM1
  .BYTE <SCRRAM2
  
SCRRAMS_H

  .BYTE >SCRRAM1
  .BYTE >SCRRAM2

COLRAMS_L

  .BYTE <COLRAM1
  .BYTE <COLRAM2
  
COLRAMS_H

  .BYTE >COLRAM1
  .BYTE >COLRAM2

BASEREGS

  .BYTE $05
  .BYTE $15

COLREGS

  .BYTE $20
  .BYTE $30
  
LAST                              ; End of the entire program

.ENDLOGICAL
