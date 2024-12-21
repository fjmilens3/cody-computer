'
' cody_computer.spin
' Main Propeller routine for the Cody Computer.
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
' Implements the "driver" of the Cody Computer responsible for running the 65C02
' and watching the bus. Also responible for controlling the address buffer, decoding
' 65C22 and RAM addresses, and performing other core operations. Other features
' (including video, audio, and serial communication) are delegated to other cogs
' mapped to the same shared memory area.
' 
CON

  _clkmode = xtal1 + pll16x 
  _xinfreq = 5_000_000

  PIN_ABE       = 16        ' Pin mappings (see below or refer to schematic)
  PIN_PHI       = 17
  PIN_RES       = 18
  PIN_RWB       = 19
  PIN_IOSEL     = 20
  PIN_RAMSEL    = 21
  PIN_AUDIO     = 27

OBJ

    video   : "cody_video.spin"
    audio   : "cody_audio.spin"
    uart    : "cody_uart.spin"

VAR
    
    long stack[128]         ' Reserved stack space for SPIN (provides a safety margin)
    
DAT

memory 
   
    long 0[4096]    ' 16K shared RAM starting at 65C02 address $A000
    long            ' 8K ROM (BASIC, character set) starting at 65C02 address $E000
    FILE "codybasic.bin"

'
' Startup routine for the entire Cody Computer. Launches the audio, video, and
' UART cogs, waits for them to come up, and then replaces the current cog with
' the driver code written in PASM.
'
PUB start
   
    audio.start(@memory)
    uart.start(@memory)
    video.start(@memory)
    
    waitcnt(cnt + 10000)
    coginit(0, @cogmain, @memory)

DAT                     org     0

'
' Entry point for the driver. Calculates addresses based on the pointer to shared
' memory, configures Propeller I/O pins for driving the circuit, and emits the
' reset pulse to start the 65C02. After that it enters into an infinite loop to
' handle the 65C02 bus and respond appropriately to bus signals. 
'
cogmain         mov     memory_ptr, PAR
              
                ' adjust ROM cutoff location with start address of memory
                add     BOUNDARY_ROM, memory_ptr
            
                ' configure the IO pins used for 6502 and bus signals
                mov     OUTA, INIT_OUTA
                mov     DIRA, INIT_DIRA
            
                ' run 65C02 reset sequence of 10 clocks with reset high
                call    #emit_reset
            
                ' dummy read to align our code with hub access windows
                ' before commencing the main loop driving the 6502
                rdbyte  data, addr

'
' Implements a single 65C02 cycle where each instruction has been counted for length,
' including hub operations. This routine will run in an infinite loop once entered,
' driving the 65C02 and decoding bus operations until the system is shut off.
' 
' At a high level, the Propeller drives the 65C02 clock and watches the bus. Depending
' on clock phase the Propeller reads the current address. If the address is within the
' Propeller, it will map the read or write to its shared memory. If the address is not,
' the address is decoded and the appropriate chip selected (SRAM or 65C22 VIA).
' 
' The timing should be completely deterministic (important since our generated clock
' is used for the 65C22's timers, which would otherwise drift) after the preceding
' rdbyte syncs up with the hub.
' 
cycle                        
                ' Begin the main 6502 loop by bringing phi low to end
                ' the previous cycle, then reset the OUTA/DIRA config.
                ' 
                ' Once we've reset our state to begin the next cycle,
                ' read from the inputs and determine what we need to do.

                andn    OUTA, MASK_PHI          ' phi2 low at start (1)
                mov     DIRA, INIT_DIRA         ' reset IO direction (2)
                mov     OUTA, INIT_OUTA         ' reset output state (3)
                mov     addr, INA               ' read address (4) 
                and     addr, MASK_WORD         ' mask address bits (5)                                                                
                cmp     addr, BOUNDARY_RAM  wc  ' test address for prop memory (6)
if_nc           jmp     #internal               ' prop internal memory path (7)
                cmp     addr, BOUNDARY_VIA  wc  ' test address for sram or io (8)
if_nc           andn    OUTA, MASK_IOSEL        ' io selected (9)
if_c            andn    OUTA, MASK_RAMSEL       ' otherwise ram selected (10)
                or      OUTA, MASK_ABE_PHI      ' address bus off, phi2 high (11)
                nop                             ' wait (12)
                nop                             ' wait (13)
                nop                             ' wait (14)
                nop                             ' wait (15)
                nop                             ' wait (16)
                nop                             ' wait (17)
                nop                             ' wait (18)
                nop                             ' wait (19)
                jmp     #cycle                  ' next loop (20)
                
                ' Accessing hub memory so capture the address while the
                ' address bus is enabled, then process as read or write.
            
internal        sub     addr, BOUNDARY_RAM      ' adjust address for prop (8)
                add     addr, memory_ptr        ' adjust with base pointer (9)
                test    MASK_RWB, INA       wz  ' read or write op? (10)
                or      OUTA, MASK_ABE_PHI      ' address bus off, phi2 high (11)
if_z            jmp     #write                  ' write operation (12)
                
                ' Performing a read operation from the hub memory, so we
                ' have to read from memory during the hub window and put
                ' the data on the data bus (note that the pin direction
                ' also has to be changed to actually put the data on the
                ' 6502 bus).
            
read            nop                             ' wait (13)
                nop                             ' wait (14)
                rdbyte  data, addr              ' read byte (15, 16)
                or      OUTA, data              ' set output data (17)
                or      DIRA, MASK_LOBYTE       ' enable outputs (18)    
                nop                             ' wait (19)
                jmp     #cycle                  ' next loop (20)
                    
                ' Performing a write operation, so we need to get the
                ' data from the 6502 data bus and write it to hub ram
                ' during our hub window.

write           mov     data, INA               ' get input data (13)
                cmp     addr, BOUNDARY_ROM  wc  ' test for non-writeable ROM area (14)
if_c            wrbyte  data, addr              ' write input data (15, 16)
                nop                             ' wait (17)
                nop                             ' wait (18)
                nop                             ' wait (19)
                jmp     #cycle                  ' next loop (20)

'
' Emits a sequence of ten clocks used as part of the reset sequence for the 65C02.
'
' The 65C02 reset sequence consists of ten clock cycles with RESET high followed by
' ten clock cycles with RESET low. When finished the RESET pin is set to high again.
' 
emit_reset    
                ' begin with reset high and emit 20 clock cycles
                or      OUTA, MASK_RES
                mov     count, #20
:loop          
                ' clock low
                andn    OUTA, MASK_PHI
                mov     temp, cnt
                add     temp, #40
                waitcnt temp, temp
              
                ' clock high
                or      OUTA, MASK_PHI
                mov     temp, cnt
                add     temp, #40
                waitcnt temp, temp
              
                ' bring reset low after 10 cycles
                cmp     count, #10      wz
if_z            andn    OUTA, MASK_RES
              
                ' next clock cycle
                djnz    count, #:loop
          
                ' bring reset high when done
                or      OUTA, MASK_RES

emit_reset_ret  ret
                     
data            long    0                               ' Temporary variable for data bytes
addr            long    0                               ' Temporary variable for address bytes
temp            long    0
count           long    0
memory_ptr      long    0

MASK_WORD       long    $FFFF                           ' Mask for various bitwise operations (words, high/low bytes)
MASK_HIBYTE     long    $FF00
MASK_LOBYTE     long    $00FF

MASK_ABE_PHI    long    ((1<<PIN_ABE) | (1<<PIN_PHI))   ' Mask for both address bus enable and PHI pins on board
MASK_PHI        long    (1<<PIN_PHI)                    ' Mask for the PHI pin (Propeller-generated 65C02 clock)
MASK_RES        long    (1<<PIN_RES)                    ' Mask for the RES pin (Propeller-generated 65C02 reset)
MASK_RWB        long    (1<<PIN_RWB)                    ' Mask for the RWB pin (65C02-generated read/write strobe)
MASK_IOSEL      long    (1<<PIN_IOSEL)                  ' Mask for the IOSEL pin (Propeller-generated 65C22 chip select)
MASK_RAMSEL     long    (1<<PIN_RAMSEL)                 ' Mask for the RAMSEL pin (Propeller-generated RAM chip select)

INIT_OUTA       long    %0011_0100_0000_0000_0000_0000  ' Initial I/O pin output values
INIT_DIRA       long    %0011_0111_0000_0000_0000_0000  ' Initial I/O pin directions

BOUNDARY_RAM    long    $A000                           ' Absolute boundary for Propeller RAM above the VIA page
BOUNDARY_VIA    long    $9F00                           ' Absolute boundary for VIA page between SRAM and Prop
BOUNDARY_ROM    long    $4000                           ' Relative boundary in RAM for start of ROM segment

                fit     496
