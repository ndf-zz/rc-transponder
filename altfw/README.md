# Alternative Firmware

## DISCtrain - Velodrome Training Timing System

[dtrn.asm](dtrn.asm) ID: 'DISC-1.0'

This firmware addresses multiple operational
issues with manufacturer-supplied transponders,
particularly for use at the DISC Velodrome.

Main features:

   - LED is switched off during Tx bursts to better
     utilise available battery power.
   - Low voltage monitoring is windowed to avoid spurious
     error messages.
   - LF sensitivity is maintained during transmit sequence
   - Tx dead times are eliminated.
   - Prolonged activation suppresses Tx only while held in loop.
   - Periodic (270s) wakeup/reset is eliminated - transponder
     will sleep indefinitely, waking only for valid activation
     or error condition flagged by AFE.
   - Pseudorandom delays are distributed in 1ms steps from 3 to 10ms,
     and the backoff timer is no longer used.
   - Initial collisions due to concurrent wakeups are reduced.

Build and install:

	$ make dtrn


## LFMON

[lfmon.asm](lfmon.asm) ID: 'LFMon1.0'

Display wakeup by LFDATA on transponder LED without
transmitting ID. Useful for troubleshooting activation
issues using the transponder's in-built AFE.

Build and install:

	$ make lfmon


## HFTEST

[hftest.asm](hftest.asm) ID: 'HFTst1.0'

After an initial LF wakeup, transmit ID once per
second for about 30s. Transmits a single burst
at a time for troubleshooting noise, loop and
reception issues. During active period, LF activations
are ignored, LED flashes briefly when ID is transmitted.

Build and install:

	$ make hftest


## Requirements

To build hex images and reprogram transponders, the following
tools are required:

   - make
   - gputils
   - objcopy
   - python3
   - MPLAB IPE (version v6.20)
   - Pickit programmer (pickit4)

On a Debian system, install MPLAB IPE
then fetch requirements with make:

	$ make requires

