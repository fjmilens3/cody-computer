;
; codycart.asm
;
; An example assembly language program for the Cody Computer. The program
; pokes the message "Cody!" into the default screen memory location after
; starting up, then loops forever.
;
; You can assemble the program with 64tass using the following command:
;
; 64tass --mw65c02 --nostart -o codycart.bin codycart.asm
;

ADDR    = $3000                 ; The actual loading address of the program
SCRRAM  = $C400                 ; The default location of screen memory

; Program header for Cody Basic's loader (needs to be first)

.WORD ADDR                      ; Starting address (just like KIM-1, Commodore, etc.)
.WORD (ADDR + LAST - MAIN - 1)  ; Ending address (so we know when we're done loading)

;
; The actual program.
;

.LOGICAL    ADDR                ; The actual program gets loaded at ADDR

MAIN        LDX #0              ; The program starts running from here
            
_LOOP       LDA TEXT,X          ; Copies TEXT into screen memory
            BEQ _DONE
            
            STA SCRRAM,X
            
            INX
            BRA _LOOP
            
_DONE       JMP _DONE           ; Loops forever
            
TEXT        .NULL "Cody!"       ; TEXT as a null-terminated string

LAST                            ; End of the entire program

.ENDLOGICAL
