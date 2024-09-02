# rc-transponder

RC Transponder Documentation

![RC Transponder](hardware/rctrans_pic.jpg "RC Transponder")

The Tag Heuer/Chronelec RC transponder is a
discontinued LF/HF magnetic induction type
identifier for sports timing applications. 

This repository contains information on the
transponder hardware as well as tools for
updating the firmware.


## Contents

   - [hardware](hardware/) : RC hardware reference
   - [firmware](firmware/) : Firmware information and analysis
   - [programmer](programmer/) : Firmware re-programmer and drill template
   - [scripts](scripts/) : Shell and python scripts
   - altfw : Alternative firmware image


## Overview

Based around the PIC16F639 Microcontroller with
Low-Frequency Analog Front-End, the RC transponder
works like a Passive Keyless Entry (PKE) device. 
It receives activation messages on 125kHz
and then responds with a numeric ID by repeating
differential pulse position encoded strings on 3.28MHz
for a short while.

Both LF and HF circuits are magnetically communicated
with a compatible Chronelec Protime decoder and loop.


## Requirements

   - python
   - binutils
   - MPLAB IPE + PicKitx
   - gputils (optional)

To read and reprogram a transponder, a compatible Pickit
programmer is required along with a MPLAB IPE installation,
python3 and objcopy. To assemble the alt firmware, gputils
is required.
