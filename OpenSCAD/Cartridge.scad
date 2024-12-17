/*
 * Cartridge.scad
 * OpenSCAD file defining the case for a Cody Computer cartridge.
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
 * The PCB mounts on the bottom portion of the cartridge, with the top
 * snapping in. A single screw is inserted from the back to the front
 * to hold the cartridge together.
 *
 * The bottom portion of the cartridge has a thin layer below the screw
 * hole. This acts as a bridge to avoid the need for supports and can
 * easily be removed by the screw itself (or a screwdriver) during
 * assembly.
 * 
 * Sanding will be required to ensure a snug fit between the cartridge
 * halves and the PCB.
 */
module CartridgeBottom() {
    
    difference () {
        
        // cartridge
        union() {
            
            difference() {
                
                // cartridge outer shell
                union() {
                    cube([55.340, 55.340, 7.6]);
                }
                
                // cartridge inner cavity
                translate([1, 0, 1]) cube([53.340, 53.340, 8.6]);
            }
        
            // thicker sections for ridges
            translate([0, 30.6 + 6.350, 0]) cube([2, 55.340 - (30.6 + 6.350), 7.6]);
            translate([53.340, 30.6 + 6.350, 0]) cube([2, 55.340 - (30.6 + 6.350), 7.6]);

            // stem for screw/PCB mount
            translate([26.670+1, 30.6, 0]) cylinder(h=5.0, d=10.6, $fn=32);
            translate([26.670+1, 30.6, 0]) cylinder(h=8.6, d=5.3, $fn=32);
            
            // bar for aligning PCB
            translate([10, 30.6 + 6.350, 0]) cube([35.340, 1, 6.6]);

            // tabs for aligning top and bottom of case
            translate([2, 52.340, 1]) cube([51.340, 1, 8.6]);
            translate([2, 30.6 + 6.350, 1]) cube([1, 53.340 - (30.6 + 6.350), 8.6]);
            translate([52.340, 30.6 + 6.350, 1]) cube([1, 53.340 - (30.6 + 6.350), 8.6]);
        }
        
        // Ridges
        translate([0, 49-8, 0]) cube([1, 2, 8.6]);
        translate([0, 49-4, 0]) cube([1, 2, 8.6]);
        translate([0, 49, 0]) cube([1, 2, 8.6]);
        
        translate([54.340, 49-8, 0]) cube([1, 2, 8.6]);
        translate([54.340, 49-4, 0]) cube([1, 2, 8.6]);
        translate([54.340, 49, 0]) cube([1, 2, 8.6]);
        
        // Label slot
        translate([4, 54.340, 2]) cube([47.340, 1, 5.6]);
        
        // M3 screw hole (for self-tapping screw)
        // Has a small amount of material as a bridge to avoid supports
        translate([26.670+1, 30.6, 2.6]) cylinder(h=8, d=2.6, $fn=32);
        translate([26.670+1, 30.6, 0]) cylinder(h=2.4, d=6.5, $fn=32);
    }
}

module CartridgeTop() {
    
    difference () {
        
        // cartridge
        union() {
            
            difference() {
                
                // cartridge outer shell
                cube([55.340, 55.340, 9.6]);
                
                // cartridge inner cavity
                translate([1, 0, 1]) cube([53.340, 53.340, 9.6]);   
            }
            
            // thicker sections for ridges
            translate([0, 30.6 + 6.350 - 2, 0]) cube([2, 55.340 - (30.6 + 6.350) + 2, 9.6]);
            translate([53.340, 30.6 + 6.350 - 2, 0]) cube([2, 55.340 - (30.6 + 6.350) + 2, 9.6]);
            
            // side stabilizers
            translate([1, 30.6 - 5.3, 0]) cube([1, 10, 10.6]);
            translate([53.340, 30.6 - 5.3, 0]) cube([1, 10, 10.6]); 
            
            translate([1, 2, 0]) cube([1, 4, 10.6]);
            translate([53.340, 2, 0]) cube([1, 4, 10.6]); 
                        
            // thicker area for label recess
            translate([3, 16, 0]) cube([49.340, 38.34, 2]);
            
            // stem for screw/PCB mount
            translate([26.670+1, 30.6, 0]) cylinder(h=10.6, d=10.6, $fn=32);
        }
        
        // Hole for exposed pins
        translate([2, 0, 0]) cube([51.340, 8, 3]);  
        
        // Ridges
        translate([0, 49-8, 0]) cube([1, 2, 10.6]);
        translate([0, 49-4, 0]) cube([1, 2, 10.6]);
        translate([0, 49, 0]) cube([1, 2, 10.6]);
        
        translate([54.340, 49-8, 0]) cube([1, 2, 10.6]);
        translate([54.340, 49-4, 0]) cube([1, 2, 10.6]);
        translate([54.340, 49, 0]) cube([1, 2, 10.6]);
        
        // Label slots
        translate([4, 54.340, 0]) cube([47.340, 1, 9.6]);
        translate([4, 18, 0]) cube([47.340, 40.340, 1]);
        
        // M3 screw hole (for self-tapping screw)
        translate([26.670+1, 30.6, 3.6]) cylinder(h=6, d=2.6, $fn=32);
        
        // Post hole (for post on other part)
        translate([26.670+1, 30.6, 8.6]) cylinder(h=2, d=5.5, $fn=32);
    }
}
