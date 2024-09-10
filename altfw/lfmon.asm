;
; Chronelec RC transponder - Alternative Firmware
;
; Test Program: LFMon
; Monitor LFDATA input and display on LED
; Date: 2024-09-11
; Version: 1.0
;


; Setup
	processor p16f639
	radix dec
	include p16f639.inc


; Configuration Word Register
	CONFIG	FOSC  = HS
	CONFIG	WDTE  = OFF
	CONFIG	PWRTE = OFF
	CONFIG	MCLRE = ON
	CONFIG	CP    = OFF
	CONFIG	CPD   = OFF
	CONFIG	BOREN = OFF
	CONFIG	IESO  = OFF
	CONFIG	FCMEN = ON
	CONFIG	WURE  = OFF


; ID Locations 'LFMon1.0'
	org	_IDLOC0
	dw	0x2646
	dw	0x26ef
	dw	0x3731
	dw	0x1730


; Registers
SPI_HI	equ	0x60		; AFE SPI request high bits
SPI_LO	equ	0x61		; AFE SPI request low bits
SPI_CNT equ	0x63		; SPI transmit/receive counter
SPI_OPT equ	0x64		; SPI control bits 0=r/w
AFE_CR0 equ	0x65		; AFE Config Register 0
AFE_CR1 equ	0x66		; AFE Config Register 1
AFE_CR2 equ	0x67		; AFE Config Register 2
AFE_CR3 equ	0x68		; AFE Config Register 3
AFE_CR4 equ	0x69		; AFE Config Register 4
AFE_CR5 equ	0x6a		; AFE Config Register 5
AFE_PR6 equ	0x6b		; AFE Column Parity Register 6
AFE_SR7 equ	0x6c		; AFE Status Register 7
PRT_CNT equ	0x70		; Parity check counter
PRT_SUM equ	0x71		; Parity ones
PRT_TMP equ	0x72		; Parity temp value
SFLAGS	equ	0x7d		; Runtime flags
AFEERR	equ	0x1		; AFE Parity error flag
LFDATA	equ	0x2		; LFDATA activity flag
INTRET	equ	0x3		; Interrupt handler called
TMP_W	equ	0x7e		; W register copy
TMP_S	equ	0x7f		; STATUS register copy (swapped)


; Program code
	org	__CODE_START


; ISR: vector_reset
; Reset handler
vector_reset:
	nop
	goto	reset_init
	nop
	nop


; ISR: vector_int
; Interrupt handler
vector_int:
	; Save STATUS and W
	movwf	TMP_W
	swapf	STATUS, W
	clrf	STATUS
	movwf	TMP_S

	; If AFE /ALERT (Parity error RA2), return handle_ra2int
	btfsc	INTCON, INTF
	goto	handle_ra2int

	; If LFDATA (PortA1 change interrupt), return handle_lfdata
	btfsc	INTCON, RAIF
	goto	handle_lfdata

	; If Timer1 rolled over, return handle_timer_overflow
	BANKSEL PIR1
	btfsc	PIR1, TMR1IF
	goto	handle_timer_overflow

interrupt_return:
	bsf	SFLAGS,INTRET
	swapf	TMP_S, W
	movwf	STATUS
	swapf	TMP_W, F
	swapf	TMP_W, W
	retfie


; ISR Sub: handle_ra2int
; Clear INTCON, flag parity error
handle_ra2int:
	bcf	INTCON, INTF
	bsf	SFLAGS, AFEERR
	goto	interrupt_return


; ISR Sub: handle_lfdata
; Respond to AFE demodulated data on LFDATA input
handle_lfdata:
	bcf	INTCON, RAIF
	; Read PORTA to clear ioca1
	BANKSEL PORTA
	btfss	PORTA,1
	goto	clear_raif
	bsf	SFLAGS, LFDATA
clear_raif:
	; Clear RAIF in case it was set while reading PORTA
	bcf	INTCON, RAIF
	goto	interrupt_return


; ISR Sub: handle_timer_overflow
handle_timer_overflow:
	BANKSEL PIR1
	bcf	PIR1, TMR1IF
	goto	interrupt_return


; ISR Sub: reset_init
; Reset routine
reset_init:
	; Disable interrupts
	bcf	INTCON, GIE

	; Set PORTA all input
	movlw	0xff
	BANKSEL TRISA
	movwf	TRISA

	; Disable analog comparators
	movlw	0x07
	BANKSEL CMCON0
	movwf	CMCON0

	; Set PORTC outputs: C0 & C5
	movlw	0xde
	BANKSEL TRISC
	movwf	TRISC

	; Set pullups and initial outputs
	movlw	0xff
	BANKSEL PORTA
	movwf	PORTA
	movlw	0xfe
	movwf	PORTC

	; Option reg: WDT 1:1
	movlw	0x08
	BANKSEL OPTION_REG
	movwf	OPTION_REG

	; Weak pull up WDA2
	movlw	0x04
	movwf	WDA

	; Enable weak pull WDA0-2
	movlw	0x07
	movwf	WPUDA

	; Disable voltage reference
	movlw	0x00
	movwf	VRCON

	; Enable low voltage detect @ 2.3V
	bsf	LVDCON, LVDEN
	movlw	0x14
	movwf	LVDCON

	; Set Oscillator control reg: 4MHz, External clock, source FOSC2:0
	movlw	0x68
	movwf	OSCCON

	; Zero memory 0x20 -> 0x7f
	movlw	0x20
	bcf	STATUS, IRP
	movwf	FSR
zeromem:
	clrf	INDF
	incf	FSR, F
	movf	FSR, W
	sublw	0x80
	btfss	STATUS, Z
	goto	zeromem

	; Configure AFE and disable lfdata int, enable GIE, PEIE, INTE
	call	configure_afe
	nop
	nop
	call	enable_lfdata

	; Disable wakeup via wdt
	call	disable_wakeup

main_loop:
	sleep

	; Executed before branch to int handler on wakeup
	bcf	SFLAGS,INTRET

	; Check for AFE error condition
	btfsc	SFLAGS,AFEERR
	goto	reset_init

	; Update LFDATA/LED
	BANKSEL PORTC
	btfss	SFLAGS,LFDATA
	goto	led_off
	bcf	SFLAGS,LFDATA
led_on:
	bcf	PORTC,5
	call	enable_wakeup_1ms
	goto	main_loop
led_off:
	btfsc	SFLAGS,INTRET
	goto	main_loop
	bsf	PORTC,5
	call	disable_wakeup
	goto	main_loop


; FUNCTION: configure_afe
; Set AFE configuration registers, soft reset AFE, enable LFDATA ouput
configure_afe:
	; CLAMP OFF -> AFE disable talk back modulation circuit
	nop
	movlw	0x00
	BANKSEL SPI_LO
	movwf	SPI_LO
	movlw	0x20
	movwf	SPI_HI
	call	spi_send

	; AFE CR0: Output Enable Filter: OE High = 1ms, OE Low = 1ms
	;	   /ALERT bit output triggered by parity error
	;	   LCX enable
	movlw	0x06
	BANKSEL AFE_CR0
	movwf	AFE_CR0
	movlw	0x00
	call	afe_update_register
	movlw	0x56
	BANKSEL AFE_CR0
	movwf	AFE_CR0
	movlw	0x00
	call	afe_update_register

	; AFE CR1: LFDATA = Demodulated output, LCX tuning = 0pF (default)
	movlw	0x00
	BANKSEL AFE_CR1
	movwf	AFE_CR1
	movlw	0x01
	call	afe_update_register

	; AFE CR2: RSSI pull down off, Carrier Clock/1, LCY tuning = 0pF
	movlw	0x00
	BANKSEL AFE_CR2
	movwf	AFE_CR2
	movlw	0x02
	call	afe_update_register

	; AFE CR3: LCZ tuning = 0pF
	movlw	0x00
	BANKSEL AFE_CR3
	movwf	AFE_CR3
	movlw	0x03
	call	afe_update_register

	; AFE CR4: LCX sensitivity reduction = -18dB, LCY sensitivity = -0dB
	movlw	0x90
	BANKSEL AFE_CR4
	movwf	AFE_CR4
	movlw	0x04
	call	afe_update_register

	; AFE CR5: Auto channel select disabled
	;	   AGCSIG demod disabled
	;	   Minimum Modulation Depth 50%
	;	   LCZ sensitivity -0dB
	movlw	0x00
	BANKSEL AFE_CR5
	movwf	AFE_CR5
	movlw	0x05
	call	afe_update_register

	; Set column parity register
	call	afe_recompute_colparity
	movlw	0x06
	call	afe_update_register

	; AFE soft reset
	movlw	0x00
	BANKSEL SPI_LO
	movwf	SPI_LO
	movlw	0xa0
	movwf	SPI_HI
	call	spi_send

	; Configure C0 and C5 as outputs
	movlw	0xde
	BANKSEL TRISC
	movwf	TRISC

	; Enable LFDATA output by pulling /CS high. Ref: datasheet 11.32.1
	; Note: Interrupt is enabled seperately by function enable_lfdata
	BANKSEL PORTC
	bsf	PORTC, RC1
	return


; FUNCTION: enable_lfdata
; Clear pending ioca1 and enable ioca1 (LFDATA interrupt)
; Note: will enable GIE, PEIE, INTE if not already set
enable_lfdata:
	BANKSEL PORTA
	movf	PORTA, W
	bcf	INTCON, RAIF
	movlw	0x02
	BANKSEL IOCA
	movwf	IOCA
	movlw	0xd8
	movwf	INTCON
	movlw	0xd8
	movwf	INTCON
	return


; FUNCTION: enable_wakeup_1ms
; Enable ~1ms wakeup via watchdog timer
enable_wakeup_1ms
	clrwdt
	movlw	0x08
	BANKSEL	OPTION_REG
	movwf	OPTION_REG
	movlw	0x1
	BANKSEL	WDTCON
	movwf	WDTCON
	return


; FUNCTION: disable_wakeup
; Disable WDT wakeup
disable_wakeup
	BANKSEL	WDTCON
	clrf	WDTCON
	return


; FUNCTION: spi_send_recv
; Send SPI command SPI_HI:SPI_LO, read response and return via SPI_HI:SPI_LO
spi_send_recv:
	BANKSEL SPI_OPT
	bsf	SPI_OPT, 0x0
	goto	prepare_send


; FUNCTION: spi_send
; Send SPI Command SPI_HI:SPI_LO and return
spi_send:
	BANKSEL SPI_OPT
	bcf	SPI_OPT, 0x0
prepare_send:
	BANKSEL TRISC
	movf	TRISC, W
	andlw	0xf1
	movwf	TRISC
	movlw	0x10
	BANKSEL SPI_CNT
	movwf	SPI_CNT
	bcf	PORTC, RC2
	bcf	PORTC, RC1
loop_send:
	BANKSEL SPI_LO
	rlf	SPI_LO, F
	rlf	SPI_HI, F
	btfss	STATUS, C
	bcf	PORTC, RC3
	btfsc	STATUS, C
	bsf	PORTC, RC3
	bsf	PORTC, RC2
	nop
	nop
	bcf	PORTC, RC2
	decfsz	SPI_CNT, F
	goto	loop_send
	bsf	PORTC, RC1
	bsf	PORTC, RC2
	btfss	SPI_OPT, 0x0
	goto	spi_end
	BANKSEL TRISC
	bsf	TRISC, TRISC3
	movlw	0x10
	BANKSEL SPI_CNT
	movwf	SPI_CNT
	bcf	PORTC, RC2
	bcf	PORTC, RC1
loop_receive:
	bsf	PORTC, RC2
	btfss	PORTC, RC3
	bcf	STATUS, C
	btfsc	PORTC, RC3
	bsf	STATUS, C
	bcf	PORTC, RC2
	rlf	SPI_LO, F
	rlf	SPI_HI, F
	decfsz	SPI_CNT, F
	goto	loop_receive
	bsf	PORTC, RC1
	bsf	PORTC, RC2
spi_end:
	BANKSEL TRISC
	movf	TRISC, W
	iorlw	0x0e
	movwf	TRISC
	return


; FUNCTION: afe_update_register
; Copy AFE register W from AFE_CR0+W to AFE over SPI
afe_update_register:
	; tmp = W
	; Write AFE_CR0+W (AFE copy register address) to FSR
	movwf	PRT_SUM
	addlw	AFE_CR0
	movwf	FSR

	; W = tmp<<1 + 0xe0 Write Command
	rlf	PRT_SUM, W				; reg: 0x071
	addlw	0xe0

	; Arrange AFE command in 0x060:0x061:
	;  [command] [address] [data] [0]
	BANKSEL SPI_HI
	movwf	SPI_HI
	bcf	STATUS, IRP
	rlf	INDF, W
	btfss	STATUS, C
	bcf	SPI_HI, 0x0
	btfsc	STATUS, C
	bsf	SPI_HI, 0x0
	rlf	INDF, W
	movwf	SPI_LO

	; Compute parity, OR with command byte 0x061
	movf	INDF, W
	call	afe_get_row_parity
	BANKSEL SPI_LO
	iorwf	SPI_LO, F

	; Update AFE register
	call	spi_send
	retlw	0x00


; FUNCTION: afe_read_config_reg
; Read AFE register W, copy to memory AFE_CR0+W and return value in W
afe_read_config_reg:
	; Store W to tmp reg PRT_SUM
	movwf	PRT_SUM
	; Set indirect pointer to AFE_CRO+W
	addlw	AFE_CR0
	movwf	FSR
	rlf	PRT_SUM, W
	addlw	0xc0
	BANKSEL SPI_HI
	movwf	SPI_HI
	call	spi_send_recv
	BANKSEL SPI_HI
	rrf	SPI_HI, W
	rrf	SPI_LO, W
	; Store value to ram
	bcf	STATUS, IRP
	movwf	INDF
	return


; FUNCTION: afe_get_row_parity
; Return row parity bit for AFE register value (W)
afe_get_row_parity:
	; src = W
	movwf	PRT_TMP
	; tmp = 0
	movlw	0x00
	movwf	PRT_SUM
	; cnt = 8
	movlw	0x08
	movwf	PRT_CNT
count_ones:
	; If src&1  tmp++
	rrf	PRT_TMP, F
	btfsc	STATUS, C
	incf	PRT_SUM, F
	; counter-- if zero break
	decfsz	PRT_CNT, F
	goto	count_ones
	; If tmp&1 (odd), return 1 else return 0
	btfsc	PRT_SUM, 0x0
	retlw	0x00
	retlw	0x01


; FUNCTION: afe_recompute_colparity
; Compute AFE column parity on ram vars and store to AFE_PR6
afe_recompute_colparity:
	BANKSEL AFE_CR0
	movf	AFE_CR0, W
	xorwf	AFE_CR1, W
	xorwf	AFE_CR2, W
	xorwf	AFE_CR3, W
	xorwf	AFE_CR4, W
	xorwf	AFE_CR5, W
	xorlw	0xff
	movwf	AFE_PR6
	return

	end

