/*
 * The keychain is gratuitous swag for the Cody Computer.
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
