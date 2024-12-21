;
; codysid.asm
; A simple SID file player for the Cody Computer. 
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
; Only supports PSID version 2, and even then it's best not to get your hopes up.
; Aside from the SID location the Cody Computer's memory map is completely different
; from the C64, and many SID files that "should work" do not. Some work but corrupt
; the screen.
;
; See https://gist.github.com/cbmeeks/2b107f0a8d36fc461ebb056e94b2f4d6 for a
; description of the various SID file layouts.
;
; To assemble using 64TASS run the following:
;
;   64tass --mw65c02 --nostart -o codysid.bin codysid.asm
;

ADDR      = $0300               ; The actual loading address of the program

SCRRAM    = $C400               ; Screen memory base address
SIDBASE   = $D400               ; SID register base address

UART1_BASE  = $D480             ; Register addresses for UART 1
UART1_CNTL  = UART1_BASE+0
UART1_CMND  = UART1_BASE+1
UART1_STAT  = UART1_BASE+2
UART1_RXHD  = UART1_BASE+4
UART1_RXTL  = UART1_BASE+5
UART1_TXHD  = UART1_BASE+6
UART1_TXTL  = UART1_BASE+7
UART1_RXBF  = UART1_BASE+8
UART1_TXBF  = UART1_BASE+16

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

ISRPTR    = $08                 ; Pointer to the ISR address zero page variable

STRPTR    = $D0                 ; Pointer to string (2 bytes)
SCRPTR    = $D2                 ; Pointer to screen (2 bytes)
SIDPTR    = $D4                 ; Pointer to SID load address (2 bytes)
SONGNUM   = $D8                 ; Song number
PLAYBIT   = $D9                 ; Play bit (are we playing a song?)
KEYROW0   = $DA                 ; Keyboard row 0
KEYROW1   = $DB                 ; Keyboard row 1
KEYROW2   = $DC                 ; Keyboard row 2
KEYROW3   = $DD                 ; Keyboard row 3
KEYROW4   = $DE                 ; Keyboard row 4
KEYROW5   = $DF                 ; Keyboard row 5

SIDHEAD   = $0200               ; Page to store the SID file header
SIDLOAD   = SIDHEAD+$08
SIDINIT   = SIDHEAD+$0A
SIDPLAY   = SIDHEAD+$0C
SIDNAME   = SIDHEAD+$16
SIDAUTH   = SIDHEAD+$36
SIDRELE   = SIDHEAD+$56
SIDSNUM   = SIDHEAD+$0E

; Program header for Cody Basic's loader (needs to be first)

.WORD ADDR                      ; Starting address (just like KIM-1, Commodore, etc.)
.WORD (ADDR + LAST - MAIN - 1)  ; Ending address (so we know when we're done loading)

; The actual program goes below here

.LOGICAL    ADDR                ; The actual program gets loaded at ADDR

;
; MAIN
;
; Main loop of the SID player. Responsible for initialization, information display,
; and menu selection.
;
MAIN        SEI
            STZ PLAYBIT         ; Not playing by default

            LDA #$07            ; Set VIA data direction register A to 00000111 (pins 0-2 outputs, pins 3-7 inputs)     
            STA VIA_DDRA
            
            LDA #<TIMERISR      ; Set up timer ISR location
            STA ISRPTR+0
            LDA #>TIMERISR
            STA ISRPTR+1
            
            LDA #<20000         ; Set up VIA timer 1 to emit ticks for timing purposes
            STA VIA_T1CL
            LDA #>20000
            STA VIA_T1CH
  
            LDA #$40            ; Set up VIA timer 1 continuous interrupts, no outputs
            STA VIA_ACR
  
            LDA #$C0            ; Enable VIA timer 1 interrupt
            STA VIA_IER
            
            CLI                 ; Turn on interrupts
            
            JSR CMDLOAD         ; Always start by loading and playing a song
            
_MENU       JSR SHOWMENU        ; Always print the menu just in case

_SCAN       JSR SHOWREGS
            
            LDA KEYROW0         ; Pressed Q for quit?
            AND #%00001
            BNE _QUIT
            
            LDA KEYROW1         ; Pressed L for load?
            AND #%10000
            BNE _LOAD
            
            LDA KEYROW2         ; Pressed N for next?
            AND #%01000
            BNE _NEXT
            
            LDA KEYROW5         ; Pressed P for previous?
            AND #%10000
            BNE _PREV
            
            BRA _SCAN           ; Repeat main loop

_QUIT       JSR STOPSID         ; Shut off SID
      
            SEI                 ; Disable interrupts

            RTS                 ; Return to BASIC and hope it works

_LOAD       JSR CMDLOAD         ; Run the load command
            BRA _MENU
            
_NEXT       LDA KEYROW2         ; Wait for N key to be released
            BNE _NEXT
            
            JSR STOPSID         ; Stop playing music
            
            LDA SONGNUM         ; Increment song number if within range, else play
            INC A
            CMP SIDSNUM
            BEQ _PLAY
            
            STA SONGNUM         ; Update song number and play
            BRA _PLAY

_PREV       LDA KEYROW5         ; Wait for P key to be released
            BNE _PREV
            
            JSR STOPSID         ; Stop playing music
            
            LDA SONGNUM         ; If song number at zero, just play the song
            BEQ _PLAY
            
            DEC SONGNUM         ; Otherwise decrement song number and then play
            BRA _PLAY
          
_PLAY       JSR SHOWINFO
            JSR STARTSID
            BRA _MENU

;
; STARTSID
;
; Begins playing the SID by calling its INIT function.
;
STARTSID    SEI                 ; Initialize and start playing the SID file
            LDA SONGNUM
            JSR _CALLINIT
            LDA #1
            STA PLAYBIT
            CLI
            RTS
_CALLINIT   JMP (SIDINIT)

;
; STOPSID
;
; Stops the currently playing SID.
;
STOPSID     SEI
            STZ PLAYBIT
            CLI

            LDA #0
            LDX #0
_LOOP       STA SIDBASE,X
            INX
            CPX #25
            BNE _LOOP
            RTS

;
; CMDLOAD
;
; Implements the menu option to load a SID file over the UART connection.
;
CMDLOAD     JSR STOPSID         ; Stop the current song and clear the SID registers
            
            JSR SHOWSCRN        ; Clear screen

            LDX #0              ; Display message about waiting to receive SID file
            LDY #3
            JSR MOVESCRN
          
            LDX #MSG_RECEIVE
            JSR PUTMSG
            
            JSR UARTON          ; Receive the SID file
            JSR LOADHEAD
            JSR LOADDATA
            JSR UARTOFF
            
            LDA SIDINIT+0       ; Swap INIT address bytes (big-endian in PSID header)
            PHA
            LDA SIDINIT+1
            STA SIDINIT+0
            PLA
            STA SIDINIT+1
            
            LDA SIDPLAY+0       ; Swap PLAY address bytes (big endian in PSID header)
            PHA
            LDA SIDPLAY+1
            STA SIDPLAY+0
            PLA
            STA SIDPLAY+1
            
            LDA SIDSNUM+0       ; Swap song count address bytes (big endian in PSID header)
            PHA
            LDA SIDSNUM+1
            STA SIDSNUM+0
            PLA
            STA SIDSNUM+1
            
            STZ SONGNUM         ; Always start at first song
            
            JSR SHOWSCRN        ; Clear screen 
            
            JSR SHOWINFO        ; Display the info of the SID file we read
                        
            JSR STARTSID        ; Start playing the current SID and song
                                    
            RTS                 ; All done

;
; KEYSCAN
;
; Scans the keyboard matrix (so that key selections for menu options can be detected).
;
KEYSCAN     PHA                   ; Preserve registers
            PHX
          
            STZ VIA_IORA          ; Start at the first row and first key of the keyboard
            LDX #0

_LOOP       LDA VIA_IORA          ; Read the keys for the current row from the VIA port
            EOR #$FF
            LSR A
            LSR A
            LSR A
            STA KEYROW0,X

            INC VIA_IORA          ; Move on to the next keyboard row
            INX
  
            CPX #6                ; Do we have any rows remaining to scan?
            BNE _LOOP
          
            PLX                   ; Restore registers
            PLA
  
            RTS

;
; TIMERISR
;
; A timer interrupt handler that scans the keyboard and calls the SID's play routine.
;
TIMERISR    BIT VIA_T1CL          ; Clear 65C22 interrupt by reading

            PHA                   ; Preserve registers
            PHX
            PHY
          
            JSR KEYSCAN           ; Scan the keyboard

            LDA PLAYBIT           ; Are we playing?
            BEQ _DONE
          
            JSR _CALLPLAY         ; Call the play routine
          
_DONE       PLY                   ; Restore registers
            PLX
            PLA
          
            RTI                   ; All done

_CALLPLAY   JMP (SIDPLAY)

;
; LOADHEAD
;
; Loads a SID file header into the SIDHEAD page. Assumes PSID version 2.
;
LOADHEAD  LDX #0

_READ     JSR UARTGET
          BCC _READ
          
          STA SIDHEAD,X
          INX
          
          CPX #$7C
          BNE _READ
          
          RTS

;
; LOADDATA
;
; Loads the SID file data into memory. The routine assumes the load address
; must be read from the file (not included in the SID header).
;
LOADDATA

_READ1    JSR UARTGET
          BCC _READ1
          STA SIDPTR+0

_READ2    JSR UARTGET
          BCC _READ2
          STA SIDPTR+1
          
          LDX #$FF
          
_READ3    DEX
          BEQ _DONE

          JSR UARTGET
          BCC _READ3
                   
          LDX #$FF              ; Reset counter
          
          STA (SIDPTR)          ; Store data
          
          INC SIDPTR+0          ; Increment load address
          BNE _READ3
          INC SIDPTR+1
          BRA _READ3

_DONE     RTS

;
; SHOWINFO
;
; Displays SID information on the screen. This includes the song name,
; author, release/copyright, load/init/play addresses, and song number.
;
SHOWINFO  LDX #0                ; Move to song name position
          LDY #3
          JSR MOVESCRN
     
          LDX #0                ; Print song name from header
_NAME     LDA SIDNAME,X
          JSR PUTCHR
          INX
          CPX #32
          BNE _NAME
          
          LDX #0                ; Move to song author position
          LDY #4
          JSR MOVESCRN
          
          LDX #0                ; Print song author from header
_AUTH     LDA SIDAUTH,X
          JSR PUTCHR
          INX
          CPX #32
          BNE _AUTH

          LDX #0                ; Move to song release/copyright position
          LDY #5
          JSR MOVESCRN
          
          LDX #0                ; Print song release/copyright information
_RELE     LDA SIDRELE,X
          JSR PUTCHR
          INX
          CPX #32
          BNE _RELE
          
          LDX #0                ; Print song load address from header
          LDY #7
          JSR MOVESCRN
          
          LDX #MSG_LOAD
          JSR PUTMSG
          
          LDA SIDLOAD+1
          JSR PUTHEX
          LDA SIDLOAD+0
          JSR PUTHEX
          
          LDX #0                ; Print song init address from header
          LDY #8
          JSR MOVESCRN
          
          LDX #MSG_INIT
          JSR PUTMSG
          
          LDA SIDINIT+1
          JSR PUTHEX
          LDA SIDINIT+0
          JSR PUTHEX
          
          LDX #0                ; Print song play address from header
          LDY #9
          JSR MOVESCRN
          
          LDX #MSG_PLAY
          JSR PUTMSG
          
          LDA SIDPLAY+1
          JSR PUTHEX
          LDA SIDPLAY+0
          JSR PUTHEX
          
          LDX #0                ; Print song number in SID
          LDY #10
          JSR MOVESCRN
          
          LDX #MSG_SONGNUM
          JSR PUTMSG
          
          LDA SONGNUM
          INC A
          JSR PUTHEX
          
          LDX #MSG_SONGOF
          JSR PUTMSG
          
          LDA SIDSNUM+0
          JSR PUTHEX
          
          RTS                   ; All done

;
; SHOWREGS
;
; Displays the SID register values as hex numbers on the screen.
;
SHOWREGS  LDX #3                ; Print register column headings
          LDY #12
          JSR MOVESCRN

          LDX #MSG_REGS
          JSR PUTMSG
          
          LDX #0                ; Print voice 1 registers
          LDY #13
          JSR MOVESCRN
          
          LDX #MSG_V1
          JSR PUTMSG
          
          LDX #0
_V1       LDA SIDBASE+0,X
          JSR PUTHEX
          LDA #20
          JSR PUTCHR
          INX
          CPX #7
          BNE _V1

          LDX #0                ; Print voice 2 registers
          LDY #14
          JSR MOVESCRN
          
          LDX #MSG_V2
          JSR PUTMSG
          
          LDX #0
_V2       LDA SIDBASE+7,X
          JSR PUTHEX
          LDA #20
          JSR PUTCHR
          INX
          CPX #7
          BNE _V2
          
          LDX #0                ; Print voice 3 registers
          LDY #15
          JSR MOVESCRN
          
          LDX #MSG_V3
          JSR PUTMSG
          
          LDX #0
_V3       LDA SIDBASE+14,X
          JSR PUTHEX
          LDA #20
          JSR PUTCHR
          INX
          CPX #7
          BNE _V3
          
          LDX #27               ; Print filter and volume registers
          LDY #13
          JSR MOVESCRN
          
          LDX #0
_FV       LDA SIDBASE+21,X
          JSR PUTHEX
          LDA #20
          JSR PUTCHR
          INX
          CPX #4
          BNE _FV
          
          RTS

;
; SHOWMENU
;
; Shows the menu text at the bottom of the screen.
;
SHOWMENU  LDX #0
          LDY #20
          JSR MOVESCRN
          
          LDX #MSG_MENU
          JSR PUTMSG
          RTS
          
;
; SHOWSCRN
;
; Shows the CodySID banner at the top of the screen.
;
SHOWSCRN  JSR CLRSCRN
            
          LDX #16
          LDY #0
          JSR MOVESCRN
          
          LDX #MSG_CODYSID
          JSR PUTMSG
          
          LDX #6
          LDY #1
          JSR MOVESCRN
          
          LDX #MSG_SUBTITLE
          JSR PUTMSG
          
          RTS
          
;
; UARTON
;
; Turns on UART 1.
;
UARTON    PHA
          PHY
          
_INIT     STZ UART1_RXTL          ; Clear out buffer registers
          STZ UART1_TXHD

          LDA #$0F                ; Set baud rate to 19200
          STA UART1_CNTL
          
          LDA #01                 ; Enable UART
          STA UART1_CMND
          
_WAIT     LDA UART1_STAT          ; Wait for UART to start up
          AND #$40
          BEQ _WAIT
          
          PLY
          PLA
          
          RTS                     ; All done

;
; UARTOFF
;
; Turns off UART 1.
;
UARTOFF   PHA

          STZ UART1_CMND          ; Clear bit to stop UART

_WAIT     LDA UART1_STAT          ; Wait for UART to stop
          AND #$40
          BNE _WAIT
        
          PLA
          
          RTS

;
; UARTGET
;
; Attempts to read a byte from the UART 1 buffer.
;
UARTGET   PHY
          
          LDA UART1_STAT          ; Test no error bits set in the status register
          BIT #$06
          BNE _ERR
          
          LDA UART1_RXTL          ; Compare current tail to current head position
          CMP UART1_RXHD
          BEQ _EMPTY
          
          TAY                     ; Read the next character from the buffer
          LDA UART1_RXBF,Y
          
          PHA                     ; Increment the receiver tail position
          INY
          TYA
          AND #$07
          STA UART1_RXTL
          PLA
          
          PLY
          SEC                     ; Set carry to indicate a character was read
          RTS
  
_EMPTY    PLY
          CLC                     ; Clear carry to indicate no character read
          RTS

_ERR      LDX #MSG_ERROR
          JSR PUTMSG
          
_DONE     JMP _DONE  

;
; MOVESCRN
;
; Moves the SCRPTR to the position for the column/row in the X and Y
; registers. All registers are clobbered by the routine.
;
MOVESCRN  LDA #<SCRRAM            ; Move screen pointer to beginning
          STA SCRPTR+0
          LDA #>SCRRAM
          STA SCRPTR+1
          
          INY                     ; Increment pointer for each row
_LOOPY    CLC 
          LDA SCRPTR+0
          ADC #40
          STA SCRPTR+0
          LDA SCRPTR+1
          ADC #0
          STA SCRPTR+1
          DEY
          BNE _LOOPY
          
          CLC                     ; Add position on column
          TXA
          ADC SCRPTR+0
          STA SCRPTR+0
          LDA SCRPTR+1
          ADC #0
          STA SCRPTR+1
          
          RTS

;
; CLRSCRN
;
; Clear the entire screen by filling it with whitespace (ASCII 20 decimal).
;
CLRSCRN   LDA #<SCRRAM            ; Move screen pointer to beginning
          STA SCRPTR+0
          LDA #>SCRRAM
          STA SCRPTR+1
          
          LDA #20                 ; Clear screen by filling with whitespaces
          
          LDY #25                 ; Loop 25 times on Y
          
_LOOPY    LDX #40                 ; Loop 40 times on X for each Y
          
_LOOPX    STA (SCRPTR)            ; Store zero

          INC SCRPTR+0            ; Increment screen position
          BNE _NEXT
          INC SCRPTR+1
          
_NEXT     DEX                     ; Next X
          BNE _LOOPX
          
          DEY                     ; Next Y
          BNE _LOOPY
          
          RTS

;
; PUTMSG
;
; Puts a message string (one of the MSG_XXX constants) on the screen.
;
PUTMSG      PHA
            PHY
            
            LDA MSGS_L,X        ; Load the pointer for the string to print
            STA STRPTR+0
            LDA MSGS_H,X
            STA STRPTR+1
            
            LDY #0
            
_LOOP       LDA (STRPTR),Y      ; Read the next character (check for null)
            BEQ _DONE
            
            JSR PUTCHR          ; Copy the character and move to next
            INY         
            
            BRA _LOOP           ; Next loop
            
_DONE       PLY
            PLA
            
            RTS

;
; PUTCHR
;
; Puts an individual ASCII character on the screen.
;
PUTCHR      STA (SCRPTR)        ; Copy the character   
            
            INC SCRPTR+0        ; Increment screen position
            BNE _DONE
            INC SCRPTR+1
          
_DONE       RTS

;
; PUTHEX
;
; Puts a byte's hex value on the screen as two hex digits.
;
PUTHEX      PHA
            PHX
            TAX
            JSR HEXTOASCII
            PHA
            TXA
            LSR A
            LSR A
            LSR A
            LSR A
            JSR HEXTOASCII
            PHA
            PLA
            JSR PUTCHR
            PLA
            JSR PUTCHR
            PLX
            PLA
            RTS
HEXTOASCII  AND #$F
            CLC
            ADC #48
            CMP #58
            BCC _DONE
            ADC #6
_DONE       RTS

;
; IDs for the message strings that can be displayed in the program.
;
MSG_CODYSID   = 0
MSG_SUBTITLE  = 1
MSG_LOAD      = 2
MSG_INIT      = 3
MSG_PLAY      = 4
MSG_REGS      = 5
MSG_V1        = 6
MSG_V2        = 7
MSG_V3        = 8
MSG_MENU      = 9
MSG_RECEIVE   = 10
MSG_SONGNUM   = 11
MSG_SONGOF    = 12
MSG_ERROR     = 13

;
; The strings displayed by the program.
;
STR_CODYSID   .NULL "CodySID!"
STR_SUBTITLE  .NULL "The Cody Computer SID Player"
STR_LOAD      .NULL "Load $"
STR_INIT      .NULL "Init $"
STR_PLAY      .NULL "Play $"
STR_REGS      .NULL "FL FH PL PH CL AD SR    CL CH FR MV"
STR_V1        .NULL "V1 "
STR_V2        .NULL "V2 "
STR_V3        .NULL "V3 "
STR_MENU      .NULL "(L)oad (Q)uit (P)rev (N)ext"
STR_RECEIVE   .NULL "Send PSID V2 file and wait for end..."
STR_SONGNUM   .NULL "Song $"
STR_SONGOF    .NULL " of $"
STR_ERROR     .NULL "ERROR!"

;
; Low bytes of the string table addresses.
;
MSGS_L
  .BYTE <STR_CODYSID
  .BYTE <STR_SUBTITLE
  .BYTE <STR_LOAD
  .BYTE <STR_INIT
  .BYTE <STR_PLAY
  .BYTE <STR_REGS
  .BYTE <STR_V1
  .BYTE <STR_V2
  .BYTE <STR_V3
  .BYTE <STR_MENU
  .BYTE <STR_RECEIVE
  .BYTE <STR_SONGNUM
  .BYTE <STR_SONGOF
  .BYTE <STR_ERROR

;
; High bytes of the string table addresses.
;
MSGS_H
  .BYTE >STR_CODYSID
  .BYTE >STR_SUBTITLE
  .BYTE >STR_LOAD
  .BYTE >STR_INIT
  .BYTE >STR_PLAY
  .BYTE >STR_REGS
  .BYTE >STR_V1
  .BYTE >STR_V2
  .BYTE >STR_V3
  .BYTE >STR_MENU
  .BYTE >STR_RECEIVE
  .BYTE >STR_SONGNUM
  .BYTE >STR_SONGOF
  .BYTE >STR_ERROR

LAST                              ; End of the entire program

.ENDLOGICAL
