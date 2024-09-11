# Helper Scripts


## rcpatch.py

Update transponder firmware, retaining original ID:

	$ ./rcpatch.py firmware.hex

Supply optional number to override the transponder's ID, eg:

	$ ./rcpatch.py firmware.hex 123456

Note: In order to erase ID Locations, a 5V VDD
is required. Set constant variable "POWER" to supply
target with 5V during programming.


## rcinfo.py

Read firmware from transponder, display
version and ID number. For example:

	$ ./rcinfo.py 
	INFO:rcinfo:Chronelec (ID@0x0198)
	INFO:rcinfo:ID: 93409 (0x16ce1)


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

