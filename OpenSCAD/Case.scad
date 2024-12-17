/*
 * Case.scad
 * OpenSCAD file defining the case for the Cody Computer.
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
 * The bottom portion of the case is affixed via screws to the keyboard mounting
 * brackets specified in a separate file. Refer to that file and the assembly
 * instructions for more information.
 *
 * The top portion of the case is magnetically attached to the top of the keyboard
 * mounting brackets for easy removal (and exploration!). The case badge and LED
 * holder also glue or press-fit into the top of the case.
 *
 * For the case badge the CODY name is recessed into the badge using an SVG file.
 * These spaces can be filled with air-dry clay similar to the keycaps. Slots for
 * color (or painted) inlays are also provided, giving an aesthetic similar to many
 * 1980s computer cases.
 */

module CaseTop() {

    difference() {
    
        union() {
    
            // bottom with cavity
            difference () {
                
                // main shape
                hull() {
                    translate([0, 2, 2]) rotate([0, 90, 0]) cylinder(h=165, r=2, $fn=20);
                    translate([0, 103, 2]) rotate([0, 90, 0]) cylinder(h=165, r=2, $fn=20);
                    translate([0, 0, 20]) cube([165, 105, 1]);
                }
                
                // interior
                translate([2, 2, 2]) cube([161, 101, 19]);
                
                // keyboard punchout
                translate([2.5, 14, 0]) translate([80, 9, 15]) union() {
                    
                    // space bar punchout
                    translate([0, 0, 0]) cube([96 + 2, 16 + 2, 30], center=true);
                    
                    // keyboard row 3 punchout
                    translate([0, 16, 0]) cube([160 + 1, 16 + 2, 30], center=true);
                    
                    // keyboard row 2 punchout
                    translate([0, 32, 0]) cube([144 + 2, 16 + 2, 30], center=true);
                    
                    // keyboard row 3 punchout
                    translate([0, 48, 0]) cube([160 + 1, 16 + 2, 30], center=true);
                
                }
    
                DELTA = 2;
                
                // decorative grooves
                translate([2, 97 + DELTA, 0]) cube([161, 2, 1]);
                translate([2, 93 + DELTA, 0]) cube([161, 2, 1]);
                translate([2, 89 + DELTA, 0]) cube([161, 2, 1]);
                translate([2, 85 + DELTA, 0]) cube([161, 2, 1]);
                translate([2, 81 + DELTA, 0]) cube([161, 2, 1]);
        
            }
    
            // magnet bosses
            translate([2.5 + 5, 2.5 + 5, 2]) MagnetBoss();
            translate([2.5 + 5, 2.5 + 5 + 90, 2]) MagnetBoss();
            translate([2.5 + 5 + 150, 2.5 + 5, 2]) MagnetBoss();
            translate([2.5 + 5 + 150, 2.5 + 5 + 90, 2]) MagnetBoss();
       
            // LED holder mount ring
            translate([22, 81+11, 0.5]) cylinder(h=1, d=13.5, center=true, $fn=50);
    
            // badge mount outline    
            translate([165 - 15 - 73 - 0.5, 84+2 - 0.5, 0]) cube([74, 13, 1]);
        }

        // LED holder mount
        translate([22, 81+11, 0]) cylinder(h=10, d=12.5, center=true, $fn=50);
    
        // badge mount        
        translate([165 - 15 - 73, 84+2, 0]) cube([73, 12, 2]);
    }
}

module CaseBottom() {

    difference() {
    
        union() {
    
            // bottom with cavity
            difference () {
                
                // main shape
                hull() {
                
                    translate([0, 2, 2]) rotate([0, 90, 0]) cylinder(h=165, r=2, $fn=20);
                
                    translate([0, 103, 2]) rotate([0, 90, 0]) cylinder(h=165, r=2, $fn=20);
                    
                    translate([0, 0, 25]) cube([165, 105, 1]);
            
                }
            
                // interior
                translate([2, 2, 2]) cube([161, 101, 25]);
        
            }
    
            // PCB mounting standoffs
            translate([2.5 + 5, 2.5 + 5, 0]) cylinder(h=9.63, d=10, $fn=20);
            translate([2.5 + 5, 2.5 + 5 + 90, 0]) cylinder(h=9.63, d=10, $fn=20);
            translate([2.5 + 5 + 150, 2.5 + 5, 0]) cylinder(h=9.63, d=10, $fn=20);
            translate([2.5 + 5 + 150, 2.5 + 5 + 90, 0]) cylinder(h=9.63, d=10, $fn=20);
        }
        
        // screw heads
        translate([2.5 + 5, 2.5 + 5, 0]) cylinder(h=7.63, d=6.5, $fn=20);
        translate([2.5 + 5, 2.5 + 5 + 90, 0]) cylinder(h=7.63, d=6.5, $fn=20);
        translate([2.5 + 5 + 150, 2.5 + 5, 0]) cylinder(h=7.63, d=6.5, $fn=20);
        translate([2.5 + 5 + 150, 2.5 + 5 + 90, 0]) cylinder(h=7.63, d=6.5, $fn=20);
    
        // screw holes (gives a couple of layers to punch out rather than using supports)
        translate([2.5 + 5, 2.5 + 5, 7.63 + 0.20]) cylinder(h=10, d=3.1, $fn=20);
        translate([2.5 + 5, 2.5 + 5 + 90, 7.63 + 0.20]) cylinder(h=10, d=3.1, $fn=20);
        translate([2.5 + 5 + 150, 2.5 + 5, 7.63 + 0.20]) cylinder(h=10, d=3.1, $fn=20);
        translate([2.5 + 5 + 150, 2.5 + 5 + 90, 7.63 + 0.20]) cylinder(h=10, d=3.1, $fn=20);
    
        // vent holes
        for(count = [0 : 6]) {
            translate([15 + count * 8, 15, 0]) VentHole();
            translate([15 + count * 8, 105 - 15 - 30, 0]) VentHole();
            translate([165 - 15 - 4 - count * 8, 15, 0]) VentHole();
            translate([165 - 15 - 4 - count * 8, 105 - 15 - 30, 0]) VentHole();
        }
        
        // expansion port
        translate([2.5 + 34.2, 0, 4]) cube([58, 10, 17 + 10]);
        
        // video port
        translate([2.5 + 95.7, 0, 11.23]) cube([12, 10, 17]);
        
        // audio port
        translate([2.5 + 114.9, 0, 11.23]) cube([12, 10, 17]);
    
        // prop plug port
        translate([2.5 + 134.1, 0, 11.23]) cube([12, 10, 17]);
        
        // side panel
        translate([0, 10 + 2.5, 11.23]) cube([5, 80, 15]);
    }
}

module LEDHolder() {

    difference() {
            
        union() {
            
            difference() {
            
                union() {
                    
                    // top ring
                    translate([0, 0, 4]) cylinder(h=2, d=14, center=true, $fn=50);
            
                    // main body
                    cylinder(h=10, d=12, center=true, $fn=50);
                }
                
                // hole for LED
                cylinder(h=10, d=11, center=true, $fn=50); // was 11
            
            }
        
            // bottom ring
            translate([0, 0, -6]) cylinder(h=2, d=12, center=true, $fn=50);
        
        }
    
        // LED lead holes
        cylinder(h=40, d=7, center=true, $fn=50);
    }   
}

module CaseBadge() {
    
    difference() {

        // Shape for the main badge (including lower part that pops into top of case)
        union() {
            cube([75, 14, 2]);    
            translate([1, 1, -2]) cube([73, 12, 2]);
        }
        
        // Slots for color inlays
        for (i = [0:4]) {
            translate([44, 1 + 2.4*i, 1]) cube([30, 2, 1]);
        }

        // CODY legend
        translate([1, 1, 1]) linear_extrude(2) import("./SVG/CodyLabel.svg", center=false);
    }    
}

module CaseBadgeInlay() {

    cube([30 - 0.2, 2 - 0.2, 1.6]);
}

module MagnetBoss() {
 
    difference () {
        
        // boss
        translate([0, 0, 2.3/2]) cube([11, 11, 2.3], center=true);

        // hole
        translate([0, 0, 0.8]) cylinder(h=1.5, d=8.0, $fn=50);
    }
}

module VentHole() {

    translate([0, 2, 0]) hull() {
        
        translate([2, 0, 0]) cylinder(h=10, d=4, $fn=20);
        translate([2, 26, 0]) cylinder(h=10, d=4, $fn=20);
    }
}

