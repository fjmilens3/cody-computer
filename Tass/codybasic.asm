;
; codybasic.asm
; BASIC ROM (and related code) for the Cody Computer
; 
; Copyright 2024-2025 Frederick John Milens III, The Cody Computer Developers.
; 
; In memory of Cody Biliter-Milens (2006-2020).
; We still love you so very, very much.
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
; Implementation of a tokenized Tiny Basic dialect for the 65C02-based Cody Computer. 
; Originally developed using an in-house assembler written in Python 3 before being 
; ported to the 64tass assembler. The file can be assembled with the following:
;
; # 64tass --mw65c02 --nostart -o codybasic.bin codybasic.asm
;
; Cody Basic is defined using the below BNF-like grammar. Most of the language is
; heavily derived from Tiny Basic. Notable differences and additions include some
; rudimentary string handling, fixed-length array support, and DATA statements.
;
; <statement>   ::=   "NEW"
;                     "LIST" [<expr> ["," <expr>]]
;                     "LOAD" <expr> "," <expr>
;                     "SAVE" <expr>
;                     "RUN"
;                     "REM"
;                     "IF" <strvar> <relop> <strexpr> "THEN" <statement>
;                     "IF" <expr> <relop> <expr> "THEN" <statement>
;                     "GOTO" <numexpr>
;                     "GOSUB" <numexpr>
;                     "RETURN"
;                     "FOR" <numvar> "=" <numexpr> "TO" <numexpr>
;                     "NEXT"
;                     "POKE" <numexpr> "," <numexpr>
;                     "INPUT" <inexpr> ["," <inexpr>]*
;                     "PRINT" <prexpr> ["," <prexpr>]* [";"]
;                     "OPEN" <expr> "," <expr>
;                     "CLOSE"
;                     "READ" <numvar> ["," <numvar>]*
;                     "RESTORE"
;                     "DATA" ["-"] <number> ["," ["-"] <number>]*
;                     "END"
;                     "SYS" <number>
;                     <numvar> "=" <expr>
;                     <strvar> "=" <strexpr>
;
; <relop>       ::=   "=" | "<" | ">" | "<=" | "=>" | "<>"
; <prexpr>      ::=   <expr> | <strexpr> | <at> | <tab>
;
; <strvar>      ::=   <letter> "$"
; <strexpr>     ::=   <strterm> ["+" <strterm>]*
; <strterm>     ::=   <string> | <strvar> | <sub> | <chr> | <str>
;
; <at>          ::=   "AT" "(" <numexpr> "," <numexpr> ")"
; <tab>         ::=   "TAB" "(" <numexpr> ")"
;
; <sub>         ::=   "SUB$" "(" <strvar> "," <numexpr> "," <numexpr> ")"
; <chr>         ::=   "CHR$" "(" <numexpr> ["," <numexpr>]* ")"
; <str>         ::=   "STR$" "(" <numexpr> ")"
;
; <numvar>      ::=   <letter> ["(" <numexpr> ")"]
; <expr>        ::=   <term> [( "+" | "-" ) <term>]*
; <term>        ::=   <factor> [( "*" | "/" ) <factor>]*
; <factor>      ::=   <function> | <numvar> | <number> | "(" <numexpr> ")" | "-" <factor>
;
; <function>    ::=   "TI"
;                     "PEEK" "(" <numexpr> ")"
;                     "RND" "(" [<numexpr>] ")"
;                     "NOT" "(" <numexpr> ")"
;                     "ABS" "(" <numexpr> ")"
;                     "SQR" "(" <numexpr> ")"
;                     "AND" "(" <numexpr> "," <numexpr> ")" 
;                     "OR" "(" <numexpr> "," <numexpr> ")" 
;                     "XOR" "(" <numexpr> "," <numexpr> ")" 
;                     "MOD" "(" <numexpr> "," <numexpr> ")"
;                     "VAL" "(" <strvar> ")"
;                     "LEN" "(" <strvar> ")"
;                     "ASC" "(" <strvar> ")"
;

; Zero page variables

SYS_A     = $00       ; Register A, X, and Y values for use in SYS statements
SYS_X     = $01
SYS_Y     = $02
RUNMODE   = $03       ; Current interpreter run mode (0 = REPL, 1 = running a program)
IOMODE    = $04       ; Current interpreter IO mode (0 = screen/keyboard, 1=UART 1, 2=UART 2)
IOBAUD    = $05       ; Current interpreter IO baud rate (1 through 15, same as UART)
JIFFIES   = $06       ; The jiffies (60ths of a second) timer count (2 bytes)
ISRPTR    = $08       ; ISR pointer (2 bytes)
STACKREG  = $0A       ; The stack register used when unwinding on an error
RANDOML   = $0B       ; Random number generator current seed (low byte)
RANDOMH   = $0C       ; Random number generator current seed (high byte)
TABPOS    = $0D       ; Tab position in the current line
PROMPT    = $0E       ; Character to show for INPUT prompts (NUL for none)
PROGOFF   = $0F       ; Current offset in the current program line

KEYROW0   = $10       ; Column bits for the last scan of keyboard row 0
KEYROW1   = $11       ; Column bits for the last scan of keyboard row 1
KEYROW2   = $12       ; Column bits for the last scan of keyboard row 2
KEYROW3   = $13       ; Column bits for the last scan of keyboard row 3
KEYROW4   = $14       ; Column bits for the last scan of keyboard row 4
KEYROW5   = $15       ; Column bits for the last scan of keyboard row 5
KEYROW6   = $16       ; Column bits for the last scan of keyboard row 6 / joystick row 0
KEYROW7   = $17       ; Column bits for the last scan of keyboard row 7 / joystick row 1
KEYDEBO   = $18       ; Keyboard code used for debouncing
KEYLAST   = $19       ; Last keyboard code and modifiers
KEYLOCK   = $1A       ; Current keyboard shift lock status
KEYMODS   = $1B       ; Current keyboard modifiers (only)
KEYCODE   = $1C       ; Current keyboard scan code (with modifiers)
EXPRSNUM  = $1D       ; Number of items in the interpreter's expression stack
GOSUBSNUM = $1E       ; Number of items in the interpreter's gosub-return stack
FORSNUM   = $1F       ; Number of items in the interpreter's for-next stack

MEMSPTR   = $20       ; The source pointer for memory-related utility routines (2 bytes)
MEMDPTR   = $22       ; The destination pointer for memory-related utility routines (2 bytes)
MEMSIZE   = $24       ; The size of memory to move for memory-related utility routines (2 bytes)
LINENUM   = $26       ; Line number for related utility routines (2 bytes)
LINEPTR   = $28       ; Line pointer for related utility routines (2 bytes)
STOPPTR   = $2A       ; Stop pointer for listing lines (2 bytes)
DBUFLEN   = $2C       ; Current length of the data buffer contents
IBUFLEN   = $2D       ; Current length of the input buffer contents
OBUFLEN   = $2E       ; Current length of the output buffer contents
TBUFLEN   = $2F       ; Current length of the token buffer contents

NUMONE    = $30       ; First parameter for number operations (2 bytes)
NUMTWO    = $32       ; Second parameter for number operations (2 bytes)
NUMANS    = $34       ; Answer for number operations (3 bytes)
CURATTR   = $37       ; The cursor's current background attributes (for color memory)
CURCOL    = $38       ; The cursor's column from 0 to 39
CURROW    = $39       ; The cursor's row from 0 to 24
CURSCRPTR = $3A       ; The cursor's memory pointer within screen memory (2 bytes)
CURCOLPTR = $3C       ; The cursor's memory pointer within color memory (2 bytes)
SPIINP    = $3E       ; SPI input byte (used internally by CART routines)
SPIOUT    = $3F       ; SPI output byte (used internally by CART routines)

PROGPTR   = $40       ; Pointer to the current line being executed in the program (2 bytes)
PROGNXT   = $42       ; Pointer to the next line to execute in the program (2 bytes)
PROGTOP   = $44       ; Pointer to the top of the current program (2 bytes)
UARTPTR   = $46       ; Base pointer to the current UART (2 bytes)
DATAPTR   = $48       ; Pointer to the next line for DATA statements (2 bytes)
DBUFPOS   = $4A       ; Index in the data buffer for READ statements
PROGEND   = $4B       ; Boundary page for program memory (can be updated/overridden)

TOKENIZEC = $4D       ; Tokenizer character (used internally during tokenizing lines)
TOKENIZEL = $4E       ; Tokenizer binary search L and R values for tokens
TOKENIZER = $4F

EXPRS_L   = $50       ; Interpreter's expression stack (low and high bytes)
EXPRS_H   = $58

GOSUBS_L  = $60       ; Interpreter's gosub-return stack (low and high bytes)
GOSUBS_H  = $68

FORLINE_L = $70       ; Interpreter's line numbers for for-nexts (low and high bytes)
FORLINE_H = $78

FORVARS_L = $80       ; Interpreter's variable addresses for for-nexts (low and high bytes)
FORVARS_H = $88

FORSTOP_L = $90       ; Interpreter's stop values for for-nexts (low and high bytes) 
FORSTOP_H = $98

; Other memory locations

VIA_BASE  = $9F00           ; VIA base address and register locations
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

UART1_BASE  = $D480
UART2_BASE  = $D4A0

UART_CNTL  = 0            ; Register offsets within a particular UART
UART_CMND  = 1
UART_STAT  = 2
UART_RXHD  = 4
UART_RXTL  = 5
UART_TXHD  = 6
UART_TXTL  = 7
UART_RXBF  = 8
UART_TXBF  = 16

VID_BLNK  = $D000         ; Video blanking status register
VID_CNTL  = $D001         ; Video control register
VID_COLR  = $D002         ; Video color register
VID_BPTR  = $D003         ; Video base pointer register
VID_SCRL  = $D004         ; Video scroll register
VID_SCRC  = $D005         ; Video screen common colors register
VID_SPRC  = $D006         ; Video sprite control register

VID_RCTL  = $D040         ; Start of row effect control bytes
VID_RVAL  = $D060         ; Start of row effect data bytes

VID_SPRB  = $D080         ; Start of sprite banks

SCRRAM  = $C400           ; Base of screen memory
COLRAM  = $D800           ; Base of color memory

PROGMEM = $0200           ; Base of program memory for Cody Basic
PROGMAX = $6500           ; Default end of program memory for Cody Basic
DATAMEM = $6600           ; Base of data memory for Cody Basic

ARRA    = DATAMEM+$0000   ; Array variable memory locations (26 variables * 128 words each)
ARRB    = DATAMEM+$0100
ARRC    = DATAMEM+$0200
ARRD    = DATAMEM+$0300
ARRE    = DATAMEM+$0400
ARRF    = DATAMEM+$0500
ARRG    = DATAMEM+$0600
ARRH    = DATAMEM+$0700
ARRI    = DATAMEM+$0800
ARRJ    = DATAMEM+$0900
ARRK    = DATAMEM+$0A00
ARRL    = DATAMEM+$0B00
ARRM    = DATAMEM+$0C00
ARRN    = DATAMEM+$0D00
ARRO    = DATAMEM+$0E00
ARRP    = DATAMEM+$0F00
ARRQ    = DATAMEM+$1000
ARRR    = DATAMEM+$1100
ARRS    = DATAMEM+$1200
ARRT    = DATAMEM+$1300
ARRU    = DATAMEM+$1400
ARRV    = DATAMEM+$1500
ARRW    = DATAMEM+$1600
ARRX    = DATAMEM+$1700
ARRY    = DATAMEM+$1800
ARRZ    = DATAMEM+$1900

STRA    = DATAMEM+$1A00   ; String variable memory locations (26 variables * 256 byte characters)
STRB    = DATAMEM+$1B00
STRC    = DATAMEM+$1C00
STRD    = DATAMEM+$1D00
STRE    = DATAMEM+$1E00
STRF    = DATAMEM+$1F00
STRG    = DATAMEM+$2000
STRH    = DATAMEM+$2100
STRI    = DATAMEM+$2200
STRJ    = DATAMEM+$2300
STRK    = DATAMEM+$2400
STRL    = DATAMEM+$2500
STRM    = DATAMEM+$2600
STRN    = DATAMEM+$2700
STRO    = DATAMEM+$2800
STRP    = DATAMEM+$2900
STRQ    = DATAMEM+$2A00
STRR    = DATAMEM+$2B00
STRS    = DATAMEM+$2C00
STRT    = DATAMEM+$2D00
STRU    = DATAMEM+$2E00
STRV    = DATAMEM+$2F00
STRW    = DATAMEM+$3000
STRX    = DATAMEM+$3100
STRY    = DATAMEM+$3200
STRZ    = DATAMEM+$3300

IBUF    = DATAMEM+$3400   ; Input buffer for INPUT statements
OBUF    = DATAMEM+$3500   ; Output buffer for PRINT, IF, and LET statements
TBUF    = DATAMEM+$3600   ; Token buffer used for tokenization

DBUFL   = DATAMEM+$3700   ; Data buffer for DATA and READ statements
DBUFH   = DATAMEM+$37A0

; Constants for relational operators in IF statements

REL_LE  = %00000001
REL_GE  = %00000010
REL_NE  = %00000100
REL_LT  = %00001000
REL_GT  = %00010000
REL_EQ  = %00100000

; Bit masks for 65C22 VIA port B related to cartridge I/O over SPI

CART_CLK      = $01
CART_MOSI     = $02
CART_MISO     = $04
CART_CS       = $08
CART_SIZE     = $10

; Constants for messages/PUTMSG (order is important)

MSG_GREET     = $0
MSG_READY     = $1
MSG_ERROR     = $2
MSG_IN        = $3

MSG_ERRORS    = ERRTABLE_L-MSGTABLE_L     ; Offset in the message table for error messages
MSG_TOKENS    = TOKTABLE_L-MSGTABLE_L     ; Offset in the message table for tokens

; Error codes for RAISEXXX routines and ERROR routine (order is important)

ERR_BREAK     = $0
ERR_SYNTAX    = $1
ERR_LOGIC     = $2
ERR_SYSTEM    = $3

; Keyboard scan codes

KEY_Q     = $01
KEY_E     = $02
KEY_T     = $03
KEY_U     = $04
KEY_O     = $05
KEY_A     = $06
KEY_D     = $07
KEY_G     = $08
KEY_J     = $09
KEY_L     = $0A
KEY_CODY  = $0B
KEY_X     = $0C
KEY_V     = $0D
KEY_N     = $0E
KEY_META  = $0F
KEY_Z     = $10
KEY_C     = $11
KEY_B     = $12
KEY_M     = $13
KEY_ARROW = $14
KEY_S     = $15
KEY_F     = $16
KEY_H     = $17
KEY_K     = $18
KEY_SPACE = $19
KEY_W     = $1A
KEY_R     = $1B
KEY_Y     = $1C
KEY_I     = $1D
KEY_P     = $1E

; CODSCII character codes

CHR_NUL       = $00
CHR_BS        = $08       ; Backspace
CHR_TAB       = $09       ; Tab
CHR_NL        = $0A       ; Newline
CHR_CR        = $0D       ; Carriage return
CHR_CAN       = $18       ; Cancel
CHR_SPACE     = $20       ; Space
CHR_QUOTE     = $22       ; Double quote
CHR_DOLLAR    = $24       ; Dollar
CHR_LPAREN    = $28
CHR_RPAREN    = $29
CHR_ASTERISK  = $2A
CHR_SLASH     = $2F
CHR_PLUS      = $2B
CHR_COMMA     = $2C
CHR_MINUS     = $2D
CHR_SEMICOLON = $3B
CHR_LESS      = $3C
CHR_EQUALS    = $3D
CHR_GREATER   = $3E
CHR_QUEST     = $3F       ; Question mark
CHR_ATSIGN    = $40       ; At sign (@)
CHR_AUPPER    = $41       ; Uppercase A
CHR_CARET     = $5E
CHR_CLEAR     = $DE       ; Clear screen and home cursor
CHR_REVERSE   = $DF       ; Reverse field

; Run modes

RM_REPL       = $0        ; Running in REPL loop
RM_PROGRAM    = $1        ; Running a BASIC program
RM_COMMAND    = $2        ; Running a single command (suppresses line numbers)

; Token constants used by the interpreter and tokenizer

TOK_NEW     = $80
TOK_LIST    = $81
TOK_LOAD    = $82
TOK_SAVE    = $83
TOK_RUN     = $84
TOK_REM     = $85
TOK_IF      = $86
TOK_THEN    = $87
TOK_GOTO    = $88
TOK_GOSUB   = $89
TOK_RETURN  = $8A
TOK_FOR     = $8B
TOK_TO      = $8C
TOK_NEXT    = $8D
TOK_POKE    = $8E
TOK_INPUT   = $8F
TOK_PRINT   = $90
TOK_OPEN    = $91
TOK_CLOSE   = $92
TOK_READ    = $93
TOK_RESTORE = $94
TOK_DATA    = $95
TOK_END    = $96
TOK_SYS     = $97
TOK_AT      = $98
TOK_TAB     = $99
TOK_SUB     = $9A
TOK_CHR     = $9B
TOK_STR     = $9C
TOK_TIME    = $9D
TOK_PEEK    = $9E
TOK_RND     = $9F
TOK_NOT     = $A0
TOK_ABS     = $A1
TOK_SQR     = $A2
TOK_AND     = $A3
TOK_OR      = $A4
TOK_XOR     = $A5
TOK_MOD     = $A6
TOK_VAL     = $A7
TOK_LEN     = $A8
TOK_ASC     = $A9
TOK_LE      = $AA
TOK_GE      = $AB
TOK_NE      = $AC
TOK_LT      = $AD
TOK_GT      = $AE
TOK_EQ      = $AF
TOK_NUM     = $FF

; Other constants

MAXSTACK  = 8         ; Maximum number of items in one of the interpreter's internal stacks
JIF_T1C   = 16667     ; VIA T1C value for jiffy clock (60 per second)
RAND_SEED = $C0D5     ; Default seed for the random number generator
CHAR_BASE = $C800     ; Location to copy charset to on startup (TODO: Decide on final location)

* = $E000             ; Actual start of our ROM image (character set and code)

CHRSET

; Default character ROM (4x8 multicolor chars)
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$04,$04,$04,$04,$00,$04,$04
.BYTE $00,$11,$11,$00,$00,$00,$00,$00
.BYTE $00,$00,$11,$15,$11,$15,$11,$00
.BYTE $00,$04,$05,$10,$04,$01,$14,$04
.BYTE $00,$00,$10,$01,$04,$10,$01,$00
.BYTE $00,$05,$10,$10,$05,$11,$11,$04
.BYTE $00,$14,$14,$10,$00,$00,$00,$00
.BYTE $00,$04,$10,$10,$10,$10,$10,$04
.BYTE $00,$04,$01,$01,$01,$01,$01,$04
.BYTE $00,$00,$11,$04,$15,$04,$11,$00
.BYTE $00,$00,$04,$04,$15,$04,$04,$00
.BYTE $00,$00,$00,$00,$00,$04,$04,$10
.BYTE $00,$00,$00,$00,$15,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$04,$04
.BYTE $00,$01,$01,$04,$04,$04,$10,$10
.BYTE $00,$04,$11,$15,$15,$11,$11,$04
.BYTE $00,$04,$14,$04,$04,$04,$04,$15
.BYTE $00,$04,$11,$01,$04,$04,$10,$15
.BYTE $00,$04,$11,$01,$04,$01,$11,$04
.BYTE $00,$01,$05,$11,$15,$01,$01,$01
.BYTE $00,$15,$10,$14,$01,$01,$11,$04
.BYTE $00,$04,$11,$10,$14,$11,$11,$04
.BYTE $00,$15,$11,$01,$04,$04,$04,$04
.BYTE $00,$04,$11,$11,$04,$11,$11,$04
.BYTE $00,$04,$11,$11,$05,$01,$11,$04
.BYTE $00,$00,$04,$04,$00,$04,$04,$00
.BYTE $00,$00,$04,$04,$00,$04,$04,$10
.BYTE $00,$00,$01,$04,$10,$04,$01,$00
.BYTE $00,$00,$00,$15,$00,$15,$00,$00
.BYTE $00,$00,$10,$04,$01,$04,$10,$00
.BYTE $00,$14,$01,$01,$04,$04,$00,$04
.BYTE $00,$04,$11,$11,$11,$10,$10,$05
.BYTE $00,$04,$11,$11,$15,$11,$11,$11
.BYTE $00,$14,$11,$11,$14,$11,$11,$14
.BYTE $00,$04,$11,$10,$10,$10,$11,$04
.BYTE $00,$14,$11,$11,$11,$11,$11,$14
.BYTE $00,$15,$10,$10,$14,$10,$10,$15
.BYTE $00,$15,$10,$10,$14,$10,$10,$10
.BYTE $00,$05,$10,$10,$11,$11,$11,$05
.BYTE $00,$11,$11,$11,$15,$11,$11,$11
.BYTE $00,$15,$04,$04,$04,$04,$04,$15
.BYTE $00,$15,$04,$04,$04,$04,$04,$10
.BYTE $00,$11,$11,$11,$14,$11,$11,$11
.BYTE $00,$10,$10,$10,$10,$10,$10,$15
.BYTE $00,$11,$15,$15,$11,$11,$11,$11
.BYTE $00,$15,$11,$11,$11,$11,$11,$11
.BYTE $00,$04,$11,$11,$11,$11,$11,$04
.BYTE $00,$14,$11,$11,$14,$10,$10,$10
.BYTE $00,$04,$11,$11,$11,$11,$15,$05
.BYTE $00,$14,$11,$11,$14,$11,$11,$11
.BYTE $00,$05,$10,$10,$04,$01,$01,$14
.BYTE $00,$15,$04,$04,$04,$04,$04,$04
.BYTE $00,$11,$11,$11,$11,$11,$11,$15
.BYTE $00,$11,$11,$11,$11,$11,$04,$04
.BYTE $00,$11,$11,$11,$11,$15,$15,$11
.BYTE $00,$11,$11,$11,$04,$11,$11,$11
.BYTE $00,$11,$11,$11,$15,$04,$04,$04
.BYTE $00,$15,$01,$01,$04,$10,$10,$15
.BYTE $00,$15,$10,$10,$10,$10,$10,$15
.BYTE $00,$10,$10,$04,$04,$04,$01,$01
.BYTE $00,$15,$01,$01,$01,$01,$01,$15
.BYTE $00,$04,$11,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$15
.BYTE $00,$10,$04,$01,$00,$00,$00,$00
.BYTE $00,$00,$00,$05,$11,$11,$11,$05
.BYTE $00,$10,$10,$14,$11,$11,$11,$14
.BYTE $00,$00,$00,$05,$10,$10,$10,$05
.BYTE $00,$01,$01,$05,$11,$11,$11,$05
.BYTE $00,$00,$00,$04,$11,$15,$10,$05
.BYTE $00,$05,$04,$04,$15,$04,$04,$04
.BYTE $00,$00,$00,$05,$11,$05,$01,$14
.BYTE $00,$10,$10,$10,$14,$11,$11,$11
.BYTE $00,$00,$04,$00,$04,$04,$04,$01
.BYTE $00,$00,$01,$00,$01,$01,$11,$04
.BYTE $00,$10,$10,$11,$11,$14,$11,$11
.BYTE $00,$04,$04,$04,$04,$04,$04,$04
.BYTE $00,$00,$00,$11,$15,$11,$11,$11
.BYTE $00,$00,$00,$14,$11,$11,$11,$11
.BYTE $00,$00,$00,$04,$11,$11,$11,$04
.BYTE $00,$00,$00,$14,$11,$11,$14,$10
.BYTE $00,$00,$00,$04,$11,$11,$05,$01
.BYTE $00,$00,$00,$10,$15,$10,$10,$10
.BYTE $00,$00,$00,$05,$10,$04,$01,$14
.BYTE $00,$00,$00,$04,$15,$04,$04,$01
.BYTE $00,$00,$00,$11,$11,$11,$11,$15
.BYTE $00,$00,$00,$11,$11,$11,$11,$04
.BYTE $00,$00,$00,$11,$11,$15,$15,$15
.BYTE $00,$00,$00,$11,$11,$04,$11,$11
.BYTE $00,$00,$00,$11,$11,$15,$01,$15
.BYTE $00,$00,$00,$15,$01,$04,$10,$15
.BYTE $00,$05,$04,$04,$14,$04,$04,$05
.BYTE $00,$04,$04,$04,$04,$04,$04,$04
.BYTE $00,$14,$04,$04,$05,$04,$04,$14
.BYTE $00,$00,$00,$14,$05,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$04,$11,$10,$14,$10,$04,$15
.BYTE $00,$04,$15,$04,$04,$04,$04,$04
.BYTE $00,$04,$14,$15,$15,$14,$04,$00
.BYTE $00,$00,$00,$55,$55,$00,$00,$00
.BYTE $00,$04,$04,$15,$15,$15,$04,$15
.BYTE $04,$04,$04,$04,$04,$04,$04,$04
.BYTE $00,$00,$00,$55,$55,$00,$00,$00
.BYTE $00,$00,$55,$55,$00,$00,$00,$00
.BYTE $00,$55,$55,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$55,$55,$00,$00
.BYTE $10,$10,$10,$10,$10,$10,$10,$10
.BYTE $04,$04,$04,$04,$04,$04,$04,$04
.BYTE $00,$00,$00,$50,$50,$04,$04,$04
.BYTE $04,$04,$04,$01,$01,$00,$00,$00
.BYTE $04,$04,$04,$50,$50,$00,$00,$00
.BYTE $40,$40,$40,$40,$40,$40,$55,$55
.BYTE $40,$40,$10,$10,$04,$04,$01,$01
.BYTE $01,$01,$04,$04,$10,$10,$40,$40
.BYTE $55,$55,$40,$40,$40,$40,$40,$40
.BYTE $55,$55,$01,$01,$01,$01,$01,$01
.BYTE $00,$00,$04,$15,$15,$15,$04,$00
.BYTE $00,$00,$00,$00,$00,$55,$55,$00
.BYTE $00,$11,$11,$15,$15,$15,$04,$04
.BYTE $10,$10,$10,$10,$10,$10,$10,$10
.BYTE $00,$00,$00,$01,$01,$04,$04,$04
.BYTE $41,$41,$14,$14,$14,$14,$41,$41
.BYTE $00,$00,$04,$15,$11,$15,$04,$00
.BYTE $00,$04,$04,$11,$11,$04,$04,$15
.BYTE $04,$04,$04,$04,$04,$04,$04,$04
.BYTE $00,$04,$04,$15,$15,$04,$04,$00
.BYTE $04,$04,$04,$55,$55,$04,$04,$04
.BYTE $40,$40,$10,$10,$40,$40,$10,$10
.BYTE $04,$04,$04,$04,$04,$04,$04,$04
.BYTE $00,$00,$10,$15,$11,$11,$11,$11
.BYTE $55,$55,$15,$15,$05,$05,$01,$01
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $50,$50,$50,$50,$50,$50,$50,$50
.BYTE $00,$00,$00,$00,$55,$55,$55,$55
.BYTE $55,$55,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$55,$55
.BYTE $40,$40,$40,$40,$40,$40,$40,$40
.BYTE $44,$44,$11,$11,$44,$44,$11,$11
.BYTE $01,$01,$01,$01,$01,$01,$01,$01
.BYTE $00,$00,$00,$00,$44,$44,$11,$11
.BYTE $55,$55,$54,$54,$50,$50,$40,$40
.BYTE $01,$01,$01,$01,$01,$01,$01,$01
.BYTE $04,$04,$04,$05,$05,$04,$04,$04
.BYTE $00,$00,$00,$00,$05,$05,$05,$05
.BYTE $04,$04,$04,$05,$05,$00,$00,$00
.BYTE $04,$04,$04,$54,$54,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$55,$55
.BYTE $00,$00,$00,$05,$05,$04,$04,$04
.BYTE $04,$04,$04,$55,$55,$00,$00,$00
.BYTE $00,$00,$00,$55,$55,$04,$04,$04
.BYTE $04,$04,$04,$54,$54,$04,$04,$04
.BYTE $40,$40,$40,$40,$40,$40,$40,$40
.BYTE $50,$50,$50,$50,$50,$50,$50,$50
.BYTE $05,$05,$05,$05,$05,$05,$05,$05
.BYTE $55,$55,$00,$00,$00,$00,$00,$00
.BYTE $55,$55,$55,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$55,$55,$55
.BYTE $01,$01,$01,$01,$01,$01,$55,$55
.BYTE $00,$00,$00,$00,$50,$50,$50,$50
.BYTE $05,$05,$05,$05,$00,$00,$00,$00
.BYTE $04,$04,$04,$54,$54,$00,$00,$00
.BYTE $50,$50,$50,$50,$00,$00,$00,$00
.BYTE $50,$50,$50,$50,$05,$05,$05,$05
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00
.BYTE $00,$00,$00,$00,$00,$00,$00,$00

; Token string table (layout must be exact, do not modify!)

* = $E800

STR_NEW
  .SHIFT "NEW"
STR_LIST
  .SHIFT "LIST"
STR_LOAD
  .SHIFT "LOAD"
STR_SAVE
  .SHIFT "SAVE"
STR_RUN
  .SHIFT "RUN"
STR_REM
  .SHIFT "REM"
STR_IF
  .SHIFT "IF"
STR_THEN
  .SHIFT "THEN"
STR_GOTO
  .SHIFT "GOTO"
STR_GOSUB
  .SHIFT "GOSUB"
STR_RETURN
  .SHIFT "RETURN"
STR_FOR
  .SHIFT "FOR"
STR_TO
  .SHIFT "TO"
STR_NEXT
  .SHIFT "NEXT"
STR_POKE
  .SHIFT "POKE"
STR_INPUT
  .SHIFT "INPUT"
STR_PRINT
  .SHIFT "PRINT"
STR_OPEN
  .SHIFT "OPEN"
STR_CLOSE
  .SHIFT "CLOSE"
STR_READ
  .SHIFT "READ"
STR_RESTORE
  .SHIFT "RESTORE"
STR_DATA
  .SHIFT "DATA"
STR_END
  .SHIFT "END"
STR_SYS
  .SHIFT "SYS"
STR_AT
  .SHIFT "AT"
STR_TAB
  .SHIFT "TAB"
STR_SUB
  .SHIFT "SUB$"
STR_CHR
  .SHIFT "CHR$"
STR_STR
  .SHIFT "STR$"
STR_TI
  .SHIFT "TI"
STR_PEEK
  .SHIFT "PEEK"
STR_RND
  .SHIFT "RND"
STR_NOT
  .SHIFT "NOT"
STR_ABS
  .SHIFT "ABS"
STR_SQR
  .SHIFT "SQR"
STR_AND
  .SHIFT "AND"
STR_OR
  .SHIFT "OR"
STR_XOR
  .SHIFT "XOR"
STR_MOD
  .SHIFT "MOD"
STR_VAL
  .SHIFT "VAL"
STR_LEN
  .SHIFT "LEN"
STR_ASC
  .SHIFT "ASC"
STR_LE
  .SHIFT "<="
STR_GE
  .SHIFT ">="
STR_NE
  .SHIFT "<>"
STR_LT
  .SHIFT "<"
STR_GT
  .SHIFT ">"
STR_EQ
  .SHIFT "="
  
;
; MEMFILL
;
; Sets a range of memory to the current accumulator value. Sets a total of MEMSIZE bytes 
; starting at the address in MEMDPTR. 
;
; Algorithm copied from http://www.6502.org/source/general/memory_move.html.
;
; Uses:
;
;   A             Byte to fill with
;   MEMSPTR       Source pointer
;   MEMDPTR       Destination pointer (modified by operation)
;   MEMSIZE       Bytes to copy (modified by operation)   
;
MEMFILL   PHA
          PHX
          PHY
  
          LDY #0                  ; Handle each group of 256 bytes first before we handle what's left over at the end
          LDX MEMSIZE+1
          BEQ _REST               ; Only 256 bytes or less to begin, so just skip to the end
  
_PAGE     STA (MEMDPTR),Y         ; Set a byte and continue on for 256 bytes
          INY
          BNE _PAGE
          INC MEMDPTR+1           ; Move to the next 256 byte destination address until we've done all of them
          DEX
          BNE _PAGE

_REST     LDX MEMSIZE+0           ; Handle the remaining 256 or fewer bytes (if we have any)
          BEQ _DONE

_BYTE     STA (MEMDPTR),Y         ; Set a byte and continue on until we've done all that's left
          INY
          DEX
          BNE _BYTE

_DONE     PLY
          PLX
          PLA

          RTS

;
; MEMCOPYDN
;
; Copies a region of memory downward. This routine should be used if the destination address
; is lower in memory than the source address. Copies a total of MEMSIZE bytes from MEMSPTR 
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
MEMCOPYDN PHA
          PHX
          PHY
        
          LDY #0
          LDX MEMSIZE+1
          BEQ _REST
        
_PAGE     LDA (MEMSPTR),Y      ; move a page at a time
          STA (MEMDPTR),Y
          INY
          BNE _PAGE
          INC MEMSPTR+1
          INC MEMDPTR+1
          DEX
          BNE _PAGE

_REST     LDX MEMSIZE
          BEQ _DONE

_BYTE     LDA (MEMSPTR),Y      ; move the remaining bytes
          STA (MEMDPTR),Y
          INY
          DEX
          BNE _BYTE

_DONE     PLY
          PLX
          PLA
  
          RTS

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
; SCREENPUT
;
; Puts the single character stored in the accumulator onto the screen at the current
; CURCOL and CURROW position. CURCOL, CURROW, CURSCRPTR, and CURCOLPTR are updated as
; needed.
;
; Interrupts are disabled during this operation because the timer ISR also uses
; these variables to update the screen's cursor.
;
; When the screen is scrolled the MEMCOPYDN and MEMFILL routines are also called and
; will change memory-related zero page variables.
;
; Uses:
;
;   A             Character to store
;   CURCOL        Updated to new position
;   CURROW        Updated to new position
;   CURCOLPTR     Updated to new position
;   CURSCRPTR     Updated to new position
;
SCREENPUT CMP #CHR_CLEAR            ; Clear screen
          BEQ _CLR
          
          CMP #CHR_REVERSE          ; Reverse field
          BEQ _REV
          
          CMP #CHR_NL               ; Newline (advance screen)
          BEQ _NL

          CMP #$F0                  ; Foreground color special character
          BCS _FG
          
          CMP #$E0                  ; Background color special character
          BCS _BG
          
          PHA
          
          PHP                       ; Store flags and disable interrupts (cursor/pointer updates are critical section)
          SEI
          
          STA (CURSCRPTR)           ; Store the character in the screen buffer
          
          PHA                       ; Store the cursor attribute in the color memory buffer
          LDA CURATTR
          STA (CURCOLPTR)
          PLA
          
          INC CURSCRPTR+0           ; Increment screen memory location
          BNE _ATTR
          INC CURSCRPTR+1
  
_ATTR     INC CURCOLPTR+0           ; Increment color memory location
          BNE _DOIT
          INC CURCOLPTR+1
  
_DOIT     LDA CURCOL                ; Increment the cursor x position
          INC A
          STA CURCOL
          CMP #40
          BNE _INT
  
          STZ CURCOL                ; Increment the cursor y position (when needed)
          LDA CURROW
          INC A
          STA CURROW
          CMP #25
          BNE _INT
          
          STZ CURCOL                ; Move the cursor to the start of the last row (0, 24)
          LDA #24
          STA CURROW

          PLP                       ; Out of critical section, copying memory can take a lot of cycles
          
          JMP _SCR                  ; Jump to scroll the memory (moved outside to make branches fit)
          
_INT      PLP                       ; Pull processor flags to re-enable the previous interrupt status

_CHR      PLA                       ; Restore the original accumulator value (the character)
          
          RTS

_CLR      JSR SCREENCLR
          RTS

_REV      LDA CURATTR
          JSR SWAPNIBS
          STA CURATTR
          RTS
          
_NL       JSR SCREENADV
          RTS
     
_FG       PHA
          PHP
          SEI

          ASL A
          ASL A
          ASL A
          ASL A
          
          PHA
          
          LDA CURATTR
          AND #$0F
          STA CURATTR
          
          PLA
          
          ORA CURATTR
          STA CURATTR
          
          PLP
          PLA
          RTS

_BG       PHA
          PHP
          SEI

          AND #$0F
          
          PHA
          
          LDA CURATTR
          AND #$F0
          STA CURATTR
          
          PLA
          
          ORA CURATTR
          STA CURATTR
          
          PLP
          PLA
          RTS   
 
_SCR      LDA #<(SCRRAM+960)        ; Move the cursor pointer to the start of the last row
          STA CURSCRPTR+0
          LDA #>(SCRRAM+960)
          STA CURSCRPTR+1
          
          LDA #<(SCRRAM + 40)       ; Scroll the screen by copying everything up by one row
          STA MEMSPTR+0
          LDA #>(SCRRAM + 40)
          STA MEMSPTR+1
  
          LDA #<SCRRAM
          STA MEMDPTR+0
          LDA #>SCRRAM
          STA MEMDPTR+1
  
          LDA #$C0
          STA MEMSIZE+0
          LDA #$03
          STA MEMSIZE+1

          JSR MEMCOPYDN

          LDA #<(COLRAM+960)        ; Move the color memory pointer to the start of the last row
          STA CURCOLPTR+0
          LDA #>(COLRAM+960)
          STA CURCOLPTR+1
          
          LDA #<(COLRAM + 40)       ; Scroll the color memory by copying everything up by one row
          STA MEMSPTR+0
          LDA #>(COLRAM + 40)
          STA MEMSPTR+1
  
          LDA #<COLRAM
          STA MEMDPTR+0
          LDA #>COLRAM
          STA MEMDPTR+1
  
          LDA #$C0
          STA MEMSIZE+0
          LDA #$03
          STA MEMSIZE+1

          JSR MEMCOPYDN
          
          LDA #<(SCRRAM+960)        ; Fill the last row on the screen with spaces
          STA MEMDPTR+0
          LDA #>(SCRRAM+960)
          STA MEMDPTR+1
  
          LDA #40
          STA MEMSIZE+0
          STZ MEMSIZE+1
          LDA #$20

          JSR MEMFILL
          
          LDA #<(COLRAM+960)        ; Fill the last row of color memory with the current attribute
          STA MEMDPTR+0
          LDA #>(COLRAM+960)
          STA MEMDPTR+1
  
          LDA #40
          STA MEMSIZE+0
          STZ MEMSIZE+1
          LDA CURATTR

          JSR MEMFILL

          JMP _CHR

;
; SCREENDEL
;
; Deletes the current character on the screen, replacing it with a space char.
;
; Uses:
;
;   CURCOL        Updated to new position
;   CURROW        Updated to new position
;   CURCOLPTR     Updated to new position
;   CURSCRPTR     Updated to new position
;
SCREENDEL PHA
          
          DEC CURCOL        ; decrement column
          BPL _DEL
          LDA #39           ; wrapped to previous column
          STA CURCOL
          DEC CURROW        ; decrement row since we wrapped around
          BPL _DEL
          STZ CURCOL        ; wrapped off screen, need to correct that
          INC CURROW
          BRA _DONE

_DEL      LDA #$20          ; clear current cursor position
          STA (CURSCRPTR)
          SEC               ; subtract one from the cursor pointer
          LDA CURSCRPTR+0
          SBC #1
          STA CURSCRPTR+0
          LDA CURSCRPTR+1
          SBC #0
          STA CURSCRPTR+1
          LDA #$20          ; replace the character with the current cursor attributes to clear it
          STA (CURSCRPTR)
          
          LDA CURATTR       ; clear current cursor position
          STA (CURCOLPTR)
          SEC               ; subtract one from the cursor pointer
          LDA CURCOLPTR+0
          SBC #1
          STA CURCOLPTR+0
          LDA CURCOLPTR+1
          SBC #0
          STA CURCOLPTR+1
          LDA CURATTR       ; replace with the current cursor attributes to clear it
          STA (CURCOLPTR)
          
_DONE     PLA
  
          RTS

;
; SCREENCLR
;
; Clears the screen and resets the cursor coordinates and memory buffer position.
;
; Interrupts are disabled during this operation because the timer ISR also uses
; these variables to update the screen's cursor.
;
; Uses the MEMFILL routine internally so additional variables will change as a result.
;
; Uses:
;
;   CURCOL        Updated to new position
;   CURROW        Updated to new position
;   CURCOLPTR     Updated to new position
;   CURSCRPTR     Updated to new position
;
SCREENCLR PHA
  
          PHP                   ; Disable interrupts (critical section)
          SEI
          
          STZ CURCOL            ; Reset the cursor x and cursor y to (0, 0)
          STZ CURROW
          
          STZ TABPOS            ; Reset tab position

          LDA #<SCRRAM          ; Reset the cursor pointer to the start of text memory
          STA CURSCRPTR+0
          LDA #>SCRRAM
          STA CURSCRPTR+1
  
          LDA #<COLRAM          ; Reset the cursor color pointer to the start of color memory
          STA CURCOLPTR+0
          LDA #>COLRAM
          STA CURCOLPTR+1
  
          PLP                   ; Restore interrupts (critical section)
          
          LDA #<SCRRAM          ; Fill the contents of text memory with spaces
          STA MEMDPTR+0
          LDA #>SCRRAM
          STA MEMDPTR+1
          LDA #<1000
          STA MEMSIZE+0
          LDA #>1000
          STA MEMSIZE+1
          LDA #$20
          JSR MEMFILL

          LDA #<COLRAM          ; Fill the contents of color memory with the current attribute
          STA MEMDPTR+0
          LDA #>COLRAM
          STA MEMDPTR+1
          LDA #<1000
          STA MEMSIZE+0
          LDA #>1000
          STA MEMSIZE+1
          LDA CURATTR
          JSR MEMFILL

          PLA

          RTS

;
; SCREENADV
;
; Advances the cursor to the start of the next line. This routine will print spaces
; for any remaining columns in the current row. 
;
; Internally calls SCREENPUT for consistency and to ensure the screen is scrolled. 
; Variables associated with the cursor its position will be updated as a result.
;
SCREENADV PHA
          PHX

          LDA #40           ; Calculate the characters left in the current line
          SEC
          SBC CURCOL
          TAX
          
_LOOP     LDA #$20          ; Print a space for each remaining character in the line
          JSR SCREENPUT
          DEX               ; Continue while we still have spaces remaining to print
          BNE _LOOP
  
          PLX
          PLA

          RTS

;
; SCREENPOS
;
; Sets the current screen position based on the values in the X and Y registers.
; The screen and color memory pointers are also updated.
;
; Interrupts are disabled during this operation because the timer ISR also uses
; these variables to update the screen's cursor.
;
; Uses:
;
;   X             Contains the new cursor X position (starting at 0)
;   Y             Contains the new cursor Y position (starting at 0)
;   CURCOL        Updated to new position
;   CORROW        Updated to new position
;   CURSCRPTR     Updated to new position
;   CURCOLPTR     Updated to new position
;
SCREENPOS PHP                 ; Disable interrupts (entering critical section)
          SEI
          
          CPX #40             ; Ensure X is within bounds
          BCC _XOK
          LDX #39
_XOK      STX CURCOL
          
          CPY #25             ; Ensure Y is within bounds
          BCC _YOK
          LDY #24
_YOK      STY CURROW
          
          LDA #<SCRRAM        ; Start at beginning of screen memory
          STA CURSCRPTR
          LDA #>SCRRAM
          STA CURSCRPTR+1
          
          LDA #<COLRAM        ; Start at beginning of color memory
          STA CURCOLPTR
          LDA #>COLRAM
          STA CURCOLPTR+1
          
          CPY #0              ; If no rows to increment just do the columns
          BEQ _COL
          
_ROW      LDA #40             ; Increment screen pointer by one row
          JSR _ADDSCR
          
          LDA #40             ; Increment color memory pointer by one row
          JSR _ADDCOL
          
          DEY                 ; Next row
          BNE _ROW
                    
_COL      TXA                 ; Screen pointer low byte
          JSR _ADDSCR
          
          TXA                 ; Color memory pointer low byte
          JSR _ADDCOL
          
          PLP                 ; Restore interrupts (leaving critical section)
          
          RTS

_ADDSCR   CLC                 ; Prepare to add to screen pointer

          ADC CURSCRPTR       ; Screen pointer low byte
          STA CURSCRPTR
          
          LDA #0              ; Screen pointer high byte
          ADC CURSCRPTR+1
          STA CURSCRPTR+1

          RTS

_ADDCOL   CLC                 ; Prepare to add to color memory pointer

          ADC CURCOLPTR       ; Color memory pointer low byte
          STA CURCOLPTR
          
          LDA #0              ; Color memory pointer high byte
          ADC CURCOLPTR+1
          STA CURCOLPTR+1

          RTS
          
;
; KEYSCAN
;
; Performs a single scan of the keyboard rows (including joystick rows) and
; updates the KEYROWX zero page variables. Called by the timer ISR.
;
; Uses:
;
;   KEYROWx       Updated with new value for each row
;
KEYSCAN   PHA                   ; Preserve registers
          PHX
          
          STZ VIA_IORA          ; Start at the first row and first key of the keyboard
          LDX #0

_LOOP     LDA VIA_IORA          ; Get the keys for the current row from the VIA port
          LSR A
          LSR A
          LSR A
          STA KEYROW0,X

          INC VIA_IORA          ; Move on to the next keyboard row
          INX
  
          CPX #8                ; Do we have any rows remaining to scan?
          BNE _LOOP
          
          PLX                   ; Restore registers
          PLA
  
          RTS

;
; KEYDECODE
;
; Decodes the contents of the KEYROWX zero page variables into a scan code,
; updating the KEYMODS and KEYCODE zero page variables. You should usually
; call KEYSCAN before calling this to update the key row data first.
;
; Uses:
;
;   KEYROWx       Read to determine the current pressed keys
;   KEYMODS       Updated with current key modifiers
;   KEYCODE       Updated with current key code
;
KEYDECODE PHX                   ; Preserve registers
          PHY

          STZ KEYMODS           ; Reset scan codes and modifiers at start of new scan
          STZ KEYCODE

          LDX #0                ; Start at the first row and first key scan code
          LDY #0

_ROW      LDA KEYROW0,X         ; Load the current row's column bits from zero page
          INX

          PHX                   ; Preserve row index

          LDX #5                ; Loop over current row's columns

_COL      INY                   ; Increment the current key number at the start of each new key

          LSR A                 ; Shift to get the next column bit

          BCS _NEXT             ; If the current column wasn't pressed, just skip to the next column
  
          CPY #KEY_META         ; Is this the META special key?
          BNE _CODY

          PHA                   ; META key is pressed, update current key modifiers
          LDA KEYMODS
          ORA #$20
          STA KEYMODS
          PLA

          BRA _NEXT             ; Continue on to the next column

_CODY     CPY #KEY_CODY         ; Is this the CODY special key?
          BNE _NORM

          PHA                   ; CODY key is pressed, update current key modifiers
          LDA KEYMODS
          ORA #$40
          STA KEYMODS
          PLA

          BRA _NEXT             ; Continue on to the next column

_NORM     PHA                   ; Not a special key so just store it as the current scan code
          TYA
          STA KEYCODE
          PLA

_NEXT     DEX                   ; Move on to the next keyboard column
          BNE _COL

          PLX                   ; Restore current row index

          CPX #6                ; Continue while we have more rows to process      
          BNE _ROW

          LDA KEYCODE           ; Update the current key scan code with the modifiers
          ORA KEYMODS
          STA KEYCODE

          PLY                   ; Restore registers
          PLX

          RTS

;
; KEYTOCHR
;
; Converts a scan code from KEYSCAN into a CODSCII character code. The scan code value in the
; accumulator will be replaced with the CODSCII character code that it represents.
;
; Uses:
;
;   A             Scan code as input, CODSCII character as output
;
KEYTOCHR  PHX
          DEC A
          TAX
          LDA _LOOKUP,X
          PLX
          RTS

_LOOKUP

.BYTE 'Q', 'E', 'T', 'U', 'O'      ; Key scan code mappings without any modifiers
.BYTE 'A', 'D', 'G', 'J', 'L'
.BYTE $00, 'X', 'V', 'N', $00
.BYTE 'Z', 'C', 'B', 'M', $0A
.BYTE 'S', 'F', 'H', 'K', ' '
.BYTE 'W', 'R', 'Y', 'I', 'P'
.BYTE $00, $00

.BYTE '!', '#', '%', '&', '('      ; Key scan code mappings with META modifier
.BYTE '@', '-', ':', $27, ']'
.BYTE $00, '<', ',', '?', $00
.BYTE '\', '>', '.', '/', $08
.BYTE '=', '+', ';', '[', ' '
.BYTE '"', '$', '^', '*', ')'
.BYTE $00, $00

.BYTE '1', '3', '5', '7', '9'      ; Key scan code mappings with CODY modifier
.BYTE 'A', 'D', 'G', 'J', 'L'
.BYTE $00, 'X', 'V', 'N', $1B
.BYTE 'Z', 'C', 'B', 'M', $18
.BYTE 'S', 'F', 'H', 'K', ' '
.BYTE '2', '4', '6', '8', '0'
.BYTE $00, $00

;
; MUL16
;
; Multiplies 16 bit integers in NUMONE and NUMTWO and stores the result in NUMANS.
;
; This code was taken from Neil Parker's "Multiplying and Dividing on the 6502" at 
; http://nparker.llx.com/a2/mult.html. Minor modifications were made for preserving
; registers across calls and for ignoring the highest (3rd) byte of the result.
;
; Uses:
;
;   NUMONE        The first argument to multiply by (clobbered by routine)
;   NUMTWO        The second argument to multiply by (clobbered by routine)
;   NUMANS        The result of the multiplication
;     
MUL16     PHA
          PHX
          PHY
          
          LDA #0
          STA NUMANS+2
          LDX #16
          
_L1       LSR NUMTWO+1
          ROR NUMTWO
          BCC _L2
          TAY
          CLC
          LDA NUMONE
          ADC NUMANS+2
          STA NUMANS+2
          TYA
          ADC NUMONE+1

_L2       ROR A
          ROR NUMANS+2
          ROR NUMANS+1
          ROR NUMANS
          DEX
          BNE _L1
          
          PLY
          PLX
          PLA
          
          RTS

;
; MOD16
;
; Calculates the result of NUMONE modulo NUMTWO and stores the result in NUMANS. The
; quotient remains in NUMONE when completed (and can be used for division as a result).
;
; NUMTWO must be nonzero or a logic error is raised to indicate division by zero.
;
; This code was taken from Neil Parker's "Multiplying and Dividing on the 6502" at 
; http://nparker.llx.com/a2/mult.html. Minor modifications were made for preserving
; registers across calls. A divide-by-zero check was also added.
;
; Uses:
;
;   NUMONE        The first argument for the modulo calculation (will contain quotient)
;   NUMTWO        The second argument for the modulo calculation by (clobbered by routine)
;   NUMANS        The result of NUMONE modulo NUMTWO
;     
MOD16     LDA NUMTWO          ; See if the low byte of the second argument is nonzero
          BNE _OK
          
          LDA NUMTWO+1        ; See if the high byte of the second argument is nonzero
          BNE _OK
          
          JMP RAISE_LOG       ; Raise a logic error for divide by zero
          
_OK       PHA
          PHX
          PHY
          STZ NUMANS
          STZ NUMANS+1
          LDX #16         ; There are 16 bits in NUMONE

_L1       ASL NUMONE      ; Shift hi bit of NUMONE into NUMANS
          ROL NUMONE+1    ; (vacating the lo bit, which will be used for the quotient)
          ROL NUMANS
          ROL NUMANS+1
          LDA NUMANS
          SEC             ; Trial subtraction
          SBC NUMTWO
          TAY
          LDA NUMANS+1
          SBC NUMTWO+1
          BCC _L2         ; Did subtraction succeed?
          STA NUMANS+1    ; If yes, save it
          STY NUMANS
          INC NUMONE      ; and record a 1 in the quotient

_L2       DEX
          BNE _L1
          PLY
          PLX
          PLA
          RTS

;
; PRE16
;
; Prepares NUMONE and NUMTWO prior to a 16-bit signed multiplication or modulus
; operation. Both registers are converted to positive NUMTWOers and the result's
; sign bit is put in the accumulator.
;
; This code was taken from Neil Parker's "Multiplying and Dividing on the 6502" at 
; http://nparker.llx.com/a2/mult.html.
;
; Uses:
;
;   A             Puts the result's sign bit into the accumulator
;   NUMONE        The first argument to adjust
;   NUMTWO        The second argument to adjust
;
PRE16     LDA NUMONE+1    ; calculate and store sign bit in result
          EOR NUMTWO+1
          AND #$80
          PHA
          LDA NUMONE+1    ; adjust NUMONE to positive if negative
          BPL _NUMTWO
          SEC
          LDA #0
          SBC NUMONE
          STA NUMONE
          LDA #0
          SBC NUMONE+1
          STA NUMONE+1
          
_NUMTWO   LDA NUMTWO+1    ; adjust NUMTWO to positive if negative
          BPL _DONE
          SEC
          LDA #0
          SBC NUMTWO
          STA NUMTWO
          LDA #0
          SBC NUMTWO+1
          STA NUMTWO+1

_DONE     PLA
          RTS

;
; ADJ16
;
; Adjusts the sign of NUMANS following a 16-bit signed multiplication or modulus
; operation. The value in the accumulator should contain the sign calculated in
; the prior call to PRE16 made before performing the operation.
;
; This code was taken from Neil Parker's "Multiplying and Dividing on the 6502" at 
; http://nparker.llx.com/a2/mult.html.
;
; Uses:
;
;   A             Puts the result's sign bit into the accumulator
;   NUMANS        Result to adjust
;
ADJ16     CMP #0        ; see if we need to adjust (have a sign bit?)
          BEQ _DONE
          SEC           ; negate the result
          LDA #0
          SBC NUMANS
          STA NUMANS
          LDA #0
          SBC NUMANS+1
          STA NUMANS+1
_DONE     RTS

;
; RND16
;
; Generates a new pseudorandom number between 0 and 255 in NUMANS based on the
; previous value in RANDOML and RANDOMH.
;
; This code was taken from https://wiki.nesdev.com/w/index.php/Random_number_generator.
; From the description: "This is a 16-bit Galois linear feedback shift register with
; polynomial $0039. The sequence of numbers it generates will repeat after 65535 calls."
;
; Note that if the seed value in RANDOML and RANDOMH is zero then the default value 
; in RAND_SEED will be loaded instead.
;
; Uses:
; 
;   NUMANS        Stores the next random value from 1 to 255 (high byte zeroed)
;   RANDOML       Low byte of random number seed, updated
;   RANDOMH       High byte of random number seed, updated
;
RND16     PHA             ; Preserve registers
          PHY

          LDA RANDOML     ; Ensure seed number wasn't zero
          BNE _CALC
          
          LDA RANDOMH
          BNE _CALC
          
          LDA #<RAND_SEED ; Otherwise override with the default value
          STA RANDOML
          
          LDA #>RAND_SEED
          STA RANDOMH
                    
_CALC     LDY #8          ; Loop 8 times to generate 8 bits
          LDA RANDOML
          
_LOOP     ASL A           ; Perform shift
	        ROL RANDOMH
          
	        BCC _SKIP       ; If we shifted a bit out, apply the feedback
	        EOR #$39

_SKIP     DEY             ; Next loop
	        BNE _LOOP
          
	        STA RANDOML     ; Update low byte of seed
          
          STA NUMANS      ; Store result
          STZ NUMANS+1
          
          PLY             ; Restore registers
          PLA
          
          RTS

;
; SQR16
;
; Calculates the square root of an unsigned 16-bit number stored in NUMONE. The result
; without remainder is returned in NUMANS.
;
; This code was taken from http://6502org.wikidot.com/software-math-sqrt where a good
; description of the algorithm can also be found.
;
; Uses:
;
;   NUMONE        Unsigned integer to find the square root of
;   NUMANS        Resulting square root of the calculation
;
SQR16     PHA             ; Preserve registers
          PHX
          PHY
          
          STZ NUMANS      ; Zero out answer
          STZ NUMANS+1
          
          LDX #8          ; Repeat 8 times for 16-bit calculation
          
_LOOP     SEC             ; Main calculation
          LDA NUMONE+1
          SBC #$40
          TAY
          LDA NUMANS+1
          SBC NUMANS
          BCC _SKIP
          STY NUMONE+1    ; Update when carry set
          STA NUMANS+1

_SKIP     ROL NUMANS      ; Shift in next two digits
          ASL NUMONE
          ROL NUMONE+1
          ROL NUMANS+1
          ASL NUMONE
          ROL NUMONE+1
          ROL NUMANS+1
          DEX
          BNE _LOOP
          STZ NUMANS+1
  
          PLY             ; Restore registers
          PLX
          PLA
          
          RTS             ; All done

;
; TOLOWER
;
; Converts the value in the accumulator to a lowercase CODSCII character if the 
; character is uppercase.
;
; Uses:
;
;   A             CODSCII code as input, will be converted to lowercase if needed.
;
TOLOWER   CMP #$41                ; Character isn't uppercase if less than 'A'
          BCC _DONE

          CMP #$7B                ; Character isn't uppercase if greater or equal to '{'
          BCS _DONE

          CLC                     ; Adjust uppercase character to lowercase
          ADC #$20

_DONE     RTS

;
; TOUPPER
;
; Converts the value in the accumulator to an uppercase CODSCII character if the 
; character is lowercase.
;
; Uses:
;
;   A             CODSCII code as input, will be converted to uppercase if needed.
;
TOUPPER   CMP #$61                ; Character isn't lowercase if less than 'A'
          BCC _DONE
  
          CMP #$7B                ; Character isn't lowercase if greater or equal to '['
          BCS _DONE
  
          SEC                     ; Adjust lowercase character to uppercase
          SBC #$20
  
_DONE     RTS

;
; TONUMBER
;
; Parses a decimal number into NUMANS. The characters for the number are read from MEMSPTR
; starting at the current Y register position, and the Y register is updated as characters
; are read from the string. MUL16 is called to perform parts of the calculation.
;
; Note that this routine does NOT handle negative numbers. To parse a negative number the
; caller will need to handle the unary minus, parse, and then negate the result in NUMANS.
;
; Uses:
;   
;   Y             The position within the string to begin parsing (updated by routine)
;   NUMANS        The parsed number
;   MEMSPTR       The pointer to the string to parse
;   NUMONE        Used internally for calculations
;   NUMTWO        Used internally for calculations
;
TONUMBER  PHA                 ; Preserve accumulator
  
          STZ NUMONE+0        ; Clear out the starting number value
          STZ NUMONE+1

_LOOP     LDA #10             ; Prepare to multiply by ten on each loop (to handle each digit)
          STA NUMTWO+0
          STZ NUMTWO+1
  
          JSR MUL16           ; Multiply the number to prepare for the next digit
  
          LDA (MEMSPTR),Y     ; Read the next character and handle it if it's a digit
          JSR ISDIGIT
          BCC _DONE
          
          INY                 ; Increment the position
          
          SEC                 ; Adjust the character to its corresponding numeric value (0 through 9)
          SBC #$30
  
          CLC                 ; Add the new ones digit to the multiplied result before the next loop
          ADC NUMANS+0
          STA NUMONE+0
          LDA NUMANS+1
          ADC #0
          STA NUMONE+1
  
          BRA _LOOP           ; Loop and process next digit

_DONE     LDA NUMONE+0        ; Copy result
          STA NUMANS+0
          LDA NUMONE+1
          STA NUMANS+1
  
          PLA                 ; Restore accumulator

          RTS

;
; TOSTRING
;
; Writes the integer value of NUMONE into the output buffer (OBUF) starting at
; the end of the buffer (OBUFLEN). The PUTOUT routine is called to store each
; digit and will enforce bounds checking on the buffer. The MOD16 routine is used
; to perform calculations to extract the digits.
;
; The route works by pushing a NUL char to mark the end, then dividing by ten with
; remainder to calculate the digits and push them on the stack in reverse order. When
; done we just pop each char off the stack and store it into the output buffer.
;
; Uses:
;
;   OBUF          Digits are written to the output buffer
;   OBUFLEN       The position to append the digits at (will be updated)
;   NUMONE        The unsigned number to convert to a string
;   NUMTWO        Used internally for calculations
;   NUMANS        Used internally for calculations
;
TOSTRING  PHA
          
          LDA #0                ; Push a NUL char to mark the end
          PHA

_LOOP     LDA #10               ; Divide by 10 once with remainder
          STA NUMTWO
          STZ NUMTWO+1
          JSR MOD16
          
          CLC                   ; Convert remainder to digit
          LDA NUMANS
          ADC #$30
          PHA                   ; Push digit on stack
          
          LDA NUMONE+1          ; If high byte is nonzero, more digits remain
          BNE _LOOP
          
          LDA NUMONE            ; If low byte is nonzero, more digits remain
          BNE _LOOP

_CHR      PLA                   ; Pull digits off the stack and print them until NUL char
          BEQ _END
          
          JSR PUTOUT            ; Write each character
          
          BRA _CHR              ; Move on to the next digit

_END      PLA                   ; Restore accumulator and return
          RTS

;
; ISSPACE
;
; Tests if the value in the accumulator is a CODSCII space character. Sets the carry
; flag if a space and clears the carry flag otherwise.
;
; Uses:
;
;   A             CODSCII character
;
ISSPACE   CMP #CHR_TAB
          BEQ _YES
  
          CMP #CHR_NL
          BEQ _YES
  
          CMP #CHR_CR
          BEQ _YES

          CMP #CHR_SPACE
          BEQ _YES
  
          CLC                     ; Not a space, clear carry and return
          RTS
  
_YES      SEC                     ; Found a space, set carry and return
          RTS

;
; ISDIGIT
;
; Tests if the value in the accumulator is a CODSCII digit character. Sets the carry
; flag if a digit and clears the carry flag otherwise.
;
; Uses:
;
;   A             CODSCII character
;
ISDIGIT   CMP #$30                ; Character isn't digit if less than '0'
          BCC _NOT
  
          CMP #$3A                ; Character isn't digit if greater or equal to ':'
          BCS _NOT
  
          SEC                     ; Found a digit, set carry and return
          RTS
  
_NOT      CLC                     ; Not a digit, clear carry and return
          RTS

;
; PUTOUT
;
; Puts the character in the accumulator into the output buffer (OBUF) at the current
; position (OBUFLEN). The buffer length is updated with each operation. If the buffer
; overflows a system error is raised.
;
; Uses:
;
;   A             Accumulator containing the character to write into the buffer
;   OBUF          Updated with the character to write into the buffer
;   OBUFPOS       Updated with the new length of the buffer
;
PUTOUT    PHY                     ; Preserve the Y register
          
          LDY OBUFLEN             ; Fetch the current output buffer length
          
          CPY #$FF                ; Buffer overflow?
          BEQ _SYS
          
          STA OBUF,Y              ; Store value in buffer
          
          INC OBUFLEN             ; Increment the output buffer length
          
          INC TABPOS              ; Increment the tab position
          
          CMP #CHR_NL             ; Reset tab position on newlines
          BNE _DONE
          
          STZ TABPOS              ; Clear tab position
          
_DONE     PLY                     ; Restore the Y register
          
          RTS                     ; Done

_SYS      JMP RAISE_SYS           ; Indicate a buffer overflow

;
; PUTMSG
;
; Puts one of the messages from the message table into the output buffer. The
; message number should be stored in the accumulator. PUTOUT is called to copy
; each character with bounds checking.
;
; Uses:
;
;   A             Accumulator containing the message number to print
;   OBUF          Updated with the character to write into the buffer
;   OBUFPOS       Updated with the new length of the buffer
;   MEMSPTR       Used internally to store the pointer to the string to print
;
PUTMSG    PHA                     ; Preserve registers
          PHY
      
          TAY                     ; Use value in accumulator as message number to print
          
          LDA MSGTABLE_L,Y        ; Get message string low byte
          STA MEMSPTR
          
          LDA #MSGTABLE_H         ; Calculate message string high byte
          CPY #MSG_TOKENS
          BCC _HIBYTE
          LDA #TOKTABLE_H
_HIBYTE   STA MEMSPTR+1

          LDY #0                  ; Start at beginning of the string

_LOOP     LDA (MEMSPTR),Y         ; Load the next character
          
          BIT #$80                ; Test top bit to see if this is the last char
          PHP

          AND #$7F                ; Put the character into the output buffer
          JSR PUTOUT

          INY                     ; Increment position in string

          PLP                     ; Was this the last char?
          BEQ _LOOP

_END      PLY                     ; Restore registers
          PLA
          
          RTS

;
; SERIALON
;
; Turns on UART 1 or UART 2 based on the parameters in IOMODE and IOBAUD after
; cleaning out related memory locations. The matching SERIALOFF routine should
; be called when serial operations are completed.
;
; If the IOMODE is invalid a system error is raised.
;
; Uses:
;
;   IOMODE        The IO mode (1 for UART 1 or 2 for UART 2)
;   IOBAUD        The baud rate from 0 (none) to 15 (19200)
;   UARTPTR       Pointer variable used to access UART registers
;
SERIALON  PHA
          PHY
          
          LDA IOMODE              ; What UART are we using?
          CMP #1
          BEQ _UART1
          BCS _UART2
          
          JMP RAISE_SYS           ; Indicate an IO error (should never happen!)
          
_UART1    LDA #<UART1_BASE        ; Running UART 1
          STA UARTPTR
          LDA #>UART1_BASE
          STA UARTPTR+1
          
          BRA _INIT
        
_UART2    LDA #<UART2_BASE        ; Running UART 2
          STA UARTPTR
          LDA #>UART2_BASE
          STA UARTPTR+1   
          
_INIT     LDA #0
          
          LDY #UART_RXTL          ; Clear out buffer registers
          STA (UARTPTR),Y
          
          LDY #UART_TXHD
          STA (UARTPTR),Y
          
          LDA IOBAUD              ; Set baud rate
          AND #$0F
          LDY #UART_CNTL
          STA (UARTPTR),Y
          
          LDA #01                 ; Enable UART
          LDY #UART_CMND
          STA (UARTPTR),Y
          
          LDY #UART_STAT          ; Wait for UART to start up
_WAIT     LDA (UARTPTR),Y
          AND #$40
          BEQ _WAIT
          
          PLY
          PLA
          
          RTS                     ; All done
          
;
; SERIALOFF
;
; Turns off the current UART based on the value in IOMODE. The routine will
; wait for any pending bits to be sent out (but not for incoming bits). It
; also waits to ensure the UART has actually stopped by checking the relevant
; status register bits.
;
; Uses:
;
;   IOMODE        The IO mode (1 for UART 1 or 2 for UART 2)
;   UARTPTR       Pointer variable used to access UART registers
;
SERIALOFF PHA
          PHY

          LDA IOMODE              ; Special check in case this was called incorrectly
          BEQ _DONE

_WAITBUF  LDY #UART_TXHD          ; Wait for any pending characters to transmit
          LDA (UARTPTR),Y
          LDY #UART_TXTL
          CMP (UARTPTR),Y
          BNE _WAITBUF
          
          LDY #UART_STAT          ; Wait for any pending byte to be sent out
_WAITBIT  LDA (UARTPTR),Y
          AND #$10
          BNE _WAITBIT

_SHUTOFF  LDA #0
          LDY #UART_CMND
          STA (UARTPTR),Y         ; Clear bit to stop UART

          LDY #UART_STAT
_WAITOFF  LDA (UARTPTR),Y         ; Wait for UART to stop
          AND #$40
          BNE _WAITOFF
          
_DONE     PLY
          PLA
          
          RTS

;
; SERIALPUT
;
; Puts the byte in the accumulator out via the UART selected by IOMODE. If the UART's
; ring buffer for sending data is full the routine waits until space is freed as bytes
; are sent.
;
; SERIALON must be called prior to this routine. If not, the routine will lock up once
; the send buffer is full.
;
; Uses:
;
;   A             The byte to send
;   UARTPTR       Pointer variable used to access UART registers
;
SERIALPUT PHA
          PHX
          PHY
          
          PHA                     ; Preserve character to store
          
_WAIT     LDY #UART_TXHD          ; Get current head position
          LDA (UARTPTR),Y
          
          INC A                   ; Increment by one (to test if overflow)
          AND #$07
          
          LDY #UART_TXTL          ; Compare to current tail position (equals means we overflow!)
          CMP (UARTPTR),Y
          BEQ _WAIT
          
          TAX                     ; Store new head position (we'll need it really soon)
          
          LDY #UART_TXHD          ; Use current head position to calculate offset
          CLC
          LDA (UARTPTR),Y
          ADC #UART_TXBF
          TAY
          
          PLA                     ; Store character in buffer
          STA (UARTPTR),Y
                    
          LDY #UART_TXHD          ; Update head position
          TXA
          STA (UARTPTR),Y
                    
          PLY
          PLX
          PLA
          
          RTS

;
; SERIALGET
;
; Reads a byte from the current UART into the accumulator. If the receive buffer has a 
; byte then the byte is returned in the accumulator and the carry flag is set. If the
; receive buffer is empty then the carry is cleared to indicate this.
;
; If a framing error (bit 1) or overrun (bit 2) are detected in the status register,
; the routine raises a system error.
;
; SERIALON should be called prior to calling this routine.
;
; Uses:
;
;   A             The received byte, if any
;   P             Carry set when a byte is read, cleared when no byte is read
;   UARTPTR       Pointer variable used to access UART registers
;
SERIALGET PHY
          
          LDY #UART_STAT          ; Get current status register
          LDA (UARTPTR),Y
          
          BIT #$06                ; Test that no error bits are set
          BNE _SYS
          
          LDY #UART_RXTL          ; Get current tail position
          LDA (UARTPTR),Y
                    
          LDY #UART_RXHD          ; Compare to head position
          CMP (UARTPTR),Y

          BEQ _EMPTY              ; If they match then the buffer is empty
          
          CLC                     ; Calculate the buffer position and read the character
          ADC #UART_RXBF
          TAY
          LDA (UARTPTR),Y
          
          PHA                     ; Keep the character around for later
          
          LDY #UART_RXTL          ; Update tail position since we read from the buffer
          LDA (UARTPTR),Y
          INC A
          AND #$07
          STA (UARTPTR),Y
          
          PLA                     ; Pull the character we read off the stack
                    
          PLY
          SEC                     ; Set carry to indicate a character was read
          RTS
  
_EMPTY    PLY
          CLC                     ; Clear carry to indicate no character read
          RTS

_SYS      JMP RAISE_SYS           ; Indicate we detected an IO error

;
; FLUSH
;
; Flushes the current contents of the output buffer (OBUF of OBUFLEN characters) to the
; currently selected output (according to IOMODE).
;
; Uses:
;
;   IOMODE        Read to determine the current IO mode.
;   OBUF          Updated with the character to write into the buffer
;   OBUFPOS       Updated with a value of zero when done
;
FLUSH     PHA                     ; Preserve registers
          PHX
          PHY
          
          LDY IOMODE              ; We'll be checking the IO mode a lot

          LDX #0                  ; Start at the beginning

_LOOP     CPX OBUFLEN             ; Check that we have more characters to print
          BEQ _END
          
          LDA OBUF,X              ; Load the next character from the output buffer
          INX

          CPY #0                  ; Determine whether to use screen or serial output
          BEQ _SCREEN
          
_SERIAL   JSR SERIALPUT           ; Print it to the serial port (current UART)
          BRA _LOOP
          
_SCREEN   JSR SCREENPUT           ; Print it on the screen
          BRA _LOOP
          
_END      STZ OBUFLEN             ; Clear the length of the output buffer (we're empty now)

_NOOFF    PLY                     ; Restore registers
          PLX
          PLA
          
          RTS                     ; All done

;
; ISALPHA
;
; Tests if the value in the accumulator is a CODSCII alpha character (uppercase or lowercase).
; Sets the carry flag if an alpha character and clears the carry flag otherwise.
;
; Uses:
;
;   A             CODSCII character
;   P             Carry flag set if alpha char, cleared if not.
;
ISALPHA   CMP #$41                ; Character isn't letter if less than 'A'
          BCC _NOT
  
          CMP #$5B                ; Character isn't uppercase letter if greater or equal to '['
          BCS _LOW
  
          BRA _YES                ; Found a letter
  
_LOW      CMP #$61                ; Character isn't lowercase letter if less than 'a'
          BCC _NOT
  
          CMP #$7B                ; Character isn't lowercase letter if greater or equal to '{'
          BCS _NOT
  
_YES      SEC                     ; Found a letter, set carry and return
          RTS
  
_NOT      CLC                     ; Not a letter, clear carry and return
          RTS

;
; READKBD
;
; Reads the keyboard into the input buffer (IBUF) and updates the length (IBUFLEN) in the
; buffer. Screen contents will be updated as the user presses keys. The routine will not
; return until a carriage return is read. The routine depends on many other routines to
; decode keypresses and update the screen as data is entered.
;
; For this routine to function, the timer ISR must be running and scanning the keyboard.
; The routine waits for the jiffies count to be updated and then decodes any key press.
;
; Uses:
;
;   IBUF          Input buffer updated with text (including ending carriage return)
;   IBUFLEN       Input buffer length (including ending carriage return)
;   JIFFIES       Watched to determine when the timer ISR has executed
;   KEYCODE       Current key scan code (updated)
;   KEYDEBO       Variable used to assist in debouncing key presses (updated)
;   KEYLAST       The last key read, used to suppress multiple key presses (updated)
;
READKBD   PHA                   ; Preserve registers
          PHX
          
          LDX #0                ; Start at beginning of input buffer
                    
_NEXT     LDA JIFFIES

_WAIT     JSR BLINK             ; Wait for jiffies to change to know we got a new keyboard scan
          CMP JIFFIES
          BEQ _WAIT

          JSR KEYDECODE         ; Decode whatever key was pressed (if anything)
          
          LDA KEYCODE           ; Debounce keys by making sure we read the same code twice in a row
          CMP KEYDEBO
          STA KEYDEBO
          BNE _NEXT
          
          LDA KEYCODE           ; Suppress repeated key presses by comparing to last key read
          CMP KEYLAST
          STA KEYLAST
          BEQ _NEXT
  
          CMP #$60              ; Check for CODY + META (shift lock) toggle
          BEQ _TOG
  
          BIT #$1F              ; Suppress key codes when no keys (aside from modifiers) were pressed
          BEQ _NEXT
  
          JSR KEYTOCHR          ; Convert key code to CODSCII code and preserve on stack
          PHA
  
          LDA KEYLOCK           ; Check if the shift lock is set
          BEQ _KEY
  
          PLA                   ; Convert CODSCII code to lowercase
          JSR TOLOWER
          PHA

_KEY      PLA                   ; Restore keyboard CODSCII code from stack
          
          CMP #CHR_CAN          ; Skip cancel character
          BEQ _NEXT
  
          CMP #CHR_BS           ; Check for backspace character
          BEQ _DEL
  
          CPX #$FE              ; Check for space to store character
          BEQ _NEXT
  
          STA IBUF,X            ; Put the character in the buffer
          INX
          
          CMP #CHR_NL           ; Check for newline character (end of line)
          BEQ _DONE
          
          JSR SCREENPUT         ; Echo to the screen

          BRA _NEXT
  
_DEL      CPX #0                ; Check that we have something in the buffer to delete
          BEQ _NEXT
          
          DEX                   ; Back up one position the buffer and remove the char from the screen
          JSR SCREENDEL
  
          BRA _NEXT
  
_TOG      LDA KEYLOCK           ; Toggle shift lock
          EOR #$01
          STA KEYLOCK
          
          BRA _NEXT
          
_DONE     STX IBUFLEN           ; Update input buffer length
          
          LDA #20               ; TODO: CLEAR BLINKING CURSOR (MAKE THIS BETTER, ALSO SEE ABOVE)
          STA (CURSCRPTR)
          
          PLX                   ; Restore registers
          PLA
          
          RTS

;
; READSER
;
; Reads a line from a UART into IBUF and updates IBUFLEN. The SERIALxxx routines are used
; to read a line of text into the buffer. 
;
; This routine is essentially the serial equivalent of READKBD. You must call SERIALON
; before using this routine and remember to call SERIALOFF when finished.
;
; To facilitate compatiblity across operating systems both newlines and carriage returns
; can end a line. However, no translation between endings is performed.
;
; If the input buffer overflows then a system error is raised.
;
; Uses:
;
;   IBUF          Input buffer updated with text (including ending newline/return)
;   IBUFLEN       Input buffer length (including ending newline/return)   
;
READSER   PHA
          PHX
          
          LDX #0                ; Start at beginning of buffer
          
_READ     JSR SERIALGET         ; Poll for next character
          BCC _READ             
          
          STA IBUF,X            ; Store the character and increment the buffer position
          INX
          
          CPX #$FE              ; Do we still have space in the buffer?
          BCS _SYS
          
          CMP #CHR_NL           ; Newline characters can be an end of line
          BEQ _DONE
          
          CMP #CHR_CR           ; Carriage return characters can be an end of line
          BEQ _DONE
          
          BRA _READ             ; Continue
          
_DONE     STX IBUFLEN           ; Store the input line length
          
          PLX
          PLA
          
          RTS
          
_SYS      JMP RAISE_SYS         ; Indicate we're out of space in the input buffer

;
; TOKENIZE
;
; Tokenizes the contents in the input buffer (IBUF) and places the result into the token
; buffer (TBUF). Tokenized strings can then be evaluated directly or inserted into the
; program if they start with a line number. The tokenizer is built around specific tests
; combined with a binary search for matching keyword tokens.
;
; The routine checks the bounds on TBUF but assumes IBUF is correctly terminated with a
; carriage return. If the token buffer overflows a system error is raised.
;
; IMPORTANT: If new tokens are added to Cody Basic, the _TOKTABLE in this routine must
; also be updated. Failure to do so will break the binary search at the core of the
; tokenization process.
;
; A tokenized line has the following layout:
;
; [<SZ> <LO> <HI>] <data bytes> <NL>
;
; Where SZ is the size of the line in bytes, LO is the lower byte of the line
; number, HI is the higher byte of the line number, and NL is the ASCII newline.
; The SZ, LO, and HI values will not be present in tokenized lines entered in immediate
; mode (to be executed rather than inserted into a program).
;
; The data bytes are tokenized. Tokens from the table have their high-most bit set.
;
; Note that tokenized lines beginning with a line number will NOT have their size
; prepended at the start of the line by this routine. The caller must check that the
; line begins with a number and patch the first byte with the TBUFLEN value before
; inserting it into the program.
;
; Numeric tokens have the following layout:
;
; <$FF> <LO> <HI>
;
; Where $FF is the token indicating a number is coming up, LO is the lower byte
; of the number, and HI is the higher byte of the number.
;
; String tokens begin and end with double-quote characters:
;
; <$22> <chars> <$22>
;
; Where $22 is the ASCII double-quote character. Note that this means string
; literals cannot contain double-quotes.
;
; Uses:
;
;   IBUF          Input buffer where the string to be tokenized is read from
;   TBUF          Token buffer updated with the tokenized string
;   TBUFLEN       Token buffer length updated with the length of the string
;   MEMSPTR       Used internally for token matching
;   MEMDPTR       Used internally for token matching
;   TOKENIZEL     Left bound for binary search when matching tokens
;   TOKENIZER     Right bound for binary search when matching tokens
;
TOKENIZE  PHA                 ; Preserve registers
          PHX
          PHY

          LDX #0              ; Use X for position in IBUF, Y for position in TBUF
          LDY #0

_SKIP     LDA IBUF,X          ; Check for leading space

          CMP #CHR_NL         ; Newlines are significant to us so exclude them
          BEQ _LOOP
          
          JSR ISSPACE         ; Otherwise check for non-space characters
          BCC _LOOP

          INX                 ; Consume whitespace character and repeat
          BRA _SKIP

_LOOP     LDA IBUF,X          ; Load the next character
  
          CMP #CHR_NL         ; End of line?
          BEQ _END
  
          CMP #CHR_QUOTE      ; String?
          BEQ _STR

          JSR ISALPHA         ; Letter?
          BCS _LET
          
          JSR ISDIGIT         ; Digit?
          BCS _NUM
          
          CMP #CHR_LESS       ; Rule out relational operator ranges
          BCC _CHR
          
          CMP #CHR_QUEST
          BCS _CHR
          
          JMP _OPR            ; Relational operators handled as special case

_CHR      LDA IBUF,X          ; Load character

          JSR TOUPPER         ; Convert to uppercase

          JSR _PUT            ; Store the character

          INX                 ; Increment input buffer position

          BRA _LOOP           ; Next character

_END      JSR _PUT            ; Store the carriage return as the last character in the line

          STY TBUFLEN         ; Update the token buffer length
          
          PLY                 ; Restore registers
          PLX
          PLA
          
          RTS
              
_STR      LDA IBUF,X          ; Load the starting quote
  
          JSR _PUT            ; Store starting quote

          INX                 ; Increment input buffer position

_STRLOOP  LDA IBUF,X          ; Load the next character
          
          INX                 ; Increment input buffer position
          
          JSR _PUT            ; Store the character
  
          CMP #CHR_QUOTE      ; If it was a quote, we're done tokenizing the string
          BEQ _LOOP
  
          CMP #CHR_NL         ; If it was NOT a newline, continue on
          BNE _STRLOOP
  
          DEX                 ; Move back in both buffers to "unread" the carriage return
          DEY
          
          LDA #CHR_QUOTE      ; We had a carriage return in a string, so close the string
          JSR _PUT
          
          JMP _LOOP           ; Next character in input buffer

_LET      INX                 ; Look ahead one character
          LDA IBUF,X
          DEX
          
          JSR ISALPHA         ; If also a letter then parse as token, otherwise char
          BCS _TOK
          BRA _CHR
          
_NUM      LDA #<IBUF          ; Input buffer lower byte
          STA MEMSPTR
          
          LDA #>IBUF          ; Input buffer high byte
          STA MEMSPTR+1

          PHY                 ; Preserve current token buffer position
          
          TXA                 ; Move the current input buffer position into the y-register
          TAY
          
          JSR TONUMBER        ; Parse the number
          
          TYA                 ; Move the updated input buffer position back into the x-register
          TAX
        
          PLY                 ; Restore the token buffer position off the stack
          
          LDA #$FF            ; Write the sentinel value for a number token
          JSR _PUT
          
          LDA NUMANS          ; Store number low byte
          JSR _PUT
          
          LDA NUMANS+1        ; Store number high byte
          JSR _PUT
          
          JMP _LOOP

_TOK      PHX                 ; Preserve our registers before beginning the token matching
          PHY
          
          TXA                 ; Lower byte is the current buffer position (assumes page alignment)
          STA MEMSPTR
          
          LDA #>IBUF          ; Upper byte is the page of the input buffer (assumes page alignment)
          STA MEMSPTR+1

          STZ TOKENIZEL       ; Prepare for binary search
          LDA #(_TOKTABLEEND - _TOKTABLE)
          STA TOKENIZER
          
_TOKNEXT  LDA TOKENIZER       ; Are we done yet? (top value wrapped around)
          BMI _TOKNONE

          LDA TOKENIZEL       ; Are we done yet? (L <= R)
          CMP TOKENIZER

          BCC _TOKCOMP
          BEQ _TOKCOMP
          
_TOKNONE  PLY                 ; Restore token buffer (Y) and input buffer (X) positions
          PLX
          
          JMP _CHR            ; Process as normal character
                    
_TOKCOMP  CLC                 ; Calculate our position in the token lookup table
          LDA TOKENIZEL
          ADC TOKENIZER
          LSR A
          TAX
          
          PHX
          
          LDA _TOKTABLE,X     ; Get the token's matching index in the string table
          TAX
          
          LDA TOKTABLE_L,X    ; Put the token's address in the memory destination pointer
          STA MEMDPTR
          LDA #TOKTABLE_H
          STA MEMDPTR+1
          
          PLX
          
          LDY #$00            ; Use the y register for our position in the strings
          
_TOKCHAR  LDA (MEMDPTR),Y     ; Get the destination char and test the high bit for the end of string
          BIT #$80
          PHP
          
          AND #$7F            ; Mask out the valid portion of the char for later comparision
          STA TOKENIZEC

          LDA (MEMSPTR),Y     ; Get the next character from the input string and UPPERCASE it
          JSR TOUPPER
          
          CMP TOKENIZEC       ; Compare it to the token string and see if we still match
          BEQ _TOKOK
          BCC _TOKLO
          BCS _TOKHI

_TOKOK    INY                 ; Move to next char

          PLP                 ; If we've reached the end of the token we're testing against, we have a match
          BNE _TOKYES
          BRA _TOKCHAR
          
_TOKHI    PLP
          TXA                 ; Input token was greater, move to top partition
          INC A
          STA TOKENIZEL
          BRA _TOKNEXT
          
_TOKLO    PLP
          TXA                 ; Input token was less, move to bottom partition
          DEC A
          STA TOKENIZER
          BRA _TOKNEXT
          
_TOKYES   STY MEMSPTR         ; Shove the token's length somewhere we already clobbered

          TXA                 ; Get the matching index in the token table (not the token ID)
          
          LDA _TOKTABLE,X     ; Use it to put the matching token's ID into the accumulator
          
          ORA #$80            ; Set high bit in byte to mark it as a token
          
          PLY                 ; Restore the token buffer offset into the Y register
          
          JSR _PUT            ; Put the token into the token buffer
          
          PLA                 ; Pull the input buffer position from the stack
          
          CLC                 ; Adjust by the token's length
          ADC MEMSPTR
          
          PHX                 ; Temporarily store the token value in X
          
          TAX                 ; Restore the input buffer offset into the X register
          
          PLA                 ; Get the token value back into the accumulator
          
          CMP #TOK_REM        ; If we had a REM token we should save time for the rest of the line
          BEQ _REM
          
          JMP _LOOP           ; Next character

_REM      LDA IBUF,X          ; Skip tokenizing after a REMARK to save time
  
          CMP #CHR_NL         ; End of line?
          BEQ _REMEND
          
          JSR _PUT            ; Copy the character
          
          INX                 ; Next character
          BRA _REM

_REMEND   JMP _END

_PUT      CPY #$FE            ; Check that we have room in the token buffer
          BEQ _SYS
          
          STA TBUF,Y          ; Store the accumulator value into the token buffer
          INY
          
          RTS                 ; Go back where we came from

_SYS      JMP RAISE_SYS       ; Indicate that the token buffer is out of space

_OPR      LDA IBUF,X          ; Consume starting character
          INX
          
          CMP #CHR_EQUALS     ; Handle possible equals sign
          BNE _OPLESS
        
          LDA #TOK_EQ
          BRA _OPDONE
          
_OPLESS   CMP #CHR_LESS       ; Handle possible less than/less than or equal/not equals
          BNE _OPGRTR
          
          LDA IBUF,X
          
          CMP #CHR_EQUALS
          BNE _OPNE
          
          INX
          LDA #TOK_LE
          BRA _OPDONE
          
_OPNE     CMP #CHR_GREATER
          BNE _OPLT
          
          INX
          LDA #TOK_NE
          BRA _OPDONE
          
_OPLT     LDA #TOK_LT
          BRA _OPDONE

_OPGRTR   LDA IBUF,X          ; Handle greater than/greater than or equals

          CMP #CHR_EQUALS
          BNE _OPGT
          
          INX
          LDA #TOK_GE
          BRA _OPDONE
               
_OPGT     LDA #TOK_GT
          BRA _OPDONE
          
_OPDONE   JSR _PUT
          JMP _LOOP

_TOKTABLE                     ; Token table in alphabetical order (used for binary search)

  .BYTE TOK_ABS-TOK_NEW
  .BYTE TOK_AND-TOK_NEW
  .BYTE TOK_ASC-TOK_NEW
  .BYTE TOK_AT-TOK_NEW
  .BYTE TOK_CHR-TOK_NEW
  .BYTE TOK_CLOSE-TOK_NEW
  .BYTE TOK_DATA-TOK_NEW
  .BYTE TOK_END-TOK_NEW
  .BYTE TOK_FOR-TOK_NEW
  .BYTE TOK_GOSUB-TOK_NEW
  .BYTE TOK_GOTO-TOK_NEW
  .BYTE TOK_IF-TOK_NEW
  .BYTE TOK_INPUT-TOK_NEW
  .BYTE TOK_LEN-TOK_NEW
  .BYTE TOK_LIST-TOK_NEW
  .BYTE TOK_LOAD-TOK_NEW
  .BYTE TOK_MOD-TOK_NEW
  .BYTE TOK_NEW-TOK_NEW
  .BYTE TOK_NEXT-TOK_NEW
  .BYTE TOK_NOT-TOK_NEW
  .BYTE TOK_OPEN-TOK_NEW
  .BYTE TOK_OR-TOK_NEW
  .BYTE TOK_PEEK-TOK_NEW
  .BYTE TOK_POKE-TOK_NEW
  .BYTE TOK_PRINT-TOK_NEW
  .BYTE TOK_READ-TOK_NEW
  .BYTE TOK_REM-TOK_NEW
  .BYTE TOK_RESTORE-TOK_NEW
  .BYTE TOK_RETURN-TOK_NEW
  .BYTE TOK_RND-TOK_NEW
  .BYTE TOK_RUN-TOK_NEW
  .BYTE TOK_SAVE-TOK_NEW
  .BYTE TOK_SQR-TOK_NEW
  .BYTE TOK_STR-TOK_NEW
  .BYTE TOK_SUB-TOK_NEW
  .BYTE TOK_SYS-TOK_NEW
  .BYTE TOK_TAB-TOK_NEW
  .BYTE TOK_THEN-TOK_NEW
  .BYTE TOK_TIME-TOK_NEW
  .BYTE TOK_TO-TOK_NEW
  .BYTE TOK_VAL-TOK_NEW
  .BYTE TOK_XOR-TOK_NEW

_TOKTABLEEND

;
; FINDLINE
;
; Attempts to find a line with line number LINENUM in program memory starting at the
; PROGMEM base address. If a match is found, the carry flag is set. If no match is
; found the carry flag is cleared. The matching line number will be stored in LINEPTR.
;
; Uses:
;
;   LINENUM       The line number to search for in the program
;   LINEPTR       The pointer to the matching line number (valid if carry is set)
;
FINDLINE  PHA                 ; Preserve registers
          PHY
  
          LDA #<PROGMEM       ; Start at the beginning of program memory
          STA LINEPTR+0
          LDA #>PROGMEM
          STA LINEPTR+1
 
_LOOP     LDA LINEPTR+0       ; Ensure that we're not at the top of program memory already
          CMP PROGTOP+0
          BNE _COMP
  
          LDA LINEPTR+1
          CMP PROGTOP+1
          BNE _COMP

          BRA _NO

_COMP     LDY #2              ; Skip leading line size byte when doing line number comparison
  
          LDA (LINEPTR),Y     ; Compare current and desired line number high bytes
          CMP LINENUM+1
          BNE _TEST
  
          DEY                 ; Compare current and desired line number low bytes
          LDA (LINEPTR),Y
          CMP LINENUM

_TEST     BEQ _YES            ; Found a match

          BCS _NO             ; Current line greater than desired line number, doesn't exist

          CLC                 ; Current line less than desired line number, move to next line

          LDA LINEPTR+0       ; Add current line size to low address byte
          ADC (LINEPTR)
          STA LINEPTR+0

          LDA LINEPTR+1       ; Propagate carry to high address byte
          ADC #0
          STA LINEPTR+1

          BRA _LOOP
  
_NO       CLC                 ; No match found, clear carry
          BRA _END

_YES      SEC                 ; Match found, set carry

_END      PLY                 ; Restore registers
          PLA
          
          RTS

;
; ENTERLINE
;
; Enters a tokenized line in TBUF into program memory. If a matching line number is
; found, that line will be deleted before the new line is inserted. If the line is blank
; no content will be inserted.
;
; If insufficient space exists in program memory then a system error is raised.
;
; Uses:
;
;   TBUF          The token buffer containing the new line
;   TBUFLEN       The length of the line stored in the token buffer
;   PROGTOP       The current top of program memory (updated after deletions/insertions)
;   LINENUM       Used internally for finding/matching lines
;   LINEPTR       Used internally for finding/matching lines
;   MEMSPTR       Used internally for copying memory/inserting/deleting lines
;   MEMDPTR       Used internally for copying memory/inserting/deleting lines
;
ENTERLINE PHA                 ; Preserve registers
          
          LDA TBUF+1          ; Get the line number we're looking for
          STA LINENUM+0
          LDA TBUF+2
          STA LINENUM+1
  
          JSR FINDLINE        ; See if the line number entered already exists
          BCC _NEW
  
_DEL      LDA LINEPTR+0       ; Use matching line as destination (deleting line by copying over it)
          STA MEMDPTR+0
          LDA LINEPTR+1
          STA MEMDPTR+1
  
          CLC                 ; Calculate end of matching line as the source pointer
          LDA MEMDPTR+0
          ADC (LINEPTR)
          STA MEMSPTR+0
          LDA MEMDPTR+1
          ADC #0
          STA MEMSPTR+1
          
          SEC                 ; Calculate number of bytes to move down from the top
          LDA PROGTOP+0
          SBC MEMSPTR+0
          STA MEMSIZE+0
          LDA PROGTOP+1
          SBC MEMSPTR+1
          STA MEMSIZE+1
          
          SEC                 ; Adjust the top address in program memory because we deleted a line
          LDA PROGTOP+0
          SBC (LINEPTR)
          STA PROGTOP+0
          LDA PROGTOP+1
          SBC #0
          STA PROGTOP+1

          JSR MEMCOPYDN       ; Delete the current line by moving memory down
  
_NEW      LDA TBUFLEN         ; If nothing on the new line, don't insert anything (just a deletion?)
          CMP #4
          BEQ _END
          
          LDA LINEPTR+0       ; Is our insertion position the same as the top of program memory?
          CMP PROGTOP+0
          BNE _MOV
  
          LDA LINEPTR+1
          CMP PROGTOP+1
          BNE _MOV
  
          BRA _INS            ; If so, we can just insert without copying memory to make space
  
_MOV      LDA LINEPTR+1       ; If we're on the last page of program memory just say we're out
          CMP PROGEND
          BEQ _SYS
          
          LDA LINEPTR+0       ; Use the insertion position as source pointer to move memory
          STA MEMSPTR+0
          LDA LINEPTR+1
          STA MEMSPTR+1
          
          CLC                 ; Calculate the destination pointer for copying memory
          LDA MEMSPTR+0
          ADC TBUFLEN
          STA MEMDPTR+0
          LDA MEMSPTR+1
          ADC #0
          STA MEMDPTR+1
          
          SEC                 ; Calculate the amount of memory to copy to make room for the new line
          LDA PROGTOP+0
          SBC MEMSPTR+0
          STA MEMSIZE+0
          LDA PROGTOP+1
          SBC MEMSPTR+1
          STA MEMSIZE+1
  
          JSR MEMCOPYUP       ; Copy the memory up to make room for the new line
  
_INS      JSR INSLINE         ; Insert the line
  
_END      PLA                 ; Restore registers

          RTS
          
_SYS      JMP RAISE_SYS       ; Indicate we're out of BASIC program memory

;
; INSLINE
;
; Inserts the line in the token buffer into program memory at the location in LINEPTR.
; This code exists separately from ENTERLINE because it is also used when a program
; is loaded via LOADBAS, allowing the load routine to skip the overhead in ENTERLINE.
;
; If insufficient space exists in program memory a system error is raised.
;
; Uses:
;
;   A             Clobbered
;   TBUF          Token buffer, updated with line length
;   TBUFLEN       Token buffer length (clobbered)
;   LINEPTR       Destination pointer for new line
;   MEMSPTR       Used internally to copy memory
;   MEMDPTR       Used internally to copy memory
;
INSLINE   LDA LINEPTR+1       ; If we're on the last page of program memory just say we're out
          CMP PROGEND
          BEQ _SYS
          
          LDA TBUFLEN         ; Store token buffer length as first byte in line
          STA TBUF
  
          STA MEMSIZE+0       ; Set size of memory to copy into program buffer
          STZ MEMSIZE+1
  
          LDA #<TBUF          ; Use token buffer as source pointer
          STA MEMSPTR+0
          LDA #>TBUF
          STA MEMSPTR+1

          LDA LINEPTR+0       ; Use line pointer found for line number as destination pointer
          STA MEMDPTR+0
          LDA LINEPTR+1
          STA MEMDPTR+1

          JSR MEMCOPYDN       ; Copy the memory

          CLC                 ; Update the top of memory to the new location
          LDA PROGTOP+0
          ADC TBUFLEN
          STA PROGTOP+0
          LDA PROGTOP+1
          ADC #0
          STA PROGTOP+1
          
          RTS

_SYS      JMP RAISE_SYS       ; Indicate we're out of BASIC program memory

;
; LISTPROG
;
; Lists the current program memory contents as text. Each line is written to
; the output buffer (OBUF) and then flushed (via FLUSH) at the end of each
; line.
;
; The appropriate starting and stopping pointers must be set in LINEPTR and
; STOPPTR respectively. A sanity check is performed for each line (e.g. in
; case line numbers were transposed in the user-provided LIST line numbers).
;
; This routine forms the core of the LIST statement in Cody Basic and also
; serves as the foundation for saving programs over serial ports (when output
; is redirected).
;
; Uses:
;
;   OBUF          Clobbered, used as output for each line
;   OBUFLEN       Clobbered, updated for each line
;   LINEPTR       Pointer to starting line when listing program (clobbered)
;   STOPPTR       Pointer to stopping line when listing program (clobbered)
;
LISTPROG  PHA                   ; Preserve registers
          PHX
          PHY
  
_LOOP     LDA LINEPTR+0         ; Always do a sanity check (data can come from LIST)
          CMP PROGTOP+0
          BNE _SANE
  
          LDA LINEPTR+1
          CMP PROGTOP+1
          BNE _SANE
          
          BRA _DONE
  
_SANE     LDA LINEPTR+0         ; Are we at the line we're supposed to stop at?
          CMP STOPPTR+0
          BNE _LINE
  
          LDA LINEPTR+1
          CMP STOPPTR+1
          BNE _LINE

_DONE     PLY                   ; No more lines in program, restore registers
          PLX
          PLA
  
          RTS                   ; All done
          
_LINE     STZ OBUFLEN           ; Start at the beginning of the output buffer

          LDY #1                ; Start at beginning of line (skipping line length byte)
  
          LDA (LINEPTR),Y       ; Copy line number low byte
          STA NUMONE+0
          INY
  
          LDA (LINEPTR),Y       ; Copy line number high byte
          STA NUMONE+1
          INY
            
          JSR TOSTRING          ; Write the number's digits to the output buffer

_PART     LDA (LINEPTR),Y       ; Load the next byte in the line

          CMP #$FF              ; Do we have a number token?
          BEQ _NUM
          
          BIT #$80              ; Do we have a token to decode?
          BNE _TOK
          
          JSR PUTOUT            ; Normal character, put it into the output buffer
          INY
          
          CMP #CHR_NL           ; If it was a newline, move on to the next source line
          BEQ _NEXT
          
          BRA _PART             ; Next part of the current line
          
_TOK      AND #$7F              ; Mask out the number of the actual token

          CLC                   ; Adjust the token number into the message table
          ADC #MSG_TOKENS
          
          JSR PUTMSG            ; Put the token's text into the output buffer
          
          INY                   ; Consume the token
          
          BRA _PART             ; Next part of the current line
          
_NUM      INY                   ; Skip leading number token tag
          
          LDA (LINEPTR),Y       ; Copy integer low byte
          STA NUMONE+0
          INY
          
          LDA (LINEPTR),Y       ; Copy integer high byte
          STA NUMONE+1
          INY
            
          JSR TOSTRING          ; Print integer
            
          BRA _PART             ; Next part of the current line

_NEXT     JSR FLUSH             ; Flush the output buffer
          
          CLC                   ; Move the pointer to the next line
          LDA LINEPTR+0
          ADC (LINEPTR)
          STA LINEPTR+0
          LDA LINEPTR+1
          ADC #0
          STA LINEPTR+1
          
          BRA _LOOP             ; Next line

;
; EXSTMT
;
; Executes a statement as part of the Cody Basic interpreter. The first toke on 
; the current line is examined and used as an index into a jump table of commands.
; If a syntax error or invalid command is found then ERR_SYNTAX is raised by calling
; RAISE_SYN.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine. The following list of variables is only a start.
;
; Uses:
;
;   A             Clobbered
;   X             Clobbered
;   Y             Clobbered
;   EXPRSNUM      Expression stack size, clobbered (reset to zero)
;   PROGOFF       Offset in current line, updated
;
EXSTMT    STZ EXPRSNUM        ; Start at the bottom of the expression stack
          
          JSR EXSKIP          ; Skip any whitespace before we run into a token
          
          LDY PROGOFF         ; Get the current offset in the current line
          
          LDA (PROGPTR),Y     ; Get the current byte 
                              
          CMP #CHR_NL         ; Was it a newline? If so the entire line was blank
          BEQ _END
          
          CMP #TOK_SYS+1      ; Check that the byte isn't too big to be a valid token
          BCS _SYN
          
          SEC                 ; Subtract from the first statement token to get the index
          SBC #TOK_NEW
          
          BCC _ASN            ; If the result was less than that, assume it was an assignment
          
          ASL A               ; Multiply by two to convert the number into a jump table index
          TAX
          
          INC PROGOFF         ; Increment the current offset since we consumed the token
          
          JMP (_JMP,X)        ; Jump to the code for the statement we have
          
_END      RTS

_ASN      JMP EXASSIGN        ; Jump to the assignment

_SYN      JMP RAISE_SYN       ; Raise syntax error

_JMP      .WORD EXNEW
          .WORD EXLIST
          .WORD EXLOAD
          .WORD EXSAVE
          .WORD EXRUN
          .WORD EXNOP
          .WORD EXIF
          .WORD _SYN
          .WORD EXGOTO
          .WORD EXGOSUB
          .WORD EXRETURN
          .WORD EXFOR
          .WORD _SYN
          .WORD EXNEXT
          .WORD EXPOKE
          .WORD EXINPUT
          .WORD EXPRINT
          .WORD EXOPEN
          .WORD EXCLOSE
          .WORD EXREAD
          .WORD EXRESTORE
          .WORD EXNOP
          .WORD EXEND
          .WORD EXSYS

;
; EXNEW
;
; Executes a NEW statement, clearing out the current program and variable space.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine. 
;
EXNEW     JSR ONLYREPL        ; Only valid in REPL mode
          
          JSR NEWPROG
          
          RTS

;
; EXLIST
;
; Executes a LIST statement, showing the contents of the current program on the screen.
; Start and stop line numbers may optionally be provided.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine. 
;
; Uses:
;
;   A             Clobbered
;   X             Clobbered
;   Y             Clobbered
;   PROGOFF       Offset in current line, updated
;   LINENUM       Used when finding start and stop locations, clobbered
;   LINEPTR       Used when finding start and stop locations, clobbered
;   STOPPTR       Updated with end line pointer, clobbered
;   RUNMODE       Temporarily updated to enable user breaks
;   NUMONE        Used during calculations
;   NUMTWO        Used during calculations
;   NUMANS        Used during calculations
;   EXPRSNUM      Used during calculations
;
EXLIST    JSR ONLYREPL        ; Only valid in REPL mode
          
          JSR EXSKIP          ; Skip any leading whitespace
          
          LDY PROGOFF         ; Read the next character
          LDA (PROGPTR),Y
          
          CMP #CHR_NL         ; If no parameters we have two defaults to provide
          BEQ _TWO
          
          JSR EXEXPR          ; Evaluate the starting line number and convert to its pointer
          JSR _FIND
          
          JSR EXSKIP          ; Skip any leading whitespace
          
          LDY PROGOFF         ; Read the next character
          LDA (PROGPTR),Y
          
          CMP #CHR_NL         ; If we have one parameter we have just one default to provide
          BEQ _ONE
          
          JSR EXCOMMA         ; Get the comma
          
          JSR EXEXPR          ; Evaluate the ending line number and convert to its pointer
          JSR _FIND
          
          BRA _LIST           ; Go ahead and list the program
          
_TWO      LDA #<PROGMEM       ; Get the base address of program memory
          STA NUMANS
          LDA #>PROGMEM
          STA NUMANS+1
          
          JSR PUSHANS         ; Push it on the stack as our default

_ONE      LDA PROGTOP         ; Get the address of the top of program memory
          STA NUMANS
          LDA PROGTOP+1
          STA NUMANS+1
          
          JSR PUSHANS         ; Push it on the stack as our default
          
_LIST     LDX EXPRSNUM        ; Get the number of items on the expression stack

          LDA EXPRS_L-1,X     ; Copy the stopping pointer into STOPPTR
          STA STOPPTR
          LDA EXPRS_H-1,X
          STA STOPPTR+1
          
          DEX                 ; Decrement stack count
          
          LDA EXPRS_L-1,X     ; Copy the starting pointer into LINEPTR
          STA LINEPTR
          LDA EXPRS_H-1,X
          STA LINEPTR+1
          
          DEX                 ; Decrement stack count
          
          STX EXPRSNUM        ; Update stack count before we forget to

          LDA #RM_COMMAND     ; Running without a line number so we can break
          STA RUNMODE

          JSR LISTPROG        ; List our program
          
          STZ RUNMODE         ; Return to REPL runmode
          
          RTS                 ; All done
          
_FIND     LDX EXPRSNUM        ; Get the number of items on the expression stack

          LDA EXPRS_L-1,X     ; Copy the line number over from the expression stack
          STA LINENUM+0
          LDA EXPRS_H-1,X
          STA LINENUM+1
          
          JSR FINDLINE        ; Find the matching line (or the insert position for it)
          
          LDA LINEPTR         ; Replace the line's number with its pointer on the stack
          STA EXPRS_L-1,X
          LDA LINEPTR+1
          STA EXPRS_H-1,X
          
          RTS                 ; Go back where we came from

;
; EXLOAD
;
; Executes a LOAD statement, loading a BASIC or binary program via one of the UARTs.
; Calls LOADBAS or LOADBIN as appropriate to handle the actual loading. For BASIC
; programs the new program is loaded and control returns to the interpreter, but for
; binary programs control jumps to the newly-loaded program's starting address.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine. 
;
; Uses:
;
;   A             Clobbered
;   RUNMODE       Temporarily updated to enable user breaks
;   IOMODE        Updated with the UART number for loading
;   IOBAUD        Updated to use 19200 baud for loading
;   NUMONE        Used during calculations
;   NUMTWO        Used during calculations
;
EXLOAD    JSR ONLYREPL        ; Only valid in REPL mode
          
          LDA #RM_COMMAND     ; Running without a line number so we can break
          STA RUNMODE
          
          JSR EXEXPR          ; Device argument
          
          JSR EXCOMMA         ; Comma separator
          
          JSR EXEXPR          ; Mode argument (0 for BASIC, 1 for binary)
          
          JSR POPBOTH         ; Pop results
        
          LDA #$F             ; Read at 19200 baud
          STA IOBAUD
          
          LDA NUMONE          ; Use device number as UART number
          STA IOMODE
                    
          LDA NUMTWO          ; Read BASIC or binary file as appropriate
          BNE _BIN
          
_BAS      JSR LOADBAS         ; Load the BASIC program

          STZ RUNMODE         ; Reset run mode and return
          RTS
          
_BIN      JMP LOADBIN

;
; EXSAVE
;
; Executes a SAVE statement, saving the current BASIC program via one of the UARTs. To
; handle a save, the routine redirects output to the UART, lists the entire program via
; LISTPROG, and then restores output to the screen. 
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine. 
;
; Uses:
;
;   A             Clobbered
;   IOMODE        Updated with the UART number for loading
;   IOBAUD        Updated to use 19200 baud for loading
;   NUMONE        Used during calculations
;   LINEPTR       Updated with start of program memory
;   STOPPTR       Updated with the top of the program
;   OBUFLEN       Modified when writing lines
;
EXSAVE    JSR ONLYREPL        ; Only valid in REPL mode
          
          LDA #RM_COMMAND     ; Running without a line number so we can break
          STA RUNMODE
          
          JSR EXEXPR          ; Read the device number for the UART
          JSR POPONE
          
          LDA NUMONE          ; Use it as the UART number
          STA IOMODE
          
          LDA #$F             ; Save at 19200 baud
          STA IOBAUD
          
          LDA #<PROGMEM       ; Start at the beginning of program memory
          STA LINEPTR
          LDA #>PROGMEM
          STA LINEPTR+1

          LDA PROGTOP         ; Stop at the top of program memory
          STA STOPPTR
          LDA PROGTOP+1
          STA STOPPTR+1
          
          JSR SERIALON        ; Start the serial port
          
          JSR LISTPROG        ; List the program out the serial port to "save" it
                    
          STZ OBUFLEN         ; Write an empty line to mark the end (the loader expects this!)
          LDA #CHR_NL
          JSR PUTOUT
          JSR FLUSH
          
          JSR SERIALOFF       ; Stop the serial port
          
          STZ RUNMODE         ; Reset run mode
          
          STZ IOBAUD          ; Go back to screen/keyboard IO when we're done
          STZ IOMODE
          
          RTS

;
; EXRUN
;
; Executes a RUN statement, resetting variables and data by calling NEWVARS and
; RESTORE first. The PROGPTR is updated with the start of program memory, then
; continues to execute statements until the RUNMODE is cleared. EXSTMT is called
; for each line in the program.
;
; On each loop the PROGNXT pointer is updated to the assumed next position in memory,
; allowing the called statement to override it (GOSUB, RETURN, GOTO, and NEXT use this
; feature).
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine. 
;
; Uses:
;
;   A             Clobbered
;   RUNMODE       Updated during the loop, must be cleared to end the program
;   PROGPTR       Updated with the start of the program (and each successive line)
;   PROGNXT       Updated at the start of each loop, may be updated by other routines
;   GOSUBSNUM     Reset at start
;   FORSNUM       Reset at start
;
EXRUN     JSR ONLYREPL        ; Only valid in REPL mode
          
          JSR NEWVARS         ; Reset variable memory
          
          JSR RESTORE         ; Reset data buffer for DATA/READ statements
          
          LDA #RM_PROGRAM     ; Set RUNMODE to running
          STA RUNMODE

          STZ GOSUBSNUM       ; Start out with empty GOSUB/RETURN and FOR/NEXT stacks
          STZ FORSNUM
          
          LDA #<PROGMEM       ; Use the start of program memory as our starting position
          STA PROGPTR
          LDA #>PROGMEM
          STA PROGPTR+1
          
_LOOP     LDA RUNMODE         ; Check that we're still running (e.g. no END statement was executed)
          BEQ _DONE

          JSR ISEND           ; Make sure that this line isn't actually the end of the program
          BEQ _DONE
          
_CONT     CLC                 ; Prepare to calculate the NEXT line we'll be running

          LDA PROGPTR         ; Calculate the low byte by adding our pointer to the line's size
          ADC (PROGPTR)
          STA PROGNXT

          LDA PROGPTR+1       ; Propagate the carry
          ADC #0
          STA PROGNXT+1
          
          LDA #4              ; Start at the first non-line-number position in the current line
          STA PROGOFF
          
          JSR EXSTMT          ; Execute the statement on this line
     
          LDA PROGNXT         ; Copy the NEXT line's pointer over to use as the current line
          STA PROGPTR
          LDA PROGNXT+1
          STA PROGPTR+1
          
          BRA _LOOP           ; Repeat, run the next statement
          
_DONE     STZ RUNMODE         ; Clear run mode
          
          STZ IOMODE          ; Clear IO mode
          
          RTS                 ; Done

;
; EXNOP
;
; Executes a no-operation statement in the Cody Computer. Suitable for REM, DATA and other
; operations that shouldn't do anything when the interpreter encounters them.
;
EXNOP     RTS

;
; EXIF
;
; Executes an IF statement, handling evaluation of the relational expression and branching.
; Largely separate branches exist for numeric relational expressions and string relational
; expressions. If the expression evaluates to true, EXSTMT is recursively called for the
; remainder of the statement.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine. 
;
; Uses:
;
;   A             Clobbered
;   X             Clobbered
;   Y             Clobbered
;   PROGOFF       Current position in program line, updated
;   OBUF          Updated in string comparisons
;   OBUFLEN       Updated in string comparisons
;   NUMONE        Updated in numeric comparisons
;   NUMTWO        Updated in numeric comparisons
;   GOSUBSNUM     Reset at start
;   FORSNUM       Reset at start
;
EXIF      JSR EXSKIP          ; Skip any leading space after the "IF"
          
          LDY PROGOFF         ; Read the first character to see if it could be a string var
          LDA (PROGPTR),Y
          
          JSR ISALPHA         ; If we have a string var it has to start with a letter
          BCC _NUM
          
          INY                 ; Read the next character to see if it's a dollar sign
          LDA (PROGPTR),Y
          
          CMP #CHR_DOLLAR     ; If we have a string var it ends with a dollar sign
          BNE _NUM
                  
_STR      JSR EXVAR           ; Parse a string variable (syntax error if not a string) 
          BCC _SYN
                    
          JSR _RELOP          ; Evaluate the relational operator and store the index temporarily
          PHA
          
          LDA TABPOS          ; Preserve tab position
          PHA
          
          STZ OBUFLEN         ; Evaluate the right hand side as a string into the output buffer
          JSR EXSTREXPR
          
          PLA                 ; Restore tab position
          STA TABPOS
                    
          LDX OBUFLEN         ; Append a NUL to the end of the buffer to make the comparison easier
          LDA #0
          STA OBUF,X
          
          JSR POPONE          ; Pop the string variable address off the stack
          
          LDY #0              ; Loop over the string in the buffer
          
_STRLOOP  LDA (NUMONE),Y      ; Compare the characters in the string and the output buffer
          CMP OBUF,Y

          BEQ _STRNEXT        ; Branch depending on the result of the comparison
          BCC _LT
          BRA _GT

_STRNEXT  CMP #0              ; If we have a null char for both, the strings are equal
          BEQ _EQ
          
          INY                 ; Increment the position in the output buffer to compare to
          
          BRA _STRLOOP        ; Next character

_SYN      JMP RAISE_SYN       ; Raise a syntax error (needs to be here for branch distance purposes)

_NUM      JSR EXEXPR          ; Evaluate left hand side of the relational operator
          
          JSR _RELOP          ; Evaluate the relational operator and store the index temporarily
          PHA
          
          JSR EXEXPR          ; Evaluate the right hand side of the relational operator
                    
          JSR POPBOTH         ; Pop both numbers off the stack
          
          LDA NUMONE+1        ; Compare high bytes using a signed comparison
          CMP NUMTWO+1
          
          BEQ _LO
          BMI _LT
          BPL _GT

_LO       LDA NUMONE          ; Compare low bytes using an unsigned comparison
          CMP NUMTWO
          
          BEQ _EQ
          BCC _LT
          BRA _GT

_EQ       LDA #(REL_LE | REL_GE | REL_EQ)     ; Equals is true for "<=", ">=", or "="
          BRA _THEN
          
_LT       LDA #(REL_LE | REL_LT | REL_NE)     ; Less than is true for "<=", "<" or "<>"
          BRA _THEN

_GT       LDA #(REL_GE | REL_GT | REL_NE)     ; Greater than is true for ">=", ">" or "<>"
          BRA _THEN

_THEN     PLX                 ; Get the index in our table for the relational operator

          AND _BITS,X         ; AND the table entry with the possible matches we have
          
          BEQ _DONE           ; If nothing matches, then the result of the comparison was false
          
          LDA #TOK_THEN       ; We expect a "THEN" token after the string 
          JSR EXCHARACT
          
          JMP EXSTMT          ; Then evaluate the rest of the line as its own statement
          
_DONE     RTS                 ; Nothing to do since condition was false

_BITS     .BYTE REL_LE        ; Lookup table that matches valid relop results with relops
          .BYTE REL_GE
          .BYTE REL_NE
          .BYTE REL_LT
          .BYTE REL_GT
          .BYTE REL_EQ

_RELOP    JSR EXSKIP          ; Skip any leading space

          LDY PROGOFF         ; Load the next character from the line (should be a relop token)
          LDA (PROGPTR),Y
          
          INC PROGOFF         ; Consume the token
          
          CMP #(TOK_EQ+1)     ; Was the token out of the expected range (too high)?
          BCS _SYN
          
          SEC                 ; Adjust token into lookup table value (and check if too low)
          SBC #TOK_LE
          BCC _SYN
          
          RTS                 ; All done, leave index in accumulator

;
; EXGOTO
;
; Executes a GOTO statement, moving PROGNXT to the line to be evaluated. Much of this
; code is utilized by EXGOSUB given its similar nature, so changes to this routine must
; be considered more broadly.
;
; If a matching line number cannot be found, a logic error is raised.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine. 
;
; Uses:
;
;   A             Clobbered
;   PROGNXT       Updated with the matching line number's pointer (if found)
;   LINENUM       Updated with destination line number (for finding a match)
;   NUMONE        Used for line number expression result
;
EXGOTO    JSR ONLYRUN         ; Only valid in RUN mode
          
          JSR EXEXPR          ; Evaluate the line number to jump to
          
          JSR POPONE          ; Pop the number off the stack
          
          LDA NUMONE          ; Copy line number to LINENUM before we search
          STA LINENUM
          LDA NUMONE+1
          STA LINENUM+1
          
          JSR FINDLINE        ; Try to find a matching line (control flow error if none)
          BCC _LOG
          
          LDA LINEPTR         ; Use the pointer we found as the next line to execute
          STA PROGNXT
          LDA LINEPTR+1
          STA PROGNXT+1
          
          RTS                 ; All done
          
_LOG      JMP RAISE_LOG       ; Indicate the line number was invalid

;
; EXGOSUB
;
; Executes a GOSUB statement. The current value of PROGNXT is pushed onto the gosub/return
; stack, then EXGOTO is called to handle the remainder of the operation (evaluating the
; line number and setting it up to run).
;
; If the gosub/return stack is full, a system error is raised. If the line number is
; invalid a logic error should be raised by GOTO (when called to handle the rest).
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine. 
;
; Uses:
;
;   A             Clobbered
;   X             Clobbered
;   PROGNXT       Pushed onto the gosub/return stack as tne destination position
;   GOSUBSNUM     Updated for new entry
;   GOSUBS_L      Updated for new entry
;   GOSUBS_H      Updated for new entry
;
EXGOSUB   JSR ONLYRUN         ; Only valid in RUN mode
          
          LDX GOSUBSNUM       ; Do we have room on the GOSUB/RETURN stack?
          CPX #MAXSTACK
          BCS _SYS
          
          LDA PROGNXT         ; Store the NEXT line pointer to execute as our return position
          STA GOSUBS_L,X
          LDA PROGNXT+1
          STA GOSUBS_H,X
          
          INC GOSUBSNUM       ; Increment stack count (we just pushed an item on it)
          
          JMP EXGOTO          ; The rest of our statement is just like a GOTO, so go there

_SYS      JMP RAISE_SYS       ; Indicate the GOSUB-RETURN stack is out of memory

;
; EXRETURN
;
; Executes a RETURN statement. The top value on the gosub/return stack is popped and
; used as the value for PROGNXT. If the stack is empty a logic error is raised.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine. 
;
; Uses:
;
;   A             Clobbered
;   PROGNXT       Pushed onto the gosub/return stack as tne destination position
;   GOSUBSNUM     Decremented with popped entry.
;   GOSUBS_L      Updated for new entry
;   GOSUBS_H      Updated for new entry
;
EXRETURN  JSR ONLYRUN         ; Only valid in RUN mode
          
          LDX GOSUBSNUM       ; Load the number of GOSUB/RETURN entries (control flow error if none)
          BEQ _LOG
          
          LDA GOSUBS_L-1,X    ; Copy the top item on the GOSUB/RETURN stack as our next line to run
          STA PROGNXT
          LDA GOSUBS_H-1,X
          STA PROGNXT+1
          
          DEC GOSUBSNUM       ; Decrement count (we just removed an item from the stack)
          
          RTS                 ; All done
          
_LOG      JMP RAISE_LOG       ; Indicate we have a RETURN without a GOSUB

;
; EXFOR
;
; Executes a FOR statement. Evaluates the lvalue, initial value, and final value,
; updating the various for/next stack items with these positions. PROGNXT is also
; used as the return location for NEXT statements when the loop repeats.
;
; If the for/next stack is full a system error is raised.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine. 
;
; Uses:
;
;   A             Clobbered
;   X             Clobbered
;   FORSNUM       Incremented for new entry on for/next stack
;   FORLINE_L     Updated with line pointer to use in NEXT statements
;   FORLINE_H     Updated with line pointer to use in NEXT statements
;   FORVARS_L     Updated with address of number variable used as index
;   FORVARS_H     Updated with address of number variable used as index
;   FORSTOP_L     Updated with stop value for loop
;   FORSTOP_H     Updated with stop value for loop
;
EXFOR     JSR ONLYRUN         ; Only valid in RUN mode
          
          JSR EXVAR           ; Evaluate the loop variable as an lvalue (only number vars)
          BCS _SYN
          
          JSR EXEQUALS        ; Consume equals
                    
          JSR EXEXPR          ; Evaluate starting expression
          
          LDA #TOK_TO         ; Consume "TO"
          JSR EXCHARACT
          
          JSR EXEXPR          ; Evaluate ending expression
          
          LDX FORSNUM         ; Do we have room on the FOR/NEXT stack?
          CPX #MAXSTACK
          BCS _SYS
          
          LDA PROGNXT         ; Store the line pointer to execute as our return position
          STA FORLINE_L,X
          LDA PROGNXT+1
          STA FORLINE_H,X
          
          JSR POPONE          ; Pop the ending value for the FOR loop off the stack
          
          LDA NUMONE          ; Store the ending value into the FORSTOPs
          STA FORSTOP_L,X
          LDA NUMONE+1
          STA FORSTOP_H,X
          
          JSR POPBOTH         ; Pop the variable address and the initial value off the stack
          
          LDA NUMONE          ; Store the variable address into the FORVARS
          STA FORVARS_L,X
          LDA NUMONE+1
          STA FORVARS_H,X
          
          LDA NUMTWO          ; Store the low byte of the initial loop value
          STA (NUMONE)
          
          INC NUMONE          ; Move to the high byte (relies on page alignment to be safe)
          
          LDA NUMTWO+1        ; Store the high byte of the initial loop value
          STA (NUMONE)
          
          INC FORSNUM         ; Increment stack count (we just pushed an item on it)
          
          RTS                 ; All done

_SYN      JMP RAISE_SYN       ; Raise syntax error

_SYS      JMP RAISE_SYS       ; Indicate the FOR-NEXT stack is out of memory

;
; EXNEXT
;
; Executes a NEXT statement. The terminating conditions for the topmost loop on the for/next
; stack are evaluated. If the loop is running then control is returned to the FORLINE position
; by updating PROGNXT. If not, the loop information is popped from the stack and control 
; continues as normal. If the for/next stack is empty a logic error is raised.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine. 
;
; Uses:
;
;   A             Clobbered
;   X             Clobbered
;   Y             Clobbered
;   PROGNXT       Updated with start of loop if loop is still running
;   FORSNUM       Decremented if loop is finished
;   FORLINE_L     Used to repeat loop
;   FORLINE_H     Used to repeat loop
;   FORVARS_L     Used to obtain pointer to index variable
;   FORVARS_H     Used to obtain pointer to index variable
;   FORSTOP_L     Used to obtain final loop value
;   FORSTOP_H     Used to obtain final loop value
;
EXNEXT    JSR ONLYRUN         ; Only valid in RUN mode

          LDX FORSNUM         ; Load the number of FOR/NEXT entries (logic error if none)
          BEQ _LOG
          
          LDA FORVARS_L-1,X   ; Assemble the variable address from the low and high bytes
          STA MEMSPTR
          LDA FORVARS_H-1,X
          STA MEMSPTR+1
          
          LDY #0              ; Compare low bytes
          LDA (MEMSPTR),Y
          CMP FORSTOP_L-1,X
          BNE _LOOP
          
          INY                 ; Compare high bytes
          LDA (MEMSPTR),Y
          CMP FORSTOP_H-1,X
          BNE _LOOP
     
          DEC FORSNUM         ; This loop is done, remove it from the stack
          
          BRA _DONE           ; All done here
          
_LOOP     CLC                 ; Prepare to increment the variable by one

          LDY #0              ; Increment low byte
          LDA (MEMSPTR),Y
          ADC #1
          STA (MEMSPTR),Y
          
          INY                 ; Increment high byte (with carry)
          LDA (MEMSPTR),Y
          ADC #0
          STA (MEMSPTR),Y
          
          LDA FORLINE_L-1,X   ; Copy the top item on the FOR/NEXT stack as our next line to run
          STA PROGNXT
          LDA FORLINE_H-1,X
          STA PROGNXT+1
          
_DONE     RTS                 ; All done
          
_LOG      JMP RAISE_LOG       ; Indicate a NEXT-without-FOR error

;
; EXASSIGN
;
; Executes an assignment. Evaluates the lvalue using EXVAR and the rvalue using EXEXPR (for
; numeric variables) or EXSTREXPR (for string variables). Copies the result into the lvalue.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine. 
;
; Uses:
;
;   A             Clobbered
;   Y             Clobbered
;   NUMONE        Updated with lvalue pointer
;   NUMTWO        Updated with rvalue (in numeric expressions)
;   OBUF          Used in string expressions
;   OBUFLEN       Used in string expressions
;
EXASSIGN  JSR EXVAR           ; Evaluate the lvalue of the expression
                                   
          BCS _STR            ; If we had a string var we need to handle that as a special case

_NUM      JSR EXEQUALS        ; Require an equals sign
          
          JSR EXEXPR          ; Evaluate the rvalue of the expression
                    
          JSR POPBOTH         ; Pop the lvalue address and rvalue off the expression stack
          
          LDA NUMTWO          ; Store low byte of rvalue in lvalue memory location
          STA (NUMONE)
          
          INC NUMONE          ; Move to high byte (relies on variables having page alignment)
          
          LDA NUMTWO+1        ; Store high byte of rvalue in lvalue memory location
          STA (NUMONE)
          
          BRA _END            ; All done
          
_STR      JSR EXEQUALS        ; Require an equals sign

          LDA TABPOS          ; Preserve tab position
          PHA
          
          STZ OBUFLEN         ; Start at beginning of output buffer
          
          JSR EXSTREXPR       ; Evaluate the string expression to assign to the variable
          
          PLA                 ; Restore tab position
          STA TABPOS
           
          JSR POPONE          ; Pop the destination address from the expression stack
          
          LDY #0              ; Start at beginning of string
          
_STRLOOP  CPY OBUFLEN         ; See if we're at the end of the output buffer
          BEQ _STRDONE
          
          LDA OBUF,Y          ; Copy a character from the output buffer to the string
          STA (NUMONE),Y
          
          INY                 ; Increment position in buffer
          
          BNE _STRLOOP        ; Next loop
          
_STRDONE  LDA #0              ; Append null character at end of string
          STA (NUMONE),Y
          
_END      RTS

;
; EXPOKE
;
; Executes a POKE statement. The address and value to poke are evaluate as numeric
; expressions via EXEXPR, then the low byte of the number is poked into the destination
; address.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine. 
;
; Uses:
;
;   A             Clobbered
;   NUMONE        Clobbered, stores address to use
;   NUMTWO        Clobbered, stores value to poke (only low byte used)
;
EXPOKE    JSR EXEXPR          ; Calculate the address to poke to
          
          JSR EXCOMMA         ; Read the comma between the address and the byte value
          
          JSR EXEXPR          ; Calculate the value to poke into memory
          
          JSR POPBOTH         ; Pop address into NUMONE and value into NUMTWO
          
          LDA NUMTWO          ; Load the byte to store
                    
          STA (NUMONE)        ; Store it at the address we were given
          
          RTS

;
; EXINPUT
;
; Executes an INPUT statement. Processes a variable list, handling each variable
; depending on whether it is numeric or string. Prints an input prompt followed by a
; space if the PROMPT char is set, otherwise the prompt is suppressed.
;
; Unlike traditional BASICs, each item in the variable list results in a new prompt on
; a new line.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine. 
;
; Uses:
;
;   A             Clobbered
;   Y             Clobbered
;   NUMONE        Used for destination address (string or number)
;   NUMANS        Used for numeric expressions
;   IBUF          Used for string expressions
;   IBUFLEN       Used for string expressions
;   PROMPT        Read for the prompt character (if zero, no prompt)
;   IOMODE        Read to determine whether reading from keyboard or UART
;
EXINPUT   JSR ONLYRUN         ; Only valid in RUN mode
          
_LOOP     JSR EXVAR           ; Read the number or string variable and save our flags
          PHP
          
          STZ OBUFLEN         ; Move to beginning of output buffer
          
          LDA PROMPT          ; Print the input prompt if we have one (nonzero)
          BEQ _READ
          
          JSR PUTOUT          ; Print prompt char
    
          LDA #CHR_SPACE      ; Print space
          JSR PUTOUT
          
          JSR FLUSH           ; Flush to output
          
_READ     LDA IOMODE          ; Determine where to read from
          BEQ _KBD
          
_SER      JSR READSER         ; Read our input line from the UART
          BRA _INP
          
_KBD      JSR READKBD         ; Read out input line from the keyboard
          
_INP      PLP                 ; Fetch our flags and handle input (number or string?)
          BCS _STR
          
_NUM      LDA #<IBUF          ; Use the input buffer as the source for parsing a number
          STA MEMSPTR
          LDA #>IBUF
          STA MEMSPTR+1
          
          LDY #0              ; If nothing to read, just default to TONUMBER's handling
          CPY IBUFLEN
          BEQ _TONUM
          
          LDA IBUF,Y          ; Otherwise we need to check for a leading minus sign
          CMP #CHR_MINUS
          
          PHP                 ; Preserve result before deciding what to do.
          BNE _TONUM
          
          INY                 ; Skip leading minus
          
_TONUM    JSR TONUMBER        ; Parse the number
          JSR POPONE
          
          PLP                 ; Was it a negative number?
          BEQ _NEG
          
_POS      LDA NUMANS          ; Store number low byte
          STA (NUMONE)
          
          INC NUMONE          ; Move to high byte (relies on page alignment)
          
          LDA NUMANS+1        ; Store number high byte
          STA (NUMONE)
          
          BRA _NXT            ; Next item, if any

_NEG      SEC                 ; Negative number so subtract from zero

          LDA #0              ; Subtract and store low byte
          SBC NUMANS
          STA (NUMONE)
          
          INC NUMONE          ; Move to high byte (relies on page alignment)
          
          LDA #0              ; Subtract and store high byte
          SBC NUMANS+1
          STA (NUMONE)

          BRA _NXT            ; Next item, if any
          
_STR      JSR POPONE          ; Pop the destination address off the stack
          
          DEC IBUFLEN         ; Skip ending newline character in buffer when we copy
          
          LDY #0              ; Start at beginning of string
          
_STRLOOP  CPY IBUFLEN         ; Make sure we have characters left to copy
          BEQ _STRDONE
          
          LDA IBUF,Y          ; Store byte containing the character value
          STA (NUMONE),Y
          
          INY                 ; Next character
          BRA _STRLOOP

_STRDONE  LDA #0              ; Append NUL at end of string we copied
          STA (NUMONE),Y

_NXT      STZ OBUFLEN         ; Advance the output
          LDA #CHR_NL
          JSR PUTOUT
          JSR FLUSH

          JSR EXSKIP          ; Skip any spaces

          LDY PROGOFF         ; Read the next character in the line     
          LDA (PROGPTR),Y
          
          CMP #CHR_NL         ; End of the statement
          BEQ _DONE
          
          CMP #CHR_COMMA      ; Only other possibility is a comma before the next item
          BNE _SYN
          
          INC PROGOFF         ; Consume comma
          
          JMP _LOOP           ; Repeat

_DONE     RTS                 ; All done
          
_SYN      JMP RAISE_SYN       ; Raise syntax error

;
; EXPRINT
;
; Executes a PRINT statement. Evaluates each expression and puts it into the output
; buffer, flushing the buffer at the end of the statement. Also handles various
; modifiers such as AT() and TAB() as part of evaluating the statement. A newline is
; emitted at the end of each statement unless the statement was ended by a semicolon.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine. 
;
; Uses:
;
;   A             Clobbered
;   Y             Clobbered
;   PROGOFF       Current position in current line, updated
;   NUMONE        Clobbered during various expressions/modifiers
;   NUMTWO        Clobbered during various expressions/modifiers
;   OBUF          Updated with contents, flushed at end
;   OBUFLEN       Updated with buffer content length
;   TABPOS        Read to determine current tab position
;
EXPRINT   STZ OBUFLEN         ; Start at beginning of output buffer
          
_LOOP     JSR EXSKIP          ; Skip any leading space
          
          LDY PROGOFF         ; Load the next character in the current line
          LDA (PROGPTR),Y
          
          CMP #TOK_AT         ; "AT()" format specifier to change screen location
          BEQ _AT
          
          CMP #TOK_TAB        ; "TAB() format specifier to advance position in line
          BEQ _TAB
          
          CMP #CHR_QUOTE      ; Quote means a string expression
          BEQ _STR
          
          CMP #TOK_STR        ; "STR$" function means a string expression
          BEQ _STR
          
          CMP #TOK_CHR        ; "CHR$" function means a string expression
          BEQ _STR
          
          CMP #TOK_SUB        ; "SUB$" function means a string expression
          BEQ _STR
          
          CMP #CHR_NL         ; Newline means the end of the line
          BEQ _ADV
          
          CMP #CHR_SEMICOLON  ; Semicolon means the end of the line without advancing
          BEQ _END
          
          JSR ISALPHA         ; At this point, the only possibility left is a string variable
          BEQ _NUM
          
          INY                 ; Look ahead one character
          LDA (PROGPTR),Y
          
          CMP #CHR_DOLLAR     ; String variables end with a dollar sign ("$")
          BEQ _STR
          
_NUM      JSR EXEXPR          ; Evaluate expression

          JSR POPONE          ; Pop the result off the expression stack
          
          LDA NUMONE+1        ; Is it signed?
          BPL _PUTNUM       
          
          LDA #CHR_MINUS      ; Print minus sign
          JSR PUTOUT
          
          SEC                 ; Calculate absolute value of negative number
          
          LDA #0
          SBC NUMONE
          STA NUMONE
          
          LDA #0
          SBC NUMONE+1
          STA NUMONE+1
          
_PUTNUM   JSR TOSTRING        ; Convert it to a string in the output buffer
          
          BRA _NXT            ; Handle whatever is next after the number expression
          
_STR      JSR EXSTREXPR       ; Evaluate the string expression (will populate output buffer)

_NXT      JSR EXSKIP          ; Skip any whitespace

          LDY PROGOFF         ; Load the next character in the current line
          LDA (PROGPTR),Y
                    
          CMP #CHR_SEMICOLON  ; Semicolon should be handled at the start of the loop
          BEQ _LOOP
          
          CMP #CHR_NL         ; Newline should be handled at the start of the loop
          BEQ _LOOP
          
          INC PROGOFF         ; Consume the character we read
          
          CMP #CHR_COMMA      ; Comma means we continue on for another argument to PRINT
          BEQ _LOOP
          
          JMP RAISE_SYN       ; Otherwise we had a syntax error

_AT       JSR FLUSH           ; Flush the buffer first
          
          STZ OBUFLEN         ; Start at the beginning after a flush
          
          INC PROGOFF         ; Consume the "AT" token

          JSR EXTWOARG        ; Evaluate new column and row values

          JSR POPBOTH         ; Pop them from the stack
          
          LDA IOMODE          ; Don't change position if we're not writing to the screen (no-op)
          BNE _NXT
                    
          LDX NUMONE          ; Update tab and screen positions
          STX TABPOS
          LDY NUMTWO
          JSR SCREENPOS
          
          BRA _NXT            ; All done

_TAB      INC PROGOFF         ; Consume the "TAB" token

          JSR EXONEARG        ; Evaluate a one-argument number function to get the tab position
          
          JSR POPONE          ; Get the desired tab position off the expression stack
                    
_TABLOOP  LDA TABPOS          ; Before each loop make sure we aren't past the tab position we want
          CMP NUMONE
          BCS _NXT

          LDA #CHR_SPACE      ; Put another blank character into the output buffer to fill it up
          JSR PUTOUT
          
          BRA _TABLOOP        ; Next loop
          
_ADV      LDA #CHR_NL         ; Append a newline to the end of the output buffer
          JSR PUTOUT

_END      JSR FLUSH           ; Print out whatever we have (wherever it's supposed to go)

          RTS                 ; All done

;
; EXOPEN
;
; Executes an OPEN statement. Sets the IOMODE and IOBAUD from the values in the
; statement, but no error-checking is performed at this point. This routine only
; sets up the mode and baud rate, but the actual I/O happens on a per-line basis
; in INPUT and PRINT statements.
;
; Uses:
;
;   A             Clobbered
;   NUMONE        Clobbered
;   NUMTWO        Clobbered
;   IOMODE        Updated with value from statement
;   IOBAUD        Updated with value from statement
;
EXOPEN    JSR ONLYRUN         ; Only valid in RUN mode
          
          JSR EXEXPR          ; Read device number
          
          JSR EXCOMMA         ; Comma separator
          
          JSR EXEXPR          ; Baud rate (1 through 15)
          
          JSR POPBOTH         ; Get both values off the stack
          
          LDA NUMTWO          ; Baud rate (1 through 15)
          STA IOBAUD
          
          LDA NUMONE          ; Device number
          STA IOMODE
          
          BEQ _DONE           ; If a UART was selected turn serial on
          JSR SERIALON
          
_DONE     RTS

;
; EXCLOSE
;
; Executes a CLOSE statement. Both the IOMODE and IOBAUD values are reset so that any
; future I/O operations will use the keyboard and screen instead of the UART.
;
; Uses:
;
;   IOMODE        Cleared
;   IOBAUD        Cleared
;
EXCLOSE   JSR ONLYRUN         ; Only valid in RUN mode
          
          JSR SERIALOFF       ; Turn serial off (routine should check if IOMODE is actually set)
          
          STZ IOMODE          ; Clear IO mode and IO baud settings (defaults back to screen/keyboard)
          STZ IOBAUD
          
          RTS

;
; EXREAD
;
; Executes a READ statement. Numeric values are read from the data buffer for each
; variable in the statement. If the program is out of data a logic error is raised.
;
; Uses:
;
;   A             Clobbered
;   X             Clobbered
;   Y             Clobbered
;   PROGOFF       Updated
;   DBUFPOS       Incremented as items are read from the buffer
;   DBUFLEN       Decremented as items are read from the buffer
;   DBUFL         Used when reading items
;   DBUFH         Used when reading items
;
EXREAD

_LOOP     JSR EXVAR           ; Read the variable to read into, it has to be a number variable
          BCS _SYN
          
          LDA DBUFLEN         ; Verify that we still have data in the buffer to read
          BNE _READ
          
          STZ DBUFPOS         ; Out of data, need to read more in from the program
          JSR MOREDATA
          
          LDA DBUFLEN         ; Did we find any more data in the program?
          BEQ _LOG
          
_READ     JSR POPONE          ; Pop the variable address into NUMONE
             
          LDX DBUFPOS         ; Read current index in the data buffer
          
          LDA DBUFL,X         ; Copy low byte
          STA (NUMONE)
          
          INC NUMONE          ; Move on to high byte (relies on page alignment)
          
          LDA DBUFH,X         ; Store high byte
          STA (NUMONE)
                    
          DEC DBUFLEN         ; Decrement data buffer size and increment buffer position
          INC DBUFPOS
          
          JSR EXSKIP          ; Skip any whitespace
          
          LDY PROGOFF         ; Load the next character from the current line
          LDA (PROGPTR),Y
          
          CMP #CHR_NL         ; Newline means we're done with this statement
          BEQ _DONE
          
          CMP #CHR_COMMA      ; If it's not a comma then it's a syntax error
          BNE _SYN
        
          INC PROGOFF         ; Consume the comma
          
          BRA _LOOP           ; Next variable
          
_DONE     RTS
          
_SYN      JMP RAISE_SYN
_LOG      JMP RAISE_LOG

;
; EXRESTORE
;
; Handles the RESTORE statement that resets DATA-related variables and clears the
; data buffer. Calls the RESTORE routine to perform the actual work.
;
EXRESTORE JSR RESTORE         ; Reset DATA
          
          RTS                 ; All done

;
; EXEND
;
; Executes the END statement that ends a running program. Clears the RUNMODE variable
; so that the interpreter will terminate.
;
; Uses:
;
;   RUNMODE       Clobbered (set to zero to enable REPL mode)
;
EXEND     JSR ONLYRUN         ; Only valid in RUN mode
          
          STZ RUNMODE         ; Set run mode back to zero (REPL mode)
          
          RTS                 ; All done

;
; EXSYS
;
; Executes a SYS statement allowing BASIC programs to call into machine-language routines,
; including exchanging of data in the registers via zero-page variables (which can be
; modified using POKE statements).
;
; Uses:
;
;   NUMONE        Clobbered, used to store address to jump to
;   SYS_A         Read for starting accumulator value, overwritten with final one
;   SYS_X         Read for starting X register value, overwritten with final one
;   SYS_Y         Read for starting Y register value, overwritten with final one
;
EXSYS     JSR EXEXPR          ; Evaluate the expression to get the address to jump to
          
          JSR POPONE          ; Pop the number off the stack
          
          LDA SYS_A           ; Populate the registers with the values from zero page
          LDX SYS_X
          LDY SYS_Y
          
          JSR _JMP            ; Mimic an indirect JSR by calling to an indirect JMP
          
          STA SYS_A           ; Store the registers back into the zero page locations
          STX SYS_X
          STY SYS_Y
          
          RTS                 ; All done

_JMP      JMP (NUMONE)        ; Jump (kind-of JSR, see above) to the user-provided address

;
; EXSKIP
;
; Utility routine that skips whitespace during the execution of a statement.
;
; Uses:
;
;   PROGOFF       Updated to new location
;
EXSKIP    PHA                 ; Preserve registers
          PHY
          
          LDY PROGOFF         ; Fetch the offset in the current line 
          
_LOOP     LDA (PROGPTR),Y     ; Load the next character
          
          JSR ISSPACE         ; We're done if it's not a space
          BCC _END
          
          CMP #CHR_NL         ; We're done if we found a newline
          BEQ _END
          
          INY                 ; Increment the offset
          
          BRA _LOOP
          
_END      STY PROGOFF         ; Update the offset with our new position
          
          PLY                 ; Restore registers
          PLA
          
          RTS

;
; EXEXPR
;
; Evaluates a numeric expression consisting of addition and subtraction operations.
; Each argument is evaluated as a term by calling EXTERM. Results are put on the
; expression stack.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine. 
;
; Uses:
;
;   A             Clobbered
;   X             Clobbered
;   Y             Clobbered
;   PROGOFF       Current position in current line, updated
;   EXPRSNUM      Expression stack size, updated
;   EXPRS_L       Expression stack, updated
;   EXPRS_H       Expression stack, updated
;
EXEXPR    JSR EXTERM          ; Evaluate the left side of the (possible) operator
          
_LOOP     JSR EXSKIP          ; Skip any leading space
          
          LDY PROGOFF         ; Load the next character
          LDA (PROGPTR),Y
          
          CMP #CHR_PLUS       ; Addition operation
          BEQ _ADD
          
          CMP #CHR_MINUS      ; Subtraction operation
          BEQ _SUB
          
          RTS                 ; All done

_ADD      INC PROGOFF         ; Consume plus character

          JSR EXTERM          ; Evaluate the right side of the plus sign
          
          LDX EXPRSNUM        ; Find how many items we have on the expression stack
          
          CLC                 ; Prepare for addition
          
          LDA EXPRS_L-2,X     ; Add number low bytes together and put back on stack
          ADC EXPRS_L-1,X
          STA EXPRS_L-2,X

          LDA EXPRS_H-2,X     ; Add number high bytes together and put back on stack
          ADC EXPRS_H-1,X
          STA EXPRS_H-2,X
          
          DEC EXPRSNUM        ; Decrement stack by one (took two values off, put result back on)
          
          BRA _LOOP           ; Next
          
_SUB      INC PROGOFF         ; Consume minus character

          JSR EXTERM          ; Evaluate the right side of the minus sign
          
          LDX EXPRSNUM        ; Find how many items we have on the expression stack
          
          SEC                 ; Prepare for subtraction
          
          LDA EXPRS_L-2,X     ; Subtract number low bytes and put back on stack
          SBC EXPRS_L-1,X
          STA EXPRS_L-2,X

          LDA EXPRS_H-2,X     ; Subtract number high bytes and put back on stack
          SBC EXPRS_H-1,X
          STA EXPRS_H-2,X
          
          DEC EXPRSNUM        ; Decrement stack by one (took two values off, put result back on)
          
          BRA _LOOP           ; Next

;
; EXTERM
;
; Evaluates a numeric expression consisting of multiplication and division operations.
; Each argument is evaluated as a factor by calling FACTOR. Results are put on the
; expression stack.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine. 
;
; Uses:
;
;   A             Clobbered
;   Y             Clobbered
;   PROGOFF       Current position in current line, updated
;   NUMONE        Used in calculations
;   NUMTWO        Used in calculations
;   NUMANS        Used in calculations
;
EXTERM    JSR EXFACTOR        ; Evaluate the left side of the (possible) operator
          
_LOOP     JSR EXSKIP          ; Skip any leading space
          
          LDY PROGOFF         ; Load the next character
          LDA (PROGPTR),Y
          
          CMP #CHR_ASTERISK   ; Multiplication operation
          BEQ _MUL
          
          CMP #CHR_SLASH      ; Division operation
          BEQ _DIV
          
          RTS                 ; All done

_MUL      INC PROGOFF         ; Consume multiply operator
          
          JSR EXFACTOR        ; Evaluate the right side of the multiply sign
          
          JSR POPBOTH         ; Pop both values off the expression stack
          
          JSR PRE16 
          
          PHA
          
          JSR MUL16           ; Multiply the numbers together
          
          PLA
          
          JSR ADJ16
          
          JSR PUSHANS         ; Push the result back on the stack
          
          BRA _LOOP           ; Next
          
_DIV      INC PROGOFF         ; Consume divide operator

          JSR EXFACTOR        ; Evaluate the right side of the division sign
          
          JSR POPBOTH         ; Pop both values off the expression stack
          
          JSR PRE16
          
          PHA
          
          JSR MOD16           ; Divide using the modulus operation (division result is also calculated)
          
          LDA NUMONE          ; Copy division result low byte (from the modulus) to the answer
          STA NUMANS
          
          LDA NUMONE+1        ; Copy division result high byte (from the modulus) to the answer
          STA NUMANS+1
          
          PLA
          
          JSR ADJ16
          
          JSR PUSHANS         ; Push the result back on the stack
                    
          BRA _LOOP           ; Next

;
; EXFACTOR
;
; Evaluates the portion of a numeric expression consisting of literals, variables, nested
; expressions, or functions. Results are put on the expression stack.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine. 
;
; Uses:
;
;   A             Clobbered
;   Y             Clobbered
;   PROGOFF       Current position in current line, updated
;   NUMONE        Used in calculations
;   NUMANS        Used in calculations
;
EXFACTOR  JSR EXSKIP          ; Skip any leading spaces
          
          LDY PROGOFF         ; Get the offset in the current line
          
          LDA (PROGPTR),Y     ; Read the character there
          
          CMP #CHR_MINUS      ; Is it a negative number?
          BEQ _NEG
          
          CMP #TOK_NUM        ; Is it a number literal?
          BEQ _NUM
          
          CMP #CHR_LPAREN     ; Is it a nested expression?
          BEQ _EXP
          
          JSR ISALPHA         ; Is it a letter for a variable name?
          BCS _VAR
          
          CMP #TOK_ASC+1      ; Check that the byte isn't too big to be a valid token
          BCS _SYN
          
          INC PROGOFF         ; Consume the token
          
          SEC                 ; Subtract the start of the function tokens to get our index
          SBC #TOK_TIME
          
          BCC _SYN            ; If the result was less than that the token value was too low
          
          ASL A               ; Multiply by two to convert the number into a jump table index
          TAX
          
          JMP (_JMP,X)        ; Jump to the code for the function we have
          
_NUM      INY                 ; Skip the leading $FF tag at the start of the number

          LDA (PROGPTR),Y     ; Fetch number literal low byte 
          STA NUMANS
          INY
                   
          LDA (PROGPTR),Y     ; Fetch number literal high byte
          STA NUMANS+1
          INY
          
          STY PROGOFF         ; Update the offset in the current line
          
          JSR PUSHANS         ; Push the number onto the expression stack
          
          RTS                 ; All done
          
_EXP      JSR EXLPAREN        ; Grab the left parenthesis

          JSR EXEXPR          ; Process the nested expression
          
          JSR EXRPAREN        ; Grab the right parenthesis
          
          RTS                 ; All done
          
_VAR      JSR EXVAR           ; Evaluate variable to get its address in memory

          BCS _SYN            ; If we read a string variable, it's a syntax error here
          
          JSR POPONE          ; Pop the variable's address off the stack
          
          LDA (NUMONE)        ; Read and store the low byte of the variable
          STA NUMANS
          
          INC NUMONE          ; Increment address by one (safe because of page alignment)
          
          LDA (NUMONE)        ; Read and store the high byte of the variable
          STA NUMANS+1
          
          JSR PUSHANS         ; Push the number (not its address) on the stack

          RTS
          
_NEG      INC PROGOFF         ; Consume the unary minus

          JSR EXFACTOR        ; Process the rest of the factor

          LDX EXPRSNUM        ; Get the current expression stack size
          
          SEC                 ; Prepare to subtract
          
          LDA #0              ; Subtract low byte from zero in place on stack
          SBC EXPRS_L-1,X
          STA EXPRS_L-1,X
          
          LDA #0              ; Subtract high byte from zero in place on stack
          SBC EXPRS_H-1,X
          STA EXPRS_H-1,X

_END      RTS

_SYN      JMP RAISE_SYN       ; Raise a syntax error
          
_JMP
          .WORD EXTIME
          .WORD EXPEEK
          .WORD EXRND
          .WORD EXNOT
          .WORD EXABS
          .WORD EXSQR
          .WORD EXAND
          .WORD EXOR
          .WORD EXXOR
          .WORD EXMOD
          .WORD EXVAL
          .WORD EXLEN
          .WORD EXASC

;
; EXTIME
;
; Evaluates the TIME pseudovariable, pushing the current JIFFIES value onto the
; expression stack. Interrupts are temporarily disabled to read the JIFFIES.
;
; Uses:
;
;   A             Clobbered
;   PROGOFF       Current position in current line, updated
;   NUMANS        Clobbered
;   JIFFIES       Current value read and pushed on expression stack
;
EXTIME    SEI                 ; Disable interrupts
          
          LDA JIFFIES         ; Copy the current jiffies count
          STA NUMANS
          
          LDA JIFFIES+1
          STA NUMANS+1
          
          CLI                 ; Enable interrupts
          
          JSR PUSHANS         ; Push it as the result
                    
          RTS

;
; EXPEEK
;
; Evaluates the PEEK function. Evaluates an expression used as an address, 
; then returns the byte at that address by pushing it on the expression stack.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine. 
;
; Uses:
;
;   A             Clobbered
;   NUMONE        Clobbered
;   NUMANS        Clobbered
;
EXPEEK    JSR EXONEARG        ; Evaluate one number argument to get the address
          
          JSR POPONE          ; Pop the address off the expression stack
       
          LDA (NUMONE)        ; Read the byte at the address
          
          STA NUMANS          ; Copy it over to the NUMANS variable (high byte zeroed)
          STZ NUMANS+1
          
          JSR PUSHANS         ; Push it on the expression stack
          
          RTS                 ; All done

;
; EXRND
;
; Evaluates the RND function. If an argument is provided the expression is evaluated and
; used as the new random number seed. A new random number is generated using RND16 and
; returned.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine.
;
; Uses:
;
;   A             Clobbered
;   X             Clobbered
;   Y             Clobbered
;   PROGOFF       Updated
;   RANDOML       May be updated
;   RANDOMH       May be updated
;
EXRND     JSR EXLPAREN        ; Parse left parenthesis

          JSR EXSKIP          ; Skip any whitespace
          
          LDY PROGOFF         ; Check the next character
          LDA (PROGPTR),Y
          
          CMP #CHR_RPAREN     ; If a right parenthesis then just compute the next random
          BEQ _CALC
    
          JSR EXEXPR          ; Evaluate new seed value
          
          LDX EXPRSNUM        ; Pop the new random seed off the expression stack

          LDA EXPRS_L-1,X     ; Complement the low byte and put it back on stack
          STA RANDOML

          LDA EXPRS_H-1,X     ; Complement the high byte and put it back on stack
          STA RANDOMH
          
          DEC EXPRSNUM        ; Decrement expression stack position
          
_CALC     JSR EXRPAREN        ; Consume right parenthesis

          JSR RND16           ; Calculate random number
          
          JSR PUSHANS         ; Push the result on the stack
          
          RTS

;
; EXNOT
;
; Evaluates the NOT function. Evaluates the argument provided and then replaces its
; value on the stack with its bits negated.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine.
;
; Uses:
;
;   A             Clobbered
;   X             Clobbered
;
EXNOT     JSR EXONEARG        ; Evaluate one number argument
          
          LDX EXPRSNUM        ; Get the current expression stack size
          
          LDA EXPRS_L-1,X     ; Complement the low byte and put it back on stack
          EOR #$FF
          STA EXPRS_L-1,X

          LDA EXPRS_H-1,X     ; Complement the high byte and put it back on stack
          EOR #$FF
          STA EXPRS_H-1,X
          
          RTS

;
; EXABS
;
; Evaluates the ABS function. Evaluates the argument provided and then replaces its
; value on the stack with its absolute value.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine.
;
; Uses:
;
;   A             Clobbered
;   X             Clobbered
;
EXABS     JSR EXONEARG        ; Evaluate one number argument

          LDX EXPRSNUM        ; Get the current expression stack size
          
          LDA EXPRS_H-1,X     ; Is it a negative number?
          BPL _DONE
          
          SEC                 ; Prepare to subtract
          
          LDA #0              ; Subtract low byte from zero in place on stack
          SBC EXPRS_L-1,X
          STA EXPRS_L-1,X
          
          LDA #0              ; Subtract high byte from zero in place on stack
          SBC EXPRS_H-1,X
          STA EXPRS_H-1,X
          
_DONE     RTS

;
; EXSQR
;
; Evaluates the SQR function. Evaluates the argument provided and then calculates its
; square root using the SQR16 routine. If the argument is negative a logic error is
; raised.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine.
;
; Uses:
;
;   A             Clobbered
;   NUMONE        Clobbered
;
EXSQR     JSR EXONEARG        ; Evaluate one number argument

          JSR POPONE          ; Pop value off stack
          
          LDA NUMONE+1        ; Ensure value for square root is positive (test highest bit)
          BIT #$80
          BNE _LOG
          
          JSR SQR16           ; Calculate the square root
          
          JSR PUSHANS         ; Push answer back on stack
          
          RTS                 ; All done
          
_LOG      JMP RAISE_LOG       ; Quantity error (argument cannot be negative)

;
; EXAND
;
; Evaluates the AND function. Evaluates the two arguments provided and then returns 
; the bitwise AND of their values as the top value on the expression stack.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine.
;
; Uses:
;
;   A             Clobbered
;   X             Clobbered
;   EXPRSNUM      Decremented
;   EXPRS_L       Modified
;   EXPRS_H       Modified
;
EXAND     JSR EXTWOARG        ; Evaluate two number arguments to get our operands
          
          LDX EXPRSNUM        ; Get the current expression stack size

          LDA EXPRS_L-2,X     ; AND number low bytes together and put back on stack
          AND EXPRS_L-1,X
          STA EXPRS_L-2,X

          LDA EXPRS_H-2,X     ; AND number high bytes together and put back on stack
          AND EXPRS_H-1,X
          STA EXPRS_H-2,X
          
          DEC EXPRSNUM        ; Decrement stack by one (took two values off, put result back on)
          
          RTS                 ; All done

;
; EXOR
;
; Evaluates the OR function. Evaluates the two arguments provided and then returns 
; the bitwise OR of their values as the top value on the expression stack.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine.
;
; Uses:
;
;   A             Clobbered
;   X             Clobbered
;   EXPRSNUM      Decremented
;   EXPRS_L       Modified
;   EXPRS_H       Modified
;  
EXOR      JSR EXTWOARG        ; Evaluate two number arguments to get our operands
          
          LDX EXPRSNUM        ; Get the current expression stack size

          LDA EXPRS_L-2,X     ; OR number low bytes together and put back on stack
          ORA EXPRS_L-1,X
          STA EXPRS_L-2,X

          LDA EXPRS_H-2,X     ; OR number high bytes together and put back on stack
          ORA EXPRS_H-1,X
          STA EXPRS_H-2,X
          
          DEC EXPRSNUM        ; Decrement stack by one (took two values off, put result back on)
          
          RTS                 ; All done
    
;
; EXXOR
;
; Evaluates the XOR function. Evaluates the two arguments provided and then returns 
; the bitwise exclusive-OR of their values as the top value on the expression stack.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine.
;
; Uses:
;
;   A             Clobbered
;   X             Clobbered
;   EXPRSNUM      Decremented
;   EXPRS_L       Modified
;   EXPRS_H       Modified
;
EXXOR     JSR EXTWOARG        ; Evaluate two number arguments to get our operands
          
          LDX EXPRSNUM        ; Get the current expression stack size

          LDA EXPRS_L-2,X     ; XOR number low bytes together and put back on stack
          EOR EXPRS_L-1,X
          STA EXPRS_L-2,X
          
          LDA EXPRS_H-2,X     ; XOR number high bytes together and put back on stack
          EOR EXPRS_H-1,X
          STA EXPRS_H-2,X
          
          DEC EXPRSNUM        ; Decrement stack by one (took two values off, put result back on)
          
          RTS                 ; All done

;
; EXMOD
;
; Evaluates the MOD function. Evaluates the two arguments provided and then returns 
; the result of argument 1 MOD argument 2 by calling MOD16 and putting its result on
; the expression stack.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine.
;
; Uses:
;
;   A             Clobbered
;   NUMONE        Clobbered
;   NUMTWO        Clobbered
;    
EXMOD     JSR EXTWOARG        ; Evaluate two number arguments to get our operands

          JSR POPBOTH         ; Pop both the arguments into NUMONE and NUMTWO
          
          JSR PRE16
          
          PHA
          
          JSR MOD16           ; Calculate the modulus
          
          PLA
          
          JSR ADJ16
          
          JSR PUSHANS         ; Push the answer back on the expression stack
          
          RTS                 ; All done

;
; EXVAL
;
; Evaluates the VAL function. Evaluates a string argument and then converts it to a
; numeric value (or zero if it cannot be parsed).
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine.
;
; Uses:
;
;   A             Clobbered
;   X             Clobbered
;   Y             Clobbered
;   EXPRS_L       Modified
;   EXPRS_H       Modified
;    
EXVAL     JSR EXSTRARG        ; Evaluate a string function (only takes string variables)
          
          LDX EXPRSNUM        ; Get the stack size
          
          LDA EXPRS_L-1,X     ; Copy the string address to MEMSPTR
          STA MEMSPTR
          LDA EXPRS_H-1,X
          STA MEMSPTR+1
          
          LDY #0              ; Start at beginning of the string
          
          LDA (MEMSPTR),Y     ; Check for leading minus (negative numbers)
          CMP #CHR_MINUS
          BEQ _NEG
          
_POS      JSR TONUMBER        ; Convert to a number
                 
          LDA NUMANS          ; Copy the resulting number back on the stack
          STA EXPRS_L-1,X
          
          LDA NUMANS+1
          STA EXPRS_H-1,X
          
          RTS                 ; All done
          
_NEG      INY                 ; Skip leading minus
                    
          JSR TONUMBER        ; Convert to a number
          
          SEC                 ; Subtract result from zero to get a negative number      
          
          LDA #0
          SBC NUMANS
          STA EXPRS_L-1,X
          
          LDA #0
          SBC NUMANS+1
          STA EXPRS_H-1,X
          
          RTS                 ; All done

;
; EXLEN
;
; Evaluates the LEN function. Evaluates a string argument and then calculates its length
; by counting characters until a NUL character is reached. If no terminating char is 
; found a system error is raised.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine.
;
; Uses:
;
;   A             Clobbered
;   Y             Clobbered
;   NUMONE        Clobbered
;   NUMTWO        Clobbered
;   NUMANS        Clobbered
;
EXLEN     JSR EXSTRARG        ; Evaluate a string function (only takes string variables)
          
          JSR POPONE          ; Pop the result into NUMONE
          
          STZ NUMANS          ; Start with a character count of zero
          STZ NUMANS+1
          
_LOOP     LDA (NUMONE)        ; Load the character and see if it's a zero (NUL ends the string)
          BEQ _DONE
          
          INC NUMONE          ; Move to the next character
          BEQ _SYS
          
          INC NUMANS          ; Increment count and repeat (relies on strings being at most 255 chars)
          BRA _LOOP
          
_DONE     JSR PUSHANS         ; Push the answer on the stack
          
          RTS                 ; All done

_SYS      JMP RAISE_SYS       ; Indicate we couldn't find a terminating NUL

;
; EXASC
;
; Evaluates the ASC function. Evaluates a string argument and returns the numeric value
; for the first character of the string.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine.
;
; Uses:
;
;   A             Clobbered
;   Y             Clobbered
;   NUMONE        Clobbered
;   NUMTWO        Clobbered
;   NUMANS        Clobbered
;   
EXASC     JSR EXLPAREN        ; Left parenthesis
          
          JSR EXVAR           ; String variable
          BCC _SYN
        
          JSR EXRPAREN        ; Right parenthesis
          
          JSR POPONE          ; Get string pointer
          
          LDA (NUMONE)        ; Read character at beginning 
          
          STA NUMANS          ; Store character code on stack as result
          STZ NUMANS+1
          
          JSR PUSHANS
          
          RTS

_SYN      JMP RAISE_SYN       ; Syntax error
          
;
; EXONEARG
;
; Helper routine that evaluates a single numeric argument between parentheses.
;
EXONEARG  JSR EXLPAREN
          JSR EXEXPR
          JSR EXRPAREN
          RTS

;
; EXTWOARG
;
; Helper routine that evaluates two numeric arguments (separated by commas)
; between parentheses.
;
EXTWOARG  JSR EXLPAREN
          JSR EXEXPR
          JSR EXCOMMA
          JSR EXEXPR
          JSR EXRPAREN
          RTS

;
; EXSTRARG
;
; Helper routine that evaluates a string variable argument between two 
; parentheses. If the argument is not a string variable a syntax error occurs.
;
EXSTRARG  JSR EXLPAREN
          JSR EXVAR
          BCS _OK
          JMP RAISE_SYN
_OK       JSR EXRPAREN
          RTS

;
; EXSTREXPR
;
; Evaluates a string expression, concatenating string terms into the buffer.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine.
;
; Uses:
;
;   A             Clobbered
;   Y             Clobbered
;   PROGOFF       Updated with new position in current line
;
EXSTREXPR JSR EXSKIP
          
          JSR EXSTRTERM       ; Evaluate the string term we started with
          
_LOOP     JSR EXSKIP          ; Skip any leading space
          
          LDY PROGOFF         ; Load the next character
          LDA (PROGPTR),Y
          
          CMP #CHR_PLUS       ; Concatenation operator is the only one supported
          BEQ _CAT
          
          RTS                 ; All done

_CAT      INC PROGOFF         ; Consume operator
          
          JSR EXSTRTERM       ; Evaluate the next string term to concatenate
          
          BRA _LOOP           ; Next
          
          RTS

;
; EXSTRTERM
;
; Evaluates a term in a string expression, putting the results into the current
; position in the output buffer using the PUTOUT routine. If a string argument 
; has no matching NUL character then a system error is raised.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine.
;
; Uses:
;
;   A             Clobbered
;   Y             Clobbered
;   PROGOFF       Updated with new position in current line
;   NUMONE        Clobbered
; 
EXSTRTERM LDY PROGOFF         ; Load the next character
          LDA (PROGPTR),Y
          
          CMP #CHR_QUOTE      ; String literal
          BEQ _LIT
          
          CMP #TOK_CHR        ; CHR$ function (char code to string)
          BEQ EXCHR
          
          CMP #TOK_STR        ; STR$ function (number to string)
          BEQ EXSTR
          
          CMP #TOK_SUB        ; SUB$ function (substring to string)
          BEQ EXSUB
          
          JSR EXVAR           ; String variable is all we have left
          BCS _VAR

          JMP RAISE_SYN       ; Otherwise it's a syntax error, nothing we can do
          
_LIT      INY                 ; Skip the leading quote

_LITLOOP  LDA (PROGPTR),Y     ; Read the next character
          
          CMP #CHR_NL         ; Newlines shouldn't happen, but if they do, stop immediately
          BEQ _LITDONE
          
          INY                 ; Consume whatever character we read
          
          CMP #CHR_QUOTE      ; End quote means we're done with the string literal
          BEQ _LITDONE
          
          JSR PUTOUT          ; Otherwise just copy the character to the output buffer
          
          BRA _LITLOOP        ; Repeat
          
_LITDONE  STY PROGOFF         ; Update the offset in the current line

          RTS                 ; All done

_VAR      JSR POPONE          ; Pop the variable address off the stack

          LDY #0              ; Start at the beginning
          
_VARLOOP  LDA (NUMONE),Y      ; Read the character from the string (zero/NUL indicates end of string)
          BEQ _VARDONE
          
          JSR PUTOUT          ; Put the character from the string into the output buffer
          
          INY                 ; Consume the character
                    
          BEQ _SYS            ; If we wrapped around then we never found a terminating NUL
          
          BRA _VARLOOP
  
_VARDONE  RTS                 ; All done
    
_SYS      JMP RAISE_SYS       ; Raise system error indicating we didn't find a NUL

;
; EXCHR
;
; Evaluates a CHR$ string function in a string expression, putting the characters
; corresponding to the evaluated numeric expressions into the output buffer. If the
; value is outside the valid range (greater than one byte), a logic error is raised.
;
; This function accepts a variable number of arguments.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine.
;
; Uses:
;
;   A             Clobbered
;   Y             Clobbered
;   PROGOFF       Updated with new position in current line
;   NUMONE        Clobbered
; 
EXCHR     INC PROGOFF         ; Consume the "CHR$" token

          JSR EXLPAREN        ; Read left parenthesis
          
_LOOP     JSR EXEXPR          ; Evaluate numeric expression
          
          JSR POPONE          ; Pop the result
          
          LDA NUMONE+1        ; Ensure we have a valid character
          BNE _LOG
          
          LDA NUMONE          ; Load the character

          JSR PUTOUT          ; Write it to the buffer
          
          JSR EXSKIP          ; Skip any whitespace

          LDY PROGOFF         ; Load the next character in the current line
          LDA (PROGPTR),Y
      
          INC PROGOFF         ; Consume the character
                    
          CMP #CHR_RPAREN     ; Right parenthesis is the end
          BEQ _DONE
          
          CMP #CHR_COMMA      ; Comma means we continue on for another argument
          BEQ _LOOP
          
          JMP RAISE_SYN       ; Otherwise we had a syntax error
          
_DONE     RTS                 ; All done
          
_LOG      JMP RAISE_LOG       ; Character value wasn't legal (must be between 0 and 255)

;
; EXSTR
;
; Evaluates a STR$ string function in a string expression, evaluating a numeric expression
; and putting its string equivalent into the output buffer.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine.
;
; Uses:
;
;   A             Clobbered
;   PROGOFF       Updated with new position in current line
;   NUMONE        Clobbered
; 
EXSTR     INC PROGOFF         ; Consume the "STR$" token

          JSR EXONEARG        ; Evaluate a one-argument numeric function to get the number
          
          JSR POPONE          ; Pop the number into NUMONE
          
          LDA NUMONE+1        ; Is it signed?
          BPL _NUM       
          
          LDA #CHR_MINUS      ; Print minus sign
          JSR PUTOUT
          
          SEC                 ; Calculate absolute value of negative number
          
          LDA #0
          SBC NUMONE
          STA NUMONE
          
          LDA #0
          SBC NUMONE+1
          STA NUMONE+1
                    
_NUM      JSR TOSTRING        ; Convert it to a string in the output buffer
          
          RTS                 ; All done

;
; EXSUB
;
; Evaluates a SUB$ string function in a string expression, getting a string variable
; and two numeric expressions, then copying the substring corresponding to that range
; into the output buffer. If the index is out of range then a logic error is raised.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine.
;
; Uses:
;
;   A             Clobbered
;   X             Clobbered
;   Y             Clobbered
;   PROGOFF       Updated with new position in current line
;   NUMONE        Clobbered
;   NUMTWO        Clobbered
; 
EXSUB     INC PROGOFF         ; Consume the SUB$ token

          JSR EXLPAREN        ; Left parenthesis
          
          JSR EXVAR           ; String variable
          BCC _SYN
                    
          JSR EXCOMMA         ; Comma separator

          JSR EXEXPR          ; Starting index
          
          JSR EXCOMMA         ; Comma separator
          
          JSR EXEXPR          ; Number of characters to copy
          
          JSR EXRPAREN        ; Closing parenthesis
          
          JSR POPONE          ; Get number of characters

          LDX NUMONE          ; Store the number in X for our count
          
          JSR POPBOTH         ; Get the variable address and starting index
          
          LDA NUMTWO+1        ; Check that the starting position high byte is zero
          BNE _LOG
          
          LDY NUMTWO          ; Load the starting position
          
_LOOP     LDA (NUMONE),Y      ; Read the next character from the source string
          BEQ _DONE
          
          JSR PUTOUT          ; Put it in the output buffer
          
          INY                 ; Skip a byte for each character in the string
          
          CPY #0              ; If we wrapped around it means we had a bad position
          BEQ _LOG
          
          DEX                 ; Decrement number of remaining characters and loop if more
          BNE _LOOP
          
_DONE     RTS                 ; All done
          
_SYN      JMP RAISE_SYN       ; Raise syntax error

_LOG      JMP RAISE_LOG       ; Raise logic error (array index out of bounds)

;
; EXVAR
;
; Evaluates a variable (number or string) and pushes the resulting address in memory onto
; the expression stack (via PUSHANS). Note that like most of Cody Basic's interpreter, it
; relies on variables/arrays being page-aligned.
;
; If an array index is out of bounds a logic error is raised.
;
; If the variable is a number, the carry flag is NOT set.
; If the variable is a string, the carry flag IS set.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine. The following list of variables is only a start.
;
; Uses:
;
;   A             Clobbered
;   Y             Clobbered
;   P             Carry flag set (string) or cleared (number)
;   PROGOFF       Current position in the current line, updated as characters consumed
;   PROGPTR       Used to determine the current line
;
EXVAR     JSR EXSKIP          ; Consume leading space
          
          LDY PROGOFF         ; Load the next character from the current line
          LDA (PROGPTR),Y
          
          INC PROGOFF         ; Consume the character
          
          JSR ISALPHA         ; If not a letter, it's a syntax error
          BCC _SYN
          
          SEC                 ; Calculate the page number assuming we have an array variable
          SBC #CHR_AUPPER
          
          CLC                 ; Determine the actual page location based on the start of vars
          ADC #>ARRA
          
          STZ NUMANS          ; Assume by default we DO NOT have an index into an array
          STA NUMANS+1
          
          LDY PROGOFF         ; Load another character
          LDA (PROGPTR),Y
          
          CMP #CHR_DOLLAR     ; String variable so we need to adjust our pointer into string memory
          BEQ _STR
          
          CMP #CHR_LPAREN     ; Array index so we need to adjust our pointer within array memory
          BNE _NUM
          
          JSR EXLPAREN        ; Consume left parenthesis
          
          LDA NUMANS+1        ; Preserve high byte of variable address (will be clobbered by expr eval)
          PHA
          
          JSR EXEXPR          ; Evaluate expression for array index
          
          PLA                 ; Restore the high byte of the variable address (just got clobbered)
          STA NUMANS+1
          
          JSR EXRPAREN        ; Consume right parenthesis
          
          JSR POPONE          ; Pop the array index off the stack
          
          LDA NUMONE+1        ; High byte should be zero (or will be out of range)
          BNE _LOG
          
          LDA NUMONE          ; Low byte should be less than 128 (or will be out of range)
          BIT #$80
          BNE _LOG
          
          ASL A               ; Shift low byte by one (multiply by two because numbers are two bytes wide)
          
          STA NUMANS          ; Store the index as the low byte

_NUM      JSR PUSHANS         ; Store the address of the variable
                    
          CLC                 ; Clear carry to indicate it's a number variable

          RTS                 ; All done
               
_STR      CLC                 ; Adjust pointer from array memory to string memory
          LDA #26
          ADC NUMANS+1
          STA NUMANS+1
          
          INC PROGOFF         ; Consume dollar sign

          JSR PUSHANS         ; Store the address of the variable

          SEC                 ; Set carry to indicate it's a string variable

          RTS                 ; All done

_SYN      JMP RAISE_SYN       ; Raise a syntax error

_LOG      JMP RAISE_LOG       ; Raise a logic error (array index out of bounds)

;
; EXEQUALS
;
; Helper for requiring the next non-whitespace character to be an equal sign. Calls
; EXCHARACT for the actual testing and logic.
; 
; Uses:
;
;   A             Clobbered
;
EXEQUALS  LDA #TOK_EQ
          BRA EXCHARACT
          
;
; EXCOMMA
;
; Helper for requiring the next non-whitespace character to be a comma. Calls EXCHARACT
; for the actual testing and logic.
; 
; Uses:
;
;   A             Clobbered
;
EXCOMMA   LDA #CHR_COMMA
          BRA EXCHARACT

;
; EXLPAREN
;
; Helper for requiring the next non-whitespace character to be a left parenthesis.
; Calls EXCHARACT for the actual testing and logic.
; 
; Uses:
;
;   A             Clobbered
;
EXLPAREN  LDA #CHR_LPAREN
          BRA EXCHARACT

;
; EXRPAREN
;
; Helper for requiring the next non-whitespace character to be a right parenthesis.
; Calls EXCHARACT for the actual testing and logic.
; 
; Uses:
;
;   A             Clobbered
;
EXRPAREN  LDA #CHR_RPAREN
          BRA EXCHARACT

;
; EXCHARACT
;
; Tests that the next NON-WHITESPACE character in the current line matches the
; current value of the accumulator. If they are different than RAISE_SYN is
; called. On a match the offset into the current line (PROGOFF) is updated.
;
; Uses:
;
;   A             Accumulator containing the character to test for
;   Y             Clobbered
;   PROGOFF       Updated to the new line position
;
EXCHARACT JSR EXSKIP          ; Skip any trailing space
          
          LDY PROGOFF         ; Get offset into current line
          
          CMP (PROGPTR),Y     ; Compare with the value in the accumulator
          BNE _SYN

          INC PROGOFF         ; Consume the character since it was a match
          
          RTS                 ; All done
          
_SYN      JMP RAISE_SYN       ; Raise a syntax error

;
; POPONE
;
; Pops the top of the expression stack (EXPRS_L/EXPRS_H) into NUMONE.
;
; No check for stack underflow as this will never occur under correct interpreter
; operation. Problems in user code that could produce such a condition should be
; caught as syntax errors.
;
; Uses:
;
;   NUMONE        Updated with the top number from the expression stack
;   EXPRSNUM      Updated with the new stack item count
;   EXPRS_L       Contains the number's low byte on the top of the stack
;   EXPRS_H       Contains the number's high byte on the top of the stack
;
POPONE    PHA                 ; Preserve registers
          PHX

          LDX EXPRSNUM        ; Fetch the current size of the expression stack
          
          LDA EXPRS_L-1,X     ; Store the low byte into NUMONE
          STA NUMONE
          
          LDA EXPRS_H-1,X     ; Store the high byte into NUMONE
          STA NUMONE+1
          
          DEC EXPRSNUM        ; Decrement the count by one
          
          PLX                 ; Restore registers
          PLA
          
          RTS                 ; All done

;
; POPBOTH
;
; Pops the top two values on the expression stack (EXPRS_L/EXPRS_H) into NUMONE and
; NUMTWO. The topmost value goes into NUMTWO and the second to topmost goes into 
; NUMONE.
;
; No check for stack underflow as this will never occur under correct interpreter
; operation. Problems in user code that could produce such a condition should be
; caught as syntax errors.
;
; Uses:
;
;   NUMONE        Updated with the second-to-top number from the expression stack
;   NUMTWO        Updated with the top number from the expression stack
;   EXPRSNUM      Updated with the new stack item count
;   EXPRS_L       Contains the number's low byte on the top of the stack
;   EXPRS_H       Contains the number's high byte on the top of the stack
;
POPBOTH   PHA                 ; Preserve registers
          PHX

          LDX EXPRSNUM        ; Fetch the current size of the expression stack
          
          DEX                 ; Decrement the count by one
          
          LDA EXPRS_L,X       ; Store the low byte into NUMTWO
          STA NUMTWO
          
          LDA EXPRS_H,X       ; Store the high byte into NUMTWO
          STA NUMTWO+1

          DEX                 ; Decrement the count by one

          LDA EXPRS_L,X       ; Store the low byte into NUMONE
          STA NUMONE
          
          LDA EXPRS_H,X       ; Store the high byte into NUMONE
          STA NUMONE+1
                    
          STX EXPRSNUM        ; Update the size of the expression stack

          PLX                 ; Restore registers
          PLA
          
          RTS                 ; All done

;
; PUSHANS
;
; Pushes the value in NUMANS onto the interpreter's expression stack. If the stack
; would overflow then a system error is raised instead.
;
; Uses:
;
;   NUMANS        The number to push onto the expression stack
;   EXPRSNUM      Updated with the new stack item count
;   EXPRS_L       Updated with the low byte of NUMANS on the stack
;   EXPRS_H       Updated with the high byte of NUMANS on the stack
;
PUSHANS   PHA                 ; Preserve registers
          PHX
          
          LDX EXPRSNUM        ; Fetch the current size of the expression stack
          
          CPX #MAXSTACK       ; Check that the stack isn't going to overflow
          BCS _SYS
          
          LDA NUMANS          ; Store NUMANS low byte on stack
          STA EXPRS_L,X
          
          LDA NUMANS+1        ; Store NUMANS high byte on stack
          STA EXPRS_H,X
          
          INC EXPRSNUM        ; Increment the number of items on the stack by one
          
          PLX                 ; Restore registers
          PLA
          
          RTS                 ; All done
          
_SYS      JMP RAISE_SYS       ; Expression stack would overflow

;
; RESTORE
;
; Resets all data buffer-related variables (DBUFLEN, DBUFPOS) and moves the DATAPTR to
; the start of the program. Called when starting to run a program or when a RESTORE
; statement is executed in a running program.
;
; Uses:
;
;   DBUFLEN       Reset to zero
;   DBUFPOS       Reset to zero
;   DATAPTR       Set to PROGPTR
;
RESTORE   STZ DBUFLEN         ; Reset data buffer positions
          STZ DBUFPOS

          LDA #<PROGMEM       ; Move data line pointer to start of program
          STA DATAPTR+0
          LDA #>PROGMEM
          STA DATAPTR+1
          
          RTS

;
; MOREDATA
;
; Executes a DATA statement. Unlike all other statements this occurs when a READ
; statement needs more data, so some workarounds for the interpreter are required.
; We need to temporarily preserve some of the running program's position variables,
; override them with those for the DATA statements, and restore them when we're done.
;
; The routine loops until a new DATA line is found or the end of the program is
; reached. If a DATA statement is found, its values are loaded into the DBUF for
; use by READ statements.
;
; Uses:
;
;   A             Clobbered
;   X             Clobbered
;   Y             Clobbered
;   DBUFL         Updated with data
;   DBUFH         Updated with data
;   DBUFPOS       Incremented as data added
;   DBUFLEN       Incremented as data added
;
MOREDATA  LDA PROGPTR         ; Preserve the current program pointer
          PHA
          LDA PROGPTR+1
          PHA
          
          LDA PROGOFF         ; Preserve the current program line offset
          PHA
          
          LDA DATAPTR         ; Temporarily use the line pointer as the data pointer
          STA PROGPTR
          LDA DATAPTR+1
          STA PROGPTR+1

_LINE     JSR ISEND           ; Are we at the end of the program?
          BNE _LINEOK
          
          JMP _DONE           ; End of program (need JMP because of distance)

_LINEOK   LDA #4              ; Start after line number in the current line
          STA PROGOFF
          
          JSR EXSKIP          ; Skip whitespace

          LDY PROGOFF         ; Read the next token
          LDA (PROGPTR),Y
          INC PROGOFF
          
          CMP #TOK_DATA       ; If a DATA statement, process the line
          BEQ _LOOP
          
          JSR _NXTLINE        ; Otherwise go to the next line
          
          BRA _LINE
          
_LOOP     JSR EXSKIP          ; Skip whitespace
          
          LDY PROGOFF         ; Load the next character from the current line
          LDA (PROGPTR),Y
          
          INY                 ; Consume number token symbol
          
          CMP #CHR_NL         ; Newline means we're done
          BEQ _EOL
          
          CMP #CHR_MINUS      ; Minus means a negative number
          BEQ _NEG
          
          CMP #TOK_NUM        ; Otherwise just a number (or a syntax error)
          BNE _SYN
          
_POS      LDX DBUFLEN         ; Load the current data buffer length
          
          LDA (PROGPTR),Y     ; Store data low byte
          STA DBUFL,X
          INY
          
          LDA (PROGPTR),Y     ; Store data high byte
          STA DBUFH,X
          INY
          
          BRA _NXT            ; Next number in list
          
_NEG      STY PROGOFF         ; Update program offset

          JSR EXSKIP          ; Skip any trailing space after the minus sign

          LDY PROGOFF         ; Load the next character from the current line
          LDA (PROGPTR),Y
          
          CMP #TOK_NUM        ; Must be a number
          BNE _SYN
          INY
          
          LDX DBUFLEN         ; Load the current data buffer length
                    
          SEC                 ; Prepare to subtract
          
          LDA #0              ; Subtract low byte from zero and store in buffer
          SBC (PROGPTR),Y
          STA DBUFL,X
          INY
          
          LDA #0              ; Subtract high byte from zero and store in buffer
          SBC (PROGPTR),Y 
          STA DBUFH,X
          INY
          
_NXT      STY PROGOFF         ; Update program offset

          INC DBUFLEN         ; Update data buffer length (overflow shouldn't happen)
                    
          JSR EXSKIP          ; Skip any trailing space after the number
          
          LDY PROGOFF         ; Read and consume the next character in the line
          LDA (PROGPTR),Y
          INC PROGOFF
          
          CMP #CHR_NL         ; Newline means we're done
          BEQ _EOL
          
          CMP #CHR_COMMA      ; Otherwise it needs to be a comma
          BNE _SYN
          
          BRA _LOOP           ; Next data value in list

_EOL      JSR _NXTLINE
        
_DONE     PLA                 ; Restore the program line offset
          STA PROGOFF
          
          PLA                 ; Restore the program pointer
          STA PROGPTR+1
          PLA
          STA PROGPTR+0

          RTS

_SYN      JMP RAISE_SYN

_NXTLINE  CLC                 ; Move to the next line by adding the line length

          LDA PROGPTR
          ADC (PROGPTR)
          STA PROGPTR
          STA DATAPTR

          LDA PROGPTR+1
          ADC #0
          STA PROGPTR+1
          STA DATAPTR+1

          RTS
          
;
; ISEND
;
; Tests if the interpreter has reached the end of the BASIC program by testing if PROGPTR
; and PROGTOP are equal. The processor flags will indicate whether the values were equal
; or not.
;
; Uses:
;
;   A           Clobbered
;
ISEND     LDA PROGPTR
          CMP PROGTOP
          BNE _DONE
          
          LDA PROGPTR+1
          CMP PROGTOP+1
          BNE _DONE

_DONE     RTS

;
; NEWPROG
;
; Resets program memory positions, calling NEWVARS to zero out data memory and RESTORE to
; clear data buffer space. The current program pointer is also reset. This routine should
; be called on startup and whenever NEW is executed in the REPL.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine. The following list of variables is only a start.
;
; Uses:
;
;   A             Clobbered
;   PROGTOP       Reset to start of program memory (PROGMEM)
;   PROGPTR       Reset to zero
;
NEWPROG   LDA #<PROGMEM       ; Reset top of program memory to base of program memory
          STA PROGTOP+0
          LDA #>PROGMEM
          STA PROGTOP+1

          JSR NEWVARS         ; Clear variables
          
          JSR RESTORE         ; Restore data buffer and settings
          
          ;
          ; TODO: Other initialization/program pointer/line number/etc. clearing
          ;

          STZ PROGPTR         ; Clear pointer to current program line (REPL mode by default)
          STZ PROGPTR+1
          
          RTS

;
; NEWVARS
;
; Zeroes out all of data memory (including the actual buffer used for DATA statements,
; which is just a part of the whole). This should be called whenever a new program is
; created (i.e. NEWPROG) as well as whenever a BASIC program is RUN.
;
; Note that as part of the BASIC interpreter, just about any variable may be clobbered
; or modified by this routine. The following list of variables is only a start.
;
; Uses:
;
;   A             Clobbered
;   MEMDPTR       Clobbered
;   MEMSIZE       Clobbered
;
NEWVARS   LDA #<DATAMEM       ; Set contents of data memory
          STA MEMDPTR
          LDA #>DATAMEM
          STA MEMDPTR+1

          LDA #$FF            ; Clear 52 pages of 256 bytes each
          STA MEMSIZE
          LDA #$34
          STA MEMSIZE+1
          
          LDA #0              ; Fill with zeroes
          JSR MEMFILL
          
          RTS

;
; ONLYREPL
;
; Routine that checks the current RUNMODE is zero (indicating REPL mode). If the
; RUNMODE is nonzero then a logic error is raised.
;
; This is intended to be called at the start of any statement that requires a
; particular run mode to function correctly (i.e. used as a guard).
;
; Uses:
;
;   A             Accumulator (clobbered)
;   RUNMODE       Checked to determine current run mode (expected to be zero)
;
ONLYREPL  LDA RUNMODE         ; Load the current run mode and ensure it's zero
          BEQ _OK
          
          JMP RAISE_LOG       ; Raise logic error
          
_OK       RTS

;
; ONLYRUN
;
; Routine that checks the current RUNMODE is nonzero (indicating run mode). If the
; RUNMODE is zero then a logic error is raised.
; 
; This is intended to be called at the start of any statement that requires a particular
; run mode to function correctly (i.e. used as a guard).
;
; Uses:
;
;   A             Accumulator (clobbered)
;   RUNMODE       Checked to determine current run mode (expected to be nonzero)
;       
ONLYRUN   LDA RUNMODE         ; Load the current run mode and ensure it's nonzero
          BNE _OK

          JMP RAISE_LOG       ; Raise logic error
          
_OK       RTS

;
; RAISE_BRK
;
; Helper routine that raises a break. A break is caused by the user pressing the
; CODY and ARROW keys and isn't an error. However, the control flow for a break
; is essentially the same as an error (display a message and return to the REPL
; loop).
;
RAISE_BRK LDA #ERR_BREAK
          BRA ERROR

;
; RAISE_SYN
;
; Helper routine that raises a syntax error. A syntax error occurs when the 
; statement entered into BASIC cannot be parsed. This is very similar to a
; WHAT? error in Tiny Basic.
;    
RAISE_SYN LDA #ERR_SYNTAX
          BRA ERROR

;
; RAISE_LOG
;
; Helper routine that raises a logic error. A logic error occurs when a 
; statement is evaluated but the requested action(s) are not valid to perform.
; This is very similar to a HOW? error in Tiny Basic.
;
; Logic errors include:
;
; - Division by zero
; - NEXT without FOR
; - RETURN without GOSUB
; - Out of DATA during READ
; - Invalid GOTO and GOSUB line numbers
; - Array index out of bounds
; - Illegal quantities (negative instead of positive number)
; - Mode errors (REPL vs RUN)
;
RAISE_LOG LDA #ERR_LOGIC
          BRA ERROR

;
; RAISE_SYS
;
; Helper routine that raises a system error. A system error occurs when a 
; statement is evaluated and the actions performed but cannot be completed
; because of some other reason. This is very similar to a SORRY error in
; Tiny Basic.
;
; System errors include:
;
; - Serial port I/O errors
; - No more memory for FOR-NEXT
; - No more memory for GOSUB-RETURN
; - No more memory for BASIC code
; - Buffer overflow (input, output)
; - Stack overflow (expressions too complex)
; - Input line too long
; - String too long (or unable to find end of string)
;
RAISE_SYS LDA #ERR_SYSTEM
          BRA ERROR

;
; ERROR
;
; Handles an error condition in the BASIC interpreter or related code. The 6502 stack is
; unwound to the value in STACKREG, serial outputs are disabled, IO is directed back to 
; the keyboard and screen, and an error message is displayed based on the ERR_XXX code in
; the accumulator. The exact nature of the message will vary based on the current RUNMODE.
;
; This routine will not return. Control passes to the BASIC interpreter's REPL loop.
; 
; Uses:
;
;   A             Accumulator, should contain ERR_XXX error code
;   S             Unwound to STACKREG
;   PROGPTR       Read to determine line number (based on RUNMODE)
;   RUNMODE       Checked to determine current run mode, then cleared
;   STACKREG      Stack register value to unwind to
;   IOMODE        Cleared
;   IOBAUD        Cleared
;   OBUFLEN       Cleared
;
ERROR     LDX STACKREG        ; Unwind the stack
          TXS
          
          JSR SERIALOFF       ; Turn off serial mode (just in case it was on)
          
          STZ IOMODE          ; Reset IO mode for all future output
          STZ IOBAUD
          
          STZ OBUFLEN         ; Reset output buffer position
          
          PHA                 ; Preserve the provided error code in the accumulator
          
          LDA #CHR_NL         ; Ensure error messages begin on a new line
          JSR PUTOUT
          
          PLA                 ; Restore the error code into the accumulator
          
          CLC                 ; Calculate the message table index for the provided error
          ADC #MSG_ERRORS
          
          JSR PUTMSG          ; Print the error
      
          CMP #MSG_ERRORS     ; "Break" errors don't have the word "error" (just BREAK IN ...)
          BEQ _BREAK
          
          LDA #MSG_ERROR      ; Print the word "ERROR" for all other errors
          JSR PUTMSG
          
_BREAK    LDA RUNMODE         ; Are we running a program right now? (otherwise hide line numbers)
          CMP #RM_PROGRAM
          BNE _NOLINE
          
          LDA #MSG_IN         ; Append "IN" to our error message
          JSR PUTMSG
          
          LDY #1              ; Start at line number position in current line
          
          LDA (PROGPTR),Y     ; Copy line number low byte
          STA NUMONE
          
          INY                 ; Next byte
          
          LDA (PROGPTR),Y     ; Copy line number high byte
          STA NUMONE+1
          
          JSR TOSTRING        ; Write the line number into the buffer
          
_NOLINE   LDA #CHR_NL         ; New line after the error message
          JSR PUTOUT
          
          LDA #CHR_NL         ; Blank line
          JSR PUTOUT
          
          LDA #MSG_READY      ; Ready message
          JSR PUTMSG
          
          JSR FLUSH           ; Print the error message
          
          STZ RUNMODE         ; Reset run mode (REPL mode after errors or breaks)
          
          CLI                 ; Enable interrupts (in case we came from the interrupt routine)
          
          JMP REPL            ; Return to the REPL loop

;
; BLINK
;
; Blinks the cursor. Called by READKBD to indicate the current location for text entry.
; The routine examines one of the bits in the JIFFIES count, determining if the cursor
; should be drawn with reversed attributes or not.
;
; Uses:
;
;   JIFFIES       The jiffies count (examined to determine whether to blink)
;   CURATTR       The current cursor attributes (used when drawing the cursor)
;   CURCOLPTR     The location in memory to update with the cursor attributes
;
BLINK     PHA

          LDA JIFFIES         ; Determine whether we draw the cursor in reverse field
          AND #$40
          BEQ _BLANK

          LDA CURATTR         ; Cursor shown with reversed attributes when bit is low
          BRA _UPDATE

_BLANK    LDA CURATTR         ; Cursor shown with default attributes when bit is high
          JSR SWAPNIBS
          
_UPDATE   STA (CURCOLPTR)     ; Update attributes on screen

          PLA
          
          RTS

;
; SWAPNIBS
;
; Swaps the high and low nibbles in the accumulator.
;
; Uses an approach attributed to David Galloway and published online at
; http://www.6502.org/source/general/SWN.html for further reading.
;
; Uses:
;
;   A             Accumulator, nibbles will be swapped
;
SWAPNIBS  ASL  A
          ADC  #$80
          ROL  A
          ASL  A
          ADC  #$80
          ROL  A
          RTS

;
; TIMERISR
;
; Default interrupt handler for the timer interrupt on the 65C22 VIA. Updates the jiffy
; count in JIFFIES and performs a keyboard scan, checking for user break (CODY + ARROW).
; This routine's address should be copied into ISRPTR as part of the startup sequence.
;
; If a break is detected, a break "error" is raised by calling RAISE_BRK.
; 
; Uses:
;
;   JIFFIES       Updated with the new jiffies count
;   KEYROWxxx     Updated by the keyboard scanning routine 
;
TIMERISR  PHA               ; Preserve accumulator
          
          BIT VIA_T1CL      ; Read the 6522 to clear the interrupt
                    
          JSR KEYSCAN       ; Scan keyboard
          
          INC JIFFIES       ; Increment jiffy count lower byte (after scanning!)
          BNE _TEST
          
          INC JIFFIES+1     ; Increment jiffy count upper byte on overflow
          
_TEST     LDA RUNMODE       ; Only allow breaks if we're running a program
          BEQ _DONE

          LDA KEYROW2       ; Check for Cody key on row 2 (and ONLY the Cody key)
          CMP #$1E
          BNE _DONE

          LDA KEYROW3       ; Check for arrow key on row 3 (and ONLY the arrow key)
          CMP #$0F
          BNE _DONE
          
          JMP RAISE_BRK     ; Break
          
_DONE     PLA               ; Restore accumulator
                    
          RTI               ; Return from interrupt routine

;
; ISRSTUB
;
; Simple routine that jumps to the address in ISRPTR. Because the ISR routine address is
; hardcoded in the ROM, pointing it to this allows non-ROM code to replace the TIMERISR
; with their own custom interrupt handler.
;
ISRSTUB   JMP (ISRPTR)

;
; MAIN
;
; The MAIN routine is the start of the entire system. It performs one-time initialization 
; and checks for the presence of a cartridge on the expansion  port. If one is found, it
; loads the program from the cartridge, otherwise it starts BASIC.
;
; This routine affects too many variables to mention each. Refer to the source instead.
;
MAIN      LDA #>PROGMAX         ; Set the top of program memory to the default page
          STA PROGEND

          JSR INIT              ; Run initialization on startup
          
          JSR CARTCHECK         ; Check for cartridge plugged in
          BEQ BASIC
  
          STZ IOMODE            ; Cartridge found, load and run binary instead of BASIC
          STZ IOBAUD
          JMP LOADBIN
          
BASIC     JSR INIT              ; Re-run BASIC initialization just to be safe

          TSX                   ; Preserve the stack register for unwinding on error conditions
          STX STACKREG

          STZ OBUFLEN           ; Move to beginning of the output buffer
  
          LDA #MSG_GREET        ; Print the welcome message
          JSR PUTMSG
          JSR FLUSH
  
          LDA #MSG_READY        ; Print the ready message
          JSR PUTMSG
          JSR FLUSH
  
          CLI                   ; Enable interrupts and drop through to the REPL loop

REPL      STZ RUNMODE           ; Clear out RUNMODE

          STZ IOMODE            ; Direct all IO to screen and keyboard

          JSR READKBD           ; Read a line of input and advance the screen
          JSR SCREENADV

          JSR TOKENIZE          ; Tokenize the input
  
          LDA TBUF              ; Line number to add or execute the line immediately?
          CMP #$FF
          BNE _EXEC

          JSR ENTERLINE         ; Enter the line into the program
  
          BRA REPL              ; Next read-eval-print loop
  
_EXEC     STZ PROGOFF           ; Start at the beginning of the line
  
          LDA #<TBUF            ; Use the token buffer as the line we're going to run
          STA PROGPTR
          LDA #>TBUF
          STA PROGPTR+1
  
          JSR EXSTMT            ; Execute the statement in the token buffer
  
          STZ OBUFLEN           ; Move to beginning of output buffer

          LDA #MSG_READY        ; Print the ready message after each REPL operation
          JSR PUTMSG
          JSR FLUSH
  
          BRA REPL              ; Next read-eval-print loop

;
; INIT
;
; Initialization routine for Cody BASIC. Called at startup and when a program returns
; from a binary program to restore some sensible defaults. Note that PROGEND is not
; reset by this routine so that expansion cartridges and binary programs can load in
; resident programs at the top of program memory and move down the boundary location.
;
; This routine affects too many variables to mention each. Refer to the source instead.
;
INIT      SEI                 ; Shut off interrupts

          LDA #<CHAR_BASE     ; Copy ROM characters into video memory region on startup
          STA MEMDPTR
          LDA #>CHAR_BASE
          STA MEMDPTR+1
  
          LDA #<CHRSET
          STA MEMSPTR
          LDA #>CHRSET
          STA MEMSPTR+1
  
          LDA #<2048
          STA MEMSIZE
          LDA #>2048
          STA MEMSIZE+1
  
          JSR MEMCOPYDN
  
          STZ IOMODE
          STZ IOBAUD
  
          STZ VID_SCRL          ; Clear out scroll registers
  
          STZ VID_CNTL          ; Clear out control register
  
          LDA #$E7              ; Point the video hardware to default color memory, border color yellow
          STA VID_COLR
  
          LDA #$95              ; Point the video hardware to the default screen and character set
          STA VID_BPTR
  
          STZ KEYLAST           ; Clear out the major keyboard-related zero page variables
          STZ KEYLOCK
          STZ KEYMODS
          STZ KEYCODE
  
          STZ IBUFLEN           ; Clear out buffer lengths
          STZ OBUFLEN
          STZ TBUFLEN
  
          STZ JIFFIES           ; Clear jiffy count
          STZ JIFFIES+1
  
          LDA #<TIMERISR        ; Set up ISR routine address
          STA ISRPTR+0
          LDA #>TIMERISR
          STA ISRPTR+1
  
          LDA #<JIF_T1C         ; Set up VIA timer 1 to emit ticks (60 per second)
          STA VIA_T1CL
          LDA #>JIF_T1C
          STA VIA_T1CH
  
          LDA #$40              ; Set up VIA timer 1 continuous interrupts, no outputs
          STA VIA_ACR
  
          LDA #$7F              ; Disable all interrupt sources
          STA VIA_IER

          LDA #$C0              ; Enable VIA timer 1 interrupt
          STA VIA_IER
  
          LDA #$07              ; Set VIA data direction register A to 00000111 (pins 0-2 outputs, pins 3-7 inputs)
          STA VIA_DDRA
  
          LDA #$16              ; Set current cursor attribute to white on blue
          STA CURATTR
  
          LDA #CHR_QUEST        ; Use question mark for input prompts
          STA PROMPT
  
          JSR SCREENCLR         ; Clear the screen on startup

          JSR NEWPROG           ; Clear memory and reset variables

          RTS                   ; All done
          
;
; CARTCHECK
;
; Checks for the presence of a cartridge on the expansion port. Toggles CA2 on
; the 65C22 VIA and checks if CA1 was triggered on the rising edge; cartridges
; should have these two pins connected, so a positive result shows a cartridge
; is present.
;
; Uses:
;
;   A             Clobbered, nonzero if cartridge is present
;   VIA_PCR       Modified for toggling CA1/CA2
;   VIA_PCR       Modified for toggling CA1/CA2
;   VIA_IFR       Modified for toggling CA1/CA2
;
CARTCHECK LDA #$0D              ; Set CA2 to LOW output, CA1 to positive edge trigger
          STA VIA_PCR

          LDA VIA_IORA          ; Clear the existing CA1 flag value in the VIA_IFR register

          LDA #$0F              ; Toggle CA2 HIGH
          STA VIA_PCR

          LDA VIA_IFR           ; Push the CA1 flag value in the VIA_IFR register for later
          PHA

          LDA #$0D              ; Set CA2 to LOW output, CA1 to positive edge trigger
          STA VIA_PCR

          LDA VIA_IORA          ; Clear the existing CA1 flag value in the VIA_IFR register

          PLA                   ; Pop the stored CA1 flag value and test if bit was set
          AND #$02

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
; Uses:
;
;   VIA_DDRB      Modified
;   VIA_IORB      Modified
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
; Uses:
;
;   VIA_IORB      Modified
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
; Uses:
;
;   A             Should contain byte to transmit, replaced with byte received
;   VIA_IORB      Modified
;   SPIINP        Clobbered
;   SPIOUT        Clobbered
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
; LOADBAS
;
; Loads a BASIC program from a serial port. The current program is cleared by calling
; NEWPROG, then each line is read, tokenized, and inserted at the current end of the
; program. The UART must be configured (see IOMODE and IOBAUD) before calling this routine.
;
; Simple checks are performed to ensure line numbers arrive in sequence and that the
; data isn't obviously corrupt (i.e. each line begins with a line number). If an error
; occurs during loading a system error is raised.
;
; Before receiving each line the main loop sends a question mark. This can be ignored by
; normal terminal applications, but a dedicated system for the Cody Computer could use
; this to send along the next line immediately. Because of the time involved in tokenizing
; lines, typical terminal applications need to insert a worst-case delay after each line.
; Watching for the question mark (patterned after how INPUT statements work over serial)
; could be a significant optimization.
;
; Uses:
;
;   A             Clobbered
;   X             Clobbered
;   LINENUM       Clobbered
;   PROGTOP       Updated as lines are added to the program
;
LOADBAS   JSR NEWPROG         ; Clear out the current program
          
          STZ LINENUM         ; Start at "line zero" as the first line
          STZ LINENUM+1
          
          JSR SERIALON        ; Turn serial port on
          
_LOOP     LDA #CHR_QUEST      ; Send question mark prompt (for more advanced loaders)
          JSR SERIALPUT

          JSR READSER         ; Read a line of input
          
          LDX IBUFLEN         ; Make sure we actually read a full line
          CPX #2
          BCC _DONE
          
          DEX                 ; Replace trailing character with a newline (could be a carriage return!)
          LDA #CHR_NL
          STA IBUF,X
          
          JSR TOKENIZE        ; Tokenize the line
          
          LDA TBUF            ; Basic validity check (must start with line number)
          CMP #$FF
          BNE _SYS
          
          LDA TBUF+2          ; Another validity check (ensure line numbers ascending)
          CMP LINENUM+1
          BNE _LINE

          LDA TBUF+1
          CMP LINENUM
          BEQ _SYS   
_LINE     BCC _SYS
          
          LDA PROGTOP         ; Set destination as the top of the program
          STA LINEPTR
          LDA PROGTOP+1
          STA LINEPTR+1
          
          JSR INSLINE         ; Insert the line into the program

          LDA TBUF+1          ; Update last line number for future tests
          STA LINENUM
          LDA TBUF+2
          STA LINENUM+1
          
          BRA _LOOP           ; Read the next line
          
_DONE     JSR SERIALOFF       ; Turn off serial port
          
          STZ IOMODE          ; Clear I/O settings back to screen/keyboard
          STZ IOBAUD

          STZ RUNMODE         ; Not "running" any more
          
          RTS

_SYS      JMP RAISE_SYS       ; Indicate IO error during read

;
; LOADBIN
;
; Loads a binary program and runs it. The IOMODE and IOBAUD variables must be
; set prior to calling this routine. Different code paths handle loading from
; cartridges or via UART.
; 
; If IOMODE is zero the program is loaded from a cartridge on the expansion port.
; Checks are performed to determine whether the attached SPI memory uses two-byte
; or three-byte addresses (using the SIZE line on the expansion port). The SPI
; protocol used should work with standard SPI EEPROM, Flash, and FRAM chips, but
; compatibility must be checked with the data sheet. Read it before you solder.
;
; Binary program formats differ slightly from the MOS/KIM-1. Each binary begins
; with a starting address followed by an ending address (to determine how many
; bytes should be read). Once the program is loaded the routine jumps to the
; starting address and typically does not return. If it does the routine jumps
; back to BASIC to restart the interpreter (results may vary depending on the
; system's previous state).
;
; Uses:
;
;   A             Clobbered
;   X             Clobbered
;   LINENUM       Clobbered
;   PROGTOP       Updated as lines are added to the program
;
LOADBIN   LDA IOMODE
          BEQ _INITSPI

_INITSER  JSR SERIALON        ; Start running serial port
          
          BRA _LOAD
          
_INITSPI  JSR CARTON          ; Begin SPI transaction

          LDA #$03            ; Command 3 to begin reading
          JSR CARTXFER

          LDX #2              ; Assume a cartridge with a two-byte address
          
          LDA VIA_IORB        ; If cart size bit is high, we have a three-byte address
          BIT #CART_SIZE
          BEQ _ADDR
          INX
          
_ADDR     LDA #$00            ; Send the appropriate number of zeroed address bytes
          JSR CARTXFER
          DEX
          BNE _ADDR

_LOAD     JSR _READ           ; Read starting address (low and high bytes)
          STA MEMSPTR
          STA PROGPTR
          
          JSR _READ
          STA MEMSPTR+1 
          STA PROGPTR+1
          
          JSR _READ           ; Read ending address (low and high bytes)
          STA MEMDPTR
          
          JSR _READ
          STA MEMDPTR+1
          
_LOOP     JSR _READ           ; Read and store another byte
          STA (MEMSPTR)       ; Store it in memory

          LDA MEMSPTR         ; If not at the destination address, read another byte
          CMP MEMDPTR
          BNE _INCR
          
          LDA MEMSPTR+1
          CMP MEMDPTR+1
          BNE _INCR
          
          LDA IOMODE          ; Finished loading, shutdown for SPI vs serial is different
          BEQ _DONESPI
          BNE _DONESER
                              
_INCR     INC MEMSPTR         ; Increment source pointer by one
          BNE _LOOP        
          INC MEMSPTR+1
          BRA _LOOP

_DONESER  JSR SERIALOFF       ; Stop running serial port 

          STZ IOMODE          ; Clear I/O settings back to screen/keyboard
          STZ IOBAUD
          
          BRA _DONE
          
_DONESPI  JSR CARTOFF

_DONE     STZ RUNMODE         ; Ensure run mode is zero before jumping to loaded binary
          
          SEI                 ; Disable interrupts for BASIC (keyboard scan and clock)
          
          LDX STACKREG        ; Roll back the BASIC stack
          TXS
          
          JSR _JUMP
          
          JMP BASIC           ; If it returns for some reason, restart BASIC and hope

_JUMP     JMP (PROGPTR)       ; Jump to the load address (indirect JSR workaround)

_READ     LDA IOMODE          ; Determine what mode we're running in
          BNE _READSER

_READSPI  LDA #$00            ; Read value and return as accumulator
          JSR CARTXFER
          RTS
          
_READSER  JSR SERIALGET       ; Busy-wait for another byte
          BCC _READSER
          RTS

;
; PUTHEX
;
; Debug code that prints a hex code to the screen.
;
; TODO: REMOVE BEFORE RELEASE.
;
.comment
PUTHEX
  PHA
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
  JSR SCREENPUT
  PLA
  JSR SCREENPUT
  PLX
  PLA
  RTS
HEXTOASCII
  AND #$F
  CLC
  ADC #48
  CMP #58
  BCC HEXTOASCII1
  ADC #6
HEXTOASCII1
  RTS
.endcomment

; Low-byte pointer table for messages/tokens (order is important!)
; See below for high bytes

MSGTABLE_L
  .BYTE <STR_GREET
  .BYTE <STR_READY
  .BYTE <STR_ERROR
  .BYTE <STR_IN
ERRTABLE_L
  .BYTE <STR_BREAK
  .BYTE <STR_SYNTAX
  .BYTE <STR_LOGIC
  .BYTE <STR_SYSTEM
TOKTABLE_L
  .BYTE <STR_NEW
  .BYTE <STR_LIST
  .BYTE <STR_LOAD
  .BYTE <STR_SAVE
  .BYTE <STR_RUN
  .BYTE <STR_REM
  .BYTE <STR_IF
  .BYTE <STR_THEN
  .BYTE <STR_GOTO
  .BYTE <STR_GOSUB
  .BYTE <STR_RETURN
  .BYTE <STR_FOR
  .BYTE <STR_TO
  .BYTE <STR_NEXT
  .BYTE <STR_POKE
  .BYTE <STR_INPUT
  .BYTE <STR_PRINT
  .BYTE <STR_OPEN
  .BYTE <STR_CLOSE
  .BYTE <STR_READ
  .BYTE <STR_RESTORE
  .BYTE <STR_DATA
  .BYTE <STR_END
  .BYTE <STR_SYS
  .BYTE <STR_AT
  .BYTE <STR_TAB
  .BYTE <STR_SUB
  .BYTE <STR_CHR
  .BYTE <STR_STR
  .BYTE <STR_TI
  .BYTE <STR_PEEK
  .BYTE <STR_RND
  .BYTE <STR_NOT
  .BYTE <STR_ABS
  .BYTE <STR_SQR
  .BYTE <STR_AND
  .BYTE <STR_OR
  .BYTE <STR_XOR
  .BYTE <STR_MOD
  .BYTE <STR_VAL
  .BYTE <STR_LEN
  .BYTE <STR_ASC
  .BYTE <STR_LE
  .BYTE <STR_GE
  .BYTE <STR_NE
  .BYTE <STR_LT
  .BYTE <STR_GT
  .BYTE <STR_EQ

; Constants for token and message table entry high bytes
; Most are identical, tokens and other messages are page-aligned
; to save space

TOKTABLE_H = >STR_NEW
MSGTABLE_H = >STR_GREET

; Message string table (layout must be exact, do not modify!)

* = $FFA0

STR_GREET
  .SHIFT $0A, "   **** CODY COMPUTER BASIC V1.0 ****", $0A
STR_READY
  .SHIFT $0A, "READY.", $0A
STR_ERROR
  .SHIFT " ERROR"
STR_IN
  .SHIFT " IN "
STR_BREAK
  .SHIFT "BREAK"
STR_SYNTAX
  .SHIFT "SYNTAX"
STR_LOGIC
  .SHIFT "LOGIC"
STR_SYSTEM
  .SHIFT "SYSTEM"

* = $FFFC               ; 6502 start address

.WORD MAIN

* = $FFFE               ; interrupt handler address (jumps to stub handler)

.WORD ISRSTUB
