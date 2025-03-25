;
; codyhires.asm
; A bitmap demo displaying a high-resolution PETSCII Commodore 64 graphic.
;
; The image is from "The Game Is Apaw!" by iLKke. The C64 font is taken
; from the US C64 character ROM. Copyright on the image and ROM remain
; with the original owners of each.
;
; Copyright 2025 Frederick John Milens III, The Cody Computer Developers.
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
; To assemble using 64TASS run the following:
;
;   64tass --mw65c02 --nostart -o codyhires.bin codyhires.asm
;
ADDR      = $0300               ; The actual loading address of the program

SCRRAM    = $A000               ; Screen memory location
CHRRAM    = $C800               ; Character memory location
COLRAM    = $D800               ; Color memory location

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

; Variables

MEMSPTR   = $20       ; The source pointer for memory-related utility routines (2 bytes)
MEMDPTR   = $22       ; The destination pointer for memory-related utility routines (2 bytes)
MEMSIZE   = $24       ; The size of memory to move for memory-related utility routines (2 bytes)

; Program header for Cody Basic's loader (needs to be first)

.WORD ADDR                      ; Starting address (just like KIM-1, Commodore, etc.)
.WORD (ADDR + LAST - MAIN - 1)  ; Ending address (so we know when we're done loading)

; The actual program goes below here

.LOGICAL    ADDR                ; The actual program gets loaded at ADDR

;
; MAIN
;
; The starting point of the demo. Sets up the VID and copies all the data.
; Once the data is in place the high-resolution character mode is enabled.
;
MAIN        LDA #<FONT_DATA   ; Copy the C64 character ROM
            STA MEMSPTR

            LDA #>FONT_DATA
            STA MEMSPTR+1

            LDA #<CHRRAM
            STA MEMDPTR

            LDA #>CHRRAM
            STA MEMDPTR+1

            LDA #<2048
            STA MEMSIZE

            LDA #>2048
            STA MEMSIZE+1
            
            JSR MEMCOPYUP

            LDX #0
            
_LOOP       TXA
            STA SCRRAM,X
            
            LDA #$16
            STA COLRAM,X
            
            INX
            BNE _LOOP

            LDA #$E0            ; Point the video hardware to default color memory, border color black
            STA VID_COLR
  
            LDA #$05            ; Point the video hardware to the screen memory and default character set
            STA VID_BPTR

            LDA VID_CNTL        ; Set high resolution character graphics mode
            ORA #$20
            STA VID_CNTL
          
_DONE       BRA _DONE           ; Loop forever (TODO: For now...)
            
;
; MEMCOPYUP
;
; Copies a region of memory upward. This routine should be used if the destination address
; is higher in memory than the source address. Copies a total of MEMSIZE bytes from MEMSPTR 
; to MEMDPTR.
;
; Algorithm copied from http://www.6502.org/source/general/memory_move.html.
;
; Uses:
;
;   MEMSPTR       Source pointer (modified by operation)
;   MEMDPTR       Destination pointer (modified by operation)
;   MEMSIZE       Bytes to copy (modified by operation) 
;
MEMCOPYUP PHA
          PHX
          PHY

          LDX MEMSIZE+1     ; the last byte must be moved first
          CLC               ; start at the final pages of FROM and TO
          TXA
          ADC MEMSPTR+1
          STA MEMSPTR+1
          CLC
          TXA
          ADC MEMDPTR+1
          STA MEMDPTR+1
          INX               ; allows the use of BNE after the DEX below
          LDY MEMSIZE
          BEQ _NEXT
          DEY               ; move bytes on the last page first
          BEQ _ONCE

_LOOP     LDA (MEMSPTR),Y
          STA (MEMDPTR),Y
          DEY
          BNE _LOOP

_ONCE     LDA (MEMSPTR),Y   ; handle Y = 0 separately
          STA (MEMDPTR),Y
  
_NEXT     DEY
          DEC MEMSPTR+1     ; move the next page (if any)
          DEC MEMDPTR+1
          DEX
          BNE _LOOP

          PLY
          PLX
          PLA
        
          RTS

;
; C64 uppercase/PETSCII font taken from the US C64 character ROM. See
; https://www.zimmers.net/anonftp/pub/cbm/firmware/characters/ for the
; source. Copyright remains with the appropriate copyright holder(s).
;
FONT_DATA

  .BYTE $3c,$66,$6e,$6e,$60,$62,$3c,$00
  .BYTE $18,$3c,$66,$7e,$66,$66,$66,$00
  .BYTE $7c,$66,$66,$7c,$66,$66,$7c,$00
  .BYTE $3c,$66,$60,$60,$60,$66,$3c,$00
  .BYTE $78,$6c,$66,$66,$66,$6c,$78,$00
  .BYTE $7e,$60,$60,$78,$60,$60,$7e,$00
  .BYTE $7e,$60,$60,$78,$60,$60,$60,$00
  .BYTE $3c,$66,$60,$6e,$66,$66,$3c,$00
  .BYTE $66,$66,$66,$7e,$66,$66,$66,$00
  .BYTE $3c,$18,$18,$18,$18,$18,$3c,$00
  .BYTE $1e,$0c,$0c,$0c,$0c,$6c,$38,$00
  .BYTE $66,$6c,$78,$70,$78,$6c,$66,$00
  .BYTE $60,$60,$60,$60,$60,$60,$7e,$00
  .BYTE $63,$77,$7f,$6b,$63,$63,$63,$00
  .BYTE $66,$76,$7e,$7e,$6e,$66,$66,$00
  .BYTE $3c,$66,$66,$66,$66,$66,$3c,$00
  .BYTE $7c,$66,$66,$7c,$60,$60,$60,$00
  .BYTE $3c,$66,$66,$66,$66,$3c,$0e,$00
  .BYTE $7c,$66,$66,$7c,$78,$6c,$66,$00
  .BYTE $3c,$66,$60,$3c,$06,$66,$3c,$00
  .BYTE $7e,$18,$18,$18,$18,$18,$18,$00
  .BYTE $66,$66,$66,$66,$66,$66,$3c,$00
  .BYTE $66,$66,$66,$66,$66,$3c,$18,$00
  .BYTE $63,$63,$63,$6b,$7f,$77,$63,$00
  .BYTE $66,$66,$3c,$18,$3c,$66,$66,$00
  .BYTE $66,$66,$66,$3c,$18,$18,$18,$00
  .BYTE $7e,$06,$0c,$18,$30,$60,$7e,$00
  .BYTE $3c,$30,$30,$30,$30,$30,$3c,$00
  .BYTE $0c,$12,$30,$7c,$30,$62,$fc,$00
  .BYTE $3c,$0c,$0c,$0c,$0c,$0c,$3c,$00
  .BYTE $00,$18,$3c,$7e,$18,$18,$18,$18
  .BYTE $00,$10,$30,$7f,$7f,$30,$10,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $18,$18,$18,$18,$00,$00,$18,$00
  .BYTE $66,$66,$66,$00,$00,$00,$00,$00
  .BYTE $66,$66,$ff,$66,$ff,$66,$66,$00
  .BYTE $18,$3e,$60,$3c,$06,$7c,$18,$00
  .BYTE $62,$66,$0c,$18,$30,$66,$46,$00
  .BYTE $3c,$66,$3c,$38,$67,$66,$3f,$00
  .BYTE $06,$0c,$18,$00,$00,$00,$00,$00
  .BYTE $0c,$18,$30,$30,$30,$18,$0c,$00
  .BYTE $30,$18,$0c,$0c,$0c,$18,$30,$00
  .BYTE $00,$66,$3c,$ff,$3c,$66,$00,$00
  .BYTE $00,$18,$18,$7e,$18,$18,$00,$00
  .BYTE $00,$00,$00,$00,$00,$18,$18,$30
  .BYTE $00,$00,$00,$7e,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$18,$18,$00
  .BYTE $00,$03,$06,$0c,$18,$30,$60,$00
  .BYTE $3c,$66,$6e,$76,$66,$66,$3c,$00
  .BYTE $18,$18,$38,$18,$18,$18,$7e,$00
  .BYTE $3c,$66,$06,$0c,$30,$60,$7e,$00
  .BYTE $3c,$66,$06,$1c,$06,$66,$3c,$00
  .BYTE $06,$0e,$1e,$66,$7f,$06,$06,$00
  .BYTE $7e,$60,$7c,$06,$06,$66,$3c,$00
  .BYTE $3c,$66,$60,$7c,$66,$66,$3c,$00
  .BYTE $7e,$66,$0c,$18,$18,$18,$18,$00
  .BYTE $3c,$66,$66,$3c,$66,$66,$3c,$00
  .BYTE $3c,$66,$66,$3e,$06,$66,$3c,$00
  .BYTE $00,$00,$18,$00,$00,$18,$00,$00
  .BYTE $00,$00,$18,$00,$00,$18,$18,$30
  .BYTE $0e,$18,$30,$60,$30,$18,$0e,$00
  .BYTE $00,$00,$7e,$00,$7e,$00,$00,$00
  .BYTE $70,$18,$0c,$06,$0c,$18,$70,$00
  .BYTE $3c,$66,$06,$0c,$18,$00,$18,$00
  .BYTE $00,$00,$00,$ff,$ff,$00,$00,$00
  .BYTE $08,$1c,$3e,$7f,$7f,$1c,$3e,$00
  .BYTE $18,$18,$18,$18,$18,$18,$18,$18
  .BYTE $00,$00,$00,$ff,$ff,$00,$00,$00
  .BYTE $00,$00,$ff,$ff,$00,$00,$00,$00
  .BYTE $00,$ff,$ff,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$ff,$ff,$00,$00
  .BYTE $30,$30,$30,$30,$30,$30,$30,$30
  .BYTE $0c,$0c,$0c,$0c,$0c,$0c,$0c,$0c
  .BYTE $00,$00,$00,$e0,$f0,$38,$18,$18
  .BYTE $18,$18,$1c,$0f,$07,$00,$00,$00
  .BYTE $18,$18,$38,$f0,$e0,$00,$00,$00
  .BYTE $c0,$c0,$c0,$c0,$c0,$c0,$ff,$ff
  .BYTE $c0,$e0,$70,$38,$1c,$0e,$07,$03
  .BYTE $03,$07,$0e,$1c,$38,$70,$e0,$c0
  .BYTE $ff,$ff,$c0,$c0,$c0,$c0,$c0,$c0
  .BYTE $ff,$ff,$03,$03,$03,$03,$03,$03
  .BYTE $00,$3c,$7e,$7e,$7e,$7e,$3c,$00
  .BYTE $00,$00,$00,$00,$00,$ff,$ff,$00
  .BYTE $36,$7f,$7f,$7f,$3e,$1c,$08,$00
  .BYTE $60,$60,$60,$60,$60,$60,$60,$60
  .BYTE $00,$00,$00,$07,$0f,$1c,$18,$18
  .BYTE $c3,$e7,$7e,$3c,$3c,$7e,$e7,$c3
  .BYTE $00,$3c,$7e,$66,$66,$7e,$3c,$00
  .BYTE $18,$18,$66,$66,$18,$18,$3c,$00
  .BYTE $06,$06,$06,$06,$06,$06,$06,$06
  .BYTE $08,$1c,$3e,$7f,$3e,$1c,$08,$00
  .BYTE $18,$18,$18,$ff,$ff,$18,$18,$18
  .BYTE $c0,$c0,$30,$30,$c0,$c0,$30,$30
  .BYTE $18,$18,$18,$18,$18,$18,$18,$18
  .BYTE $00,$00,$03,$3e,$76,$36,$36,$00
  .BYTE $ff,$7f,$3f,$1f,$0f,$07,$03,$01
  .BYTE $00,$00,$00,$00,$00,$00,$00,$00
  .BYTE $f0,$f0,$f0,$f0,$f0,$f0,$f0,$f0
  .BYTE $00,$00,$00,$00,$ff,$ff,$ff,$ff
  .BYTE $ff,$00,$00,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$00,$00,$ff
  .BYTE $c0,$c0,$c0,$c0,$c0,$c0,$c0,$c0
  .BYTE $cc,$cc,$33,$33,$cc,$cc,$33,$33
  .BYTE $03,$03,$03,$03,$03,$03,$03,$03
  .BYTE $00,$00,$00,$00,$cc,$cc,$33,$33
  .BYTE $ff,$fe,$fc,$f8,$f0,$e0,$c0,$80
  .BYTE $03,$03,$03,$03,$03,$03,$03,$03
  .BYTE $18,$18,$18,$1f,$1f,$18,$18,$18
  .BYTE $00,$00,$00,$00,$0f,$0f,$0f,$0f
  .BYTE $18,$18,$18,$1f,$1f,$00,$00,$00
  .BYTE $00,$00,$00,$f8,$f8,$18,$18,$18
  .BYTE $00,$00,$00,$00,$00,$00,$ff,$ff
  .BYTE $00,$00,$00,$1f,$1f,$18,$18,$18
  .BYTE $18,$18,$18,$ff,$ff,$00,$00,$00
  .BYTE $00,$00,$00,$ff,$ff,$18,$18,$18
  .BYTE $18,$18,$18,$f8,$f8,$18,$18,$18
  .BYTE $c0,$c0,$c0,$c0,$c0,$c0,$c0,$c0
  .BYTE $e0,$e0,$e0,$e0,$e0,$e0,$e0,$e0
  .BYTE $07,$07,$07,$07,$07,$07,$07,$07
  .BYTE $ff,$ff,$00,$00,$00,$00,$00,$00
  .BYTE $ff,$ff,$ff,$00,$00,$00,$00,$00
  .BYTE $00,$00,$00,$00,$00,$ff,$ff,$ff
  .BYTE $03,$03,$03,$03,$03,$03,$ff,$ff
  .BYTE $00,$00,$00,$00,$f0,$f0,$f0,$f0
  .BYTE $0f,$0f,$0f,$0f,$00,$00,$00,$00
  .BYTE $18,$18,$18,$f8,$f8,$00,$00,$00
  .BYTE $f0,$f0,$f0,$f0,$00,$00,$00,$00
  .BYTE $f0,$f0,$f0,$f0,$0f,$0f,$0f,$0f
  .BYTE $c3,$99,$91,$91,$9f,$99,$c3,$ff
  .BYTE $e7,$c3,$99,$81,$99,$99,$99,$ff
  .BYTE $83,$99,$99,$83,$99,$99,$83,$ff
  .BYTE $c3,$99,$9f,$9f,$9f,$99,$c3,$ff
  .BYTE $87,$93,$99,$99,$99,$93,$87,$ff
  .BYTE $81,$9f,$9f,$87,$9f,$9f,$81,$ff
  .BYTE $81,$9f,$9f,$87,$9f,$9f,$9f,$ff
  .BYTE $c3,$99,$9f,$91,$99,$99,$c3,$ff
  .BYTE $99,$99,$99,$81,$99,$99,$99,$ff
  .BYTE $c3,$e7,$e7,$e7,$e7,$e7,$c3,$ff
  .BYTE $e1,$f3,$f3,$f3,$f3,$93,$c7,$ff
  .BYTE $99,$93,$87,$8f,$87,$93,$99,$ff
  .BYTE $9f,$9f,$9f,$9f,$9f,$9f,$81,$ff
  .BYTE $9c,$88,$80,$94,$9c,$9c,$9c,$ff
  .BYTE $99,$89,$81,$81,$91,$99,$99,$ff
  .BYTE $c3,$99,$99,$99,$99,$99,$c3,$ff
  .BYTE $83,$99,$99,$83,$9f,$9f,$9f,$ff
  .BYTE $c3,$99,$99,$99,$99,$c3,$f1,$ff
  .BYTE $83,$99,$99,$83,$87,$93,$99,$ff
  .BYTE $c3,$99,$9f,$c3,$f9,$99,$c3,$ff
  .BYTE $81,$e7,$e7,$e7,$e7,$e7,$e7,$ff
  .BYTE $99,$99,$99,$99,$99,$99,$c3,$ff
  .BYTE $99,$99,$99,$99,$99,$c3,$e7,$ff
  .BYTE $9c,$9c,$9c,$94,$80,$88,$9c,$ff
  .BYTE $99,$99,$c3,$e7,$c3,$99,$99,$ff
  .BYTE $99,$99,$99,$c3,$e7,$e7,$e7,$ff
  .BYTE $81,$f9,$f3,$e7,$cf,$9f,$81,$ff
  .BYTE $c3,$cf,$cf,$cf,$cf,$cf,$c3,$ff
  .BYTE $f3,$ed,$cf,$83,$cf,$9d,$03,$ff
  .BYTE $c3,$f3,$f3,$f3,$f3,$f3,$c3,$ff
  .BYTE $ff,$e7,$c3,$81,$e7,$e7,$e7,$e7
  .BYTE $ff,$ef,$cf,$80,$80,$cf,$ef,$ff
  .BYTE $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
  .BYTE $e7,$e7,$e7,$e7,$ff,$ff,$e7,$ff
  .BYTE $99,$99,$99,$ff,$ff,$ff,$ff,$ff
  .BYTE $99,$99,$00,$99,$00,$99,$99,$ff
  .BYTE $e7,$c1,$9f,$c3,$f9,$83,$e7,$ff
  .BYTE $9d,$99,$f3,$e7,$cf,$99,$b9,$ff
  .BYTE $c3,$99,$c3,$c7,$98,$99,$c0,$ff
  .BYTE $f9,$f3,$e7,$ff,$ff,$ff,$ff,$ff
  .BYTE $f3,$e7,$cf,$cf,$cf,$e7,$f3,$ff
  .BYTE $cf,$e7,$f3,$f3,$f3,$e7,$cf,$ff
  .BYTE $ff,$99,$c3,$00,$c3,$99,$ff,$ff
  .BYTE $ff,$e7,$e7,$81,$e7,$e7,$ff,$ff
  .BYTE $ff,$ff,$ff,$ff,$ff,$e7,$e7,$cf
  .BYTE $ff,$ff,$ff,$81,$ff,$ff,$ff,$ff
  .BYTE $ff,$ff,$ff,$ff,$ff,$e7,$e7,$ff
  .BYTE $ff,$fc,$f9,$f3,$e7,$cf,$9f,$ff
  .BYTE $c3,$99,$91,$89,$99,$99,$c3,$ff
  .BYTE $e7,$e7,$c7,$e7,$e7,$e7,$81,$ff
  .BYTE $c3,$99,$f9,$f3,$cf,$9f,$81,$ff
  .BYTE $c3,$99,$f9,$e3,$f9,$99,$c3,$ff
  .BYTE $f9,$f1,$e1,$99,$80,$f9,$f9,$ff
  .BYTE $81,$9f,$83,$f9,$f9,$99,$c3,$ff
  .BYTE $c3,$99,$9f,$83,$99,$99,$c3,$ff
  .BYTE $81,$99,$f3,$e7,$e7,$e7,$e7,$ff
  .BYTE $c3,$99,$99,$c3,$99,$99,$c3,$ff
  .BYTE $c3,$99,$99,$c1,$f9,$99,$c3,$ff
  .BYTE $ff,$ff,$e7,$ff,$ff,$e7,$ff,$ff
  .BYTE $ff,$ff,$e7,$ff,$ff,$e7,$e7,$cf
  .BYTE $f1,$e7,$cf,$9f,$cf,$e7,$f1,$ff
  .BYTE $ff,$ff,$81,$ff,$81,$ff,$ff,$ff
  .BYTE $8f,$e7,$f3,$f9,$f3,$e7,$8f,$ff
  .BYTE $c3,$99,$f9,$f3,$e7,$ff,$e7,$ff
  .BYTE $ff,$ff,$ff,$00,$00,$ff,$ff,$ff
  .BYTE $f7,$e3,$c1,$80,$80,$e3,$c1,$ff
  .BYTE $e7,$e7,$e7,$e7,$e7,$e7,$e7,$e7
  .BYTE $ff,$ff,$ff,$00,$00,$ff,$ff,$ff
  .BYTE $ff,$ff,$00,$00,$ff,$ff,$ff,$ff
  .BYTE $ff,$00,$00,$ff,$ff,$ff,$ff,$ff
  .BYTE $ff,$ff,$ff,$ff,$00,$00,$ff,$ff
  .BYTE $cf,$cf,$cf,$cf,$cf,$cf,$cf,$cf
  .BYTE $f3,$f3,$f3,$f3,$f3,$f3,$f3,$f3
  .BYTE $ff,$ff,$ff,$1f,$0f,$c7,$e7,$e7
  .BYTE $e7,$e7,$e3,$f0,$f8,$ff,$ff,$ff
  .BYTE $e7,$e7,$c7,$0f,$1f,$ff,$ff,$ff
  .BYTE $3f,$3f,$3f,$3f,$3f,$3f,$00,$00
  .BYTE $3f,$1f,$8f,$c7,$e3,$f1,$f8,$fc
  .BYTE $fc,$f8,$f1,$e3,$c7,$8f,$1f,$3f
  .BYTE $00,$00,$3f,$3f,$3f,$3f,$3f,$3f
  .BYTE $00,$00,$fc,$fc,$fc,$fc,$fc,$fc
  .BYTE $ff,$c3,$81,$81,$81,$81,$c3,$ff
  .BYTE $ff,$ff,$ff,$ff,$ff,$00,$00,$ff
  .BYTE $c9,$80,$80,$80,$c1,$e3,$f7,$ff
  .BYTE $9f,$9f,$9f,$9f,$9f,$9f,$9f,$9f
  .BYTE $ff,$ff,$ff,$f8,$f0,$e3,$e7,$e7
  .BYTE $3c,$18,$81,$c3,$c3,$81,$18,$3c
  .BYTE $ff,$c3,$81,$99,$99,$81,$c3,$ff
  .BYTE $e7,$e7,$99,$99,$e7,$e7,$c3,$ff
  .BYTE $f9,$f9,$f9,$f9,$f9,$f9,$f9,$f9
  .BYTE $f7,$e3,$c1,$80,$c1,$e3,$f7,$ff
  .BYTE $e7,$e7,$e7,$00,$00,$e7,$e7,$e7
  .BYTE $3f,$3f,$cf,$cf,$3f,$3f,$cf,$cf
  .BYTE $e7,$e7,$e7,$e7,$e7,$e7,$e7,$e7
  .BYTE $ff,$ff,$fc,$c1,$89,$c9,$c9,$ff
  .BYTE $00,$80,$c0,$e0,$f0,$f8,$fc,$fe
  .BYTE $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
  .BYTE $0f,$0f,$0f,$0f,$0f,$0f,$0f,$0f
  .BYTE $ff,$ff,$ff,$ff,$00,$00,$00,$00
  .BYTE $00,$ff,$ff,$ff,$ff,$ff,$ff,$ff
  .BYTE $ff,$ff,$ff,$ff,$ff,$ff,$ff,$00
  .BYTE $3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f
  .BYTE $33,$33,$cc,$cc,$33,$33,$cc,$cc
  .BYTE $fc,$fc,$fc,$fc,$fc,$fc,$fc,$fc
  .BYTE $ff,$ff,$ff,$ff,$33,$33,$cc,$cc
  .BYTE $00,$01,$03,$07,$0f,$1f,$3f,$7f
  .BYTE $fc,$fc,$fc,$fc,$fc,$fc,$fc,$fc
  .BYTE $e7,$e7,$e7,$e0,$e0,$e7,$e7,$e7
  .BYTE $ff,$ff,$ff,$ff,$f0,$f0,$f0,$f0
  .BYTE $e7,$e7,$e7,$e0,$e0,$ff,$ff,$ff
  .BYTE $ff,$ff,$ff,$07,$07,$e7,$e7,$e7
  .BYTE $ff,$ff,$ff,$ff,$ff,$ff,$00,$00
  .BYTE $ff,$ff,$ff,$e0,$e0,$e7,$e7,$e7
  .BYTE $e7,$e7,$e7,$00,$00,$ff,$ff,$ff
  .BYTE $ff,$ff,$ff,$00,$00,$e7,$e7,$e7
  .BYTE $e7,$e7,$e7,$07,$07,$e7,$e7,$e7
  .BYTE $3f,$3f,$3f,$3f,$3f,$3f,$3f,$3f
  .BYTE $1f,$1f,$1f,$1f,$1f,$1f,$1f,$1f
  .BYTE $f8,$f8,$f8,$f8,$f8,$f8,$f8,$f8
  .BYTE $00,$00,$ff,$ff,$ff,$ff,$ff,$ff
  .BYTE $00,$00,$00,$ff,$ff,$ff,$ff,$ff
  .BYTE $ff,$ff,$ff,$ff,$ff,$00,$00,$00
  .BYTE $fc,$fc,$fc,$fc,$fc,$fc,$00,$00
  .BYTE $ff,$ff,$ff,$ff,$0f,$0f,$0f,$0f
  .BYTE $f0,$f0,$f0,$f0,$ff,$ff,$ff,$ff
  .BYTE $e7,$e7,$e7,$07,$07,$ff,$ff,$ff
  .BYTE $0f,$0f,$0f,$0f,$ff,$ff,$ff,$ff
  .BYTE $0f,$0f,$0f,$0f,$f0,$f0,$f0,$f0

LAST                              ; End of the entire program
      
.ENDLOGICAL
