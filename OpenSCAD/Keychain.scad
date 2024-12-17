/*
 * Keychain.scad
 * The keychain is gratuitous swag for the Cody Computer.
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
 * It can be printed and then assembled using the same process as for the case badge,
 * including the use of air-dry clay and color inlays. A hole is provided to attach
 * the item as on a keychain.
 */
 
module Keychain() {
    
    difference() {

        // main part
        translate([-10, 0, -1]) cube([85, 14, 3]);
        
        // slots for color inlays
        for (i = [0:4]) {
            translate([44, 1 + 2.4*i, 1]) cube([30, 2, 1]);
        }
        
        // hole
        translate([-4.5, 7, 0]) cylinder(h=10, d=5, center=true, $fn=30);
        
        // CODY label
        translate([1, 1, 1]) linear_extrude(2) import("./SVG/CodyLabel.svg", center=false);
    }
}
