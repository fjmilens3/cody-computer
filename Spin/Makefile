# If the Parallax tools are not in the PATH,
# set the following environment variables to the complete paths to the respective tool executables.

# Parallax OpenSpin: https://github.com/parallaxinc/OpenSpin
OPENSPIN ?= openspin
# Parallax PropLoader: https://github.com/parallaxinc/PropLoader
PROPLOADER ?= proploader

CODY_COMPUTER_DEPS = \
    cody_audio.spin \
    cody_line.spin \
    cody_uart.spin \
    cody_video.spin \
    codybasic.bin

.PHONY: all
all: cody_computer.binary

# Rebuild/re-copy the Cody BASIC ROM image if necessary.
# Normally the codybasic.bin committed into the Git repo is always up-to-date,
# but it may need updating if there are local changes to codybasic.asm.
codybasic.bin: ../Tass/codybasic.asm
	$(MAKE) -C ../Tass $@
	cp ../Tass/$@ $@

cody_computer.binary: cody_computer.spin $(CODY_COMPUTER_DEPS)
	$(OPENSPIN) -o $@ $<

ifneq ($(PORT),)
    PROPLOADER_FLAGS += -p "$(PORT)"
endif

.PHONY: upload
upload: cody_computer.binary
	$(PROPLOADER) $(PROPLOADER_FLAGS) -e -r -s $<

# Not deleting codybasic.bin, because it is committed into Git.
.PHONY: clean
clean:
	$(RM) *.binary
