;
;==================================================================================================
;   IDE DISK DRIVER
;==================================================================================================
;
#IF (IDETRACE >= 2)
#DEFINE		DCALL	CALL
#ELSE
#DEFINE		DCALL	\;
#ENDIF
;
; IO PORT ADDRESSES
;
#IF (IDEMODE == IDEMODE_MK4)
IDEBASE		.EQU	MK4_IDE
#ELSE
IDEBASE		.EQU	$20
#ENDIF

#IF ((IDEMODE == IDEMODE_DIO) | (IDEMODE == IDEMODE_MK4))
#IF (IDE8BIT)
IDEDATA		.EQU 	$IDEBASE + $00	; DATA PORT (8 BIT)
#ELSE
IDEDATALO	.EQU 	$IDEBASE + $00	; DATA PORT (16 BIT LO BYTE)
IDEDATAHI	.EQU 	$IDEBASE + $08	; DATA PORT (16 BIT HI BYTE)
IDEDATA		.EQU	IDEDATALO
#ENDIF
#ENDIF
;
#IF (IDEMODE == IDEMODE_DIDE)
#IF (IDE8BIT)
IDEDATA		.EQU 	$IDEBASE + $00	; DATA PORT (8 BIT OR 16 BIT PIO LO/HI BYTES)
#ELSE
IDEDATA		.EQU 	$IDEBASE + $08	; DATA PORT (16 BIT PIO LO/HI BYTES)
IDEDMA		.EQU 	$IDEBASE + $09	; DATA PORT (16 BIT DMA LO/HI BYTES)
#ENDIF
#ENDIF
;
IDEERR		.EQU 	$IDEBASE + $01	; READ: ERROR REGISTER; WRITE: PRECOMP
IDESECTC	.EQU 	$IDEBASE + $02	; SECTOR COUNT
IDESECTN	.EQU 	$IDEBASE + $03	; SECTOR NUMBER
IDECYLLO	.EQU 	$IDEBASE + $04	; CYLINDER LOW
IDECYLHI	.EQU 	$IDEBASE + $05	; CYLINDER HIGH
IDEDEVICE	.EQU 	$IDEBASE + $06	; DRIVE/HEAD
IDESTTS		.EQU 	$IDEBASE + $07	; READ: STATUS; WRITE: COMMAND
IDECTRL		.EQU 	$IDEBASE + $0E	; READ: ALTERNATIVE STATUS; WRITE; DEVICE CONTROL
IDEADDR		.EQU 	$IDEBASE + $0F	; DRIVE ADDRESS (READ ONLY)
;
;
;
IDECMD_RECAL	.EQU	$10
IDECMD_READ	.EQU	$20
IDECMD_WRITE	.EQU	$30
IDECMD_IDDEV	.EQU	$EC
IDECMD_SETFEAT	.EQU	$EF
;
IDE_RCOK	.EQU	0
IDE_RCCMDERR	.EQU	1
IDE_RCRDYTO	.EQU	2
IDE_RCBUFTO	.EQU	3
IDE_RCBSYTO	.EQU	4
;
; UNIT CONFIGURATION
;
IDE_DEVICES:
IDE_DEVICE0	.DB	%11100000	; LBA, MASTER DEVICE
IDE_DEVICE1	.DB	%11110000	; LBA, SLAVE DEVICE
;
;
;
IDE_INIT:
	PRTS("IDE:$")			; LABEL FOR IO ADDRESS
;
#IF (IDEMODE == IDEMODE_DIO)
	PRTS(" MODE=DIO$")
#ENDIF
#IF (IDEMODE == IDEMODE_DIDE)
	PRTS(" MODE=DIDE$")
#ENDIF
#IF (IDEMODE == IDEMODE_MK4)
	PRTS(" MODE=MK4$")
#ENDIF
	; PRINT IDE INTERFACE PORT ADDRESS
	PRTS(" IO=0x$")		; LABEL FOR IO ADDRESS
	LD	A,IDEDATA		; GET IO ADDRESS
	CALL	PRTHEXBYTE		; PRINT IT
;
	; RESET INTERFACE
	CALL	IDE_RESET		; INTERFACE RESET
	CALL	DELAY			; SMALL DELAY
;
	; SET GLOBAL STATUS TO OK (ZERO)
	XOR	A			; STATUS OK
	LD	(IDE_STAT),A		; INITIALIZE IT
;
	; PROBE FOR DEVICE(S)
	LD	A,(IDE_DEVICE0)		; DEVICE 0
	DCALL	PC_SPACE		; IF DEBUGGING, PRINT A SPACE
	DCALL	PC_LBKT			; IF DEBUGGING, PRINT LEFT BRACKET
	CALL	IDE_PROBE		; PROBE FOR DEVICE 0 PRESENCE
	DCALL	PC_RBKT			; IF DEBUGGING, PRINT A RIGHT BRACKET
	JR	NZ,IDE_INIT1		; IF DEVCIE 0 NOT PRESENT, SKIP DEVICE 1 PROBE
	LD	HL,IDE_UNITCNT		; POINT TO UNIT COUNT
	INC	(HL)			; INCREMENT IT
	LD	A,(IDE_DEVICE1)		; DEVICE 1
	DCALL	PC_SPACE		; IF DEBUGGING, PRINT A SPACE
	DCALL	PC_LBKT			; IF DEBUGGING, PRINT A LEFT BRACKET
	CALL	IDE_PROBE		; PROBE FOR DEVICE 1 PRESENT
	DCALL	PC_RBKT			; IF DEBUGGING, PRINT A RIGHT BRACKET
	JR	NZ,IDE_INIT1		; IF DEVICE 1 NOT PRESENT, SKIP
	LD	HL,IDE_UNITCNT		; POINT TO UNIT COUNT
	INC	(HL)			; INCREMENT IT
;
IDE_INIT1:
	; RESTORE DEFAULT DEVICE SELECTION (DEVICE 0)
	LD	A,(IDE_DEVICE0)		; DEVICE 0
	OUT	(IDEDEVICE),A		; SELECT IT
	CALL	DELAY			; SMALL DELAY AFTER SELECT
;
	; PRINT UNIT COUNT
	PRTS(" UNITS=$")		; PRINT LABEL FOR UNIT COUNT
	LD	A,(IDE_UNITCNT)		; GET UNIT COUNT
	CALL	PRTDECB			; PRINT IT IN DECIMAL
;
	; CHECK FOR ZERO DEVICES AND BAIL OUT IF SO
	LD	A,(IDE_UNITCNT)		; GET UNIT COUNT
	OR	A			; SET FLAGS
	RET	Z			; IF ZERO, WE ARE DONE
;
	; DEVICE SETUP LOOP
	LD	B,A			; LOOP ONCE PER UNIT
	LD	C,0			; C IS UNIT INDEX
IDE_INIT2:
	PUSH	BC			; SAVE LOOP CONTROL
	CALL	IDE_INIT3		; HANDLE THE NEXT UNIT
	POP	BC			; RESTORE LOOP CONTROL
	INC	C			; INCREMENT UNIT INDEX
	DJNZ	IDE_INIT2		; LOOP UNTIL DONE
	RET				; INIT FINISHED
;
IDE_INIT3:	; SUBROUTINE TO QUERY A DEVICE

	; PRINT PREFIX FOR UNIT INFO "IDE#:"
	CALL	NEWLINE			; FORMATTING: START A NEW LINE
	LD	DE,IDESTR_PREFIX	; POINT TO STRING "IDE"
	CALL	WRITESTR		; PRINT STRING
	LD	A,C			; UNIT NUMBER TO ACCUM
	LD	(IDE_CURUNIT),A		; SAVE THE CURRENT UNIT
	CALL	PRTDECB			; PRINT IT IN DECIMAL
	CALL	PC_COLON		; PRINT THE ENDING COLON
;	
	LD	A,C			; UNIT NUMBER TO ACCUM
	CALL	IDE_SELECT		; SELECT THE CORRECT DEVICE
;
#IF (IDE8BIT)
	PRTS(" 8BIT$")
	CALL	IDE_SET8BIT		; SET 8BIT TRANSFER FEATURE
	RET	NZ			; BAIL OUT ON ERROR
#ENDIF
;
	CALL	IDE_IDENTIFY		; EXECUTE IDENTIFY COMMAND
	RET	NZ			; BAIL OUT ON ERROR
;
	LD	DE,(DIOBUF)		; POINT TO BUFFER
	DCALL	DUMP_BUFFER		; DUMP IT IF DEBUGGING
;
	; PRINT LBA/NOLBA
	CALL	PC_SPACE		; SPACING
	LD	HL,(DIOBUF)		; POINT TO BUFFER START
	LD	DE,98+1			; OFFSET OF BYTE CONTAINING LBA FLAG
	ADD	HL,DE			; POINT TO FINAL BUFFER ADDRESS
	LD	A,(HL)			; GET THE BYTE
	BIT	1,A			; CHECK THE LBA BIT
	LD	DE,IDESTR_NO		; POINT TO "NO" STRING
	CALL	Z,WRITESTR		; PRINT "NO" BEFORE "LBA" IF LBA NOT SUPPORTED
	PRTS("LBA$")			; PRINT "LBA" REGARDLESS
;
	; PRECOMPUTE LOC TO STORE 32-BIT CAPACITY
	LD	HL,IDE_CAPLIST		; POINT TO CAPACITY ARRAY
	LD	A,(IDE_CURUNIT)		; GET CUR UNIT NUM
	RLCA				; MULTIPLY BY 4
	RLCA				; ... TO OFFSET BY DWORDS
	CALL	ADDHLA			; ADD OFFSET TO POINTER
	PUSH	HL			; SAVE POINTER
;
	; GET, SAVE, AND PRINT STORAGE CAPACITY (BLOCK COUNT)
	PRTS(" BLOCKS=0x$")		; PRINT FIELD LABEL
	LD	HL,(DIOBUF)		; POINT TO BUFFER START
	LD	DE,120			; OFFSET OF SECGTOR COUNT
	ADD	HL,DE			; POINT TO ADDRESS OF SECTOR COUNT
	CALL	LD32			; LOAD IT TO DE:HL
	POP	BC			; RECOVER POINTER TO CAPACITY ARRAY ENTRY
	CALL	ST32			; SAVE CAPACITY
	CALL	PRTHEX32		; PRINT HEX VALUE
;
	; PRINT STORAGE SIZE IN MB
	PRTS(" SIZE=$")			; PRINT FIELD LABEL
	LD	B,11			; 11 BIT SHIFT TO CONVERT BLOCKS --> MB
	CALL	SRL32			; RIGHT SHIFT
	CALL	PRTDEC			; PRINT LOW WORD IN DECIMAL (HIGH WORD DISCARDED)
	PRTS("MB$")			; PRINT SUFFIX
;
	RET
;
;
;
IDE_DISPATCH:
	LD	A,B		; GET REQUESTED FUNCTION
	AND	$0F
	JR	Z,IDE_READ
	DEC	A
	JR	Z,IDE_WRITE
	DEC	A
	JR	Z,IDE_STATUS
	DEC	A
	JR	Z,IDE_MEDIA
	CALL	PANIC
;
;
;
IDE_READ:
	LD	A,IDECMD_READ
	LD	(IDE_CMD),A
	CALL	IDE_RW
	RET	NZ
	CALL	IDE_BUFRD
	RET
;
;
;
IDE_WRITE:
	LD	A,IDECMD_WRITE
	LD	(IDE_CMD),A
	CALL	IDE_RW
	RET	NZ
	CALL	IDE_BUFWR
	RET
;
;
;
IDE_STATUS:
	LD	A,(IDE_STAT)	; LOAD STATUS
	OR	A		; SET FLAGS
	RET
;
; IDE_MEDIA
;
IDE_MEDIA:
	LD	A,C		; GET THE DEVICE/UNIT
	AND	$0F		; ISOLATE UNIT
	LD	HL,IDE_UNITCNT	; POINT TO UNIT COUNT
	CP	(HL)		; COMPARE TO UNIT COUNT
	LD	A,MID_HD	; ASSUME WE ARE OK
	RET	C		; RETURN
	XOR	A		; NO MEDIA
	RET			; AND RETURN
;
;
;
IDE_RW:
	; SELECT DEVICE
	LD	A,(HSTDSK)		; HSTDSK -> HEAD BIT 4 TO SELECT UNIT
	AND	$0F
	CALL	IDE_SELECT
	CALL	IDE_SETUP		; SETUP CYL, TRK, HEAD
	JR	IDE_RUNCMD		; RETURN THRU RUNCMD
;
;
;
IDE_RUNCMD:
	; CLEAR RESULTS
	XOR	A			; A = 0
	LD	(IDE_STAT),A		; CLEAR DRIVER STATUS CODE
	LD	(IDE_STTS),A		; CLEAR SAVED STTS
	LD	(IDE_ERRS),A		; CLEAR SAVED ERR
	CALL	IDE_WAITRDY		; WAIT FOR DRIVE READY
	RET	NZ			; BAIL OUT ON TIMEOUT
	LD	A,(IDE_CMD)		; GET THE COMMAND
	OUT	(IDESTTS),A		; SEND IT (STARTS EXECUTION)
	CALL	IDE_WAITRDY		; WAIT FOR DRIVE READY (COMMAND DONE)
	RET	NZ			; BAIL OUT ON TIMEOUT
	CALL	IDE_CHKERR		; CHECK FOR ERRORS
	RET	NZ			; BAIL OUT ON TIMEOUT
	DCALL	IDE_PRT			; PRINT COMMAND IF DEBUG ENABLED
	XOR	A			; SET RESULT
	RET				; DONE
;
;
;
IDE_ERRCMD:
	LD	A,IDE_RCCMDERR
	JR	IDE_ERR
;
IDE_ERRRDYTO:
	LD	A,IDE_RCRDYTO
	JR	IDE_ERR
;
IDE_ERRBUFTO:
	LD	A,IDE_RCBUFTO
	JR	IDE_ERR
;
IDE_ERRBSYTO:
	LD	A,IDE_RCBSYTO
	JR	IDE_ERR
;
IDE_ERR:
	LD	(IDE_STAT),A		; SAVE ERROR AS STATUS
#IF (IDETRACE >= 1)
	PUSH	AF			; SAVE ACCUM
	CALL	IDE_PRT			; PRINT COMMAND SUMMARY
	POP	AF			; RESTORE ACCUM
#ENDIF
	OR	A			; MAKE SURE FLAGS ARE SET
	RET				; DONE
;
; SOFT RESET OF ALL DEVICES
;
IDE_RESET:
	LD	A,%00001110		; NO INTERRUPTS, ASSERT RESET BOTH DRIVES
	OUT	(IDECTRL),A
	LD	DE,16			; DELAY ~250US
	CALL	VDELAY
	LD	A,%00001010		; NO INTERRUPTS, DEASSERT RESET
	OUT	(IDECTRL),A
	XOR	A
	LD	(IDE_STAT),A		; STATUS OK
	RET				; SAVE IT
;
; SELECT DEVICE IN A
;
IDE_SELECT:
	LD	HL,IDE_DEVICES
	CALL	ADDHLA
	LD	A,(HL)			; LOAD DEVICE
	LD	(IDE_DEVICE),A		; SHADOW REGISTER

	CALL	IDE_WAITBSY
	RET	NZ

	LD	A,(IDE_DEVICE)		; RECOVER DEVICE VALUE
	OUT	(IDEDEVICE),A		; SELECT DEVICE
	; DELAY???
	RET
;
;
;
IDE_PROBE:
	OUT	(IDEDEVICE),A	; SELECT IT
	CALL	DELAY
	IN	A,(IDESECTC)
	DCALL	PRTHEXBYTE
	CP	$01
	RET	NZ
	DCALL	PC_SPACE
	IN	A,(IDESECTN)
	DCALL	PRTHEXBYTE
	CP	$01
	RET	NZ
	DCALL	PC_SPACE
	IN	A,(IDECYLLO)
	DCALL	PRTHEXBYTE
	CP	$00
	RET	NZ
	DCALL	PC_SPACE
	IN	A,(IDECYLHI)
	DCALL	PRTHEXBYTE
	CP	$00
	RET	NZ
	DCALL	PC_SPACE
	IN	A,(IDESTTS)
	DCALL	PRTHEXBYTE		; PRINT STATUS
	CP	0
	JR	NZ,IDE_PROBE1
	OR	$FF			; SIGNAL ERROR
	RET
	
IDE_PROBE1:
	XOR	A			; SIGNAL SUCCESS
	RET
;
;
;	
IDE_SET8BIT:
	; DEVICE *MUST* ALREADY BE SELECTED!
	LD	A,IDECMD_SETFEAT
	LD	(IDE_CMD),A
	LD	A,$01			; $01 ENABLES 8-BIT XFR FEATURE
	OUT	(IDEERR),A		; SET FEATURS VALUE
	JP	IDE_RUNCMD		; EXIT THRU RUNCMD
;
;
;
IDE_IDENTIFY:
	; DEVICE *MUST* ALREADY BE SELECTED!
	LD	A,IDECMD_IDDEV
	LD	(IDE_CMD),A
	CALL	IDE_RUNCMD
	RET	NZ
	JP	IDE_BUFRD		; EXIT THRU BUFRD
;
;
;
IDE_WAITRDY:
	LD	B,15			; ~15 SECOND TIMEOUT?
IDE_WAITRDY1:
	LD	DE,-1			; ~1 SECOND INNER LOOP
IDE_WAITRDY2:
	IN	A,(IDESTTS)		; READ STATUS
	LD	(IDE_STTS),A		; SAVE IT
	AND	%11000000		; ISOLATE BUSY AND RDY BITS
	XOR	%01000000		; WE WANT BUSY(7) TO BE 0 AND RDY(6) TO BE 1
	;JR	Z,IDE_WAITRPT		; DIAGNOSTIC
	RET	Z			; ALL SET, RETURN WITH Z SET
	CALL	DELAY			; DELAY 16US
	DEC	DE
	LD	A,D
	OR	E
	JR	NZ,IDE_WAITRDY2		; INNER LOOP RETURN
	DJNZ	IDE_WAITRDY1		; OUTER LOOP RETURN
	JP	IDE_ERRRDYTO		; EXIT WITH RDYTO ERR
;
;
;
IDE_WAITBUF:
	LD	B,3			; ~3 SECOND TIMEOUT???
IDE_WAITBUF1:
	LD	DE,-1			; ~1 SECOND INNER LOOP
IDE_WAITBUF2:
	IN	A,(IDESTTS)		; WAIT FOR DRIVE'S 512 BYTE READ BUFFER
	LD	(IDE_STTS),A		; SAVE IT
	AND	%10001000		; TO FILL (OR READY TO FILL)
	XOR	%00001000
	;JR	Z,IDE_WAITRPT		; DIAGNOSTIC
	RET	Z
	CALL	DELAY			; DELAY 16US
	DEC	DE
	LD	A,D
	OR	E
	JR	NZ,IDE_WAITBUF2
	DJNZ	IDE_WAITBUF1
	JP	IDE_ERRBUFTO		; EXIT WITH BUFTO ERR
;
;
;
IDE_WAITBSY:
	LD	B,3			; ~3 SECOND TIMEOUT???
IDE_WAITBSY1:
	LD	DE,-1			; ~1 SECOND INNER LOOP
IDE_WAITBSY2:
	IN	A,(IDESTTS)		; WAIT FOR DRIVE'S 512 BYTE READ BUFFER
	LD	(IDE_STTS),A		; SAVE IT
	AND	%10000000		; TO FILL (OR READY TO FILL)
	;JR	Z,IDE_WAITRPT		; DIAGNOSTIC
	RET	Z
	CALL	DELAY			; DELAY 16US
	DEC	DE
	LD	A,D
	OR	E
	JR	NZ,IDE_WAITBSY2
	DJNZ	IDE_WAITBSY1
	JP	IDE_ERRBSYTO		; EXIT WITH BSYTO ERR
;
;
;
IDE_WAITRPT:
	PUSH	AF
	CALL	PC_SPACE
	LD	A,B
	CALL	PRTHEXBYTE
	LD	A,D
	CALL	PRTHEXBYTE
	LD	A,E
	CALL	PRTHEXBYTE
	POP	AF
	RET
;
;
;
IDE_CHKERR:
	IN	A,(IDESTTS)		; GET STATUS
	LD	(IDE_STTS),A		; SAVE IT
	AND	%00000001		; ERROR BIT SET?
	RET	Z			; NOPE, RETURN WITH ZF
;
	IN	A,(IDEERR)		; READ ERROR REGISTER
	LD	(IDE_ERRS),A		; SAVE IT
	JP	IDE_ERRCMD		; EXIT VIA ERRCMD
;
;
;
IDE_BUFRD:
	CALL	IDE_WAITBUF		; WAIT FOR BUFFER READY
	RET	NZ			; BAIL OUT IF TIMEOUT

	LD	HL,(DIOBUF)
	LD	B,0

#IF (IDE8BIT | (IDEMODE == IDEMODE_DIDE))
	LD	C,IDEDATA
	INIR
	INIR
#ELSE
	LD	C,IDEDATAHI
IDE_BUFRD1:
	IN	A,(IDEDATALO)		; READ THE LO BYTE
	LD	(HL),A			; SAVE IN BUFFER
	INC	HL			; INC BUFFER POINTER
	INI				; READ AND SAVE HI BYTE, INC HL, DEC B
	JP	NZ,IDE_BUFRD1		; LOOP AS NEEDED
#ENDIF
	JP	IDE_CHKERR		; RETURN THRU CHKERR
;
;
;
IDE_BUFWR:
	CALL	IDE_WAITBUF		; WAIT FOR BUFFER READY
	RET	NZ			; BAIL OUT IF TIMEOUT

	LD	HL,(DIOBUF)
	LD	B,0

#IF (IDE8BIT | (IDEMODE == IDEMODE_DIDE))
	LD	C,IDEDATA
	OTIR
	OTIR
#ELSE
	LD	C,IDEDATAHI
IDE_BUFWR1:
	LD	A,(HL)			; GET THE LO BYTE AND KEEP IT IN A FOR LATER
	INC	HL			; BUMP TO NEXT BYTE IN BUFFER
	OUTI				; WRITE HI BYTE, INC HL, DEC B
	OUT	(IDEDATALO),A		; NOW WRITE THE SAVED LO BYTE TO LO BYTE
	JP	NZ,IDE_BUFWR1		; LOOP AS NEEDED
#ENDIF
	JP	IDE_CHKERR		; RETURN THRU CHKERR
;
;
;
IDE_SETUP:
	LD	A,1
	OUT	(IDESECTC),A
	
	; SEND 3 BYTES OF LBA T:SS -> CYL:SEC (CC:S)
	LD	A,(HSTLBAHI)		; LBA HIGH LSB
	LD	(IDE_CYLHI),A		;   SAVE IT
	OUT	(IDECYLHI),A		;   -> CYLINDER HI
	LD	A,(HSTLBALO + 1)	; LBA LOW MSB
	LD	(IDE_CYLLO),A		;   SAVE IT
	OUT	(IDECYLLO),A		;   -> CYLINDER LO
	LD	A,(HSTLBALO)		; LBA LOW LSB
	LD	(IDE_SEC),A		;   SAVE IT
	OUT	(IDESECTN),A		;   -> SECTOR NUM
#IF (DSKYENABLE)
	CALL	IDE_DSKY
#ENDIF
	RET
;
;
;
#IF (DSKYENABLE)
IDE_DSKY:
	LD	HL,DSKY_HEXBUF
	LD	A,(IDE_DEVICE)
	LD	(HL),A
	INC	HL
	LD	A,(IDE_CYLHI)
	LD	(HL),A
	INC	HL
	LD	A,(IDE_CYLLO)
	LD	(HL),A
	INC	HL
	LD	A,(IDE_SEC)
	LD	(HL),A
	CALL	DSKY_HEXOUT
	RET
#ENDIF
;
;
;
IDE_PRT:
	CALL	NEWLINE

	LD	DE,IDESTR_PREFIX	
	CALL	WRITESTR
	CALL	PC_COLON
	
	CALL	PC_SPACE
	LD	DE,IDESTR_CMD
	CALL	WRITESTR
	LD	A,(IDE_CMD)
	CALL	PRTHEXBYTE

	CALL	PC_SPACE
	CALL	PC_LBKT
	LD	A,(IDE_CMD)
	LD	DE,IDESTR_READ
	CP	IDECMD_READ
	JP	Z,IDE_PRTCMD
	LD	DE,IDESTR_WRITE
	CP	IDECMD_WRITE
	JP	Z,IDE_PRTCMD
	LD	DE,IDESTR_SETFEAT
	CP	IDECMD_SETFEAT
	JP	Z,IDE_PRTCMD
	LD	DE,IDESTR_IDDEV
	CP	IDECMD_IDDEV
	JP	Z,IDE_PRTCMD
	LD	DE,IDESTR_RECAL
	CP	IDECMD_RECAL
	JP	Z,IDE_PRTCMD
	LD	DE,IDESTR_UNKCMD
IDE_PRTCMD:	
	CALL	WRITESTR
	CALL	PC_RBKT

	CALL	PC_SPACE
	LD	A,(IDE_DEVICE)
	CALL	PRTHEXBYTE
	LD	A,(IDE_CYLHI)
	CALL	PRTHEXBYTE
	LD	A,(IDE_CYLLO)
	CALL	PRTHEXBYTE
	LD	A,(IDE_SEC)
	CALL	PRTHEXBYTE

	CALL	PC_SPACE
	LD	DE,IDESTR_ARROW
	CALL	WRITESTR

	CALL	PC_SPACE
	IN	A,(IDESTTS)
	CALL	PRTHEXBYTE

	CALL	PC_SPACE
	IN	A,(IDEERR)
	CALL	PRTHEXBYTE

	CALL	PC_SPACE
	LD	DE,IDESTR_RC
	CALL	WRITESTR
	LD	A,(IDE_STAT)
	CALL	PRTHEXBYTE

	CALL	PC_SPACE
	CALL	PC_LBKT
	LD	A,(IDE_STAT)
	LD	DE,IDESTR_RCOK
	CP	IDE_RCOK
	JP	Z,IDE_PRTRC
	LD	DE,IDESTR_RCCMDERR
	CP	IDE_RCCMDERR
	JP	Z,IDE_PRTRC
	LD	DE,IDESTR_RCRDYTO
	CP	IDE_RCRDYTO
	JP	Z,IDE_PRTRC
	LD	DE,IDESTR_RCBUFTO
	CP	IDE_RCBUFTO
	JP	Z,IDE_PRTRC
	LD	DE,IDESTR_RCBSYTO
	CP	IDE_RCBSYTO
	JP	Z,IDE_PRTRC
	LD	DE,IDESTR_RCUNK
IDE_PRTRC:	
	CALL	WRITESTR
	CALL	PC_RBKT

	RET
;
;
;
IDESTR_PREFIX	.TEXT	"IDE$"
IDESTR_CMD	.TEXT	"CMD=$"
IDESTR_RC	.TEXT	"RC=$"
IDESTR_ARROW	.TEXT	"-->$"
IDESTR_READ	.TEXT	"READ$"
IDESTR_WRITE	.TEXT	"WRITE$"
IDESTR_SETFEAT	.TEXT	"SETFEAT$"
IDESTR_IDDEV	.TEXT	"IDDEV$"
IDESTR_RECAL	.TEXT	"RECAL$"
IDESTR_UNKCMD	.TEXT	"UNKCMD$"
IDESTR_RCOK	.TEXT	"OK$"
IDESTR_RCCMDERR	.TEXT	"COMMAND ERROR$"
IDESTR_RCRDYTO	.TEXT	"READY TIMEOUT$"
IDESTR_RCBUFTO	.TEXT	"BUFFER TIMEOUT$"
IDESTR_RCBSYTO	.TEXT	"BUSY TIMEOUT$"
IDESTR_RCUNK	.TEXT	"UNKNOWN ERROR$"
IDESTR_NO	.TEXT	"NO$"
;
;==================================================================================================
;   IDE DISK DRIVER - DATA
;==================================================================================================
;
IDE_UNITCNT	.DB	0
IDE_CURUNIT	.DB	0
IDE_STAT	.DB	0
;
IDE_CMD		.DB	0
IDE_DEVICE	.DB	0
IDE_CYLHI	.DB	0
IDE_CYLLO	.DB	0
IDE_SEC		.DB	0
IDE_STTS	.DB	0
IDE_ERRS	.DB	0
;
IDE_CAPLIST	.FILL	2 * 4,0		; CAPACITY OF EACH UNIT IN BLOCKS, 1 DWORD PER UNIT
;
;
;
;
; Error Register (ERR bit being set in the Status Register)
;
; Bit 7: BBK (Bad Block Detected) Set when a Bad Block is detected.
; Bit 6: UNC (Uncorrectable Data Error) Set when Uncorrectable Error is encountered.
; Bit 5: MC (Media Changed) Set to 0.
; Bit 4: IDNF (ID Not Found) Set when Sector ID not found.
; Bit 3: MCR (Media Change Request) Set to 0.
; Bit 2: ABRT (Aborted Command) Set when Command Aborted due to drive error.
; Bit 1: TKONF (Track 0 Not Found) Set when Executive Drive Diagnostic Command. 
; Bit 0: AMNF (Address mark Not Found) Set in case of a general error.
;
; Status Register (When the contents of this register are read by the host, the IREQ# bit is cleared)
;
; Bit 7: BSY (Busy) Set when the drive is busy and unable to process any new ATA commands.
; Bit 6: DRDY (Data Ready) Set when the device is ready to accept ATA commands from the host.
; Bit 5: DWF (Drive Write Fault) Always set to 0.
; Bit 4: DSC (Drive Seek Complete) Set when the drive heads have been positioned over a specific track.
; Bit 3: DRQ (Data Request) Set when device is ready to transfer a word or byte of data to or from the host and the device.
; Bit 2: CORR (Corrected Data) Always set to 0.
; Bit 1: IDX (Index) Always set to 0.
; Bit 0: ERR (Error) Set when an error occurred during the previous ATA command.