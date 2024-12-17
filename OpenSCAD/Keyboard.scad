/*
 * Keyboard.scad
 * OpenSCAD file defining the keyboard for the Cody Computer (with the exception of the keycaps).
 *
 * Copyright 2024 Frederick John Milens III, The Cody Computer Developers.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 3
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 *
 * The Cody Computer's mechanical keyboard is designed for Cherry MX or compatible switches
 * and contains a total of 31 keys in four rows, including two keys used for a spacebar row.
 *
 * The Cody Computer's keyboard brackets form a major portion of the computer's assembly.
 * The bottom of the brackets mount to the top of the motherboard PCB using M3 screws and 
 * the keyboard plate slide-fits into notches in the top of the brackets.
 *
 * The brackets also provide some structural support for the case itself. The sides of the
 * brackets act as additional structural support for the walls of the case, and the tops of
 * the brackets hold magnets to connect to the interior top of the case.
 *
 * For the keyboard plate, space is provided for the PCB and a Dupont-style connector below 
 * the keyboard plate.
 */

module KeyboardPlate() {
    
    difference() {
        
        // keyboard plate
        cube([160, 69, 9.2]);
    
        // bottom cutout for PCB and component leads
        translate([0, 2, 0]) cube([160, 65, 4.2]);
        
        // keyboard row 1
        for (i = [0:9]) translate([1 + i * 16, 51.5, 0]) cube([14, 14, 20]);
     
        // keyboard row 2
        for (i = [0:8]) translate([9 + i * 16, 35.5, 0]) cube([14, 14, 20]);
          
        // keyboard row 3
        for (i = [0:9]) translate([1 + i * 16, 19.5, 0]) cube([14, 14, 20]);
    
        // space bar
        translate([33, 3.5, 0]) cube([14, 14, 20]);
        translate([113, 3.5, 0]) cube([14, 14, 20]);
        
        // empty region below spacebar for dupont connector leads (keyboard connector)
        translate([49, 3.5, 0]) cube([62, 14, 7.2]);
        
        // punchout in front for dupont connector plug (keyboard connector)
        translate([65.5, 0, 0]) cube([29, 10, 2.6]);
    }
}

module KeyboardBracketWithoutHoles() {
    
    difference () {
        
        // main bracket
        union() {
            
            difference() {
                
                // bracket rectangle
                cube([100, 30, 10]); // was 35mm high
            
                // top hole for keyboard plate press-fit
                translate([10, 30 - 9.2 - 2, 0]) cube([69, 9.2, 10]);
            
                // top hole for keyboard plate press-fit
                translate([12, 30 - 9.2, 0]) cube([65, 9.2, 10]);
            
                // bottom hole for components
                translate([10, 0, 0]) cube([80, 15, 10]); // was 20mm high
                               
                
            }
            
            // side panel
            translate([10, 0, 0]) cube([80, 15, 3]); // was 20 mm high
        }
        
        // M3 screw hole for left side of bracket
        translate([3.5, 20, 3.5]) translate([1.5, 0, 1.5]) rotate([90, 0, 0]) cylinder(h=20, d=2.6, $fn=50);
        
        // M3 screw hole for right side of bracket
        translate([93.5, 20, 3.5]) translate([1.5, 0, 1.5]) rotate([90, 0, 0]) cylinder(h=20, d=2.6, $fn=50);
        
        // magnet hole
        translate([1, 30, 1]) translate([4, 0, 4]) rotate([90, 0, 0]) cylinder(h=1.5, d=8.0, $fn=50);
       
        // magnet hole
        translate([91, 30, 1]) translate([4, 0, 4]) rotate([90, 0, 0]) cylinder(h=1.5, d=8.0, $fn=50); 
    }

}

module KeyboardBracketWithHoles() {

    difference() {
        
        translate([100, 0, 0]) mirror([1, 0, 0]) KeyboardBracketWithoutHoles();
        
        // joystick
        translate([30.55, 1.8]) DB9Hole();

        // joystick
        translate([64.06, 1.8]) DB9Hole();

        // power
        translate([13.2, 0]) cube([10.5, 11.5, 10]);
    }

}

module DB9Hole() {
    translate([9.5, 0]) hull() {
        translate([-6.85, 7.28]) cylinder(h=10, r=2.4, $fn=20);
        translate([6.85, 7.28]) cylinder(h=10, r=2.4, $fn=20);
        translate([-6.125, 1.9]) cylinder(h=10, r=2.4, $fn=20);
        translate([6.125, 1.9]) cylinder(h=10, r=2.4, $fn=20);
    }
}
