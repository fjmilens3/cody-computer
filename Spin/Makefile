OPENSPIN ?= openspin
PROPLOADER ?= proploader

CODY_COMPUTER_DEPS = \
    cody_audio.spin \
    cody_line.spin \
    cody_uart.spin \
    cody_video.spin \
    codybasic.bin

.PHONY: all
all: cody_computer.binary

codybasic.bin: ../Tass/codybasic.asm
	$(MAKE) -C ../Tass $@
	cp ../Tass/$@ $@

cody_computer.binary: cody_computer.spin $(CODY_COMPUTER_DEPS)
	$(OPENSPIN) -o $@ $<

.PHONY: upload
upload: cody_computer.binary
	$(PROPLOADER) -e -s $<

.PHONY: clean
clean:
	$(RM) *.binary
