# Hardware


## Circuit Analysis

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


## Measurements

### LF Input

![Activation Signal](activation-lfdata.png "Activation Signal")
![20ms Period](activation-period.png "20ms Activation Period")

125kHz LF activation signal and AFE demodulated output on LFDATA. 

### HF Output

![Transmit](transmit_led_02.png "Transmit Signal")

Example transmission (shown with RC5/LED output) - 0.8s total.

![Single Token](tx_50us.png "Single Token")
![Bit Encoding](tx_10us.png "Bit Encoding")

Token modulation, gaps positioned by delays encoded in ID block.

![CCLK U3 Input](u3-input.png "CCLK and U3 Input")
![CCLK U4 Input](u4-input.png "CCLK and U4 Input")
![DAT U4 Input](tx_100ns.png "DAT U4 Input")

Gating CCLK/DAT signals through U2 into U3 and U4.

### Wakeup Reset

![LED LFDATA](wake_up_reset.png "LED LFDATA Wakeup")
![LED DAT](wake_to_tx.png "LED DAT Wakeup")

LED/LFDATA and LED/DAT on reception of valid activation. LFDATA
noise after trigger bit is due to AFE reconfiguration out of reset.
Transmit sequence begins about 7ms after wakeup, the first token
is transitted about 2ms later.
