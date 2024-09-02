# Firmware Analysis

## "Track" Variant

An alternative firmware was provided for use on the
DISC Velodrome which disables "sleep" modes in the
original firmware. The only difference between original
and track firmware variants is the removal of the
branch test at offset 0x013a. This change prolongs
activation of the transponder when held over a loop,
and removes minimum activation intervals.


## Files

   - 93388.hex: Standard RC Firmware
   - 93388.asm: Annotated Program Listing
   - 125333.hex: Modified "Track" RC Firmware

