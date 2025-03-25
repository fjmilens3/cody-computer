'
' cody_line.spin
' Scanline renderer for Cody Computer video output.
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
' Implements a single line renderer for the Cody Computer's video subsystem. A total
' of four renderers (each running in their own cog) are used to generate output data
' for video. Each line consists of 160 visible pixels containing 40 characters and
' up to 8 sprites from the current sprite bank.
' 
' Refer to the video renderer for general documentation.
' 
' When running, each renderer reads in the video registers from shared memory. It then
' generates a single output line in the current buffer using the current screen memory,
' colors, character set, and sprite data. While the main video cog reads this data out,
' the renderer can begin working on the next line. A renderer is responsible for every
' fourth line (because there are four renderers).
'  
' Each renderer consists of 100 longs in Propeller memory:
' 
'   ---------------------------------
'   RENDERER NUMBER          (1 long)
'   ---------------------------------
'   SHARED MEMORY POINTER    (1 long)
'   ---------------------------------
'   COLOR TABLE POINTER      (1 long)
'   ---------------------------------
'   TOGGLE                   (1 long)
'   ---------------------------------
'   BUFFER 1 (192 bytes)   (48 longs)
'   -------------------------------
'   BUFFER 2 (192 bytes)   (48 longs)
'   ---------------------------------
' 
' The toggle is used to control the renderer and has four options:
' 
'   TOGGLE_EMPTY ($00)
'   TOGGLE_FRAME ($01)
'   TOGGLE_LINE1 ($02)
'   TOGGLE_LINE2 ($03)
'
' The renderer should be controlled via the toggle values:
' 
'   1. Write TOGGLE_EMPTY prior to starting the renderer cog.
'   2. Write TOGGLE_FRAME to indicate the start of a new frame.
'   3. Write TOGGLE_LINE1 to indicate the start of a line in buffer 1.
'   4. Write TOGGLE_LINE2 to indicate the start of a line in buffer 2.
'   5. Alternate step (3) and step (4) for a total of 50 lines (48 if vertical scroll enabled).
'   6. Repeat the process for the next frame starting at step (2).
'
CON

    _CLKMODE = xtal1 + pll16x     
    _XINFREQ = 5_000_000  

PUB start(pointer) 

    cognew(@cogmain, pointer)
    waitcnt(cnt + 10000)

DAT             org 0

'
' Main routine for the line renderer cog. Stores the parameters before
' entering an infinite loop waiting for toggle updates and rendering lines
' based on main memory contents.
'
cogmain
                ' Load parameters and calculate pointers from the scanline structure
                ' using the calculated offsets within the mailbox memory area
                add     renderer_index, PAR
                add     memory_ptr, PAR
                add     lookup_ptr, PAR
                add     toggle_ptr, PAR
                add     buffer1_ptr, PAR
                add     buffer2_ptr, PAR
                
                rdlong  renderer_index, renderer_index
                rdlong  memory_ptr, memory_ptr
                rdlong  lookup_ptr, lookup_ptr
                
                ' Adjust our offsets into shared memory now that we know where it is
                add     VIDCTL_REGS_OFFSET, memory_ptr
                add     SPRITE_REGS_OFFSET, memory_ptr
                
                add     ROWEFF_CNTL_OFFSET, memory_ptr
                add     ROWEFF_DATA_OFFSET, memory_ptr
                
:frame_loop
                ' Wait for the TOGGLE_FRAME value to begin the next frame
                rdlong  toggle, toggle_ptr
                cmp     toggle, TOGGLE_FRAME    wz
if_nz           jmp     #:frame_loop
                wrlong  TOGGLE_EMPTY, toggle_ptr
                
                ' Read in the video registers at the start of a new frame
                mov     video_register_ptr, VIDCTL_REGS_OFFSET
               
                rdbyte  blankreg, video_register_ptr
                add     video_register_ptr, #1
                
                rdbyte  controlreg, video_register_ptr
                add     video_register_ptr, #1
               
                rdbyte  colorreg, video_register_ptr
                add     video_register_ptr, #1
                
                rdbyte  basereg, video_register_ptr
                add     video_register_ptr, #1
                
                rdbyte  scrollreg, video_register_ptr
                add     video_register_ptr, #1
               
                rdbyte  screenreg, video_register_ptr
                add     video_register_ptr, #1
               
                rdbyte  spritereg, video_register_ptr
                add     video_register_ptr, #1
                
                ' Render each line
                mov     lines_remaining, #50
                mov     curr_scanline, renderer_index
                
:line_loop  
                ' Wait for a TOGGLE_LINE1 or TOGGLE_LINE2 value to begin the next line
                rdlong  toggle, toggle_ptr
                
                cmp     toggle, TOGGLE_EMPTY    wz
if_z            jmp     #:line_loop
                
                cmp     toggle, TOGGLE_FRAME    wz
if_z            jmp     #:frame_loop
                
                ' Clear toggle value once we begin a new line                    
                wrlong  TOGGLE_EMPTY, toggle_ptr
                
                ' Select the destination buffer for this scanline
                cmp     toggle, TOGGLE_LINE1    wz
if_z            mov     buffer_ptr, buffer1_ptr
        
                cmp     toggle, TOGGLE_LINE2    wz
if_z            mov     buffer_ptr, buffer2_ptr
                
                ' Read any row effects that may be pending for this scanline
                call    #apply_row_effects
                
                ' Decode the video registers (including any raster changes)
                call    #decode_registers
                
                ' Render the scanline to the buffer
                call    #render_chars_lo
                call    #render_sprites
                
                ' Go to the next line
                add     curr_scanline, #4
                djnz    lines_remaining, #:line_loop 
                
                ' Begin a new frame
                jmp     #:frame_loop

'
' Renders the characters for the current scanline for the low resolution
' multicolor mode (160x200, 4 colors per square). For each character the
' value in screen memory is read, then the character data for the current
' line is fetched. Finally the character is blitted to the scanline buffer
' using the current colors. (Adjustments are made for soft-scrolling when
' scrolling is enabled.)
' 
' In bitmap mode the layout is slightly different. Data is read as in
' character mode, but the screen memory is arranged as a sequence of 1000
' multicolor "characters" instead. The actual character memory is unused.
'
render_chars_lo           
                ' Set up the output pointer taking into account the left "margin" for sprites
                mov     dest_ptr, buffer_ptr
                add     dest_ptr, #12
                
                ' Update the output start position to account for horizontal scrolling
                test    controlreg, #%00000100  wz
if_nz           sub     dest_ptr, scrollh
                
                ' Update the source line position to account for vertical scrolling
                mov     adjustv, #0
                test    controlreg, #%00000010  wz
if_nz           mov     adjustv, scrollv
                
                ' Precalculate the current offset for each character based on the scanline
                mov     char_offset_y, curr_scanline
                add     char_offset_y, adjustv
                and     char_offset_y, #%0111
                
                ' Determine offset in the screen and color memory based on the current row
                mov     screen_memory_offset, curr_scanline
                add     screen_memory_offset, adjustv
                shr     screen_memory_offset, #3
                add     screen_memory_offset, #SCREEN_OFFSET_TABLE
                movs    :load_offset, screen_memory_offset
                nop
                
:load_offset    mov     screen_memory_offset, 0_0
                
                ' Calculate the locations in color and screen memory using the offset above
                mov     curr_colors_ptr, colmem_ptr
                add     curr_colors_ptr, screen_memory_offset
                
                test    controlreg, #%00010000 wz
if_z            mov     curr_screen_adv, #1
if_nz           mov     curr_screen_adv, #8
if_nz           shl     screen_memory_offset, #3
                
                mov     curr_screen_ptr, scrmem_ptr
                add     curr_screen_ptr, screen_memory_offset
                
                mov     chars_remaining, #40
                
:char_loop      rdbyte  color_data, curr_colors_ptr
                
                shl     color_data, #1
                add     color_data, lookup_ptr
                
                rdword  color_data, color_data
                or      color_data, common_screen_colors
                
                add     curr_colors_ptr, #1
                
                test    controlreg, #%00010000              wz
if_nz           mov     source_ptr, curr_screen_ptr
if_z            rdbyte  source_ptr, curr_screen_ptr
if_z            shl     source_ptr, #3
if_z            add     source_ptr, chrset_ptr
                add     source_ptr, char_offset_y
                add     dest_ptr, #3
                rdbyte  pixel_data, source_ptr
                
                mov     pixels_remaining, #4
                
:pixel_loop     mov     temp, pixel_data
                and     temp, #%11
                
                shl     temp, #3
                ror     color_data, temp
                
                wrbyte  color_data, dest_ptr
                
                sub     dest_ptr, #1
                rol     color_data, temp                      
                
                shr     pixel_data, #2
                djnz    pixels_remaining, #:pixel_loop
                
                add     dest_ptr, #5
                add     curr_screen_ptr, curr_screen_adv
                
                djnz    chars_remaining, #:char_loop                        
                
render_chars_lo_ret    ret

'
' Renders the sprites for the current scanline. The code loops through each sprite
' in the current sprite bank to determine what sprites to draw (and where), and the
' actual sprite bytes are read from the sprite pointer locations in the registers.
' (Adjustments are made for soft-scrolling when scrolling is enabled.)
'
render_sprites  

                ' Start sprite pointer at the beginning of the current bank   
                mov     curr_sprite_ptr, spritereg
                and     curr_sprite_ptr, #$30
                shl     curr_sprite_ptr, #1
                add     curr_sprite_ptr, SPRITE_REGS_OFFSET
                
                ' Draw the 8 sprites we have in this bank
                mov     sprites_remaining, #8
:sprite_loop
                ' Read in and check the sprite x coordinate is within bounds
                rdbyte  sprite_x, curr_sprite_ptr
                add     curr_sprite_ptr, #1
                
                cmp     sprite_x, #0        wz
if_z            jmp     #:next_sprite
                
                cmp     sprite_x, #172      wc
if_nc           jmp     #:next_sprite
                
                ' Read in and check the sprite y coordinate is within bounds
                rdbyte  sprite_y, curr_sprite_ptr
                add     curr_sprite_ptr, #1
               
                ' Adjust sprite y position by subtracting top margin amount
                sub     sprite_y, #21
                sub     sprite_y, curr_scanline
                neg     sprite_y, sprite_y

                cmp     sprite_y, #0        wc
if_c            jmp     #:next_sprite
                
                cmp     sprite_y, #21       wc
if_nc           jmp     #:next_sprite
                    
                ' Read in the sprite colors and combine them with the common sprite color
                rdbyte  sprite_colors, curr_sprite_ptr
                shl     sprite_colors, #1
                add     sprite_colors, lookup_ptr
                rdword  sprite_colors, sprite_colors
                shl     sprite_colors, #8
                or      sprite_colors, common_sprite_colors
                add     curr_sprite_ptr, #1
                
                ' Read in the sprite pointer and adjust for the current scanline
                rdbyte  sprite_ptr, curr_sprite_ptr
                add     sprite_y, #SPRITE_OFFSET_TABLE
                movs    :load_offset, sprite_y
                shl     sprite_ptr, #6
:load_offset    add     sprite_ptr, 0_0
                add     sprite_ptr, memory_ptr
                
                ' Set up our destination buffer
                mov     dest_ptr, buffer_ptr
                add     dest_ptr, sprite_x
                
                ' Draw each byte remaining in this scanline
                mov     chars_remaining, #3
:byte_loop
                ' Read in the sprite data
                rdbyte  pixel_data, sprite_ptr
                add     sprite_ptr, #1
                
                ' Draw each pixel in this byte (in reverse order)
                add     dest_ptr, #3
                mov     pixels_remaining, #4
:pixel_loop             
                ' Move the current color into position for drawing
                mov     temp, pixel_data
                and     temp, #%11
                shl     temp, #3
                ror     sprite_colors, temp
                
                ' Draw the pixel if non-transparent
                cmp     temp, #0                wz
if_nz           wrbyte  sprite_colors, dest_ptr
                sub     dest_ptr, #1
                
                ' Prepare for the next pixel
                rol     sprite_colors, temp                   
                shr     pixel_data, #2
                
                djnz    pixels_remaining, #:pixel_loop
                
                add     dest_ptr, #5
                djnz    chars_remaining, #:byte_loop
                
:next_sprite            
                ' Increment the sprite register pointer to the start of the next sprite
                andn    curr_sprite_ptr, #3
                add     curr_sprite_ptr, #4
                
                ' Loop if we have more sprites remaining
                djnz    sprites_remaining, #:sprite_loop
                
render_sprites_ret      ret

'
' Decodes the video registers into variables. This should be called prior to each
' scanline, incorporating the original values in the registers plus any updates
' from raster effects.
'
decode_registers

                ' Calculate color memory position
                mov     colmem_ptr, colorreg
                shr     colmem_ptr, #4
                shl     colmem_ptr, #10
                add     colmem_ptr, memory_ptr
                
                ' Calculate screen memory position
                mov     scrmem_ptr, basereg
                shr     scrmem_ptr, #4
                shl     scrmem_ptr, #10
                add     scrmem_ptr, memory_ptr
                
                ' Calculate character set position
                mov     chrset_ptr, basereg
                and     chrset_ptr, #$7
                shl     chrset_ptr, #11
                add     chrset_ptr, memory_ptr  
                
                ' Calculate scroll values
                mov     scrollv, scrollreg
                and     scrollv, #%00000111
                
                mov     scrollh, scrollreg
                shr     scrollh, #4
                and     scrollh, #%00000011
                
                ' Calculate shared screen colors
                mov     common_screen_colors, screenreg
                shl     common_screen_colors, #1
                add     common_screen_colors, lookup_ptr
                rdword  common_screen_colors, common_screen_colors
                shl     common_screen_colors, #16
                
                ' Calculate shared sprite color
                mov     common_sprite_colors, spritereg
                shl     common_sprite_colors, #1
                add     common_sprite_colors, lookup_ptr
                rdword  common_sprite_colors, common_sprite_colors
                shl     common_sprite_colors, #24
                
decode_registers_ret  ret

'
' Applies the row effects (a simplified version of a raster interrupt) for the
' current scanline. Each row effect control byte and data byte are read and
' compared to the current scanline's row for applicability. If the row effect
' should be applied the appropriate register is updated.
'
apply_row_effects

                ' Quick check to ensure that row effects are enabled
                test    controlreg, #%00001000          wz
if_z            jmp     #apply_row_effects_ret

                ' Calculate what row we're currently on for row effects
                mov     roweff_row, curr_scanline
                shr     roweff_row, #3
                
                ' Start at the beginning of each bank of registers
                mov     roweff_cntl_ptr, ROWEFF_CNTL_OFFSET
                mov     roweff_data_ptr, ROWEFF_DATA_OFFSET
                
                ' Begin the row effects loop
                mov     roweff_remaining, #32
                
                ' Read the control and data bytes
:loop           rdbyte  roweff_cntl_byte, roweff_cntl_ptr
                
                mov     temp, roweff_cntl_byte
                and     temp, #%00011111
                
                rdbyte  roweff_data_byte, roweff_data_ptr
                
                ' Test that this line is applicable for this row
                cmp     temp, roweff_row                wz
if_nz           jmp     #:next
                
                ' Apply the replacement for the selected register
                mov     temp, roweff_cntl_byte
                and     temp, #%11100000
        
                cmp     temp, #%10000000                wz
if_z            mov     basereg, roweff_data_byte
                
                cmp     temp, #%10100000                wz
if_z            mov     scrollreg, roweff_data_byte
                
                cmp     temp, #%11000000                wz
if_z            mov     screenreg, roweff_data_byte
                
                cmp     temp, #%11100000                wz
if_z            mov     spritereg, roweff_data_byte
                
:next           add     roweff_cntl_ptr, #1
                add     roweff_data_ptr, #1
                
                djnz    roweff_remaining, #:loop
                
apply_row_effects_ret   ret

chars_remaining         long    0                   ' Number of characters remaining in current line
lines_remaining         long    0                   ' Number of lines remaining in current frame
pixels_remaining        long    0                   ' Number of pixels remaining in current operation

curr_scanline           long    0                   ' Current scanline

buffer_ptr              long    0                   ' Pointer to current buffer position
source_ptr              long    0                   ' Pointer to current source position
dest_ptr                long    0                   ' Pointer to current destination address for rendering operations

toggle                  long    0                   ' Temporary storage for reading toggle value from mailbox                 

blankreg                long    0                   ' Video blanking register (unused)
controlreg              long    0                   ' Video control register
colorreg                long    0                   ' Color register
basereg                 long    0                   ' Base register value
scrollreg               long    0                   ' Scroll register value
screenreg               long    0                   ' Shared screen color register value
spritereg               long    0                   ' Sprite control register value

scrollh                 long    0                   ' Decoded horizontal scroll amount
scrollv                 long    0                   ' Decoded vertical scroll amount
adjustv                 long    0                   ' Calculated adjustment for vertical scrolling

renderer_index          long    $0                  ' Number of this renderer
memory_ptr              long    $4                  ' Pointer to the shared memory
lookup_ptr              long    $8                  ' Pointer to the color lookup table
toggle_ptr              long    $C                  ' Pointer to the toggle
buffer1_ptr             long    $10                 ' Pointer to the start of buffer 1
buffer2_ptr             long    $D0                 ' Pointer to the start of buffer 2

pixel_data              long    0                   ' Pixels used for sprite or character rendering operations
color_data              long    0                   ' Colors used for character rendering operations
char_offset_y           long    0                   ' Calculated offset in a character based on current scanline

screen_memory_offset    long    0                   ' Variable to store lookup value from SCREEN_OFFSET_TABLE

scrmem_ptr              long    0                   ' Pointer to screen memory
colmem_ptr              long    0                   ' Pointer to color memory
chrset_ptr              long    0                   ' Pointer to the character set memory

common_screen_colors    long    0                   ' Decoded common screen colors
common_sprite_colors    long    0                   ' Decoded common sprite colors (actually just one)

video_register_ptr      long    0                   ' Pointer used for reading video registers from shared memory
 
sprites_remaining       long    0

sprite_x                long    0                   ' Variables to hold sprite register values
sprite_y                long    0
sprite_colors           long    0
sprite_ptr              long    0 

curr_sprite_ptr         long    0                   ' Pointer to the current register for the current sprite

roweff_remaining        long    0                   ' Number of row effects remaining
roweff_cntl_ptr         long    0                   ' Pointer to the current row effect control byte
roweff_data_ptr         long    0                   ' Pointer to the current row effect data byte
roweff_cntl_byte        long    0                   ' Current row effect control byte
roweff_data_byte        long    0                   ' Current row effect data byte
roweff_row              long    0                   ' Current row for row effects

SCREEN_OFFSET_TABLE     long    0                   ' Offset table for each row's location in screen memory
                        long    40
                        long    80
                        long    120
                        long    160                  
                        long    200
                        long    240
                        long    280
                        long    320
                        long    360                    
                        long    400
                        long    440
                        long    480
                        long    520
                        long    560
                        long    600
                        long    640
                        long    680
                        long    720
                        long    760
                        long    800                    
                        long    840
                        long    880
                        long    920
                        long    960

SPRITE_OFFSET_TABLE     long    0                   ' Offset table for each sprite row's location in sprite memory
                        long    3
                        long    6
                        long    9
                        long    12
                        long    15
                        long    18
                        long    21
                        long    24
                        long    27
                        long    30
                        long    33
                        long    36
                        long    39
                        long    42
                        long    45
                        long    48
                        long    51
                        long    54
                        long    57
                        long    60
                        long    63
                        long    0                        

VIDCTL_REGS_OFFSET      long    $3000               ' Offset for the video registers in shared memory
SPRITE_REGS_OFFSET      long    $3080               ' Offset for the sprite banks in shared memory

ROWEFF_CNTL_OFFSET      long    $3040               ' Offsets for the row effect banks
ROWEFF_DATA_OFFSET      long    $3060

temp                    long    $0

curr_chrset_ptr         long    0
curr_screen_ptr         long    0
curr_colors_ptr         long    0
curr_screen_adv         long    0

TOGGLE_EMPTY            long    $0
TOGGLE_FRAME            long    $1
TOGGLE_LINE1            long    $2
TOGGLE_LINE2            long    $3

                        fit     496
