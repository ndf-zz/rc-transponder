# Helper Scripts

## rcpatch.py

Update transponder firmware, retaining ID block. For example:

	$ ./rcpatch.py firmware.hex
	[...]
	DEBUG:rcpatch:Found ID block at offset: 0x198
	DEBUG:rcpatch:93388 - 016ccc0003040704040205050205020305040403040502020304050202
	DEBUG:rcpatch:Saved original firmware to 93388_orig.hex
	[...]
	Device Type:PIC16F639
	Program Succeeded.
	Operation Succeeded

## ipecmd

IPECMD command wrapper for running MPLAB IPE tool:

	$ ./ipecmd -?

To restore a backup firmware image:

	$ ./ipecmd -TPPK4 -P16F639 -Ffirmware.hex -M
	DFP Version Used : PIC16Fxxx_DFP,1.6.156,Microchip
	[...]
	Erasing...
	The following memory area(s) will be programmed:
	program memory: start address = 0x0, end address = 0x7ff
	configuration memory
	Programming/Verify complete
 	Program Report
	2024-08-30, 20:33:39
	Device Type:PIC16F639
	Program Succeeded.
	Operation Succeeded

