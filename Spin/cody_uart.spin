'
' cody_uart.spin
' Simple UART implementations for the Cody Computer.
' 
' Copyright 2024 Frederick John Milens III, The Cody Computer Developers.
' 
' This program is free software; you can redistribute it and/or
' modify it under the terms of the GNU General Public License
' as published by the Free Software Foundation; either version 3
' of the License, or (at your option) any later version.

' This program is distributed in the hope that it will be useful,
' but WITHOUT ANY WARRANTY; without even the implied warranty of
' MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
' GNU General Public License for more details.
'
' You should have received a copy of the GNU General Public License
' along with this program; if not, write to the Free Software
' Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
'
' SUMMARY
' 
' Implements two simplified UART peripherals for the Cody Computer. The implementation is
' very basic, and while it suffices to transfer programs and perform rudimentary serial I/O,
' it is not a particularly robust UART. Each UART consists of several emulated registers for
' configuration and two ring buffers for transmitting/receiving bytes. Rates up to 19200
' baud are supported. Interrupts are not supported and the UART must be polled by the 65C02.
' 
' The actual logic is implemented using interleaved coroutines to handle the two UARTs by
' jumping between them very fast. For a more straightforward implementation (without any
' complications introduced by exposing the features as simulated peripherals), refer to
' Chip Gracey's "Full Duplex Serial" and similar implementations available from the 
' Parallax OBEX (https://obex.parallax.com/).
' 
' The UARTs are mapped into 65C02 memory at addresses $D480 (UART 1) and $D4A0 (UART 2).
' 
' Each UART has the following registers:
' 
'   $00   Control register
'   $01   Command register
'   $02   Status register
'   $03   Reserved
'   $04   Receive ring buffer head register
'   $05   Receive ring buffer tail register
'   $06   Transmit ring buffer head register
'   $07   Transmit ring buffer tail register
'   $08   Receive ring buffer 0
'   $09   Receive ring buffer 1
'   $0A   Receive ring buffer 2
'   $0B   Receive ring buffer 3
'   $0C   Receive ring buffer 4
'   $0D   Receive ring buffer 5
'   $0E   Receive ring buffer 6
'   $0F   Receive ring buffer 7
'   $10   Transmit ring buffer 0
'   $11   Transmit ring buffer 1
'   $12   Transmit ring buffer 2
'   $13   Transmit ring buffer 3
'   $14   Transmit ring buffer 4
'   $15   Transmit ring buffer 5
'   $16   Transmit ring buffer 6
'   $17   Transmit ring buffer 7
' 
' CONTROL REGISTER
' 
' The control register is used to set the baud rate. This register is write-only.
' 
' The lower four bits contain the baud rate. The higher four bits are unused.
' 
' Supported values and baud rates (taken from the 6551's baud rate generator) are as follows:
' 
'   $0    None
'   $1    50
'   $2    75
'   $3    110
'   $4    135
'   $5    150
'   $6    300
'   $7    600
'   $8    1200
'   $9    1800
'   $A    2400
'   $B    3600
'   $C    4800
'   $D    7200
'   $E    9600
'   $F    19200
' 
' COMMAND REGISTER
' 
' The command register is used to enable or disable the UART. This register is write-only.
' 
' Bit 0 will enable the UART if set (1) or disable the UART if cleared (0). Because the UART
' may not immediately respond to changes, you must test the busy bit in the status register
' to see when the UART has actually started or stopped.
' 
' STATUS REGISTER
' 
' x6x4321x
' 
' The status register indicates the current condition of the UART. This register is read-only.
' 
' Bit 1 indicates if a framing error has occurred. The bit will be set if a stop bit was
' received incorrectly (stop bits should be 1, not 0). This can happen as the result of timing
' errors or incompatible baud rates between the transmitter and receiver.
' 
' Bit 2 indicates if an overrun has occurred. The bit will be set if the receive head pointer
' catches up to the receive tail pointer. This can happen when an additional byte is received
' by the UART when the receive buffer is full. The UART must be disabled and enabled to clear
' the bit.
' 
' Bit 3 indicates if a receive operation is currently in progress. The bit will be set if a
' start bit has been encountered but the corresponding stop bit has not been encountered.
' 
' Bit 4 indicates if a transmit operation is currently in progress. The bit will be set if a
' byte has been fetched from the ring buffer and is in the process of being sent.
' 
' Bit 6 indicates if the UART is running. This bit will be set when the UART is active and
' cleared when the UART is not active. Monitoring the state of this bit is important when
' disabling or enabling the UART (see COMMAND REGISTER).
' 
' RECEIVE RING BUFFER HEAD REGISTER
' 
' The register indicates the head position in the receive ring buffer. This register is read-only.
' 
' The UART will update this register as bytes are received and stored in the buffer.
' 
' Only the low three bits are used because the ring buffer only has a depth of eight bytes.
' 
' RECEIVE RING BUFFER TAIL REGISTER
' 
' The register indicates the tail position in the receive ring buffer. This register is write-only.
' 
' The CPU must update this register as bytes are consumed out of the buffer.
' 
' Only the low three bits are used because the ring buffer only has a depth of eight bytes.
'
' TRANSMIT RING BUFFER HEAD REGISTER
' 
' The register indicates the head position in the receive ring buffer. This register is write-only.
' 
' The CPU must update this register as bytes are added to the buffer.
' 
' Only the low three bits are used because the ring buffer only has a depth of eight bytes.
' 
' TRANSMIT RING BUFFER TAIL REGISTER
' 
' The register indicates the tail position in the receive ring buffer. This register is read-only.
' 
' The UART will update this register as bytes are consumed out of the buffer.
' 
' Only the low three bits are used because the ring buffer only has a depth of eight bytes.
'
  _CLKMODE = xtal1 + pll16x     
  _XINFREQ = 5_000_000  

'
' Starts the UART cog. Requires a pointer to the beginning of shared Propeller
' memory. The UART cog will calculate the offsets within the shared memory region
' for the registers and ring buffers for each UART.
'
PUB start(mem_ptr)

    cognew(@cogmain, mem_ptr)

DAT             org     0
                
'
' Starting routine of the UART cog. Performs some initial address calculation
' based on the pointer to shared memory, configures I/O pins, and sets up some
' pointers for coroutines.
'
cogmain
                ' Adjust all pointers using hub memory base address
                mov     temp, #18
:adjust         add     UART1_CONTROL, PAR
                add     :adjust, INC_DEST
                djnz    temp, #:adjust  
                
                ' Initialize serial port pins
                or      DIRA, UART1_TX_PIN
                or      OUTA, UART1_TX_PIN
               
                or      DIRA, UART2_TX_PIN              
                or      OUTA, UART2_TX_PIN
                
                ' Prepare to run as coroutines
                mov     uart2_task, #uart2

'
' Main routine for UART 1 implementation, handling both receive and transmit.
' Exchanges control with UART 2 via coroutines.
'
uart1           
                ' Yield to other UART
                jmpret  uart1_task, uart2_task
            
                ' Is the UART running?
                rdbyte  temp, UART1_COMMAND          
                test    temp, #$01              wz
if_z            jmp     #:disabled
                
                ' Mark UART1 status bit as high
                or      uart1_state, #$40
                wrbyte  uart1_state, UART1_STATUS
                
                 ' Get the baud rate for the UART
                rdbyte  temp, UART1_CONTROL
                and     temp, #$0F
                add     temp, #BAUD_RATE_TABLE
                movs    :baud, temp
                nop
:baud           mov     uart1_delta, 0-0

                ' Yield to other UART
:transmit       jmpret  uart1_task, uart2_task

                ' Do we have bits left to send?
                cmp     uart1_tx_left, #0       wz
if_nz           jmp     #:send
        
                ' Get buffer head and tail positions
                rdbyte  head, UART1_TXHEAD
                and     head, #$07
                
                rdbyte  tail, UART1_TXTAIL
                and     tail, #$07
                
                ' Is the buffer empty? If so, move on
                cmp     head, tail              wz
if_z            jmp     #:receive
               
                ' Mark transmit bit as high
                or      uart1_state, #$10
                wrbyte  uart1_state, UART1_STATUS
                
                ' Read the next item from memory
                mov     temp, UART1_TXBUF
                add     temp, tail
                rdbyte  uart1_tx_bits, temp
               
                ' Update the tail position
                add     tail, #1
                and     tail, #$07
                wrbyte  tail, UART1_TXTAIL
               
                ' Construct frame for bits (start and stop bit)
                or      uart1_tx_bits, #$100
                shl     uart1_tx_bits, #2
                or      uart1_tx_bits, #1
                
                ' Calculate first timestamp to send a bit
                mov     uart1_tx_time, CNT
                add     uart1_tx_time, uart1_delta
                
                ' Loop 11 times (high, start, data, stop)
                mov     uart1_tx_left, #11
                                     
:send           
                ' Yield to other UART
                jmpret  uart1_task, uart2_task
                
                 ' See if it's time to send data
                mov     temp, uart1_tx_time
                sub     temp, CNT
                cmps    temp, #0                wc
if_nc           jmp     #:receive
        
                ' Shift out the next bit
                shr     uart1_tx_bits, #1       wc
                muxc    OUTA, UART1_TX_PIN
                add     uart1_tx_time, uart1_delta
                
                ' Decrement bit count by one
                sub     uart1_tx_left, #1       wz

                ' Clear transmit bit when done with the byte
if_z            andn    uart1_state, #$10
if_z            wrbyte  uart1_state, UART1_STATUS

:receive        
                ' Yield to other UART
                jmpret  uart1_task, uart2_task

                ' Are we already receiving a byte?
                cmp     uart1_rx_left, #0       wz
if_nz           jmp     #:recv

                ' Do we have a start bit? (start bits are 0)
                test    UART1_RX_PIN, INA       wz
if_nz           jmp     #uart1
                
                ' Mark receive bit as high
                or      uart1_state, #$08
                wrbyte  uart1_state, UART1_STATUS
                
                ' Calculate first timestamp to receive a bit
                mov     uart1_rx_time, uart1_delta
                shr     uart1_rx_time, #1
                add     uart1_rx_time, uart1_delta
                add     uart1_rx_time, CNT
                
                ' Clear out bits
                mov     uart1_rx_bits, #0
                
                ' Nine bits to receive (includes the stop bit)
                mov     uart1_rx_left, #9
                                        
:recv           
                ' Yield to other UART
                jmpret  uart1_task, uart2_task
                
                ' See if it's time to receive data
                mov     temp, uart1_rx_time
                sub     temp, CNT
                cmps    temp, #0                wc
if_nc           jmp     #uart1
                    
                ' Read the next bit
                test    UART1_RX_PIN, INA       wz
if_nz           or      uart1_rx_bits, BIT_9
                shr     uart1_rx_bits, #1
                add     uart1_rx_time, uart1_delta
                
                ' Decrement number of bits left to read
                sub     uart1_rx_left, #1       wz
if_nz           jmp     #uart1
                
                ' Test stop bit was set (framing error?)
                test    uart1_rx_bits, BIT_8    wz
if_z            jmp     #:frame
        
                ' Yield to other UART
                jmpret  uart1_task, uart2_task
                
                ' Get buffer head and tail positions
                rdbyte  head, UART1_RXHEAD 
                and     head, #$07
                
                rdbyte  tail, UART1_RXTAIL
                and     tail, #$07
                
                ' Check for overflow (can only store 7 items)
                mov     temp, tail
                sub     temp, head
                abs     temp, temp
                cmp     temp, #7                wc
if_nc           jmp     #:overflow
         
                ' Calculate address for next byte in buffer
                mov     temp, UART1_RXBUF
                add     temp, head
                
                ' Calculate new buffer head position
                add     head, #1
                and     head, #$07
                
                ' Update buffer and position
                wrbyte  uart1_rx_bits, temp
                wrbyte  head, UART1_RXHEAD
                
                ' Clear receive bit at end of byte
                andn    uart1_state, #$08
                wrbyte  uart1_state, UART1_STATUS
                
                jmp     #uart1
                
:frame
                ' Set frame bit (bit 1) on status register
                or      uart1_state, #$02
                wrbyte  uart1_state, UART1_STATUS
                
                jmp     #uart1
                
:overflow
                ' Set overflow bit (bit 2) on status register
                or      uart1_state, #$04
                wrbyte  uart1_state, UART1_STATUS
                
                jmp     #uart1
                
:disabled       
                ' Clear any pending bits in the system 
                mov     uart1_rx_left, #0
                mov     uart1_tx_left, #0
                mov     uart1_state, #0
                
                ' Clear out any registers managed by the UART
                wrbyte  ZERO, UART1_RXHEAD
                wrbyte  ZERO, UART1_TXTAIL
                wrbyte  ZERO, UART1_STATUS
                
                jmp     #uart1

'
' Main routine for UART 2 implementation, handling both receive and transmit.
' Exchanges control with UART 1 via coroutines. The code itself is a copy of
' the UART 1 code with variables replaced (to point to UART 2 instead).
'
uart2           
                ' Yield to other UART
                jmpret  uart2_task, uart1_task
            
                ' Is the UART running? 
                rdbyte  temp, UART2_COMMAND
                test    temp, #$01              wz
if_z            jmp     #:disabled
                
                ' Mark UART1 status bit as high
                or      uart2_state, #$40
                wrbyte  uart2_state, UART2_STATUS
                
                ' Get the baud rate for the UART
                rdbyte  temp, UART2_CONTROL
                and     temp, #$0F
                add     temp, #BAUD_RATE_TABLE
                movs    :baud, temp
                nop
:baud           mov     uart2_delta, 0-0

:transmit       
                ' Yield to other UART
                jmpret  uart2_task, uart1_task

                ' Do we have bits left to send?
                cmp     uart2_tx_left, #0       wz
if_nz           jmp     #:send
        
                ' Get buffer head and tail positions
                rdbyte  head, UART2_TXHEAD
                and     head, #$07
                
                rdbyte  tail, UART2_TXTAIL
                and     tail, #$07
                
                ' Is the buffer empty? If so, move on
                cmp     head, tail              wz
if_z            jmp     #:receive
               
                ' Mark transmit bit as high
                or      uart2_state, #$10
                wrbyte  uart2_state, UART2_STATUS
                
                ' Read the next item from memory
                mov     temp, UART2_TXBUF
                add     temp, tail
                rdbyte  uart2_tx_bits, temp
               
                ' Update the tail position
                add     tail, #1
                and     tail, #$07
                wrbyte  tail, UART2_TXTAIL
               
                ' Construct frame for bits (start and stop bit)
                or      uart2_tx_bits, #$100
                shl     uart2_tx_bits, #2
                or      uart2_tx_bits, #1
                
                ' Calculate first timestamp to send a bit
                mov     uart2_tx_time, CNT
                add     uart2_tx_time, uart2_delta
                
                ' Loop 11 times (high, start, data, stop)
                mov     uart2_tx_left, #11
                
:send
                ' Yield to other UART
                jmpret  uart2_task, uart1_task
                
                ' See if it's time to send data
                mov     temp, uart2_tx_time
                sub     temp, CNT
                cmps    temp, #0                wc
if_nc           jmp     #:receive
        
                ' Shift out the next bit
                shr     uart2_tx_bits, #1       wc
                muxc    OUTA, UART2_TX_PIN
                add     uart2_tx_time, uart2_delta
                
                ' Decrement bit count by one
                sub     uart2_tx_left, #1       wz

                ' Clear transmit bit when done with the byte
if_z            andn    uart2_state, #$10
if_z            wrbyte  uart2_state, UART2_STATUS
        
:receive        
                ' Yield to other UART
                jmpret  uart2_task, uart1_task

                ' Are we already receiving a byte?
                cmp     uart2_rx_left, #0       wz
if_nz           jmp     #:recv

                ' Do we have a start bit? (start bits are 0)
                test    UART2_RX_PIN, INA       wz
if_nz           jmp     #uart2
        
                ' Mark receive bit as high
                or      uart2_state, #$08
                wrbyte  uart2_state, UART2_STATUS
                
                ' Calculate first timestamp to receive a bit
                mov     uart2_rx_time, uart2_delta
                shr     uart2_rx_time, #1
                add     uart2_rx_time, uart2_delta
                add     uart2_rx_time, CNT
                
                ' Clear out bits
                mov     uart2_rx_bits, #0
                
                ' Nine bits to receive (includes the stop bit)
                mov     uart2_rx_left, #9
            
:recv           
                ' Yield to other UART
                jmpret  uart2_task, uart1_task

                ' See if it's time to receive data
                mov     temp, uart2_rx_time
                sub     temp, CNT
                cmps    temp, #0                wc
if_nc           jmp     #uart2

                ' Read the next bit
                test    UART2_RX_PIN, INA       wz
if_nz           or      uart2_rx_bits, BIT_9
                shr     uart2_rx_bits, #1
                add     uart2_rx_time, uart2_delta
                
                ' Decrement number of bits left to read
                sub     uart2_rx_left, #1       wz
if_nz           jmp     #uart2
                
                ' Test stop bit was set (framing error?)
                test    uart2_rx_bits, BIT_8    wz
if_z            jmp     #:frame
        
                ' Yield to other UART
                jmpret  uart2_task, uart1_task
                
                ' Get buffer head and tail positions
                rdbyte  head, UART2_RXHEAD
                and     head, #$07
                
                rdbyte  tail, UART2_RXTAIL
                and     tail, #$07
                
                ' Check for overflow (can only store 7 items)
                mov     temp, tail
                sub     temp, head
                abs     temp, temp
                cmp     temp, #7                wc
if_nc           jmp     #:overflow
               
                ' Calculate address for next byte in buffer
                mov     temp, UART2_RXBUF
                add     temp, head
                
                ' Calculate new buffer head position
                add     head, #1
                and     head, #$07
                
                ' Update buffer and position
                wrbyte  uart2_rx_bits, temp
                wrbyte  head, UART2_RXHEAD
                
                ' Clear receive bit at end of byte
                andn    uart2_state, #$08
                wrbyte  uart2_state, UART2_STATUS
                
                jmp     #uart2
                
:frame          
                ' Set frame bit (bit 1) on status register
                or      uart2_state, #$02
                wrbyte  uart2_state, UART2_STATUS
                
                jmp     #uart2
                
:overflow       
                ' Set overflow bit (bit 2) on status register
                or      uart2_state, #$04
                wrbyte  uart2_state, UART2_STATUS
                
                jmp     #uart2
                
:disabled       
                ' Clear any pending bits in the system 
                mov     uart2_rx_left, #0
                mov     uart2_tx_left, #0
                mov     uart2_state, #0
                
                ' Clear out any registers managed by the UART
                wrbyte  ZERO, UART2_RXHEAD
                wrbyte  ZERO, UART2_TXTAIL
                wrbyte  ZERO, UART2_STATUS
                
                jmp     #uart2
                
UART1_CONTROL   long    $3480           ' Pointers to UART 1 registers in hub memory (will be adjusted)
UART1_COMMAND   long    $3481
UART1_STATUS    long    $3482
UART1_RXHEAD    long    $3484
UART1_RXTAIL    long    $3485
UART1_TXHEAD    long    $3486
UART1_TXTAIL    long    $3487
UART1_RXBUF     long    $3488
UART1_TXBUF     long    $3490

UART2_CONTROL   long    $34A0           ' Pointers to UART 2 registers in hub memory (will be adjusted)
UART2_COMMAND   long    $34A1
UART2_STATUS    long    $34A2
UART2_RXHEAD    long    $34A4
UART2_RXTAIL    long    $34A5
UART2_TXHEAD    long    $34A6
UART2_TXTAIL    long    $34A7
UART2_RXBUF     long    $34A8
UART2_TXBUF     long    $34B0

uart1_rx_bits   long    $0              ' Variables used internally by the UART 1 implementation 
uart1_rx_time   long    $0
uart1_rx_left   long    $0
uart1_tx_bits   long    $0
uart1_tx_time   long    $0
uart1_tx_left   long    $0
uart1_delta     long    $0
uart1_state     long    $0

uart2_rx_bits   long    $0              ' Variables used internally by the UART 2 implementation
uart2_rx_time   long    $0
uart2_rx_left   long    $0
uart2_tx_bits   long    $0
uart2_tx_time   long    $0
uart2_tx_left   long    $0
uart2_delta     long    $0
uart2_state     long    $0

head            long    $0              ' Temporary variables used for circular buffers and data
tail            long    $0
temp            long    $0

uart1_task      long    $0              ' Coroutine pointer for the current UART 1 position
uart2_task      long    $0              ' Coroutine pointer for the current UART 2 position

ZERO            long    0               ' Constant for writing 0 to hub memory

BIT_9           long    (1 << 9)        ' Constant mask for bit 9
BIT_8           long    (1 << 8)        ' Constant mask for bit 8

UART1_TX_PIN    long    (1 << 30)       ' Constant for UART 1's TX pin (same as the Prop Plug)
UART1_RX_PIN    long    (1 << 31)       ' Constant for UART 1's RX pin (same as the Prop Plug)

UART2_TX_PIN    long    (1 << 22)       ' Constant for UART 2's TX pin (on the expansion slot)
UART2_RX_PIN    long    (1 << 23)       ' Constant for UART 2's RX pin (on the expansion slot)

INC_DEST        long    (1 << 9)        ' Constant to increment an opcode's destination address

BAUD_RATE_TABLE long    0                               ' 0x0
                long    (80_000_000 /    50)            ' 0x1
                long    (80_000_000 /    75)            ' 0x2
                long    (80_000_000 /   110)            ' 0x3
                        
                long    (80_000_000 /   135)            ' 0x4
                long    (80_000_000 /   150)            ' 0x5
                long    (80_000_000 /   300)            ' 0x6
                long    (80_000_000 /   600)            ' 0x7
                        
                long    (80_000_000 /  1200)            ' 0x8
                long    (80_000_000 /  1800)            ' 0x9
                long    (80_000_000 /  2400)            ' 0xA
                long    (80_000_000 /  3600)            ' 0xB
                        
                long    (80_000_000 /  4800)            ' 0xC
                long    (80_000_000 /  7200)            ' 0xD
                long    (80_000_000 /  9600)            ' 0xE
                long    (80_000_000 / 19200)            ' 0xF

                fit     496
