# SPDX-License-Identifier: MIT
#
# RC-Transponder - Alternative Firmware
#

GPASM = gpasm
ASFLAGS = -w 1
IPECMD = ../scripts/ipecmd
RCPATCH = ../scripts/rcpatch.py
RCINFO = ../scripts/rcinfo.py
IPEOPTS = -TPPK4 -P16F639 -W

%.hex: %.asm
	$(GPASM) $(ASFLAGS) $<

.PHONY: help
help:
	@echo
	@echo Targets:
	@echo " lfmon           build lfmon and program transponder"
	@echo " hftest          build hftest and program transponder"
	@echo " dtrn            build dtrn and program transponder"
	@echo " info            read transponder info"
	@echo " erase           bulk erase transponder"
	@echo " requires        install development dependencies"
	@echo " clean           remove intermediate files"
	@echo

.PHONY: all
all: lfmon.hex hftest.hex dtrn.hex

.PHONY: lfmon
lfmon: lfmon.hex
	$(RCPATCH) lfmon.hex

.PHONY: hftest
hftest: hftest.hex
	$(RCPATCH) hftest.hex

.PHONY: dtrn
dtrn: dtrn.hex
	$(RCPATCH) dtrn.hex

.PHONY: info
info:
	$(RCINFO)

.PHONY: erase
erase:
	$(IPECMD) $(IPEOPTS) -E

.PHONY: requires
requires:
	sudo apt-get install build-essential python3-minimal gputils

.PHONY: clean
clean:
	-rm -f *.hex *.cod *.lst
