;
; codyprog.asm
; A simple cartridge programmer for the Cody Computer.
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
; To assemble using 64TASS run the following:
;
;   64tass --mw65c02 --nostart -o codyprog.bin codyprog.asm
;

ADDR      = $0300               ; The actual loading address of the program

SCRRAM    = $C400               ; Screen memory base address

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

STRPTR    = $D0                 ; Pointer to string (2 bytes)
SCRPTR    = $D2                 ; Pointer to screen (2 bytes)
PRGPTR    = $D4                 ; Pointer to the start of the program data
PRGTOP    = $D6                 ; Pointer to the end of the program data
PRGLEN    = $D8                 ; Length of the program in memory

KEYROW0   = $DA                 ; Keyboard row 0
KEYROW1   = $DB                 ; Keyboard row 1
KEYROW2   = $DC                 ; Keyboard row 2
KEYROW3   = $DD                 ; Keyboard row 3
KEYROW4   = $DE                 ; Keyboard row 4
KEYROW5   = $DF                 ; Keyboard row 5

SPIINP    = $E0                 ; SPI input byte
SPIOUT    = $E1                 ; SPI output byte

PRGMEM    = $1000               ; Start of the program to burn into the EEPROM

CART_CLK  = $01                 ; Bit masks for 65C22 port B cartridge pins
CART_MOSI = $02
CART_MISO = $04
CART_CS   = $08
CART_SIZE = $10

; Program header for Cody Basic's loader (needs to be first)

.WORD ADDR                      ; Starting address (just like KIM-1, Commodore, etc.)
.WORD (ADDR + LAST - MAIN - 1)  ; Ending address (so we know when we're done loading)

; The actual program goes below here

.LOGICAL    ADDR                ; The actual program gets loaded at ADDR

;
; MAIN
;
; Main loop of the programmer. Responsible for initialization, information display,
; and menu selection.
;
MAIN        STZ PRGLEN          ; Clear program length
            STZ PRGLEN+1
            
            JSR SHOWSCRN
            
_LOOP       JSR KEYSCAN         ; Scan the keyboard

            LDA KEYROW0         ; Pressed Q for quit?
            AND #%00001
            BNE _QUIT
            
            LDA KEYROW1         ; Pressed L for load?
            AND #%10000
            BNE _LOAD
            
            LDA KEYROW5         ; Pressed P for program?
            AND #%10000
            BNE _PROG
            
            BRA _LOOP           ; Repeat main loop
            
_QUIT       RTS                 ; Return to BASIC
            
_LOAD       JSR CMDLOAD         ; Run the load command
            BRA _LOOP
            
_PROG       JSR CMDPROG         ; Run the program command
            BRA _LOOP

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
; CMDLOAD
;
; Implements the menu option to load a binary file over the UART connection.
;
CMDLOAD     JSR SHOWSCRN        ; Clear screen
            
            JSR UARTON          ; Receive the binary file
            JSR LOADBIN
            JSR UARTOFF
        
            JSR SHOWSCRN        ; Redraw screen with file length
            
            JSR UARTON          ; Verify the binary file
            JSR VERIBIN
            JSR UARTOFF
            
            RTS                 ; All done

;
; CMDPROG
;
; Implements the menu option to program the SPI EEPROM on the cartridge.
;
CMDPROG     JSR SHOWSCRN        ; Clear screen

            JSR PROGCART        ; Program the cartridge
            
            JSR VERICART        ; Verify the cartridge contents
            
            RTS                 ; All done

;
; LOADBIN
;
; Loads a binary file into memory.
;
LOADBIN   LDA #<PRGMEM          ; Move to beginning of memory
          STA PRGPTR+0
          
          LDA #>PRGMEM
          STA PRGPTR+1
          
          LDX #MSG_WAITBINA     ; Display message about waiting for data
          JSR SHOWSTAT
          
_READ1    JSR UARTGET           ; Read the first byte
          BCC _READ1
          
          JSR _SAVE             ; Save it to memory
          
          LDX #MSG_RECVDATA     ; Display message about receiving data
          JSR SHOWSTAT
          
          LDX #$FF              ; Timeout counter
          
_READ2    DEX                   ; Wait for byte with timeout
          BEQ _DONE
          
          JSR UARTGET       
          BCC _READ2

          JSR _SAVE             ; Save data
                   
          LDX #$FF              ; Reset counter
          BRA _READ2
          
_DONE     SEC                   ; Calculate program length
          
          LDA PRGPTR+0
          SBC #<PRGMEM
          STA PRGLEN+0
          
          LDA PRGPTR+1
          SBC #>PRGMEM
          STA PRGLEN+1

          LDA PRGPTR+0          ; Update end of program
          STA PRGTOP+0
          
          LDA PRGPTR+1
          STA PRGTOP+1
          
          RTS

_SAVE     STA (PRGPTR)          ; Store data
          
          INC PRGPTR+0          ; Increment address
          BNE _NEXT
          INC PRGPTR+1
       
_NEXT     RTS

;
; VERIBIN
;
; Verifies the binary file in memory.
;
VERIBIN   LDA #<PRGMEM          ; Move to beginning of memory
          STA PRGPTR+0
          
          LDA #>PRGMEM
          STA PRGPTR+1
          
          LDX #MSG_WAITREPE   ; Display message about waiting for data
          JSR SHOWSTAT
          
_READ1    JSR UARTGET           ; Read the first byte
          BCC _READ1
          
          JSR _VERIFY           ; Check the byte against the memory
          BNE _FAILED
          
          LDX #MSG_VERIDATA     ; Display message about verifying data
          JSR SHOWSTAT
          
          LDX #$FF              ; Timeout counter
          
_READ2    DEX                   ; Wait for byte with timeout
          BEQ _DONE
          JSR UARTGET       
          BCC _READ2
                   
          LDX #$FF              ; Reset counter
          
          JSR _VERIFY           ; Check the byte
          BNE _FAILED
          
          BRA _READ2
          
_DONE     LDA PRGPTR+0          ; Verify program length was the same
          CMP PRGTOP+0
          BNE _FAILED
          
          LDA PRGPTR+1
          CMP PRGTOP+1
          BNE _FAILED
          
          LDX #MSG_VERIFYOK     ; Update status message
          JSR SHOWSTAT
          
          RTS

_VERIFY   CMP (PRGPTR)          ; Compare bytes
          PHP
          
          INC PRGPTR+0          ; Increment address
          BNE _NEXT
          INC PRGPTR+1
       
_NEXT     PLP                   ; Restore flags and return
          RTS

_FAILED   STZ PRGLEN+0          ; Clear program length (bad file?)
          STZ PRGLEN+1
          
          LDX #MSG_VERIFYBAD    ; Update status message
          JSR SHOWSTAT
          
          RTS                   ; All done

;
; PROGCART
;
; Writes the program in memory to the SPI EEPROM on the cartridge.
;
PROGCART  LDA #<PRGMEM          ; Move to beginning of memory
          STA PRGPTR+0
          
          LDA #>PRGMEM
          STA PRGPTR+1
          
          LDX #MSG_PROGDATA     ; Display message about programming data
          JSR SHOWSTAT

          JSR _BEGIN            ; Begin initial SPI transaction
          
_LOOP     LDA PRGPTR+0          ; Ensure we're not at the top of the data
          CMP PRGTOP+0
          BNE _CONT
          
          LDA PRGPTR+1
          CMP PRGTOP+1
          BNE _CONT
          
          JSR _END              ; Done programming
          
          LDX #MSG_CLEAR        ; Clear status message
          JSR SHOWSTAT
          
          RTS

_CONT     LDA (PRGPTR)          ; Send the next byte to the cartridge
          JSR CARTXFER
          
          INC PRGPTR+0          ; Increment address
          BNE _LOOP
          INC PRGPTR+1
          
          JSR _END              ; New page, need to start new transaction
          JSR _BEGIN
          
          BRA _LOOP
     
_BEGIN    JSR CARTON            ; Begin SPI transaction for write enable

          LDA #6                ; Write enable command
          JSR CARTXFER
          
          JSR CARTOFF           ; End SPI transction for write enable
          
          JSR CARTON            ; Begin SPI transaction for writing data
          
          LDA #2                ; Write starting address command
          JSR CARTXFER
          
          JSR CARTSIZE          ; Check cartridge size
          BEQ _ADDR
          
          LDA #0                ; Write address highest byte, greater than 64K only
          JSR CARTXFER
          
_ADDR     SEC                   ; Write address high byte
          LDA PRGPTR+1
          SBC #>PRGMEM
          JSR CARTXFER
          
          LDA #0                ; Write address low byte
          JSR CARTXFER
          
          RTS

_END      JSR CARTOFF           ; End previous transaction
          
          JSR CARTON            ; New transaction to read status register
          
_WAIT     LDA #5                ; Read status register command
          JSR CARTXFER
          
          LDA #0                ; Read the status register
          JSR CARTXFER
          
          AND #$01              ; Wait until previous write is completed
          BNE _WAIT
          
          JSR CARTOFF           ; End transaction and return
          
          RTS

;
; VERICART
;
; Reads the SPI EEPROM and compares it to the program in memory.
;
VERICART  LDA #<PRGMEM          ; Move to beginning of memory
          STA PRGPTR+0
          
          LDA #>PRGMEM
          STA PRGPTR+1
          
          LDX #MSG_VERIDATA     ; Display message about verifying data
          JSR SHOWSTAT
          
          JSR CARTON            ; Begin initial SPI transaction
          
          LDA #3                ; Read command
          JSR CARTXFER
          
          JSR CARTSIZE          ; Check cartridge size
          BEQ _ADDR
          
          LDA #0                ; Read address highest byte, greater than 64K only
          JSR CARTXFER
          
_ADDR     LDA #0                ; Read address high byte
          JSR CARTXFER
          
          LDA #0                ; Write address low byte
          JSR CARTXFER
          
_LOOP     LDA PRGPTR+0          ; Ensure we're not at the top of the data
          CMP PRGTOP+0
          BNE _CONT
          
          LDA PRGPTR+1
          CMP PRGTOP+1
          BNE _CONT
          
          JSR CARTOFF           ; Done reading
          
          LDX #MSG_VERIFYOK     ; Verify passed
          JSR SHOWSTAT
          
          RTS

_CONT     LDA #0                ; Read the next byte from the cartridge
          JSR CARTXFER

          CMP (PRGPTR)          ; Compare the bytes to verify
          BNE _FAILED
          
          INC PRGPTR+0          ; Increment address
          BNE _LOOP
          INC PRGPTR+1
          BRA _LOOP
     
_FAILED   JSR CARTOFF           ; Turn off SPI

          LDX #MSG_VERIFYBAD    ; Display verification failed message
          JSR SHOWSTAT

          RTS

;
; SHOWSTAT
;
; Shows a message in the status bar at the bottom of the screen.
; The message number should be in the X register.
;
SHOWSTAT  PHX                     ; Preserve message number
          
          LDX #0                  ; Clear status bar
          LDY #11
          JSR MOVESCRN
          
          LDX #MSG_CLEAR
          JSR PUTMSG
          
          LDX #0                  ; Print message
          LDY #11
          JSR MOVESCRN
          
          PLX
          JSR PUTMSG
          
          RTS
          
;
; SHOWSCRN
;
; Shows the main screen.
;
SHOWSCRN  JSR CLRSCRN
            
          LDX #0
          LDY #0
          JSR MOVESCRN
          
          LDX #MSG_CODYPROG
          JSR PUTMSG
          
          LDX #0
          LDY #1
          JSR MOVESCRN
          
          LDX #MSG_SUBTITLE
          JSR PUTMSG
          
          LDX #0
          LDY #3
          JSR MOVESCRN
          
          LDX #MSG_LENGTH
          JSR PUTMSG
          
          LDX #9
          LDY #3
          JSR MOVESCRN
          
          LDA PRGLEN+1
          JSR PUTHEX
          
          LDX #11
          LDY #3
          JSR MOVESCRN
        
          LDA PRGLEN+0
          JSR PUTHEX
          
          LDX #0
          LDY #5
          JSR MOVESCRN
          
          LDX #MSG_LOADMENU
          JSR PUTMSG

          LDX #0
          LDY #6
          JSR MOVESCRN
          
          LDX #MSG_PROGMENU
          JSR PUTMSG         
          
          LDX #0
          LDY #7
          JSR MOVESCRN
          
          LDX #MSG_QUITMENU
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

_ERR      LDX #MSG_ERROR          ; UART error, display error status message
          JSR SHOWSTAT
          
_DONE     JMP _DONE  

;
; CARTSIZE
;
; Checks the cartridge size as small (64K or less) or large (greater than 64K).
; Cartridges greater than 64K require an additional address byte.
;
CARTSIZE  LDA VIA_IORB
          AND #CART_SIZE
          
          RTS
          
;
; CARTON
;
; Starts an SPI transation on the cartridge pins for the expansion port. The proper
; directions for 65C22 port B are set, outputs are set, and then the chip select is
; brought low.
;
; Calls to CARTON should be matched by a call to CARTOFF. The presence of a cartridge
; should be verified by a prior call to CARTCHECK.
;
CARTON    LDA #(CART_CLK | CART_MOSI | CART_CS)    ; Set port B directions
          STA VIA_DDRB
  
          LDA #CART_CS        ; Start with SPI select high
          STA VIA_IORB
  
          LDA #0              ; Bring select low to begin a cycle
          STA VIA_IORB
          
          RTS

;
; CARTOFF
;
; Brings the chip select high at the end of an SPI transaction with a cartridge.
;
CARTOFF   LDA #CART_CS        ; Bring select high to end the transaction
          STA VIA_IORB

          RTS

;
; CARTXFER
;
; Transfers a single byte during an SPI transaction with a cartridge. The value
; to send should be stored in the accumulator, and it will be replaced by the
; value received.
;
CARTXFER  PHX
          
          STA SPIOUT
          
          STZ SPIINP
          
          LDX #8              ; 8 bits to read

_LOOP     STZ VIA_IORB        ; Bring the clock low

          LDA #0              ; Start with no data

          ROL SPIOUT          ; Get output bit
     
          BCC _SEND
          
          ORA #CART_MOSI      ; Output bit was a 1
          
_SEND     STA VIA_IORB        ; Put the bit on MOSI     

          ORA #CART_CLK       ; Bring the SPI clock high
          STA VIA_IORB

          ROL SPIINP          ; Rotate SPI input for next bit
          
          LDA VIA_IORB        ; Read the incoming MISO
          AND #CART_MISO          
          
          BEQ _NEXT
          
          LDA SPIINP
          ORA #1
          STA SPIINP
          
_NEXT     DEX                 ; Next loop (if any remain)
          BNE _LOOP

          PLX
          
          LDA SPIINP
          
          RTS

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
MSG_CODYPROG  = 0
MSG_SUBTITLE  = 1
MSG_LOADMENU  = 2
MSG_PROGMENU  = 3
MSG_QUITMENU  = 4
MSG_WAITBINA  = 5
MSG_WAITREPE  = 6
MSG_RECVDATA  = 7
MSG_PROGDATA  = 8
MSG_VERIDATA  = 9
MSG_VERIFYOK  = 10
MSG_VERIFYBAD = 11
MSG_LENGTH    = 12
MSG_CLEAR     = 13
MSG_ERROR     = 14

;
; The strings displayed by the program.
;
STR_CODYPROG  .NULL "CodyProg"
STR_SUBTITLE  .NULL "The Cody Cartridge Programmer"
STR_LOADMENU  .NULL "(L)oad binary"
STR_PROGMENU  .NULL "(P)rogram cartridge"
STR_QUITMENU  .NULL "(Q)uit"
STR_WAITBINA  .NULL "Waiting for binary data..."
STR_WAITREPE  .NULL "Waiting for repeat data to verify..."
STR_RECVDATA  .NULL "Receiving data..."
STR_PROGDATA  .NULL "Programming data..."
STR_VERIDATA  .NULL "Verifying data..."
STR_VERIFYOK  .NULL "Verify OK."
STR_VERIFYBAD .NULL "Verify FAILED."
STR_LENGTH    .NULL "Length: $"
STR_CLEAR     .NULL "                                    "
STR_ERROR     .NULL "ERROR"

;
; Low bytes of the string table addresses.
;
MSGS_L
  .BYTE <STR_CODYPROG
  .BYTE <STR_SUBTITLE
  .BYTE <STR_LOADMENU
  .BYTE <STR_PROGMENU
  .BYTE <STR_QUITMENU
  .BYTE <STR_WAITBINA
  .BYTE <STR_WAITREPE
  .BYTE <STR_RECVDATA
  .BYTE <STR_PROGDATA
  .BYTE <STR_VERIDATA
  .BYTE <STR_VERIFYOK
  .BYTE <STR_VERIFYBAD
  .BYTE <STR_LENGTH
  .BYTE <STR_CLEAR
  .BYTE <STR_ERROR

;
; High bytes of the string table addresses.
;
MSGS_H
  .BYTE >STR_CODYPROG
  .BYTE >STR_SUBTITLE
  .BYTE >STR_LOADMENU
  .BYTE >STR_PROGMENU
  .BYTE >STR_QUITMENU
  .BYTE >STR_WAITBINA
  .BYTE >STR_WAITREPE
  .BYTE >STR_RECVDATA
  .BYTE >STR_PROGDATA
  .BYTE >STR_VERIDATA
  .BYTE >STR_VERIFYOK
  .BYTE >STR_VERIFYBAD
  .BYTE >STR_LENGTH
  .BYTE >STR_CLEAR
  .BYTE >STR_ERROR

LAST                              ; End of the entire program

.ENDLOGICAL
