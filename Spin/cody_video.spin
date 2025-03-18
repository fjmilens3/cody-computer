'
' cody_video.spin
' NTSC video generation for the Cody Computer.
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
' Implements the video driver and related code for the Cody Computer. The Cody
' Computer supports a single video mode similar to multicolor character mode on
' the Commodore 64. Output is a non-interlaced NTSC signal, 262 lines without a
' half-line, with the active display area being a 160x200 fat-pixel display.
' 
' The main driver program is responsible for outputting video signals from the
' Propeller's dedicated hardware. Rendering the data to send out is performed by
' scanline renderers running in other cogs. Communication between the cogs occurs
' through a mailbox-like mechanism documented with the scanline renderers. The
' video system is mapped into 65C02 memory starting at address $D000.
' 
' The NTSC signal generation code and related constants are derived from Eric
' Ball's NTSC Colorbar Generator. For thos interested in softwared-defined video
' his original code is recommended reading (available on https://obex.parallax.com/).
' 
' OVERVIEW
' 
' The video system has the following (simulated) registers:
' 
' $00   Blanking register
' $01   Control register
' $02   Color register
' $03   Base register
' $04   Scroll register
' $05   Screen colors register
' $06   Sprite register
'
' BLANKING REGISTER
' 
' Status register that indicates whether the visible area of the screen is being
' displayed. Set to zero when the visible area is being drawn. During the bottom
' border, top border, and vertical sync, the value is set to 1.
' 
' The transition from 0 to 1 is a good time to begin populating data for the next
' frame. Note that the tail end (shortly before 1 reverts to 0) is unsafe for any
' updates as the new frame may have started rendering internally.
' 
' CONTROL REGISTER
' 
' Used to enable or disable video features. Each bit controls a particular feature:
' 
' Bit 0 - If set, "turns off" the screen and only draws the border color.
' Bit 1 - If set, enables vertical scrolling (and reduces screen height by one row)
' Bit 2 - If set, enables horizontal scrolling (and reduces screen width by two cols)
' Bit 3 - If set, enables row effects.
' Bit 4 - If set, enables bitmap mode.
' Bit 5 - Unused.
' Bit 6 - Unused.
' Bit 7 - Unused.
' 
' The top nibble is reserved.
' 
' COLOR REGISTER
' 
' Sets the border color and the start of color memory.
' 
' The low nibble contains one of the 16 Cody Computer color codes (same as the C64).
' 
' The high nibble indicates where color memory is positioned within the 16K region
' used by the video system. The 16K region is divided into 16 1-kilobyte sections,
' and a number between 0 and 15 is used to specify which section is the color memory.
' 
' BASE REGISTER
' 
' Sets the start of screen memory and the start of character set memory.
' 
' The low nibble indicates where character set memory is positioned within the 16K
' region used by the video system. Each character set consists of 256 characters,
' each of which is defined by 8 bytes; this yields 2 kilobytes for a character set.
' The 16K region is therefore divided into 8 2-kilobyte sections. A number between 0
' and 7 is used to specify which section holds the current character set.
' 
' The high nibble indicates where screen memory is positioned within the 16K region
' used by the video system. Much like color memory, the 16K region is divided into
' 16 1-kilobyte sections. A number between 0 and 15 is used to specify which section
' is the screen memory.
' 
' The base pointers can have different values in subsequent rows using row effects.
' 
' SCROLL REGISTER
' 
' Sets the vertical and horizontal scroll amounts. These can be used for special
' effects and can be used to implement smooth scrolling (in combination with other
' programming techniques).
' 
' The low nibble contains the vertical scroll value. Permitted values range from 0
' to 7.
' 
' The high nibble contains the horizontal scroll value. Because the Cody Computer
' uses "fat" pixels that are wider than taller, the permitted values only range from
' 0 to 3.
' 
' The scroll amounts can have different values in subsequent rows using row effects.
' 
' SCREEN COLORS REGISTER
' 
' Sets the two shared ("common") screen colors. The low nibble contains color 2
' and the high nibble contains color 3. 
' 
' The screen colors can have different values in subsequent rows using row effects.
'
' SPRITE REGISTER
' 
' Sets the current sprite bank and the sprite shared ("common") color.
' 
' The low nibble contains the sprite common color. This will be used as color 3
' for sprite graphics.
' 
' The high nibble contains the sprite bank to use. The Cody Computer supports up
' to 8 sprite banks, so a value betwen 0 and 7 is permitted. (Each sprite bank
' takes up 32 bytes, and a total of 256 bytes for the eight sprite banks resides
' at address $D100).
' 
' The sprite settings can have different values in subsequent rows using row effects.
'
' ROW EFFECTS
' 
' Many 8-bit computer systems permitted special split-screen effects and graphics
' modes using raster interrupts, allowing programmers to trigger certain behaviors
' on certain scanlines. The Cody Computer permits a limited form of this using the
' row effects banks.
' 
' Row effects allow the programmer to specify new values for the base, scroll,
' screen color, and sprite registers using the raster effect registers. They contain
' 32 entries in two banks. One bank contains the control registers and the other bank
' contains the data registers. Banks reside at the following addresses in 65C02 memory:
' 
' Row effect control bank           $D040
' Row effect data bank              $D060
' 
' When each line is reached it's checked against the current row effect control line.
' If the line matches, the value is applied to the registers based on the control data.
' Note that row effects must be specified in ascending order by line number to work.
' 
' Row effects must also be enabled in the video control register.
' 
' The row effect control bank registers are as follows:
' 
' Bits 0 through 4  - Row number from 0 to 24
' Bits 5 and 6      - Destination register for replacement 
' Bit 7             - Enable bit
' 
' For bits 5 and 6 the destination register is specified as follows:
' 
' 00 - Replacement of base register
' 01 - Replacement of scroll register
' 10 - Replacement of screen register
' 11 - Replacement of sprite register
' 
' SPRITES
' 
' Sprites each have four registers:
' 
' $0    Sprite x
' $1    Sprite y
' $2    Sprite colors
' $3    Sprite pointer
' 
' Up to eight sprites can be shown on a line. As a result, a sprite bank is limited 
' to no more than eight sprites. The Cody Computer supports up to four sprite banks
' taking up a single page starting at $D080. The sprite bank to use is specified with
' the sprite register and its related override.
' 
' SPRITE X
' 
' Contains the location for the top-left corner of the sprite. Because sprites can
' appear partially offscreen, this value is offset by 12 bytes to permit a sprite to
' move off the screen horizontally; an x-coordinate of 0 on the visible screen would
' be a sprite x-coordinate of 12.
' 
' SPRITE Y
' 
' Contains the location for the top-left corner of the sprite. Because sprites can
' appear partially offscreen, this value is offset by 21 bytes to permit a sprite to
' move off the screen vertically; a y-coordinate of 0 on the visible screen would
' be a sprite y-coordinate of 21.
' 
' SPRITE COLORS
' 
' Each sprite has two unique colors. Color 1 is stored in the low nibble and color 2
' is stored in the high nibble.
' 
' SPRITE POINTER
' 
' Each sprite takes up 64 bytes (actually 63 bytes with an unused byte). The sprite
' pointer indicates where this data is stored. The video system can address 16K of
' memory, which is divided into 256 64-byte regions. The value of the sprite pointer
' is the index for one of these 256 regions.
' 
CON

    _CLKMODE = xtal1 + pll16x     
    _XINFREQ = 5_000_000

OBJ

    line_renderer : "cody_line.spin"

VAR

    long mailboxes[400]            
  
DAT

    '
    ' The COLOR_TABLE is a lookup table mapping Cody Computer color codes to 
    ' the corresponding Propeller NTSC color. The table consists of 256 word
    ' values so that two nibbles can be looked up using a single memory read.
    ' 
    ' This table is used by both the video cog (to look up border colors) and
    ' the scanline renderers (to convert Cody Computer color codes into colors
    ' for Propeller output).
    '

COLOR_TABLE

    word $02_02
    word $02_07
    word $02_5C
    word $02_CE
    word $02_3C
    word $02_BD
    word $02_0B
    word $02_7E
    word $02_6E
    word $02_6C
    word $02_5E
    word $02_04
    word $02_05
    word $02_BE
    word $02_0E
    word $02_06
    word $07_02
    word $07_07
    word $07_5C
    word $07_CE
    word $07_3C
    word $07_BD
    word $07_0B
    word $07_7E
    word $07_6E
    word $07_6C
    word $07_5E
    word $07_04
    word $07_05
    word $07_BE
    word $07_0E
    word $07_06
    word $5C_02
    word $5C_07
    word $5C_5C
    word $5C_CE
    word $5C_3C
    word $5C_BD
    word $5C_0B
    word $5C_7E
    word $5C_6E
    word $5C_6C
    word $5C_5E
    word $5C_04
    word $5C_05
    word $5C_BE
    word $5C_0E
    word $5C_06
    word $CE_02
    word $CE_07
    word $CE_5C
    word $CE_CE
    word $CE_3C
    word $CE_BD
    word $CE_0B
    word $CE_7E
    word $CE_6E
    word $CE_6C
    word $CE_5E
    word $CE_04
    word $CE_05
    word $CE_BE
    word $CE_0E
    word $CE_06
    word $3C_02
    word $3C_07
    word $3C_5C
    word $3C_CE
    word $3C_3C
    word $3C_BD
    word $3C_0B
    word $3C_7E
    word $3C_6E
    word $3C_6C
    word $3C_5E
    word $3C_04
    word $3C_05
    word $3C_BE
    word $3C_0E
    word $3C_06
    word $BD_02
    word $BD_07
    word $BD_5C
    word $BD_CE
    word $BD_3C
    word $BD_BD
    word $BD_0B
    word $BD_7E
    word $BD_6E
    word $BD_6C
    word $BD_5E
    word $BD_04
    word $BD_05
    word $BD_BE
    word $BD_0E
    word $BD_06
    word $0B_02
    word $0B_07
    word $0B_5C
    word $0B_CE
    word $0B_3C
    word $0B_BD
    word $0B_0B
    word $0B_7E
    word $0B_6E
    word $0B_6C
    word $0B_5E
    word $0B_04
    word $0B_05
    word $0B_BE
    word $0B_0E
    word $0B_06
    word $7E_02
    word $7E_07
    word $7E_5C
    word $7E_CE
    word $7E_3C
    word $7E_BD
    word $7E_0B
    word $7E_7E
    word $7E_6E
    word $7E_6C
    word $7E_5E
    word $7E_04
    word $7E_05
    word $7E_BE
    word $7E_0E
    word $7E_06
    word $6E_02
    word $6E_07
    word $6E_5C
    word $6E_CE
    word $6E_3C
    word $6E_BD
    word $6E_0B
    word $6E_7E
    word $6E_6E
    word $6E_6C
    word $6E_5E
    word $6E_04
    word $6E_05
    word $6E_BE
    word $6E_0E
    word $6E_06
    word $6C_02
    word $6C_07
    word $6C_5C
    word $6C_CE
    word $6C_3C
    word $6C_BD
    word $6C_0B
    word $6C_7E
    word $6C_6E
    word $6C_6C
    word $6C_5E
    word $6C_04
    word $6C_05
    word $6C_BE
    word $6C_0E
    word $6C_06
    word $5E_02
    word $5E_07
    word $5E_5C
    word $5E_CE
    word $5E_3C
    word $5E_BD
    word $5E_0B
    word $5E_7E
    word $5E_6E
    word $5E_6C
    word $5E_5E
    word $5E_04
    word $5E_05
    word $5E_BE
    word $5E_0E
    word $5E_06
    word $04_02
    word $04_07
    word $04_5C
    word $04_CE
    word $04_3C
    word $04_BD
    word $04_0B
    word $04_7E
    word $04_6E
    word $04_6C
    word $04_5E
    word $04_04
    word $04_05
    word $04_BE
    word $04_0E
    word $04_06
    word $05_02
    word $05_07
    word $05_5C
    word $05_CE
    word $05_3C
    word $05_BD
    word $05_0B
    word $05_7E
    word $05_6E
    word $05_6C
    word $05_5E
    word $05_04
    word $05_05
    word $05_BE
    word $05_0E
    word $05_06
    word $BE_02
    word $BE_07
    word $BE_5C
    word $BE_CE
    word $BE_3C
    word $BE_BD
    word $BE_0B
    word $BE_7E
    word $BE_6E
    word $BE_6C
    word $BE_5E
    word $BE_04
    word $BE_05
    word $BE_BE
    word $BE_0E
    word $BE_06
    word $0E_02
    word $0E_07
    word $0E_5C
    word $0E_CE
    word $0E_3C
    word $0E_BD
    word $0E_0B
    word $0E_7E
    word $0E_6E
    word $0E_6C
    word $0E_5E
    word $0E_04
    word $0E_05
    word $0E_BE
    word $0E_0E
    word $0E_06
    word $06_02
    word $06_07
    word $06_5C
    word $06_CE
    word $06_3C
    word $06_BD
    word $06_0B
    word $06_7E
    word $06_6E
    word $06_6C
    word $06_5E
    word $06_04
    word $06_05
    word $06_BE
    word $06_0E
    word $06_06

'
' Starts the video cog using the specified memory pointer as the beginning of
' shared Propeller memory. The video cog will calculate the appropriate offsets
' within the shared memory area for video registers and screen/color/sprites.
'
PUB start(mem_ptr) | index

    ' Start up the scanline renderer cogs
    repeat index from 0 to 3
    
        ' Set up each mailbox
        mailboxes[index * 100 + 0] := index
        mailboxes[index * 100 + 1] := mem_ptr
        mailboxes[index * 100 + 2] := @COLOR_TABLE
        mailboxes[index * 100 + 3] := 0
        
        ' Launch the corresponding cog
        line_renderer.start(@mailboxes + index * 400)

    ' Launch the video cog itself once the scanline cogs are running
    launch_cog(mem_ptr, @COLOR_TABLE, @mailboxes+0, @mailboxes+400, @mailboxes+800, @mailboxes+1200)

' 
' Launches the UART cog. Acts as a utility to organize parameters using the SPIN 
' interpreter's stack.
' 
PRI launch_cog(mem_ptr, ctable_ptr, scan1_ptr, scan2_ptr, scan3_ptr, scan4_ptr)

    cognew(@cogmain, @mem_ptr)

DAT             org 0

'
' Main routine for the NTSC generator cog. Stores the parameters and initializes
' registers for NTSC video output before entering an infinite loop generating
' noninterlaced NTSC video frames.
'
cogmain
                call    #load_params
                call    #init_video                       
:loop
                call    #frame                                                
                jmp     #:loop

'
' Generates a single noninterlaced NTSC frame.
'
frame
                ' Generate NTSC vertical sync
                call    #vertical_sync
              
                ' Generate NTSC blank lines after vertical sync
                call    #ntsc_blank_lines
                
                ' Set vertical blanking indicator to zero (not safe to update)
                wrbyte  ZERO, vblreg_ptr
                
                ' Read current video control register from memory
                rdbyte  control, ctlreg_ptr
                
                ' Read current border color and convert to Propeller color
                rdbyte  border, colreg_ptr
                shl     border, #1
                add     border, lookup_ptr
                rdword  border, border
                
                ' Reset scanline generators back to beginning
                wrlong  TOGGLE_FRAME, toggle1_ptr
                wrlong  TOGGLE_FRAME, toggle2_ptr
                wrlong  TOGGLE_FRAME, toggle3_ptr
                wrlong  TOGGLE_FRAME, toggle4_ptr
                
                ' Draw part of the screen top border
                call    #top_border  
                
                ' Turn scanline generators on
                wrlong  TOGGLE_LINE1, toggle1_ptr
                wrlong  TOGGLE_LINE1, toggle2_ptr
                wrlong  TOGGLE_LINE1, toggle3_ptr
                wrlong  TOGGLE_LINE1, toggle4_ptr
                
                ' Draw the rest of the screen top border
                call    #top_border
                
                ' Draw the screen (and horizontal borders)
                call    #screen_area
                
                ' Set vertical blanking indicator to 1 (safe to update)
                wrbyte  ONE, vblreg_ptr                    
                
                ' Draw screen bottom border
                call    #bottom_border
                
frame_ret       ret

'
' Initializes various registers with the appropriate settings for
' NTSC video output.
'                        
init_video
                ' Sets up the parameters for video generation
                mov     vcfg, ivcfg
                
                ' Internal PLL mode, PLLA = 16 * colorburst frequency
                mov     ctra, ictra
                
                ' 2 * colorburst frequency
                mov     frqa, ifrqa
                
                ' Configure selected video pins as outputs
                or      dira, idira

init_video_ret  ret

'
' Loads the parameters for the shared memory and scanline buffer
' locations, calculating appropriate offsets based on the values
' provided.
'
load_params                        
                mov     params_ptr, PAR
                
                rdlong  memory_ptr, params_ptr
                add     params_ptr, #4
                
                rdlong  lookup_ptr, params_ptr
                add     params_ptr, #4
                
                rdlong  temp, params_ptr
                add     toggle1_ptr, temp
                add     buffer1_ptr, temp
                add     buffer5_ptr, temp
                add     params_ptr, #4
                
                rdlong  temp, params_ptr
                add     toggle2_ptr, temp
                add     buffer2_ptr, temp
                add     buffer6_ptr, temp
                add     params_ptr, #4
                
                rdlong  temp, params_ptr
                add     toggle3_ptr, temp
                add     buffer3_ptr, temp
                add     buffer7_ptr, temp
                add     params_ptr, #4
                
                rdlong  temp, params_ptr
                add     toggle4_ptr, temp
                add     buffer4_ptr, temp
                add     buffer8_ptr, temp
                add     params_ptr, #4
                
                mov     vblreg_ptr, memory_ptr
                add     vblreg_ptr, VBLANK_REG_OFFSET
                
                mov     ctlreg_ptr, memory_ptr
                add     ctlreg_ptr, CONTROL_REG_OFFSET
                
                mov     colreg_ptr, memory_ptr
                add     colreg_ptr, COLOR_REG_OFFSET
                
load_params_ret ret                                           

'
' Emits an NTSC vertical sync signal for the start of a frame.
'
vertical_sync
                mov     numline, #9     ' 9 lines of vsync
:loop
                cmp     numline, #6 wz  ' lines 4,5,6 serration pulses
if_nz           cmp     numline, #5 wz  ' lines 1,2,3 / 7,8,9 equalizing pulses
if_nz           cmp     numline, #4 wz 
    
                mov     count, #2       ' 2 pulses per line
:half
if_nz           mov     VSCL, vscleqal  ' equalizing pulse (short)
if_z            mov     VSCL, vsclselo  ' serration pulse (long)
                waitvid sync, #0        ' -40 IRE
if_nz           mov     VSCL, vscleqhi  ' equalizing pulse (long)
if_z            mov     VSCL, vsclsync  ' serration pulse (short)
                waitvid sync, blank     ' 0 IRE

                djnz    count, #:half
                djnz    numline, #:loop
    
vertical_sync_ret   ret

'
' Emits 12 blank lines following the NTSC vertical sync.
'
ntsc_blank_lines

                mov     numline, #12
:loop
                ' Horizontal sync pulse at -40 IRE
                mov     VSCL, vsclsync
                waitvid sync, #0

                ' Blank at 0 IRE
                mov     VSCL, vsclblnk
                waitvid sync, blank

                djnz    numline, #:loop

ntsc_blank_lines_ret    ret

'
' Emits the NTSC horizontal sync at the start of a line.
'
horizontal_sync
                ' Horizontal sync pulse at -40 IRE
                mov     VSCL, vsclsync
                waitvid sync, #0

                ' Generate 5.3 microseconds blank before colorbust
                mov     VSCL, vscls2cb
                waitvid sync, blank
                
                ' Generate 9 cycles of NTSC colorburst
                mov     VSCL, vsclbrst      ' 9 cycles of colorburst
                waitvid sync, burst

horizontal_sync_ret   ret

'
' Emits the left border of a line using the border color. Included as part of
' generating the NTSC horizontal back porch (9.2 microseconds long).
'
back_porch
                mov     VSCL, vsclbp
                waitvid border, #0

back_porch_ret  ret

'
' Emits the right border of a line using the border color. Included as part of
' generating the NTSC horizontal front porch (1.5 microseconds long).
'
front_porch
                mov     VSCL, vsclfp
                waitvid border, #0

front_porch_ret ret

'
' Emits HALF of the 20-line top border using the border color.  We 
' draw it in two sections so that we can interleave some of the setup
' for the scanline renderers. If this routine is not called TWICE then
' the top border is not fully drawn.
'
top_border
                mov     numline, #10
:loop
                call    #horizontal_sync
                call    #back_porch
          
                mov     VSCL, vsclline
                waitvid border, #0

                call    #front_porch
                djnz    numline, #:loop            

top_border_ret  ret

'
' Emits the 21-line bottom border using the border color.
'
bottom_border
                mov     numline, #21
:loop
                call    #horizontal_sync
                call    #back_porch
          
                mov     VSCL, vsclline
                waitvid border, #0

                call    #front_porch
                djnz    numline, #:loop            

bottom_border_ret   ret

'
' Emits the 4-line additional top or bottom scroll border using the border color.
'
scroll_border
                mov     numline, #4
:loop
                call    #horizontal_sync
                call    #back_porch
          
                mov     VSCL, vsclline
                waitvid border, #0

                call    #front_porch
                djnz    numline, #:loop            

scroll_border_ret   ret

'
' Emits the 200 horizontal lines for the visible screen area. 
'
screen_area     
                ' Generate additional top border lines if vertical scroll enabled
                test    control, #%00000010 wz
if_nz           call    #scroll_border

                ' 25 groups of lines to generate (assuming no vertical scrolling)
                mov     numline, #25                        
                
                ' Adjust number of lines if vertical scrolling enabled
                test    control, #%00000010 wz
if_nz           sub     numline, #1

                ' Render scanlines behind the scenes as we generate NTSC signals
:loop           wrlong  TOGGLE_LINE2, toggle1_ptr
                mov     source, buffer1_ptr
                call    #scanline

                wrlong  TOGGLE_LINE2, toggle2_ptr
                mov     source, buffer2_ptr
                call    #scanline

                wrlong  TOGGLE_LINE2, toggle3_ptr                        
                mov     source, buffer3_ptr
                call    #scanline

                wrlong  TOGGLE_LINE2, toggle4_ptr
                mov     source, buffer4_ptr
                call    #scanline

                wrlong  TOGGLE_LINE1, toggle1_ptr
                mov     source, buffer5_ptr
                call    #scanline

                wrlong  TOGGLE_LINE1, toggle2_ptr                        
                mov     source, buffer6_ptr
                call    #scanline

                wrlong  TOGGLE_LINE1, toggle3_ptr                        
                mov     source, buffer7_ptr
                call    #scanline

                wrlong  TOGGLE_LINE1, toggle4_ptr                        
                mov     source, buffer8_ptr
                call    #scanline
                
                ' Continue on to next group of 8 lines
                djnz    numline, #:loop
                
                ' Generate additional bottom border lines if vertical scroll enabled
                test    control, #%00000010 wz
if_nz           call    #scroll_border
    
screen_area_ret ret

'
' Emits a single scanline including left and right borders.
'
scanline
                call    #horizontal_sync
                call    #back_porch                   
                
                ' Switch to two-color mode, 8 pixels per waitvid
                mov     VCFG, hiivcfg
                mov     VSCL, hivsclactv
                
                ' By default we have 40 waitvids (320 pixels / 8 pixels per waitvid)
                mov     count, #40
                
                ' If horizontal scrolling, draw fewer pixels and a bigger border 
                test    control, #%00000100 wz
if_nz           waitvid border, #0
if_nz           sub     count, #2
                
                ' Adjust pointer for offscreen scratch area in scanline buffer
                add     source, #12
                
:loop           
                ' Read the next four pixels from the scanline buffer
                rdlong  colors, source
                
                ' If the display is enabled, draw the pixels from the buffer
                ' If the display is shut off, draw the border color instead
                test    control, #%00000001 wz
if_z            waitvid colors, pixels
if_nz           waitvid border, #0
                
                ' Go on to the next four pixels
                add     source, #4
                djnz    count, #:loop
                
                ' If horizontal scrolling, draw a bigger border
                test    control, #%00000100 wz
if_nz           waitvid border, #0

                ' Switch back to four-color mode, 4 pixels per waitvid
                mov     VCFG, ivcfg
                mov     VSCL, vsclactv

                call    #front_porch

scanline_ret  ret

' NTSC video configuration constants

ivcfg                   long    %0_10_1_0_1_000_00000000000_011_0_00000111      ' Video Configuration Register settings
ictra                   long    %0_00001_110_00000000_000000_000_000000         ' Counter configuration for NTSC generation
ifrqa                   long    $16E8_BA2F                                      ' Frequency configuration (7,159,090.9Hz / 80MHz) << 32
idira                   long    $0700_0000                                      ' Pin direction configuration

sync                    long    $8A0200                                         ' %%0 = -40 IRE, %%1 = 0 IRE, %%2 = burst
blank                   long    %%1111_1111_1111_1111                           ' Blanking signal (16 pixels color 1)
burst                   long    %%2222_2222_2222_2222                           ' Color burst (16 pixels of color 2)

vscleqal                long    1<<12+135                                       ' NTSC sync/2
vsclsync                long    1<<12+269                                       ' NTSC sync = 4.7us
vsclblnk                long    1<<12+3371                                      ' NTSC H-sync
vsclselo                long    1<<12+1551                                      ' NTSC H/2-sync
vscleqhi                long    1<<12+1685                                      ' NTSC H/2-sync/2
vscls2cb                long    1<<12+304-269                                   ' NTSC sync to colorburst
vsclbrst                long    16<<12+16*9                                     ' NTSC 16 PLLA per cycle, 9 cycles of colorburst
vsclbp                  long    1<<12+(527-304-16*9)+213+20                     ' NTSC back porch + overscan (213)
vsclactv                long    16<<12+16*4                                     ' NTSC 16 PLLA per pixel, 4 pixels per frame
vsclline                long    1<<12+16*4*40                                   ' NTSC line safe area
vsclfp                  long    1<<12+214+86+20                                 ' NTSC overscan (214) + front porch

hivsclactv              long    8<<12+8*8                                       ' NTSC 8 PLLA per pixel, 8 pixels per frame
hiivcfg                 long    %0_10_0_0_1_000_00000000000_011_0_00000111      ' Hires video Configuration Register settings

' Other variables and constants

numline                 long    $0                  ' Number of lines to emit (used in certain loops)
count                   long    $0                  ' General-purpose counting value (used in certain loops)
temp                    long    $0                  ' General-purpose temporary value

pixels                  long    %%3210              ' Pixel pattern for four-color WAITVID operations
colors                  long    $0                  ' Current colors (pixels) to display on a scanline 
border                  long    $0                  ' Current border color to use on borders/blanked screen
control                 long    $0                  ' Current control register value
source                  long    $0                  ' Current pixel data source (pointer to a scanline buffer)

params_ptr              long    $0                  ' Pointers to simulated registers and memory locations
memory_ptr              long    $0
source_ptr              long    $0
lookup_ptr              long    $0
ctlreg_ptr              long    $0
colreg_ptr              long    $0
vblreg_ptr              long    $0

toggle1_ptr             long    $C                  ' Pointers to the toggles for each scanline renderer
toggle2_ptr             long    $C
toggle3_ptr             long    $C
toggle4_ptr             long    $C

buffer1_ptr             long    $10                 ' Pointers to each scanline buffer
buffer2_ptr             long    $10
buffer3_ptr             long    $10
buffer4_ptr             long    $10
buffer5_ptr             long    $D0
buffer6_ptr             long    $D0
buffer7_ptr             long    $D0
buffer8_ptr             long    $D0

TOGGLE_EMPTY            long    $0                  ' Toggle constants for communicating with scanline renderers
TOGGLE_FRAME            long    $1
TOGGLE_LINE1            long    $2
TOGGLE_LINE2            long    $3

VBLANK_REG_OFFSET       long    $3000               ' Special simulated register locations in shared memory
CONTROL_REG_OFFSET      long    $3001
COLOR_REG_OFFSET        long    $3002

ZERO                    long    $0                  ' Constants for updating the vertical blank register
ONE                     long    $1

                        fit     496
