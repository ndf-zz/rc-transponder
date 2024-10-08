;
; Chronelec RC transponder - road style
;
; ID Number:	93388
; ID Block:	016ccc 00030407 0404020505020502030504040304050202030405 02 02
;                 ID  |  Start |              ID no/sum                 |  
;                                                               Battery |  |
;                                                                  Stop    |  |
; Annotated disassembly by gpdasm:
;
;	$ gpdasm -n -s -p p16f639 93388.hex
;
; Memory Usage:
;
; 0x020		Transmit counter 0 [tbc]
; 0x021		Transmit counter 1 [tbc]
; 0x022		Transmit counter 2 [tbc]
; 0x023		TMR1L in transmit loop
; 0x024		Transmit inter token delay count (in units of 10)
; 0x025		[unused]
; 0x026		Count of LF data detections [tbc]
; 0x027		[unused]
; 0x028		TX token count 0->100 [tbc]
; 0x029-0x02e	[unused]
; 0x02f		Program flags (see constants below)
; 0x030		AFE Status
; 0x031-0x03f	[unused]
; 0x040-0x05c	Transponder ID Block
; 0x05d		[unused]
; 0x05e-0x05f	Temp W and STATUS
; 0x060-0x064	AFE SPI communication
; 0x065-0x06c	AFE register copies 0-7
; 0x06d-0x06f	[unused]
; 0x070		Temp counter
; 0x071		Temp AFE function value
; 0x072		AFE register no
; 0x073-0x074	Temp variables in unused AFE functions
; 0x075		Copy of AFE column parity (unused)
; 0x076-0x07a	[unused]
; 0x07b		previous TX word spacing sum
; 0x07c		Deep sleep counter
; 0x07d-0x07e	Reset keys
; 0x07f		0:"Deep sleep" - New LF input ignored
; 0x0a0-0x0bf	[unused]
;


; Setup
        processor p16f639
        radix dec
        include p16f639.inc


; Configuration Word Register: 0x28fa
        CONFIG  FOSC  = HS
        CONFIG  WDTE  = ON
        CONFIG  PWRTE = OFF
        CONFIG  MCLRE = ON
        CONFIG  CP    = OFF
        CONFIG  CPD   = OFF
        CONFIG  BOREN = OFF
        CONFIG  IESO  = OFF
        CONFIG  FCMEN = ON
        CONFIG  WURE  = ON


; ID Locations
	org	0x2000
	dw      0x3fff
	dw      0x3fff
	dw      0x3fff
	dw      0x3fff


; Constants
TX_CNT0	equ	0x20		; TX Counter 0
TX_CNT1	equ	0x21		; TX Counter 1
TX_CNT2	equ	0x22		; TX Counter 2
TX_TML	equ	0x23		; TX TMR1L Timer len in transmit loop
TX_DCNT	equ	0x24		; TX delay counter
RX_CNT	equ	0x26		; RX detection counter [tbc]
TX_TCNT	equ	0x28		; TX Token counter 0-100
SFLAGS	equ	0x2f		; Unit status flags
TXED	equ	0x0		;  0: Flag transmit of data
EOTX	equ	0x1		;  1: Flag transmit end/read mode
LFWAIT	equ	0x2		;  2: Waiting for new LFDATA
AFEERR	equ	0x3		;  3: AFE parity error detected
LFBIT	equ	0x4		;  4: Last LFDATA bit received
NEWLF	equ	0x5		;  5: New LFDATA/Ch X activity detected
AFESTAT	equ	0x30		; AFE Status
CHXACT	equ	0x5		;  5: Channel X Active
TMP_W	equ	0x5f		; W register copy
TMP_S	equ	0x5e		; STATUS register copy (swapped)
SPI_HI	equ	0x60		; AFE SPI request high bits
SPI_LO	equ	0x61		; AFE SPI request low bits
SPI_CNT	equ	0x63		; SPI transmit/receive counter
SPI_OPT	equ	0x64		; SPI control bits 0=r/w 2=?
AFE_CR0	equ	0x65		; AFE Config Register 0
AFE_CR1	equ	0x66		; AFE Config Register 1
AFE_CR2	equ	0x67		; AFE Config Register 2
AFE_CR3	equ	0x68		; AFE Config Register 3
AFE_CR4	equ	0x69		; AFE Config Register 4
AFE_CR5	equ	0x6a		; AFE Config Register 5
AFE_PR6	equ	0x6b		; AFE Column Parity Register 6
AFE_SR7	equ	0x6c		; AFE Status Register 7
C_RAM	equ	0x0070		; size: 16 bytes
TX_SUM	equ	0x07b		; Sum for computing pseudorandom delay
DS_CNT	equ	0x07c		; Deep sleep loop counter
BK_LO	equ	0x07d		; Boot key low bits
BK_HI	equ	0x07e		; Boot key high bits
DSLEEP	equ	0x07f		; Deep sleep flag, bit 0


; Program code
	org	__CODE_START				; address: 0x0000


; ISR: vector_reset
; Reset handler
vector_reset						; address: 0x0000
	nop
	goto	reset_init
	nop
	nop


; ISR: vector_int
; Interrupt handler
vector_int						; address: 0x0004
	; Save STATUS and W
        movwf   TMP_W
        swapf   STATUS, W
        clrf    STATUS
        movwf   TMP_S

	; If AFE /ALERT (Parity error RA2), return handle_ra2int
        btfsc   INTCON, INTF
        goto    handle_ra2int

        ; If LFDATA (PortA1 change interrupt), return handle_lfdata
        btfsc   INTCON, RAIF
        goto    handle_lfdata

	; If Timer1 rolled over, return handle_timer_overflow
        btfsc   PIR1, TMR1IF
        goto    handle_timer_overflow

        goto    interrupt_return


; FUNCTION: configure_afe
; Set AFE configuration registers, soft reset AFE, enable LFDATA ouput
configure_afe						; address: 0x000f
	; CLAMP OFF -> AFE disable talk back modulation circuit
        nop
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        movlw   0x00
        movwf   SPI_LO
        movlw   0x20
        movwf   SPI_HI
        call    spi_send

	; AFE CR0: Output Enable Filter disabled,
	;          /ALERT bit output triggered by parity error
	;          LCX enable
        movlw   0x06
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        movwf   AFE_CR0
        movlw   0x00
        call    afe_update_register
	; AFE CR0: Output Enable Filter: OE High = 1ms, OE Low = 1ms
        movlw   0x56
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        movwf   AFE_CR0
        movlw   0x00
        call    afe_update_register

	; AFE CR1: LFDATA = Demodulated output, LCX tuning = 0pF (default)
        movlw   0x00
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        movwf   AFE_CR1
        movlw   0x01
        call    afe_update_register

	; AFE CR2: RSSI pull down off, Carrier Clock/1, LCY tuning = 0pF, 
        movlw   0x00
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        movwf   AFE_CR2
        movlw   0x02
        call    afe_update_register

	; AFE CR3: LCZ tuning = 0pF
        movlw   0x00
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        movwf   AFE_CR3
        movlw   0x03
        call    afe_update_register

	; AFE CR4: LCX sensitivity reduction = -18dB, LCY sensitivity = -0dB
        movlw   0x90
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        movwf   AFE_CR4
        movlw   0x04
        call    afe_update_register

	; AFE CR5: Auto channel select disabled
	;          AGCSIG demod disabled
	;          Minimum Modulation Depth 50%
        ;          LCZ sensitivity -0dB
        movlw   0x00
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        movwf   AFE_CR5
        movlw   0x05
        call    afe_update_register

	; Set column parity register
        call    afe_recompute_colparity
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        movwf   (C_RAM + 5)				; reg: 0x075
        movlw   0x06
        call    afe_update_register

	; AFE soft reset
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        movlw   0x00
        movwf   SPI_LO
        movlw   0xa0
        movwf   SPI_HI
        call    spi_send

	; Configure C0 and C5 as outputs
        bsf     STATUS, RP0
        bcf     STATUS, RP1
        movlw   0xde
        movwf   TRISC

	; Enable LFDATA output by pulling /CS high. Ref: datasheet 11.32.1
	; Note: Interrupt is enabled seperately by function enable_lfdata
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        bsf     PORTC, RC1
        return


; FUNCTION: disable_lfdata
; Disable ioca1 (LFDATA interrupt) and clear any pending ioca
; Note: will enable GIE, PEIE, INTE if not already set
disable_lfdata						; address: 0x0056
        bsf     STATUS, RP0
        movlw   0x00
        movwf   IOCA
        movlw   0xd0
        movwf   INTCON
        bcf     STATUS, RP0
        movlw   0xd0
        movwf   INTCON
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        movf    PORTA, W
        bcf     INTCON, RAIF
        return


; FUNCTION: enable_lfdata
; Clear pending ioca1 and enable ioca1 (LFDATA interrupt)
; Note: will enable GIE, PEIE, INTE if not already set
enable_lfdata						; address: 0x0063
        bcf     STATUS, RP0
        movf    PORTA, W
        bcf     INTCON, RAIF
        bsf     STATUS, RP0
        bcf     STATUS, RP1
        movlw   0x02
        movwf   IOCA
        movlw   0xd8
        movwf   INTCON
        bcf     STATUS, RP0
        movlw   0xd8
        movwf   INTCON
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        return


; FUNCTION: disable_timer
; Set TMR1 = 0xff00, disable timer, disable TMR1 interrupt
disable_timer						; address: 0x0072
        bcf     STATUS, RP0
        clrf    TMR1L
        movlw   0xff
        movwf   TMR1H
        movlw   0x30
        movwf   T1CON
        bsf     STATUS, RP0
        bcf     STATUS, RP1
        movlw   0x00
        movwf   PIE1
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        return


; FUNCTION: enable_timer
; Enable TMR1 Fosc/4 / 8, and TMR1 interrupt
; If SFLAGS:LFWAIT set timer to 0xafe0 (~200ms)
; Else set timer to 0xff9c (~1ms)
enable_timer						; address: 0x007f
        bcf     STATUS, RP0
        btfss   SFLAGS, LFWAIT
        goto    skip_002
        movlw   0xe0
        movwf   TMR1L
        movlw   0xaf
        movwf   TMR1H
        goto    skip_003
skip_002						; address: 0x0087
        movlw   0x9c
        movwf   TMR1L
        movlw   0xff
        movwf   TMR1H
skip_003						; address: 0x008b
	; Enable Timer1: TMR1GE | 1:8 Prescale | Internal clock | TMR1ON
        movlw   0x31
        movwf   T1CON
        bsf     STATUS, RP0
        movlw   0x01
	movwf	PIE1
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        return


; FUNCTION: wdt_prescale_128
; Alter WDT prescale to ~268s
wdt_prescale_128					; address: 0x0093
        clrwdt
        bsf     STATUS, RP0
        movlw   0x0f
        movwf   OPTION_REG
        bcf     STATUS, RP0
        return


; FUNCTION: wdt_prescale_32
; Alter WDT prescale to ~67s
wdt_prescale_32						; address: 0x0099
        clrwdt
        bsf     STATUS, RP0
        movlw   0x0d
        movwf   OPTION_REG
        bcf     STATUS, RP0
        return


; FUNCTION: wdt_prescale_4
; Alter WDT prescale to ~8s
wdt_prescale_4						; address: 0x009f
        clrwdt
        bsf     STATUS, RP0
        movlw   0x0a
        movwf   OPTION_REG
        bcf     STATUS, RP0
        return


; FUNCTION: wdt_prescale_2
; Alter WDT prescale to ~4s
wdt_prescale_2						; address: 0x00a5
        clrwdt
        bsf     STATUS, RP0
        movlw   0x09
        movwf   OPTION_REG
        bcf     STATUS, RP0
        return


; ISR Sub: reset_init
; Reset routine
reset_init						; address: 0x00ab
	; Zero PORTA/C
        nop
        clrf    PORTA
        clrf    PORTC

	; Set PORTA all input
        bsf     STATUS, RP0
        bcf     STATUS, RP1
        movlw   0xff
        movwf   TRISA

	; Disable analog comparators
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        movlw   0x07
        movwf   CMCON0

	; Set PORTC outputs: C0 & C5
        bsf     STATUS, RP0
        bcf     STATUS, RP1
        movlw   0xde
        movwf   TRISC

	; Set A & C pullups
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        movlw   0xff
        movwf   PORTA
        movlw   0xde
        movwf   PORTC

	; Turn off LED (set C5)
        bsf     PORTC, RC5

	; Option reg: WDT prescale div = 1:2
        bsf     STATUS, RP0
        bcf     STATUS, RP1
        movlw   0x09
        movwf   OPTION_REG

	; Weak pull up WDA2
        movlw   0x04
        movwf   WDA

	; Enable weak pull WDA0-2
        movlw   0x07
        movwf   WPUDA

	; Disable voltage reference
        movlw   0x00
        movwf   VRCON

	; Enable low voltage detect @ 2.3V
        bsf     LVDCON, LVDEN
        movlw   0x14
        movwf   LVDCON

	; Set Oscillator control reg: 4MHz, External clock, source FOSC2:0
        movlw   0x68
        movwf   OSCCON

	; Set WDT: Timer period = 1:65536 ~4.2s
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        movlw   0x16
        movwf   WDTCON
        call    wdt_prescale_2

	; Zero memory 0x20 -> 0x7a
        movlw   0x20
        movwf   FSR
loop_005						; address: 0x00d7
        clrf    INDF
        incf    FSR, F
        movf    FSR, W
        sublw   0x7a
        btfss   STATUS, Z
        goto    loop_005

	; Initialise variables
        movlw   0x03
        movwf   TX_TCNT
        movlw   0x02
        movwf   TX_CNT0
        bsf     SFLAGS, LFWAIT
        movlw   0x01
        movwf   TX_CNT2
        clrf    TX_CNT1

	; Clear low voltage detect flag
        bcf     PIR1, LVDIF

	; AFESTAT = afe_read_config_reg(0x07)
	; Read AFE Status Register: ACI | AGCACT | WuCI | ALARM
        movlw   0x07
        call    afe_read_config_reg
        movwf   AFESTAT

	; Configure AFE and disable lfdata int, enable GIE, PEIE, INTE
        call    configure_afe
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        nop
        call    disable_lfdata

	; If 0x7f:0 goto skip006; else enable lfdata, GIE, PEIE, INTE
        btfsc   DSLEEP, 0x0
        goto    skip_006
        call    enable_lfdata
        goto    skip_008
skip_006						; address: 0x00f2
	; Clear AFE status
        clrf    AFESTAT
	; Saturated increment DS_CNT to 5
        incf    DS_CNT, F
        movlw   0x06
        subwf   DS_CNT, W
        btfss   STATUS, Z
        goto    skip_007
        movlw   0x05
        movwf   DS_CNT
skip_007						; address: 0x00fa
	; Clear deep sleep bit
        bcf     DSLEEP, 0x0
skip_008						; address: 0x00fb
	; Enable timer ~200ms
        call    enable_timer

	; If BK_LO == 0x59 and BK_HI == 0xae, skip_010
        movf    BK_LO, W
        sublw   0x59
        btfss   STATUS, Z
        goto    skip_009
        movf    BK_HI, W
        sublw   0xae
        btfss   STATUS, Z
        goto    skip_009
        goto    skip_010
skip_009						; address: 0x0105
	; Initialise boot keys and deep sleep
        movlw   0x59
        movwf   BK_LO
        movlw   0xae
        movwf   BK_HI
        clrf    DSLEEP
        clrf    DS_CNT
        goto    skip_011

skip_010						; address: 0x010c
        nop
	; If CHXACT Channel X Active
        btfss   AFESTAT, CHXACT
        goto    skip_011
        bcf     STATUS, RP0
        bcf     SFLAGS, LFWAIT
        bcf     SFLAGS, EOTX
        bsf     SFLAGS, NEWLF

	; Turn on LED (clear C5)
        bcf     PORTC, RC5

	; Enable timer ~1ms
        call    enable_timer

	; Disable lfdata, enable other interrupts
        call    disable_lfdata

	; Init vars
        clrf    TX_CNT2
        clrf    TX_CNT1
        movlw   0x03
        movwf   TX_TCNT
        movlw   0x02
        movwf   TX_CNT0
        clrf    DS_CNT
        bcf     DSLEEP, 0x0
        clrf    RX_CNT

	; Enable low voltage detect @ 2.3V
        bsf     STATUS, RP0
        bsf     LVDCON, LVDEN
        movlw   0x14
        movwf   LVDCON
        bcf     STATUS, RP0
skip_011						; address: 0x0124
        bcf     STATUS, RP0

loop_012						; address: 0x0125
	; If AFE parity error detected, reset
        nop
        btfss   SFLAGS, AFEERR
        goto    skip_013
        bcf     INTCON, GIE
        goto    reset_init

skip_013						; address: 0x012a
        btfss   SFLAGS, LFWAIT
        goto    skip_017

	; Read LFDATA input
        btfss   PORTC, RC4
        goto    skip_016
        btfsc   SFLAGS, LFBIT
        goto    skip_017
        bsf     SFLAGS, LFBIT
        incf    RX_CNT, F
        movlw   0x06
        subwf   RX_CNT, W
        btfss   STATUS, Z
        goto    skip_014
        movlw   0x05
        movwf   RX_CNT
skip_014						; address: 0x0138
        movlw   0x05
        subwf   RX_CNT, W

	; Test for sleep mode - omitted in track firmware variant
        btfss   STATUS, Z				; address: 0x013a
        goto    skip_015
        bsf     DSLEEP, 0x0
        goto    skip_017
skip_015						; address: 0x013e
        bcf     DSLEEP, 0x0
        goto    skip_017
skip_016						; address: 0x0140
        bcf     SFLAGS, LFBIT
skip_017						; address: 0x0141
        btfss   SFLAGS, EOTX
        goto    loop_012

        bcf     SFLAGS, EOTX
        call    disable_timer

	; Disable voltage reference
        bsf     STATUS, RP0
        bcf     STATUS, RP1
        movlw   0x00
        movwf   VRCON

	; Disable low voltage detect module
        movlw   0x00
        movwf   LVDCON
        bcf     STATUS, RP0

	; Turn off LED and lower RC0
        movlw   0xfe
        movwf   PORTC

	; If in loop too long, deep sleep
        btfss   DSLEEP, 0x0
        goto    skip_020
        movlw   0x05
        subwf   DS_CNT, W
        btfsc   STATUS, Z
        goto    skip_018

	; Deep sleep for 8s
        bcf     SFLAGS, TXED
        call    wdt_prescale_4
        call    disable_lfdata
        goto    loop_019

skip_018						; address: 0x0158
	; Deep sleep for 67s
        bcf     SFLAGS, TXED
        call    wdt_prescale_32
        call    disable_lfdata
        clrf    DS_CNT

loop_019						; address: 0x015c
        sleep
	; Ensure interrupt is serviced before branch to loop_012
        nop
        nop
        nop
        goto    loop_012
skip_020						; address: 0x0161
	; If nothing transmitted in this loop,
	;   sleep with lfdata wakeup enabled for ~270s
        btfsc   SFLAGS, TXED
        goto    label_021
        call    wdt_prescale_128
        call    enable_lfdata
        goto    loop_019
label_021						; address: 0x0166
	; Else sleep with lfdata wakeup enabled for ~4s
        bcf     SFLAGS, TXED
        call    wdt_prescale_2
        call    enable_lfdata
        goto    loop_019


; ISR Sub: handle_ra2int
; Clear INTCON, flag parity error
handle_ra2int						; address: 0x016a
        bcf     INTCON, INTF
        bsf     SFLAGS, AFEERR
        goto    interrupt_return


; ISR Sub: handle_lfdata
; Respond to AFE demodulated data on LFDATA input
handle_lfdata						; address: 0x016d
        bcf     INTCON, RAIF
        bcf     STATUS, RP0

	; If deep sleep set, skip_024
        btfsc   DSLEEP, 0x0
        goto    skip_024

	; Schedule ~4s WDT reset
        call    wdt_prescale_2

	; Turn on LED (clear C5)
        bcf     PORTC, RC5
        bcf     SFLAGS, LFWAIT
        bcf     SFLAGS, EOTX
        bsf     SFLAGS, NEWLF

	; Enable 1ms timer and disable lfdata
        call    enable_timer
        call    disable_lfdata
        clrf    TX_CNT2
        clrf    TX_CNT1
        movlw   0x03
        movwf   TX_TCNT
        movlw   0x02
        movwf   TX_CNT0
        clrf    DS_CNT
        bcf     DSLEEP, 0x0
        clrf    RX_CNT

	; Enable low voltage detect @ 2.3V
        bsf     STATUS, RP0
        bsf     LVDCON, LVDEN
        ;bsf     LVDCON, 0x4
        movlw   0x14
        movwf   LVDCON
        bcf     STATUS, RP0
        goto    skip_025

skip_024						; address: 0x0187
	; Ignore input and disable LFDATA
        bsf     SFLAGS, LFWAIT
        bcf     SFLAGS, EOTX
        movlw   0x01
        movwf   TX_CNT2
        clrf    TX_CNT1
        clrf    RX_CNT

	; Enable 200ms timer & disable lfdata
        call    enable_timer
        call    disable_lfdata

skip_025						; address: 0x018f
	; Read PORTA to clear ioca1 and clear raif again
        movf    PORTA, W
        bcf     INTCON, RAIF
        goto    interrupt_return


; ISR Sub: handle_timer_overflow
; Transmit ID if required
handle_timer_overflow					; address: 0x0192
        bcf     PIR1, TMR1IF
        bcf     STATUS, RP0
        nop

	; If SFLAGS:LFWAIT, skip_063
        btfss   SFLAGS, LFWAIT
        goto    id_block
        goto    skip_063

id_block						; address: 0x0198
	; Transfer ID block into registers 0x040:0x05c
        movlw   0x9c
        movwf   TMR1L
        movlw   0xff
        movwf   TMR1H
        movwf   TX_TML
        movlw   0x01
        movwf   0x42
        movlw   0x6c
        movwf   0x41
        movlw   0xcc
        movwf   0x40
        movlw   0x00
        movwf   0x43
        movlw   0x03
        movwf   0x44
        movlw   0x04
        movwf   0x45
        movlw   0x07
        movwf   0x46
        movlw   0x04
        movwf   0x47
        movlw   0x04
        movwf   0x48
        movlw   0x02
        movwf   0x49
        movlw   0x05
        movwf   0x4a
        movlw   0x05
        movwf   0x4b
        movlw   0x02
        movwf   0x4c
        movlw   0x05
        movwf   0x4d
        movlw   0x02
        movwf   0x4e
        movlw   0x03
        movwf   0x4f
        movlw   0x05
        movwf   0x50
        movlw   0x04
        movwf   0x51
        movlw   0x04
        movwf   0x52
        movlw   0x03
        movwf   0x53
        movlw   0x04
        movwf   0x54
        movlw   0x05
        movwf   0x55
        movlw   0x02
        movwf   0x56
        movlw   0x02
        movwf   0x57
        movlw   0x03
        movwf   0x58
        movlw   0x04
        movwf   0x59
        movlw   0x05
        movwf   0x5a
        movlw   0x02
        movwf   0x5b
        movlw   0x02
        movwf   0x5c

	; If first transmit timeout, skip to delay time calc
        btfsc   SFLAGS, NEWLF
        goto    skip_057

	; Pre-roll/back-off? return until ++TX_CNT0 == TX_TCNT
        incf    TX_SUM, F
        incf    TX_CNT0, F
        movf    TX_CNT0, W
        subwf   TX_TCNT, W
        btfss   STATUS, Z
        goto    interrupt_return

	; Saturated increment TX_TCNT to 0x63
        clrf    TX_CNT0
        incf    TX_TCNT, F
        movlw   0x64
        subwf   TX_TCNT, W
        btfss   STATUS, Z
        goto    skip_028
        movlw   0x63
        movwf   TX_TCNT

skip_028						; address: 0x01e7
	; If low voltage detected, update reg 0x5b with 0x05
        nop
        btfss   PIR1, LVDIF
        goto    label_029
        movlw   0x05
        movwf   0x5b

label_029						; address: 0x01ec
	; Toggle Port C with delay times encoded above in ID block
        movf    0x43, W
        btfsc   STATUS, Z
        goto    skip_031
        movlw   0xdf
        movwf   PORTC
        movlw   0xde
delay_030						; address: 0x01f2
        decfsz  0x43, F
        goto    delay_030
        movwf   PORTC
        movlw   0xdf
        nop
skip_031						; address: 0x01f7
        movlw   0xdf
        movwf   PORTC
        movlw   0xde
delay_032						; address: 0x01fa
        decfsz  0x44, F
        goto    delay_032
        movwf   PORTC
        movlw   0xdf
        nop
        movwf   PORTC
        movlw   0xde
delay_033						; address: 0x0201
        decfsz  0x45, F
        goto    delay_033
        movwf   PORTC
        movlw   0xdf
        nop
        movwf   PORTC
        movlw   0xde
delay_034						; address: 0x0208
        decfsz  0x46, F
        goto    delay_034
        movwf   PORTC
        movlw   0xdf
        nop
        movwf   PORTC
        movlw   0xde
delay_035						; address: 0x020f
        decfsz  0x47, F
        goto    delay_035
        movwf   PORTC
        movlw   0xdf
        nop
        movwf   PORTC
        movlw   0xde
delay_036						; address: 0x0216
        decfsz  0x48, F
        goto    delay_036
        movwf   PORTC
        movlw   0xdf
        nop
        movwf   PORTC
        movlw   0xde
delay_037						; address: 0x021d
        decfsz  0x49, F
        goto    delay_037
        movwf   PORTC
        movlw   0xdf
        nop
        movwf   PORTC
        movlw   0xde
delay_038						; address: 0x0224
        decfsz  0x4a, F
        goto    delay_038
        movwf   PORTC
        movlw   0xdf
        nop
        movwf   PORTC
        movlw   0xde
delay_039						; address: 0x022b
        decfsz  0x4b, F
        goto    delay_039
        movwf   PORTC
        movlw   0xdf
        nop
        movwf   PORTC
        movlw   0xde
delay_040						; address: 0x0232
        decfsz  0x4c, F
        goto    delay_040
        movwf   PORTC
        movlw   0xdf
        nop
        movwf   PORTC
        movlw   0xde
delay_041						; address: 0x0239
        decfsz  0x4d, F
        goto    delay_041
        movwf   PORTC
        movlw   0xdf
        nop
        movwf   PORTC
        movlw   0xde
delay_042						; address: 0x0240
        decfsz  0x4e, F
        goto    delay_042
        movwf   PORTC
        movlw   0xdf
        nop
        movwf   PORTC
        movlw   0xde
delay_043						; address: 0x0247
        decfsz  0x4f, F
        goto    delay_043
        movwf   PORTC
        movlw   0xdf
        nop
        movwf   PORTC
        movlw   0xde
delay_044						; address: 0x024e
        decfsz  0x50, F
        goto    delay_044
        movwf   PORTC
        movlw   0xdf
        nop
        movwf   PORTC
        movlw   0xde
delay_045						; address: 0x0255
        decfsz  0x51, F
        goto    delay_045
        movwf   PORTC
        movlw   0xdf
        nop
        movwf   PORTC
        movlw   0xde
delay_046						; address: 0x025c
        decfsz  0x52, F
        goto    delay_046
        movwf   PORTC
        movlw   0xdf
        nop
        movwf   PORTC
        movlw   0xde
delay_047						; address: 0x0263
        decfsz  0x53, F
        goto    delay_047
        movwf   PORTC
        movlw   0xdf
        nop
        movwf   PORTC
        movlw   0xde
delay_048						; address: 0x026a
        decfsz  0x54, F
        goto    delay_048
        movwf   PORTC
        movlw   0xdf
        nop
        movwf   PORTC
        movlw   0xde
delay_049						; address: 0x0271
        decfsz  0x55, F
        goto    delay_049
        movwf   PORTC
        movlw   0xdf
        nop
        movwf   PORTC
        movlw   0xde
delay_050						; address: 0x0278
        decfsz  0x56, F
        goto    delay_050
        movwf   PORTC
        movlw   0xdf
        nop
        movwf   PORTC
        movlw   0xde
delay_051						; address: 0x027f
        decfsz  0x57, F
        goto    delay_051
        movwf   PORTC
        movlw   0xdf
        nop
        movwf   PORTC
        movlw   0xde
delay_052						; address: 0x0286
        decfsz  0x58, F
        goto    delay_052
        movwf   PORTC
        movlw   0xdf
        nop
        movwf   PORTC
        movlw   0xde
delay_053						; address: 0x028d
        decfsz  0x59, F
        goto    delay_053
        movwf   PORTC
        movlw   0xdf
        nop
        movwf   PORTC
        movlw   0xde
delay_054						; address: 0x0294
        decfsz  0x5a, F
        goto    delay_054
        movwf   PORTC
        movlw   0xdf
        nop
        movwf   PORTC
        movlw   0xde
delay_055						; address: 0x029b
        decfsz  0x5b, F
        goto    delay_055
        movwf   PORTC
        movlw   0xdf
        nop
        movwf   PORTC
        movlw   0xde
delay_056						; address: 0x02a2
        decfsz  0x5c, F
        goto    delay_056
        movwf   PORTC
        movlw   0xde
        movwf   PORTC
        bsf     SFLAGS, TXED

skip_057						; address: 0x02a8
	; Compute next 4 bit delay time TX_DCNT from ID and counters
        bcf     SFLAGS, NEWLF
        movf    0x40, W
        addwf   0x40, W
        addwf   0x40, W
        addwf   0x41, W
        addwf   0x42, W
        addwf   TX_CNT1, W
        addwf   TX_CNT2, W
        addwf   TX_SUM, F
        movf    TX_SUM, W
        andlw   0x0f
        movwf   TX_DCNT
        movf    TX_DCNT, F

	; If TX_DCNT == 0, skip_062 (leave TMR1L = 0xff for minimum delay)
        btfss   STATUS, Z
        goto    skip_058
        goto    skip_062

skip_058						; address: 0x02b8
        nop

loop_059						; address: 0x02b9
	; Adjust delay time based on TX_DCNT (TX_TML=0xff from above)
        decf    TX_DCNT, F

	; If TX_DCNT != 0, skip_060
        btfss   STATUS, Z
        goto    skip_060

	; Subtract 10 from TX_TML, skip_061
        movlw   0x0a
        subwf   TX_TML, F
        goto    label_061

skip_060						; address: 0x02bf
	; Subtract 10 from TX_TML, loop_059
        movlw   0x0a
        subwf   TX_TML, F
        goto    loop_059

label_061						; address: 0x02c2
	; Set next delay time
        movf    TX_TML, W
        movwf   TMR1L

skip_062						; address: 0x02c4
	; Update tx counters
        incf    TX_CNT1, F
        movf    TX_CNT1, W
        sublw   0x25

	; If TX_CNT1 != 37, skip_064
        btfss   STATUS, Z
        goto    skip_064

        ; Clear TX_CNT1 and increment TX_CNT2
        clrf    TX_CNT1
        incf    TX_CNT2, F
        movf    TX_CNT2, W
        sublw   0x01

	; If TX_CNT2 != 1, skip_064
        btfss   STATUS, Z
        goto    skip_064

	; Set timer to 200ms
        bsf     SFLAGS, LFWAIT
        movlw   0xe0
        movwf   TMR1L
        movlw   0xaf
        movwf   TMR1H

 	; Turn on LED (clear C5) and return (skip_064)
        bcf     PORTC, RC5
        goto    skip_064

skip_063						; address: 0x02d6
	; Flag end of transmit and disable timer
        bsf     SFLAGS, EOTX
        call    disable_timer

skip_064						; address: 0x02d8
	; Return
        nop


; Return from interrupt, restoring W and STATUS
interrupt_return					; address: 0x02d9
        swapf   TMP_S, W
        movwf   STATUS
        swapf   TMP_W, F
        swapf   TMP_W, W
        retfie


; FUNCTION: spi_send_recv
; Send SPI command SPI_HI:SPI_LO, read response and return via SPI_HI:SPI_LO
spi_send_recv						; address: 0x02de
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        bsf     SPI_OPT, 0x0
        goto    skip_066


; FUNCTION: spi_send
; Send SPI Command SPI_HI:SPI_LO and return
spi_send						; address: 0x02e2
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        bcf     SPI_OPT, 0x0				; reg: 0x064
skip_066						; address: 0x02e5
        bsf     STATUS, RP0
        bcf     STATUS, RP1
        movf    TRISC, W
        andlw   0xf1
        movwf   TRISC
        movlw   0x10
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        movwf   SPI_CNT					; reg: 0x063
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        bcf     PORTC, RC2
        bcf     PORTC, RC1
loop_067						; address: 0x02f2
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        rlf     SPI_LO, F
        rlf     SPI_HI, F
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        btfss   STATUS, C
        bcf     PORTC, RC3
        btfsc   STATUS, C
        bsf     PORTC, RC3
        bsf     PORTC, RC2
        nop
        nop
        bcf     PORTC, RC2
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        decfsz  SPI_CNT, F
        goto    loop_067
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        bsf     PORTC, RC1
        bsf     PORTC, RC2
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        btfss   SPI_OPT, 0x0
        goto    skip_069
        bsf     STATUS, RP0
        bcf     STATUS, RP1
        bsf     TRISC, TRISC3
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        movlw   0x10
        movwf   SPI_CNT
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        bcf     PORTC, RC2
        bcf     PORTC, RC1
loop_068						; address: 0x0317
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        bsf     PORTC, RC2
        btfss   PORTC, RC3
        bcf     STATUS, C
        btfsc   PORTC, RC3
        bsf     STATUS, C
        bcf     PORTC, RC2
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        rlf     SPI_LO, F
        rlf     SPI_HI, F
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        decfsz  SPI_CNT, F
        goto    loop_068
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        bsf     PORTC, RC1
        bsf     PORTC, RC2
skip_069						; address: 0x032b
        bsf     STATUS, RP0
        bcf     STATUS, RP1
        movf    TRISC, W
        iorlw   0x0e
        movwf   TRISC
        return


; FUNCTION: afe_update_register
; Copy AFE register W from AFE_CR0+W to AFE over SPI
afe_update_register					; address: 0x0331
	; tmp = W
	; Write 0x065+W (AFE copy register address) to FSR
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        movwf   (C_RAM + 1)				; reg: 0x071
        addlw   AFE_CR0
        movwf   FSR

	; W = tmp<<1 + 0xe0 Write Command
        rlf     (C_RAM + 1), W				; reg: 0x071
        addlw   0xe0

	; Arrange AFE command in 0x060:0x061:
	;  [command] [address] [data] [0]
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        movwf   SPI_HI
        bcf     STATUS, IRP
        rlf     INDF, W
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        btfss   STATUS, C
        bcf     SPI_HI, 0x0
        btfsc   STATUS, C
        bsf     SPI_HI, 0x0
        bcf     STATUS, IRP
        rlf     INDF, W
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        movwf   SPI_LO
        bcf     SPI_LO, 0x0
        bcf     STATUS, IRP

        ; Compute parity, OR with command byte 0x061
        movf    INDF, W
        call    afe_get_row_parity
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        iorwf   SPI_LO, F

	; Update AFE register
        call    spi_send
        retlw   0x00


; FUNCTION: afe_read_config_reg
; Read AFE register W, copy to memory AFE_CR0+W and return value in W
afe_read_config_reg					; address: 0x0351
	; Store W to tmp reg 0x071
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        movwf   (C_RAM + 1)				; reg: 0x071
        addlw   AFE_CR0
        movwf   FSR
        rlf     (C_RAM + 1), W				; reg: 0x071
        addlw   0xc0
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        movwf   SPI_HI
        call    spi_send_recv
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        rrf     SPI_HI, W
        rrf     SPI_LO, W
        bcf     STATUS, IRP
        movwf   INDF
        return


; -- isolated / unused code --
label_070						; address: 0x0363
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        movwf   (C_RAM + 3)				; reg: 0x073
        call    afe_update_register
        movf    INDF, W
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        movwf   (C_RAM + 5)				; reg: 0x075
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        movf    (C_RAM + 3), W				; reg: 0x073
        call    afe_read_config_reg
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        xorwf   (C_RAM + 5), W				; reg: 0x075
        btfss   STATUS, Z
        retlw   0x01
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        btfsc   SPI_OPT, 0x2
        goto    label_072
        return
        call    afe_recompute_colparity
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        bsf     SPI_OPT, 0x2
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        movlw   0x07
        movwf   (C_RAM + 4)				; reg: 0x074
label_071						; address: 0x0381
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        bcf     STATUS, IRP
        decf    (C_RAM + 4), W				; reg: 0x074
        goto    label_070
label_072						; address: 0x0386
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        andlw   0xff
        btfss   STATUS, Z
        retlw   0x01
        decfsz  (C_RAM + 4), F				; reg: 0x074
        goto    label_071
        bcf     SPI_OPT, 0x2
        retlw   0x00


; FUNCTION: afe_load_all_configs
; Read all AFE config regs into memory AFE_CR0->AFE_SR7 -- unused --
afe_load_all_configs					; address: 0x038f
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        movlw   0x07
        movwf   (C_RAM + 4)				; reg: 0x074
label_073						; address: 0x0393
        decf    (C_RAM + 4), W				; reg: 0x074
        call    afe_read_config_reg
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        decfsz  (C_RAM + 4), F				; reg: 0x074
        goto    label_073
        return


; FUNCTION: afe_get_row_parity
; Return row parity bit for AFE register value (W)
afe_get_row_parity					; address: 0x039a
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        ; src = W
        movwf   (C_RAM + 2)				; reg: 0x072
	; tmp = 0
        movlw   0x00
        movwf   (C_RAM + 1)				; reg: 0x071
	; cnt = 8
        movlw   0x08
        movwf   C_RAM					; reg: 0x070
loop_074						; address: 0x03a1
	; If src&1  tmp++
        rrf     (C_RAM + 2), F				; reg: 0x072
        btfsc   STATUS, C
        incf    (C_RAM + 1), F				; reg: 0x071
	; counter-- if zero break
        decfsz  C_RAM, F				; reg: 0x070
        goto    loop_074
	; If tmp&1, return 1 else return 0
        btfsc   (C_RAM + 1), 0x0			; reg: 0x071
        retlw   0x00
        retlw   0x01


; FUNCTION: afe_recompute_colparity
; Compute AFE column parity on ram vars and store to AFE_PR6
afe_recompute_colparity					; address: 0x03a9
        bcf     STATUS, RP0
        bcf     STATUS, RP1
        movf    AFE_CR0, W
        xorwf   AFE_CR1, W
        xorwf   AFE_CR2, W
        xorwf   AFE_CR3, W
        xorwf   AFE_CR4, W
        xorwf   AFE_CR5, W
        xorlw   0xff
        movwf   AFE_PR6
        return


; Padding
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        call    wdt_prescale_2
        nop
        goto    reset_init
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        call    wdt_prescale_2
        nop
        goto    vector_reset
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        call    wdt_prescale_2
        nop
        goto    vector_reset
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        call    wdt_prescale_2
        nop
        goto    vector_reset
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        call    wdt_prescale_2
        nop
        goto    vector_reset
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        call    wdt_prescale_2
        nop
        goto    vector_reset
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        call    wdt_prescale_2
        nop
        goto    vector_reset
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        call    wdt_prescale_2
        nop
        goto    vector_reset
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        call    wdt_prescale_2
        nop
        goto    vector_reset
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        call    wdt_prescale_2
        nop
        goto    vector_reset
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        call    wdt_prescale_2
        nop
        goto    vector_reset
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        call    wdt_prescale_2
        nop
        goto    vector_reset
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        call    wdt_prescale_2
        nop
        goto    vector_reset
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        call    wdt_prescale_2
        nop
        goto    vector_reset
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        call    wdt_prescale_2
        nop
        goto    vector_reset
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        call    wdt_prescale_2
        nop
        goto    vector_reset
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        call    wdt_prescale_2
        nop
        goto    vector_reset
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        call    wdt_prescale_2
        nop
        goto    vector_reset
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        call    wdt_prescale_2
        nop
        goto    vector_reset
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        call    wdt_prescale_2
        nop
        goto    vector_reset
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        call    wdt_prescale_2
        nop
        goto    vector_reset
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        call    wdt_prescale_2
        nop
        goto    vector_reset
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        call    wdt_prescale_2
        nop
        goto    vector_reset

	end
