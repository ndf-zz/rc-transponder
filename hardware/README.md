# Hardware

RC Transponder circuitry is mounted on a small PCB 
under potting compound:

![PCB](rctrans_pcb.jpg "PCB")

LF activation signals are received on 125kHz coil L1 by 
the integrated AFE in U1 (PIC16F639). 

Transponder ID is transmitted by 3.28MHz transmit coil L2
attached to the back side of the PCB:

![TX Coil](rctrans_coil.jpg "TX Coil")

Driver ICs U3/U4 output the CPU clock (CCLK), gated by
PORT C0 output (DAT) through a dual NAND gate (U2).

[![Schematic](rctrans_schematic.svg "Schematic")](rctrans_schematic.pdf)

Notes:

   - Tuning capacitors C4/C5 and C15/C16 actual values are not known
   - Output driver IC U3/U4 parts are not known
