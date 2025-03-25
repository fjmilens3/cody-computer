all: codybasic.bin codybros.bin codycart.bin codyprog.bin codysid.bin codybitmap.bin resident.bin codyhires.bin

%.bin: %.asm
	64tass --mw65c02 --nostart -o $@ $<
