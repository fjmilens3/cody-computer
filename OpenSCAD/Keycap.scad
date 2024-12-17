/*
 * Keycap.scad
 * OpenSCAD file defining the keycaps for the Cody Computer's mechanical keyboard.
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
 * The Cody Computer has a total of 31 keys including a space bar. Each keycap has a Cherry
 * MX stem and legends on the top; the spacebar has two stems and no legends. Legends are
 * defined using SVG files and subtracted from the top surface of the keycap.
 *
 * Keycaps should be 3D printed top-down on a glass bed. Once printed, the keycaps may be
 * lightly sanded to remove any printing artifacts and air-dry white clay used to fill in
 * the legends. Once dry, the keycaps can be sprayed with a clear coat to seal in the clay
 * for the legends.
 *
 * The spacebar is slightly different from the other keycaps to minimize the risk that the
 * spacebar will jam. The keyboard does not use stabilizers because of the nonstandard key
 * spacing, so some modifications to the interior are required to avoid jams on either
 * side of the spacebar.
 */

module Keycap(legend) {
    
    union() {
            
        // subtract the hollow bottom part and the legend from the keycap shape
        difference() {

            // main keycap shape
            hull() {
                linear_extrude (0.1) KeySlice(15.5, 15.5);
                translate([0, 0, 13 - 0.2]) linear_extrude (0.1) KeySlice(14.5, 14.5);
            }
            
            // hollow portion at bottom of keycap
            hull() {
                linear_extrude (0.1) KeySlice(15.5 - 2, 15.5 - 2);
                translate([0, 0, 4 - 0.2]) linear_extrude (0.1) KeySlice(14.5 - 2, 14.5 - 2);
            }
            
            // recessed keycap legend on top
            translate([0, 0, 12]) linear_extrude(2) difference() {
                import(str("./SVG/Keycap", legend, ".svg"), center=true);
                translate([7, 7, 0]) square(size=1, center=true);
                translate([7, -7, 0]) square(size=1, center=true);
                translate([-7, 7, 0]) square(size=1, center=true);
                translate([-7, -7, 0]) square(size=1, center=true);
            }
        }

        // Cherry MX keystem
        translate([0, 0, 2]) KeyStem();
    }
}

module KeySlice(dimension_x, dimension_y) {
    radius_center_x = dimension_x / 2 - 1;
    radius_center_y = dimension_y / 2 - 1;
    union() {
        translate([-radius_center_x, -radius_center_y, 0]) circle(r=1, $fn=100);
        translate([-radius_center_x, radius_center_y, 0]) circle(r=1, $fn=100);
        translate([radius_center_x, -radius_center_y, 0]) circle(r=1, $fn=100);
        translate([radius_center_x, radius_center_y, 0]) circle(r=1, $fn=100);
        square(size=[dimension_x, dimension_y - 2], center=true);
        square(size=[dimension_x - 2, dimension_y], center=true);
    }
}

module KeyStem() {
    difference() {
        cube([5.4, 5.4, 4], center=true);
        union() {
            cube([1.17, 4.1, 4], center=true);
            cube([4.1, 1.17, 4], center=true);
        }
    }    
}

module Spacebar() {
    // subtract the hollow bottom part and the legend from the keycap shape
    difference() {

        // main keycap shape
        hull() {
            linear_extrude (0.1) KeySlice(95.5, 15.5);
            translate([0, 0, 13 - 0.2]) linear_extrude (0.1) KeySlice(94.5, 14.5);
        }
        
        // hollow portion at bottom of keycap
        hull() {
            linear_extrude (0.1) KeySlice(95.5 - 2, 15.5 - 2);
            translate([0, 0, 11 - 0.2]) linear_extrude (0.1) KeySlice(94.5 - 2, 14.5 - 2);
        }
    }
    
    // Cherry MX keystems
    translate([-40, 0, 2]) KeyStem();
    translate([-40, 0, 8]) cube([8, 8, 9], center=true);

    translate([40, 0, 2]) KeyStem();
    translate([40, 0, 8]) cube([8, 8, 9], center=true);

}
