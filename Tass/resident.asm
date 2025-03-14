;
; resident.asm
; A simple demo loading machine code into memory as a resident application.
;
; This is a short binary program that is loaded with a base address of
; $6500, which is an unused page that sits just above program memory. In
; the program is a routine loaded at $6510 that will cycle through the
; border colors on the Cody Computer.
;
; When you load this program it's loaded into that page and then returns
; to Cody BASIC. You can then call the loaded routine by running SYS 25872
; in BASIC.
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
;   64tass --mw65c02 --nostart -o resident.bin resident.asm
;
ADDR      = $6500               ; The actual loading address of the program

VID_BLNK  = $D000               ; Video blanking status register
VID_CNTL  = $D001               ; Video control register
VID_COLR  = $D002               ; Video color register
VID_BPTR  = $D003               ; Video base pointer register
VID_SCRL  = $D004               ; Video scroll register
VID_SCRC  = $D005               ; Video screen common colors register
VID_SPRC  = $D006               ; Video sprite control register

TEMP      = $FF                 ; Temporary variable in zero page

; Program header for Cody Basic's loader (needs to be first)

.WORD ADDR                      ; Starting address (just like KIM-1, Commodore, etc.)
.WORD (ADDR + LAST - MAIN - 1)  ; Ending address (so we know when we're done loading)

; The actual program goes below here

.LOGICAL    ADDR                ; The actual program gets loaded at ADDR

;
; MAIN
;
; Does nothing in this example. Cody BASIC will load the resident routines into
; RAM at the load address, so here we just return back to BASIC.
;
MAIN        RTS

;
; CYCLE
;
; Increments the border color in the video color register ($D002) by one.
;
; This should be loaded at $6510 (decimal 25872) so that it can be called
; via "SYS 25872". A more advanced example could pass data in zero page or
; via BASIC variables. This is just a simple demonstration.
;
* = $6510                       ; Start address of the color-cycle routine

CYCLE       PHA                 ; Preserve registers
            
            LDA VID_COLR        ; Increment the border color by one and store in temp
            INC A
            AND #$0F
            STA TEMP
            
            LDA VID_COLR        ; Combine the new value and the color register to update
            AND #$F0
            ORA TEMP
            STA VID_COLR
            
            PLA                 ; Restore registers and return
            RTS

LAST                            ; End of the entire program
      
.ENDLOGICAL
