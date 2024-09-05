# Firmware

The RC transponder runs on a
[PIC16F639](https://www.microchip.com/en-us/product/PIC16F639)
8-Bit CMOS Microcontroller with Low-Frequency Analog Front-End
[[datasheet](https://ww1.microchip.com/downloads/aemDocuments/documents/OTH/ProductDocuments/DataSheets/41232D.pdf)].

LF detection is managed by the integrated Analog Front End (AFE)
which the transponder configures with SPI commands. The AFE
automatically demodulates valid activation signals
and reports them to the MCU via LFDATA output and RA1 input.

HF transmission is achieved by gating the CPU clock with
RC0 in the timer interrupt handler. Since the CPU clock
is also the HF carrier, pulse position encoding times are
achieved by repeating simple busy loops.

See [hardware reference](../hardware/) for more information on
circuit layout.


## Firmware Analysis

Refer to:

   - [93388.asm](93388.asm): Annotated program listing
   - [93388.hex](93388.hex): Example firmware, transponder 93388
   - [125333.hex](125333.hex): Chronelec "Track" variant, transponder 125333


### Configuration options:

Configuration word is set to 0x28fa:

   - FOSC: HS oscillator
   - WDTE: Watchdog timer enabled
   - PWRTE: PWRT disabled
   - MCLRE: /MCLR pin function is /MCLR
   - CP: Program memory code protection is disabled
   - CPD: Data memory code protection is disabled
   - BOREN: BOR and SBOREN bits disabled
   - IESO: Internal External Switchover mode is disabled
   - FCMEM: Fail-Safe Clock Monitor is enabled
   - WURE: Wake-up and Reset enabled


### Main Program (roughly)

   - initialise analog front end (AFE)
   - set initial state variables[1]
   - if deep sleep flag is set, increment deep sleep counter
   - enable 200ms timer

   - loop:
      - if AFE error detected, disable interrupts and reset
      - if excessive LFDATA after TX complete[2]:
          - set deep sleep flag
      - if timer complete:
          - disable timer
          - disable low voltage detect
          - if deep sleep flag set, disable lfdata and schedule wdt reset
          - else enable lfdata and schedule wdt reset
          - sleep
          - reset[3]

Notes:

   1. Out of reset, variables 0x020-0x07a are cleared,
      0x07b-0x07f retain previous values
   2. Branch test at offset 0x013a omitted in track firmware
   3. Config option WURE is enabled, all wakeup events result
      in a device reset


### AFE /ALERT Interrupt Handler

AFE signals a parity error via /ALERT output and INT input.
The handler sets an error flag and returns.


### AFE LFDATA Interrupt Handler

AFE signals reception of a valid activation signal by
by writing demodulated bits to LFDATA. This is received
by PortA1 change interrupt handler:

   - if deep sleep flagged:
      - clear status flags
      - enable 200ms timer
      - disable lfdata

   - else:
      - schedule 4s wdt reset
      - turn on LED
      - set flags for transmit
      - enable 1ms timer
      - disable lfdata
      - enable low voltage detect


### Timer1 Interrupt Handler

On overflow of TMR1, the timer handler is called to transmit
ID token and/or sleep according to status flags:

   - if waiting for LFDATA, flag timer complete, disable timer and return

   - transfer ID block to RAM
   - if not a new transmit sequence:
      - increment TX_SUM
      - increment TX_CNT0
      - if TX_CNT0 != TX_TCNT, return
      - clear TX_CNT0
      - saturated increment TX_TCNT up to 0x63
      - if low voltage detected, write 0x05 to battery value @0x05b
      - transmit ID by toggling C0 with delays from ID block

   - compute pseudorandom delay time between 0 and 1.5ms
   - increment TX_CNT1
   - if TX_CNT1 == 37:
      - TX_CNT1 = 0
      - increment TX_CNT2
      - if TX_CNT2 == 1:
          - set waiting for LFDATA flag
          - enable 200ms timer
          - turn on LED
   

### ID Locations and EEPROM

ID Locations (0x2000-0x2003) and EEPROM are not programmed.


## "Track" Variant

An alternative firmware was provided for use on the
DISC Velodrome which disables "sleep" modes in the
original firmware. The only difference between original
and track firmware variants is the removal of the
branch test at offset 0x013a (See note 2 above).
This change allows continued activation of the transponder
after transmission is complete, without a minimum idle time
requirement.
