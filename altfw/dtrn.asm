;
; Chronelec RC transponder - Alternative Firmware
;
; DISCtrain Track Transponder
; Date: 2024-09-13
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


; ID Locations 'DISC-1.0'
	org	_IDLOC0
	dw	0x2249
	dw	0x29c3
	dw	0x16b1
	dw	0x1730


; Registers
IDBLOCK	equ	0x40		; ID Block base register
BATTLVL	equ	0x5b		; Low battery warning register
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
LF_CNT	equ	0x77		; Count of continuous LF triggers
TMR_DC	equ	0x78		; Timer delay counter
TMR_DL	equ	0x79		; Timer delay low bits
TMR_DH	equ	0x7a		; Timer delay high bits
LFSR_R	equ	0x7b		; LFSR shift register
TX_CNT	equ	0x7c		; Transmit counter
SFLAGS	equ	0x7d		; Runtime flags
AFEERR	equ	0x1		; AFE Parity error flag
LFDATA	equ	0x2		; LFDATA activity flag
TXACT	equ	0x4		; Transmit timer active
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
	BANKSEL PORTA
	movf	PORTA, W
	bsf	SFLAGS, LFDATA

	; Clear RAIF in case it was set while reading PORTA
	bcf	INTCON, RAIF
	goto	interrupt_return


; ISR Sub: handle_timer_overflow
handle_timer_overflow:
	; Wait for LVD reference to stabilise, and clear flag
	BANKSEL LVDCON
wait_for_lvd:
	btfss	LVDCON,IRVST
	goto	wait_for_lvd

	; Clear LVD flag
	BANKSEL PIR1
	bcf	PIR1,LVDIF

	; Wait for external oscillator in case still waking up
	BANKSEL OSCCON
wait_for_osc:
	btfss	OSCCON, OSTS
	goto	wait_for_osc

	; LED OFF
	BANKSEL	PORTC
	bsf	PORTC, 5

	; Transmit ID if LF_CNT < 32
	movlw	0x20
	subwf	LF_CNT, W
	btfss	STATUS, Z
	call	transmit_id
	incf	TX_CNT, F

	; Check for new activation
	btfss	SFLAGS, LFDATA
	goto	check_tx_finish
	bcf	SFLAGS, LFDATA

	; If There's been a pause >~16 beacons, reset LF_CNT
	movf	TX_CNT, W
	sublw	0x10
	btfss	STATUS, C
	clrf	LF_CNT
	clrf	TX_CNT
	incf	LF_CNT, F
	movlw	0x21
	subwf	LF_CNT, W
	btfss	STATUS, Z
	goto	check_tx_finish
saturate_lf_cnt:
	movlw	0x20
	movwf	LF_CNT


check_tx_finish:
	; Send up to 80 beacons after activation ends
	movlw	0x50
	subwf	TX_CNT, W
	btfss	STATUS, Z
	goto	transmit_reschedule

transmission_end:
	; Flag transmission end and disable timer
	clrf	LF_CNT
	bcf	SFLAGS, TXACT
	call	disable_timer
	goto	timer_end

transmit_reschedule:
	; Schedule next timer with LFSR delay time ~3-10ms
	call	update_lfsr
	call	update_timer

	; LED ON
	BANKSEL	PORTC
	bcf	PORTC, 5

timer_end:
	; Clear timer flag and return
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

	; Set PORTC outputs: C0 & C5
	movlw	0xde
	movwf	TRISC

	; Set pullups and initial outputs
	movlw	0xff
	BANKSEL PORTA
	movwf	PORTA
	movlw	0xfe
	movwf	PORTC

	; Disable analog comparators
	movlw	0x07
	movwf	CMCON0

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

	; Clamp voltage reference to VSS
	movlw	0x20
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

	; Configure AFE
	call	configure_afe

	; Prepare for sleep
	call	init_lfsr
	call	disable_wakeup
	call	disable_timer
	call	enable_lfdata

main_loop:
	sleep
	nop

	; Check for AFE error condition
	btfsc	SFLAGS, AFEERR
	goto	reset_init

	; If LFDATA set, intiate transmit
	btfss	SFLAGS, LFDATA
	goto	main_loop

	; Skip to transfer is already in progress
	btfsc	SFLAGS, TXACT
	goto	wait_for_transfer

	; LED ON
	BANKSEL	PORTC
	bcf	PORTC, 5

	bsf	SFLAGS, TXACT
	call	enable_timer
	call	update_lfsr
	call	update_timer
wait_for_transfer:
	btfsc	SFLAGS, TXACT
	goto	wait_for_transfer

	; LED OFF
	BANKSEL	PORTC
	bsf	PORTC, 5
	goto	main_loop


; FUNCTION: transmit_id
; Copy ID block into ram registers, then transmit by gating CCLK via C0
transmit_id:
	BANKSEL	IDBLOCK
	movlw	0x0f
	movwf	0x42
	movlw	0xff
	movwf	0x41
	movlw	0xff
	movwf	0x40
	movlw	0x00
	movwf	0x43
	movlw	0x00
	movwf	0x44
	movlw	0x00
	movwf	0x45
	movlw	0x00
	movwf	0x46
	movlw	0x00
	movwf	0x47
	movlw	0x00
	movwf	0x48
	movlw	0x00
	movwf	0x49
	movlw	0x00
	movwf	0x4a
	movlw	0x00
	movwf	0x4b
	movlw	0x00
	movwf	0x4c
	movlw	0x00
	movwf	0x4d
	movlw	0x00
	movwf	0x4e
	movlw	0x00
	movwf	0x4f
	movlw	0x00
	movwf	0x50
	movlw	0x00
	movwf	0x51
	movlw	0x00
	movwf	0x52
	movlw	0x00
	movwf	0x53
	movlw	0x00
	movwf	0x54
	movlw	0x00
	movwf	0x55
	movlw	0x00
	movwf	0x56
	movlw	0x00
	movwf	0x57
	movlw	0x00
	movwf	0x58
	movlw	0x00
	movwf	0x59
	movlw	0x00
	movwf	0x5a
	movlw	0x00
	movwf	BATTLVL
	movlw	0x00
	movwf	0x5c

	; Update battery flag if low voltage detected
	btfss	PIR1, LVDIF
	goto	start_tx
	movlw	0x05
	movwf	BATTLVL

start_tx:
	; Toggle Port C with delay times encoded above in ID block
	movf	0x43, W
	btfsc	STATUS, Z
	goto	tx_preamble
	nop
	bsf	PORTC, 0
	nop
pre_sym:
	decfsz	0x43, F
	goto	pre_sym
	bcf	PORTC, 0
	nop
	nop
tx_preamble:
	nop
	bsf	PORTC, 0
	nop
tx_sym_00:
	decfsz	0x44, F
	goto	tx_sym_00
	bcf	PORTC, 0
	nop
	nop
	bsf	PORTC, 0
	nop
tx_sym_01:
	decfsz	0x45, F
	goto	tx_sym_01
	bcf	PORTC, 0
	nop
	nop
	bsf	PORTC, 0
	nop
tx_sym_02:
	decfsz	0x46, F
	goto	tx_sym_02
	bcf	PORTC, 0
	nop
	nop
	bsf	PORTC, 0
	nop
tx_sym_03:
	decfsz	0x47, F
	goto	tx_sym_03
	bcf	PORTC, 0
	nop
	nop
	bsf	PORTC, 0
	nop
tx_sym_04:
	decfsz	0x48, F
	goto	tx_sym_04
	bcf	PORTC, 0
	nop
	nop
	bsf	PORTC, 0
	nop
tx_sym_05:
	decfsz	0x49, F
	goto	tx_sym_05
	bcf	PORTC, 0
	nop
	nop
	bsf	PORTC, 0
	nop
tx_sym_06:
	decfsz	0x4a, F
	goto	tx_sym_06
	bcf	PORTC, 0
	nop
	nop
	bsf	PORTC, 0
	nop
tx_sym_07:
	decfsz	0x4b, F
	goto	tx_sym_07
	bcf	PORTC, 0
	nop
	nop
	bsf	PORTC, 0
	nop
tx_sym_08:
	decfsz	0x4c, F
	goto	tx_sym_08
	bcf	PORTC, 0
	nop
	nop
	bsf	PORTC, 0
	nop
tx_sym_09:
	decfsz	0x4d, F
	goto	tx_sym_09
	bcf	PORTC, 0
	nop
	nop
	bsf	PORTC, 0
	nop
tx_sym_10:
	decfsz	0x4e, F
	goto	tx_sym_10
	bcf	PORTC, 0
	nop
	nop
	bsf	PORTC, 0
	nop
tx_sym_11:
	decfsz	0x4f, F
	goto	tx_sym_11
	bcf	PORTC, 0
	nop
	nop
	bsf	PORTC, 0
	nop
tx_sym_12:
	decfsz	0x50, F
	goto	tx_sym_12
	bcf	PORTC, 0
	nop
	nop
	bsf	PORTC, 0
	nop
tx_sym_13:
	decfsz	0x51, F
	goto	tx_sym_13
	bcf	PORTC, 0
	nop
	nop
	bsf	PORTC, 0
	nop
tx_sym_14:
	decfsz	0x52, F
	goto	tx_sym_14
	bcf	PORTC, 0
	nop
	nop
	bsf	PORTC, 0
	nop
tx_sym_15:
	decfsz	0x53, F
	goto	tx_sym_15
	bcf	PORTC, 0
	nop
	nop
	bsf	PORTC, 0
	nop
tx_sym_16:
	decfsz	0x54, F
	goto	tx_sym_16
	bcf	PORTC, 0
	nop
	nop
	bsf	PORTC, 0
	nop
tx_sym_17:
	decfsz	0x55, F
	goto	tx_sym_17
	bcf	PORTC, 0
	nop
	nop
	bsf	PORTC, 0
	nop
tx_sym_18:
	decfsz	0x56, F
	goto	tx_sym_18
	bcf	PORTC, 0
	nop
	nop
	bsf	PORTC, 0
	nop
tx_sym_19:
	decfsz	0x57, F
	goto	tx_sym_19
	bcf	PORTC, 0
	nop
	nop
	bsf	PORTC, 0
	nop
tx_sym_20:
	decfsz	0x58, F
	goto	tx_sym_20
	bcf	PORTC, 0
	nop
	nop
	bsf	PORTC, 0
	nop
tx_sym_21:
	decfsz	0x59, F
	goto	tx_sym_21
	bcf	PORTC, 0
	nop
	nop
	bsf	PORTC, 0
	nop
tx_sym_22:
	decfsz	0x5a, F
	goto	tx_sym_22
	bcf	PORTC, 0
	nop
	nop
	bsf	PORTC, 0
	nop
tx_sym_23:
	decfsz	0x5b, F
	goto	tx_sym_23
	bcf	PORTC, 0
	nop
	nop
	bsf	PORTC, 0
	nop
tx_sym_24:
	decfsz	0x5c, F
	goto	tx_sym_24
	bcf	PORTC, 0

	return


; FUNCTION: init_lfsr
; Initialise LFSR Register and then update
init_lfsr:
	movlw	0x01
	movwf	LFSR_R


; FUNCTION: update_lfsr
; Updte LFSR and return next value in W
update_lfsr:
	bcf	STATUS, C
	rrf	LFSR_R, F
	btfss	STATUS, C
	goto	lfsr_return
	movlw	0xfa
	xorwf	LFSR_R, F
lfsr_return:
	movf	LFSR_R, W
	return


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


; FUNCTION: disable_lfdata
; Disable ioca1 (LFDATA interrupt) and clear any pending ioca
; Note: will enable GIE, PEIE, INTE if not already set
disable_lfdata:
	movlw	0x00
	BANKSEL	IOCA
	movwf	IOCA
	movlw	0xd0
	movwf	INTCON
	movlw	0xd0
	movwf	INTCON
	BANKSEL	PORTA
	movf	PORTA, W
	bcf	INTCON, RAIF
	return


; FUNCTION: update_timer
; Set TMR1 for a delay of (W&0x7)+3 ms
update_timer:
	andlw	0x7
	addlw	0x3
	movwf	TMR_DC
	movlw	0xff
	movwf	TMR_DH
	movwf	TMR_DL

subtract_1ms:
	movlw	0x66
	subwf	TMR_DL, F
	btfss	STATUS, C
	decf	TMR_DH, F
	decfsz	TMR_DC, F
	goto	subtract_1ms

	BANKSEL	TMR1H
	movf	TMR_DH, W
	movwf	TMR1H
	movf	TMR_DL, W
	movwf	TMR1L
	return


; FUNCTION: enable_timer
; Enable Timer1 and interrupt
enable_timer:
	BANKSEL	TMR1L
	clrf	TMR1L
	clrf	TMR1H
	movlw	0x31
	movwf	T1CON
	BANKSEL	PIE1
	bsf	PIE1, TMR1IE
	return


; FUNCTION: disable_timer
; Disable Timer1 and interrupt
disable_timer:
	BANKSEL	T1CON
	bcf	T1CON, TMR1ON
	clrf	TMR1L
	clrf	TMR1H
	BANKSEL	PIE1
	bcf	PIE1, TMR1IE
	return


; FUNCTION: enable_wakeup_1s
; Enable ~1s wakeup via watchdog timer
enable_wakeup_1s
	clrwdt
	; WDT Prescale: 1:64
	movlw	0xe
	BANKSEL	OPTION_REG
	movwf	OPTION_REG
	; WDT On, period = 1:512 (~16ms)
	movlw	0x9
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

