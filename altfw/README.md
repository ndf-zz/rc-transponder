# Alternative Firmware

## DISCtrain - Velodrome Training Timing System

Source: dtrn.asm  
ID: 'DISC-1.0'

This firmware addresses multiple operational
issues with manufacturer-supplied transponders,
particularly for use at the DISC Velodrome.

Main features:

   - LED indicates reception of valid activation signal
   - LED is switched off during Tx sequence to better
     utilise available battery power
   - Low voltage monitoring is windowed to avoid spurious
     error messages
   - LF sensitivity is maintained during transmit sequences
   - Tx dead times are eliminated
   - Prolonged activation suppresses Tx only while held in loop
   - Periodic (270s) wakeup/reset is eliminated - transponder
     will sleep indefinitely, waking only for valid activation
     or error condition flagged by AFE
   - Initial response time is improved and pseudorandom delays
     are distributed more evenly.

Build and install:

	$ make dtrn


## LFMON

Source: lfmon.asm  
ID: 'LFMon1.0'

Display wakeup by LFDATA on transponder LED without
transmitting ID. Useful for troubleshooting activation
issues using the transponder AFE.

Build and install:

	$ make lfmon


## HFTEST

Source: hftest.asm  
ID: 'HFTst1.0'

After an initial LF wakeup, transmit ID once per
second for about 30s. Transmits a single burst
at a time for troubleshooting noise, loop and
reception issues. During active period, LF activations
are ignored, LED flashes briefly when ID is transmitted.

Build and install:

	$ make hftest
