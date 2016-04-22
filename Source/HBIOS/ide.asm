;
;=============================================================================
;   IDE DISK DRIVER
;=============================================================================
;
; TODO:
; - IMPLEMENT IDE_INITDEVICE
; - HANDLE SECONDARY INTERFACE ON DIDE
; - IMPLEMENT INTELLIGENT RESET, CHECK IF DEVICE IS ACTUALLY BROKEN BEFORE RESET
;
;	+-----------------------------------------------------------------------+
;	| CONTROL BLOCK REGISTERS						|
;	+-----------------------+-------+-------+-------------------------------+
;	| REGISTER      	| PORT	| DIR	| DESCRIPTION                   |
;	+-----------------------+-------+-------+-------------------------------+
;	| IDE_IO_ALTSTAT	| 0x0E	| R	| ALTERNATE STATUS REGISTER	|
;	| IDE_IO_CTRL		| 0x0E	| W	| DEVICE CONTROL REGISTER	|
;	| IDE_IO_DRVADR		| 0x0F	| R	| DRIVE ADDRESS REGISTER	|
;	+-----------------------+-------+-------+-------------------------------+
;
;	+-----------------------+-------+-------+-------------------------------+
;	| COMMAND BLOCK REGISTERS						|
;	+-----------------------+-------+-------+-------------------------------+
;	| REGISTER      	| PORT	| DIR	| DESCRIPTION                   |
;	+-----------------------+-------+-------+-------------------------------+
;	| IDE_IO_DATA		| 0x00	| R/W	| DATA INPUT/OUTPUT		|
;	| IDE_IO_ERR		| 0x01	| R	| ERROR REGISTER		|
;	| IDE_IO_FEAT		| 0x01	| W	| FEATURES REGISTER		|
;	| IDE_IO_COUNT		| 0x02	| R/W	| SECTOR COUNT REGISTER		|
;	| IDE_IO_SECT		| 0x03	| R/W	| SECTOR NUMBER REGISTER	|
;	| IDE_IO_CYLLO		| 0x04	| R/W	| CYLINDER NUM REGISTER (LSB)	|
;	| IDE_IO_CYLHI		| 0x05	| R/W	| CYLINDER NUM REGISTER (MSB)	|
;	| IDE_IO_DRVHD		| 0x06	| R/W	| DRIVE/HEAD REGISTER		|
;	| IDE_IO_LBA0*		| 0x03	| R/W	| LBA BYTE 0 (BITS 0-7) 	|
;	| IDE_IO_LBA1*		| 0x04	| R/W	| LBA BYTE 1 (BITS 8-15)	|
;	| IDE_IO_LBA2*		| 0x05	| R/W	| LBA BYTE 2 (BITS 16-23)	|
;	| IDE_IO_LBA3*		| 0x06	| R/W	| LBA BYTE 3 (BITS 24-27)	|
;	| IDE_IO_STAT		| 0x07	| R	| STATUS REGISTER		|
;	| IDE_IO_CMD		| 0x07	| W	| COMMAND REGISTER (EXECUTE)	|
;	+-----------------------+-------+-------+-------------------------------+
;	* LBA0-4 ARE ALTERNATE DEFINITIONS OF SECT, CYL, AND DRVHD PORTS
;
;	=== STATUS REGISTER ===
;
;	    7       6       5       4       3       2       1       0
;	+-------+-------+-------+-------+-------+-------+-------+-------+
;	|  BSY  | DRDY  |  DWF  |  DSC  |  DRQ  | CORR  |  IDX  |  ERR  |
;	+-------+-------+-------+-------+-------+-------+-------+-------+
;
;	BSY:	BUSY
;	DRDY:	DRIVE READY
;	DWF:	DRIVE WRITE FAULT
;	DSC:	DRIVE SEEK COMPLETE
;	DRQ:	DATA REQUEST
;	CORR:	CORRECTED DATA
;	IDX:	INDEX
;	ERR:	ERROR
;
;	=== ERROR REGISTER ===
;
;	    7       6       5       4       3       2       1       0
;	+-------+-------+-------+-------+-------+-------+-------+-------+
;	| BBK   |  UNC  |  MC   |  IDNF |  MCR  | ABRT  | TK0NF |  AMNF |
;	+-------+-------+-------+-------+-------+-------+-------+-------+
;	(VALID WHEN ERR BIT IS SET IN STATUS REGISTER)
;
;	BBK:	BAD BLOCK DETECTED
;	UNC:	UNCORRECTABLE DATA ERROR
;	MC:	MEDIA CHANGED
;	IDNF:	ID NOT FOUND
;	MCR:	MEDIA CHANGE REQUESTED
;	ABRT:	ABORTED COMMAND
;	TK0NF:	TRACK 0 NOT FOUND
;	AMNF:	ADDRESS MARK NOT FOUND
;
;	=== DRIVE/HEAD / LBA3 REGISTER ===
;
;	    7       6       5       4       3       2       1       0
;	+-------+-------+-------+-------+-------+-------+-------+-------+
;	|   1   |   L   |   1   |  DRV  |  HS3  |  HS2  |  HS1  |  HS0  |
;	+-------+-------+-------+-------+-------+-------+-------+-------+
;
;	L:	0 = CHS ADDRESSING, 1 = LBA ADDRESSING
;	DRV:	0 = DRIVE 0 (PRIMARY) SELECTED, 1 = DRIVE 1 (SLAVE) SELECTED
;	HS:	CHS = HEAD ADDRESS (0-15), LBA = BITS 24-27 OF LBA
;
;	=== DEVICE CONTROL REGISTER ===
;
;	    7       6       5       4       3       2       1       0
;	+-------+-------+-------+-------+-------+-------+-------+-------+
;	|   X   |   X   |   X   |   X   |   1   | SRST  |  ~IEN |   0   |
;	+-------+-------+-------+-------+-------+-------+-------+-------+
;
;	SRST:	SOFTWARE RESET
;	~IEN:	INTERRUPT ENABLE
;
#IF (IDETRACE >= 3)
#DEFINE		DCALL	CALL
#ELSE
#DEFINE		DCALL	\;
#ENDIF
;
; UNIT MAPPING IS AS FOLLOWS:
;   IDE0:	PRIMARY MASTER
;   IDE1:	PRIMARY SLAVE
;   IDE2:	SECONDARY MASTER
;   IDE3:	SECONDARY SLAVE
;
IDE_UNITCNT		.EQU	2		; ASSUME ONLY PRIMARY INTERFACE
;
#IF (IDEMODE == IDEMODE_MK4)
IDE_IO_BASE		.EQU	MK4_IDE
#ELSE
IDE_IO_BASE		.EQU	$20
#ENDIF

#IF ((IDEMODE == IDEMODE_DIO) | (IDEMODE == IDEMODE_MK4))
#IF (IDE8BIT)
IDE_IO_DATA	.EQU 	$IDE_IO_BASE + $00	; DATA PORT (8 BIT PIO) (R/W)
#ELSE
IDE_IO_DATALO	.EQU 	$IDE_IO_BASE + $00	; DATA PORT (16 BIT PIO LO BYTE) (R/W)
IDE_IO_DATAHI	.EQU 	$IDE_IO_BASE + $08	; DATA PORT (16 BIT PIO HI BYTE) (R/W)
IDE_IO_DATA	.EQU	IDE_IO_DATALO
#ENDIF
#ENDIF
;
#IF (IDEMODE == IDEMODE_DIDE)
IDE_UNITCNT	.SET	4			; DIDE HAS PRIMARY AND SECONDARY INTERACES
#IF (IDE8BIT)
IDE_IO_DATA	.EQU 	$IDE_IO_BASE + $00	; DATA PORT (8 BIT PIO) (R/W)
#ELSE
IDE_IO_DATA	.EQU 	$IDE_IO_BASE + $08	; DATA PORT (16 BIT PIO LO/HI BYTES) (R/W)
IDE_IO_DMA	.EQU 	$IDE_IO_BASE + $09	; DATA PORT (16 BIT DMA LO/HI BYTES) (R/W)
#ENDIF
#ENDIF
;
;IDE_IO_DATA	.EQU	$IDE_IO_BASE + $00	; DATA INPUT/OUTPUT (R/W)
IDE_IO_ERR	.EQU 	$IDE_IO_BASE + $01	; ERROR REGISTER (R)
IDE_IO_FEAT	.EQU 	$IDE_IO_BASE + $01	; FEATURES REGISTER (W)
IDE_IO_COUNT	.EQU 	$IDE_IO_BASE + $02	; SECTOR COUNT REGISTER (R/W)
IDE_IO_SECT	.EQU 	$IDE_IO_BASE + $03	; SECTOR NUMBER REGISTER (R/W)
IDE_IO_CYLLO	.EQU 	$IDE_IO_BASE + $04	; CYLINDER NUM REGISTER (LSB) (R/W)
IDE_IO_CYLHI	.EQU 	$IDE_IO_BASE + $05	; CYLINDER NUM REGISTER (MSB) (R/W)
IDE_IO_DRVHD	.EQU 	$IDE_IO_BASE + $06	; DRIVE/HEAD REGISTER (R/W)
IDE_IO_LBA0	.EQU	$IDE_IO_BASE + $03	; LBA BYTE 0 (BITS 0-7) (R/W)
IDE_IO_LBA1	.EQU	$IDE_IO_BASE + $03	; LBA BYTE 1 (BITS 8-15) (R/W)
IDE_IO_LBA2	.EQU	$IDE_IO_BASE + $03	; LBA BYTE 2 (BITS 16-23) (R/W)
IDE_IO_LBA3	.EQU	$IDE_IO_BASE + $03	; LBA BYTE 3 (BITS 24-27) (R/W)
IDE_IO_STAT	.EQU 	$IDE_IO_BASE + $07	; STATUS REGISTER (R)
IDE_IO_CMD	.EQU 	$IDE_IO_BASE + $07	; COMMAND REGISTER (EXECUTE) (W)
IDE_IO_ALTSTAT	.EQU 	$IDE_IO_BASE + $0E	; ALTERNATE STATUS REGISTER (R)
IDE_IO_CTRL	.EQU 	$IDE_IO_BASE + $0E	; DEVICE CONTROL REGISTER (W)
IDE_IO_DRVADR	.EQU 	$IDE_IO_BASE + $0F	; DRIVE ADDRESS REGISTER (R)
;
; COMMAND BYTES
;
IDE_CIDE_RECAL	.EQU	$10
IDE_CIDE_READ	.EQU	$20
IDE_CIDE_WRITE	.EQU	$30
IDE_CIDE_IDDEV	.EQU	$EC
IDE_CIDE_SETFEAT	.EQU	$EF
;
; FEATURE BYTES
;
IDE_FEAT_ENABLE8BIT	.EQU	$01
IDE_FEAT_DISABLE8BIT	.EQU	$81
;
; IDE DEVICE TYPES
;
IDE_TYPEUNK	.EQU	0
IDE_TYPEATA	.EQU	1
IDE_TYPEATAPI	.EQU	2
;
; IDE DEVICE STATUS
;
IDE_STOK	.EQU	0
IDE_STINVUNIT	.EQU	-1
IDE_STNOMEDIA	.EQU	-2
IDE_STCMDERR	.EQU	-3
IDE_STIOERR	.EQU	-4
IDE_STRDYTO	.EQU	-5
IDE_STDRQTO	.EQU	-6
IDE_STBSYTO	.EQU	-7
;
; DRIVE SELECTION BYTES (FOR USE IN DRIVE/HEAD REGISTER)
;
IDE_DRVSEL:
IDE_DRVMASTER	.DB	%11100000	; LBA, MASTER DEVICE
IDE_DRVSLAVE	.DB	%11110000	; LBA, SLAVE DEVICE
;
; PER UNIT DATA OFFSETS (CAREFUL NOT TO EXCEED PER UNIT SPACE IN IDE_UNITDATA)
; SEE IDE_UNITDATA IN DATA STORAGE BELOW
;
IDE_STAT	.EQU	0		; LAST STATUS (1 BYTE)
IDE_TYPE	.EQU	1		; DEVICE TYPE (1 BYTE)
IDE_CAPACITY	.EQU	2		; DEVICE CAPACITY (1 DWORD/4 BYTES)
IDE_CFFLAG	.EQU	6		; CF FLAG (1 BYTE), NON-ZERO=CF
;
; THE IDE_WAITXXX FUNCTIONS ARE BUILT TO TIMEOUT AS NEEDED SO DRIVER WILL
; NOT HANG IF DEVICE IS UNRESPONSIVE.  DIFFERENT TIMEOUTS ARE USED DEPENDING
; ON THE SITUATION.  GENERALLY, THE FAST TIMEOUT IS USED TO PROBE FOR DEVICES
; USING FUNCTIONS THAT PERFORM NO I/O.  OTHERWISE THE NORMAL TIMEOUT IS USED.
; IDE SPEC ALLOWS FOR UP TO 30 SECS MAX TO RESPOND.  IN PRACTICE, THIS IS WAY
; TOO LONG, BUT IF YOU ARE USING A VERY OLD DEVICE, THESE TIMEOUTS MAY NEED TO
; BE ADJUSTED.  NOTE THAT THESE ARE BYTE VALUES, SO YOU CANNOT EXCEED 255.
; THE TIMEOUTS ARE IN UNITS OF .05 SECONDS.
;
IDE_TONORM	.EQU	200		; NORMAL TIMEOUT IS 10 SECS
IDE_TOFAST	.EQU	10		; FAST TIMEOUT IS 0.5 SECS
;
; MACRO TO RETURN POINTER TO FIELD WITHIN UNIT DATA
;
#DEFINE IDE_DPTR(FIELD)	CALL IDE_DPTRIMP \ .DB FIELD
;
;=============================================================================
; INITIALIZATION ENTRY POINT
;=============================================================================
;
IDE_INIT:
	CALL	NEWLINE			; FORMATTING
	PRTS("IDE:$")			; LABEL FOR IO ADDRESS
;
; SETUP THE DISPATCH TABLE ENTRIES
;
	LD	B,IDE_UNITCNT	; LOOP CONTROL
	LD	C,0		; PHYSICAL UNIT INDEX
IDE_INIT0:
	PUSH	BC		; SAVE LOOP CONTROL
	LD	B,C		; PHYSICAL UNIT
	LD	C,DIODEV_IDE	; DEVICE TYPE
	LD	DE,0		; UNIT DATA BLOB ADDRESS
	CALL	DIO_ADDENT	; ADD ENTRY, BC IS NOT DESTROYED
	POP	BC		; RESTORE LOOP CONTROL
	INC	C		; NEXT PHYSICAL UNIT
	DJNZ	IDE_INIT0	; LOOP UNTIL DONE
;
	; COMPUTE CPU SPEED COMPENSATED TIMEOUT SCALER
	; AT 1MHZ, THE SCALER IS 961 (50000US / 52TS = 961)
	; SCALER IS THEREFORE 961 * CPU SPEED IN MHZ
	LD	DE,961			; LOAD SCALER FOR 1MHZ
	LD	A,(HCB + HCB_CPUMHZ)	; LOAD CPU SPEED IN MHZ
	CALL	MULT8X16		; HL := DE * A
	LD	(IDE_TOSCALER),HL	; SAVE IT
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
	PRTS(" IO=0x$")			; LABEL FOR IO ADDRESS
	LD	A,IDE_IO_DATA		; GET IO ADDRESS
	CALL	PRTHEXBYTE		; PRINT IT
;
	; PRINT UNIT COUNT
	PRTS(" UNITS=$")		; PRINT LABEL FOR UNIT COUNT
	LD	A,IDE_UNITCNT		; GET UNIT COUNT
	CALL	PRTDECB			; PRINT IT IN DECIMAL
;
	; INITIALIZE THE IDE INTERFACE NOW
	CALL	IDE_RESET		; DO HARDWARE SETUP/INIT
	RET	NZ			; ABORT IF RESET FAILS
;
	; DEVICE DISPLAY LOOP
	LD	B,IDE_UNITCNT		; LOOP ONCE PER UNIT
	LD	C,0			; C IS UNIT INDEX
IDE_INIT1:
	LD	A,C			; UNIT NUM TO ACCUM
	PUSH	BC			; SAVE LOOP CONTROL
	CALL	IDE_INIT2		; DISPLAY UNIT INFO
	POP	BC			; RESTORE LOOP CONTROL
	INC	C			; INCREMENT UNIT INDEX
	DJNZ	IDE_INIT1		; LOOP UNTIL DONE
	RET				; DONE
;
IDE_INIT2:
	LD	(IDE_UNIT),A		; SET CURRENT UNIT
;
	; CHECK FOR BAD STATUS
	IDE_DPTR(IDE_STAT)		; GET STATUS ADR IN HL, AF TRASHED
	LD	A,(HL)
	OR	A
	JP	NZ,IDE_PRTSTAT
;
	CALL	IDE_PRTPREFIX		; PRINT DEVICE PREFIX
;
#IF (IDE8BIT)
	PRTS(" 8BIT$")
#ENDIF
;
	; PRINT LBA/NOLBA
	CALL	PC_SPACE		; FORMATTING
	LD	HL,HB_WRKBUF		; POINT TO BUFFER START
	LD	DE,98+1			; OFFSET OF BYTE CONTAINING LBA FLAG
	ADD	HL,DE			; POINT TO FINAL BUFFER ADDRESS
	LD	A,(HL)			; GET THE BYTE
	BIT	1,A			; CHECK THE LBA BIT
	LD	DE,IDE_STR_NO		; POINT TO "NO" STRING
	CALL	Z,WRITESTR		; PRINT "NO" BEFORE "LBA" IF LBA NOT SUPPORTED
	PRTS("LBA$")			; PRINT "LBA" REGARDLESS
;
	; PRINT STORAGE CAPACITY (BLOCK COUNT)
	PRTS(" BLOCKS=0x$")		; PRINT FIELD LABEL
	IDE_DPTR(IDE_CAPACITY)		; SET HL TO ADR OF DEVICE CAPACITY
	CALL	LD32			; GET THE CAPACITY VALUE
	CALL	PRTHEX32		; PRINT HEX VALUE
;
	; PRINT STORAGE SIZE IN MB
	PRTS(" SIZE=$")			; PRINT FIELD LABEL
	LD	B,11			; 11 BIT SHIFT TO CONVERT BLOCKS --> MB
	CALL	SRL32			; RIGHT SHIFT
	CALL	PRTDEC			; PRINT LOW WORD IN DECIMAL (HIGH WORD DISCARDED)
	PRTS("MB$")			; PRINT SUFFIX
;
	XOR	A			; SIGNAL SUCCESS
	RET				; RETURN WITH A=0, AND Z SET
;
;=============================================================================
; FUNCTION DISPATCH ENTRY POINT
;=============================================================================
;
IDE_DISPATCH:
	; VERIFY AND SAVE THE TARGET DEVICE/UNIT LOCALLY IN DRIVER
	LD	A,C			; DEVICE/UNIT FROM C
	AND	$0F			; ISOLATE UNIT NUM
	CP	IDE_UNITCNT
	CALL	NC,PANIC		; PANIC IF TOO HIGH
	LD	(IDE_UNIT),A		; SAVE IT
;
	; DISPATCH ACCORDING TO DISK SUB-FUNCTION
	LD	A,B		; GET REQUESTED FUNCTION
	AND	$0F		; ISOLATE SUB-FUNCTION
	JP	Z,IDE_STATUS	; SUB-FUNC 0: STATUS
	DEC	A
	JP	Z,IDE_RESET	; SUB-FUNC 1: RESET
	DEC	A
	JP	Z,IDE_SEEK	; SUB-FUNC 2: SEEK
	DEC	A
	JP	Z,IDE_READ	; SUB-FUNC 3: READ SECTORS
	DEC	A
	JP	Z,IDE_WRITE	; SUB-FUNC 4: WRITE SECTORS
	DEC	A
	JP	Z,IDE_VERIFY	; SUB-FUNC 5: VERIFY SECTORS
	DEC	A
	JP	Z,IDE_FORMAT	; SUB-FUNC 6: FORMAT TRACK
	DEC	A
	JP	Z,IDE_DEVICE	; SUB-FUNC 7: DEVICE REPORT
	DEC	A
	JP	Z,IDE_MEDIA	; SUB-FUNC 8: MEDIA REPORT
	DEC	A
	JP	Z,IDE_DEFMED	; SUB-FUNC 9: DEFINE MEDIA
	DEC	A
	JP	Z,IDE_CAP	; SUB-FUNC 10: REPORT CAPACITY
	DEC	A
	JP	Z,IDE_GEOM	; SUB-FUNC 11: REPORT GEOMETRY
;
IDE_VERIFY:
IDE_FORMAT:
IDE_DEFMED:
	CALL	PANIC		; INVALID SUB-FUNCTION
;
;
;
IDE_READ:
	LD	(IDE_DSKBUF),HL		; SAVE DISK BUFFER ADDRESS
#IF (IDETRACE == 1)
	LD	HL,IDE_PRTERR		; SET UP IDE_PRTERR
	PUSH	HL			; ... TO FILTER ALL EXITS
#ENDIF
	CALL	IDE_SELUNIT		; HARDWARE SELECTION OF TARGET UNIT
	JP	IDE_RDSEC
;
;
;
IDE_WRITE:
	LD	(IDE_DSKBUF),HL		; SAVE DISK BUFFER ADDRESS
#IF (IDETRACE == 1)
	LD	HL,IDE_PRTERR		; SET UP IDE_PRTERR
	PUSH	HL			; ... TO FILTER ALL EXITS
#ENDIF
	CALL	IDE_SELUNIT		; HARDWARE SELECTION OF TARGET UNIT
	JP	IDE_WRSEC
;
;
;
IDE_STATUS:
	; RETURN UNIT STATUS
	IDE_DPTR(IDE_STAT)		; HL := ADR OF STATUS, AF TRASHED
	LD	A,(HL)			; GET STATUS OF SELECTED UNIT
	OR	A			; SET FLAGS
	RET				; AND RETURN
;
;
;
IDE_DEVICE:
	LD	D,DIODEV_IDE		; D := DEVICE TYPE
	LD	E,C			; E := PHYSICAL UNIT
	IDE_DPTR(IDE_CFFLAG)		; POINT TO CF FLAG
	LD	A,(HL)			; GET FLAG
	OR	A			; SET ACCUM FLAGS
	LD	C,%00000000		; ASSUME NON-REMOVABLE HARD DISK
	JR	Z,IDE_DEVICE1		; IF Z, WE ARE DONE
	LD	C,%01001000		; OTHERWISE REMOVABLE COMPACT FLASH
IDE_DEVICE1:	
	XOR	A			; SIGNAL SUCCESS
	RET
;
; IDE_GETMED
;
IDE_MEDIA:
	LD	A,E			; GET FLAGS
	OR	A			; SET FLAGS
	JR	Z,IDE_MEDIA2		; JUST REPORT CURRENT STATUS AND MEDIA
;
	; GET CURRENT STATUS
	IDE_DPTR(IDE_STAT)		; POINT TO UNIT STATUS
	LD	A,(HL)			; GET STATUS
	OR	A			; SET FLAGS
	JR	NZ,IDE_MEDIA1		; ERROR ACTIVE, TO RIGHT TO RESET
;
	; USE IDENTIFY COMMAND TO CHECK DEVICE
	LD	HL,IDE_TIMEOUT		; POINT TO TIMEOUT
	LD	(HL),IDE_TOFAST		; USE FAST TIMEOUT DURING IDENTIFY COMMAND
	CALL	IDE_IDENTIFY		; EXECUTE IDENTIFY COMMAND
	LD	HL,IDE_TIMEOUT		; POINT TO TIMEOUT
	LD	(HL),IDE_TONORM		; BACK TO NORMAL TIMEOUT
	JR	Z,IDE_MEDIA2		; IF SUCCESS, BYPASS RESET
;
IDE_MEDIA1:
	CALL	IDE_RESET		; RESET IDE INTERFACE
;
IDE_MEDIA2:
	IDE_DPTR(IDE_STAT)		; POINT TO UNIT STATUS
	LD	A,(HL)			; GET STATUS
	OR	A			; SET FLAGS
	LD	D,0			; NO MEDIA CHANGE DETECTED
	LD	E,MID_HD		; ASSUME WE ARE OK
	RET	Z			; RETURN IF GOOD INIT
	LD	E,MID_NONE		; SIGNAL NO MEDIA
	RET				; AND RETURN
;
;
;
IDE_SEEK:
	BIT	7,D			; CHECK FOR LBA FLAG
	CALL	Z,HB_CHS2LBA		; CLEAR MEANS CHS, CONVERT TO LBA
	RES	7,D			; CLEAR FLAG REGARDLESS (DOES NO HARM IF ALREADY LBA)
	LD	BC,HSTLBA		; POINT TO LBA STORAGE
	CALL	ST32			; SAVE LBA ADDRESS
	XOR	A			; SIGNAL SUCCESS
	RET				; AND RETURN
;
;
;
IDE_CAP:
	IDE_DPTR(IDE_CAPACITY)		; POINT HL TO CAPACITY OF CUR UNIT
	CALL	LD32			; GET THE CURRENT CAPACITY DO DE:HL
	LD	BC,512			; 512 BYTES PER BLOCK
	IDE_DPTR(IDE_STAT)		; POINT TO UNIT STATUS
	LD	A,(HL)			; GET STATUS
	OR	A			; SET FLAGS
	RET
;
;
;
IDE_GEOM:
	; FOR LBA, WE SIMULATE CHS ACCESS USING 16 HEADS AND 16 SECTORS
	; RETURN HS:CC -> DE:HL, SET HIGH BIT OF D TO INDICATE LBA CAPABLE
	CALL	IDE_CAP			; GET TOTAL BLOCKS IN DE:HL, BLOCK SIZE TO BC
	LD	L,H			; DIVIDE BY 256 FOR # TRACKS
	LD	H,E			; ... HIGH BYTE DISCARDED, RESULT IN HL
	LD	D,16 | $80		; HEADS / CYL = 16, SET LBA CAPABILITY BIT
	LD	E,16			; SECTORS / TRACK = 16
	RET				; DONE, A STILL HAS IDE_CAP STATUS
;
;=============================================================================
; FUNCTION SUPPORT ROUTINES
;=============================================================================
;
IDE_SETFEAT:
	PUSH	AF
#IF (IDETRACE >= 3)
	CALL	IDE_PRTPREFIX
	PRTS(" SETFEAT$")
#ENDIF
	LD	A,(IDE_DRVHD)
	OUT	(IDE_IO_DRVHD),A
	DCALL	PC_SPACE
	DCALL	PRTHEXBYTE
	POP	AF
	OUT	(IDE_IO_FEAT),A		; SET THE FEATURE VALUE
	DCALL	PC_SPACE
	DCALL	PRTHEXBYTE
	LD	A,IDE_CIDE_SETFEAT	; CMD = SETFEAT
	LD	(IDE_CMD),A		; SAVE IT
	JP	IDE_RUNCMD		; RUN COMMAND AND EXIT
;
;
;
IDE_IDENTIFY:
#IF (IDETRACE >= 3)
	CALL	IDE_PRTPREFIX
	PRTS(" IDDEV$")
#ENDIF
	LD	A,(IDE_DRVHD)
	OUT	(IDE_IO_DRVHD),A
	DCALL	PC_SPACE
	DCALL	PRTHEXBYTE
	LD	A,IDE_CIDE_IDDEV
	LD	(IDE_CMD),A
	CALL	IDE_RUNCMD
	RET	NZ
	LD	HL,HB_WRKBUF
	JP	IDE_GETBUF		; EXIT THRU BUFRD
;
;
;
IDE_RDSEC:
	CALL	IDE_CHKDEVICE
	RET	NZ
;
#IF (IDETRACE >= 3)
	CALL	IDE_PRTPREFIX
	PRTS(" READ$")
#ENDIF
	LD	A,(IDE_DRVHD)
	OUT	(IDE_IO_DRVHD),A
	DCALL	PC_SPACE
	DCALL	PRTHEXBYTE
	CALL	IDE_SETADDR		; SETUP CYL, TRK, HEAD
	LD	A,IDE_CIDE_READ
	LD	(IDE_CMD),A
	CALL	IDE_RUNCMD
	RET	NZ
	LD	HL,(IDE_DSKBUF)
	JP	IDE_GETBUF
;
;
;
IDE_WRSEC:
	CALL	IDE_CHKDEVICE
	RET	NZ
;
#IF (IDETRACE >= 3)
	CALL	IDE_PRTPREFIX
	PRTS(" WRITE$")
#ENDIF
	LD	A,(IDE_DRVHD)
	OUT	(IDE_IO_DRVHD),A
	DCALL	PC_SPACE
	DCALL	PRTHEXBYTE
	CALL	IDE_SETADDR		; SETUP CYL, TRK, HEAD
	LD	A,IDE_CIDE_WRITE
	LD	(IDE_CMD),A
	CALL	IDE_RUNCMD
	RET	NZ
	LD	HL,(IDE_DSKBUF)
	JP	IDE_PUTBUF
;
;
;
IDE_SETADDR:
	; SEND 3 LOWEST BYTES OF LBA IN REVERSE ORDER
	; IDE_IO_LBA3 HAS ALREADY BEEN SET
	; HSTLBA2-0 --> IDE_IO_LBA2-0
	LD	C,IDE_IO_LBA0 + 3	; STARTING IO PORT (NOT PRE-DEC BELOW)
	LD	HL,HSTLBA + 2		; STARTING LBA BYTE ADR
	LD	B,3			; SEND 3 BYTES
IDE_SETADDR1:
;
#IF (IDETRACE >= 3)
	LD	A,(HL)
	CALL	PC_SPACE
	CALL	PRTHEXBYTE
#ENDIF
;
	DEC	C			; NEXT PORT
	OUTD				; SEND NEXT BYTE
	JR	NZ,IDE_SETADDR1		; LOOP TILL DONE
;
	; SEND COUNT OF BLOCKS TO TRANSFER
	; 1 --> IDE_IO_COUNT
	LD	A,1			; COUNT VALUE IS 1 BLOCK
;
#IF (IDETRACE >= 3)
	DCALL	PC_SPACE
	DCALL	PRTHEXBYTE
#ENDIF
;
	DEC	C			; PORT := IDE_IO_COUNT
	OUT	(C),A			; SEND IT
;
#IF (DSKYENABLE)
	CALL	IDE_DSKY
#ENDIF
;
	RET
;
;=============================================================================
; COMMAND PROCESSING
;=============================================================================
;
IDE_RUNCMD:
	CALL	IDE_WAITRDY		; WAIT FOR DRIVE READY
	RET	NZ			; BAIL OUT ON TIMEOUT
;
	LD	A,(IDE_CMD)		; GET THE COMMAND
	DCALL	PC_SPACE
	DCALL	PRTHEXBYTE
	OUT	(IDE_IO_CMD),A		; SEND IT (STARTS EXECUTION)
#IF (IDETRACE >= 3)
	PRTS(" -->$")
#ENDIF
;
	CALL	IDE_WAITBSY		; WAIT FOR DRIVE READY (COMMAND DONE)
	RET	NZ			; BAIL OUT ON TIMEOUT
;
	CALL	IDE_GETRES
	JP	NZ,IDE_CMDERR
	RET
;
;
;
IDE_GETBUF:
#IF (IDETRACE >= 3)
	PRTS(" GETBUF$")
#ENDIF

	CALL	IDE_WAITDRQ		; WAIT FOR BUFFER READY
	RET	NZ			; BAIL OUT IF TIMEOUT

	;LD	HL,(IDE_DSKBUF)
	LD	B,0

#IF (IDE8BIT | (IDEMODE == IDEMODE_DIDE))
	LD	C,IDE_IO_DATA
	INIR
	INIR
;X1:
;	NOP
;	INI
;	JR	NZ,X1
;X2:
;	NOP
;	INI
;	JR	NZ,X2
#ELSE
	LD	C,IDE_IO_DATAHI
IDE_GETBUF1:
	IN	A,(IDE_IO_DATALO)	; READ THE LO BYTE
	LD	(HL),A			; SAVE IN BUFFER
	INC	HL			; INC BUFFER POINTER
	INI				; READ AND SAVE HI BYTE, INC HL, DEC B
	JP	NZ,IDE_GETBUF1		; LOOP AS NEEDED
#ENDIF
	CALL	IDE_WAITRDY		; PROBLEMS IF THIS IS REMOVED!
	CALL	IDE_GETRES
	JP	NZ,IDE_IOERR
	RET
;
;
;
IDE_PUTBUF:
#IF (IDETRACE >= 3)
	PRTS(" GETBUF$")
#ENDIF

	CALL	IDE_WAITDRQ		; WAIT FOR BUFFER READY
	RET	NZ			; BAIL OUT IF TIMEOUT
;
	;LD	HL,(IDE_DSKBUF)
	LD	B,0

#IF (IDE8BIT | (IDEMODE == IDEMODE_DIDE))
	LD	C,IDE_IO_DATA
	OTIR
	OTIR
#ELSE
	LD	C,IDE_IO_DATAHI
IDE_PUTBUF1:
	LD	A,(HL)			; GET THE LO BYTE AND KEEP IT IN A FOR LATER
	INC	HL			; BUMP TO NEXT BYTE IN BUFFER
	OUTI				; WRITE HI BYTE, INC HL, DEC B
	OUT	(IDE_IO_DATALO),A	; NOW WRITE THE SAVED LO BYTE TO LO BYTE
	JP	NZ,IDE_PUTBUF1		; LOOP AS NEEDED
#ENDIF
	CALL	IDE_WAITRDY		; PROBLEMS IF THIS IS REMOVED!
	CALL	IDE_GETRES
	JP	NZ,IDE_IOERR
	RET
;
;
;
IDE_GETRES:
	IN	A,(IDE_IO_STAT)		; GET STATUS
	DCALL	PC_SPACE
	DCALL	PRTHEXBYTE
	AND	%00000001		; ERROR BIT SET?
	RET	Z			; NOPE, RETURN WITH ZF
;
	IN	A,(IDE_IO_ERR)		; READ ERROR REGISTER
	DCALL	PC_SPACE
	DCALL	PRTHEXBYTE
	OR	$FF			; FORCE NZ TO SIGNAL ERROR
	RET				; RETURN
;
;=============================================================================
; HARDWARE INTERFACE ROUTINES
;=============================================================================
;
; RESET ALL DEVICES ON BUS
;
IDE_RESET:
;
#IF (PLATFORM == PLT_MK4)
	; USE HARDWARE RESET LINE
	LD	A,$80			; HIGH BIT OF XAR IS IDE RESET
	OUT	(MK4_XAR),A
	LD	DE,2			; DELAY 32US (SPEC IS >= 25US)
	CALL	VDELAY
	XOR	A			; CLEAR RESET BIT
	OUT	(MK4_XAR),A
#ELSE
	; INITIATE SOFT RESET
	LD	A,%00001110		; NO INTERRUPTS, ASSERT RESET BOTH DRIVES
	OUT	(IDE_IO_CTRL),A
#ENDIF
;
	LD	DE,2			; DELAY 32US (SPEC IS >= 25US)
	CALL	VDELAY
;
	; CONFIGURE OPERATION AND END SOFT RESET
	LD	A,%00001010		; NO INTERRUPTS, DEASSERT RESET
	OUT	(IDE_IO_CTRL),A		; PUSH TO REGISTER
;
; SPEC ALLOWS UP TO 450MS FOR DEVICES TO ASSERT THEIR PRESENCE
; VIA -DASP.  I ENCOUNTER PROBLEMS LATER ON IF I DON'T WAIT HERE
; FOR THAT TO OCCUR.  THUS FAR, IT APPEARS THAT 150MS IS SUFFICIENT
; FOR ANY DEVICE ENCOUNTERED.  MAY NEED TO EXTEND BACK TO 500MS
; IF A SLOWER DEVICE IS ENCOUNTERED.
;
	;LD	DE,500000/16		; ~500MS
	LD	DE,150000/16		; ~???MS
	CALL	VDELAY
;
	; CLEAR OUT ALL DATA (FOR ALL UNITS)
	LD	HL,IDE_UDATA
	LD	BC,IDE_UDLEN
	XOR	A
	CALL	FILL
;
	LD	A,(IDE_UNIT)		; GET THE CURRENT UNIT SELECTION
	PUSH	AF			; AND SAVE IT

	; PROBE / INITIALIZE ALL UNITS
	LD	B,IDE_UNITCNT		; NUMBER OF UNITS TO TRY
	LD	C,0			; UNIT INDEX FOR LOOP
IDE_RESET1:
	LD	A,C			; UNIT NUMBER TO A
	PUSH	BC
	CALL	IDE_INITUNIT		; PROBE/INIT UNIT
	POP	BC
	INC	C			; NEXT UNIT
	DJNZ	IDE_RESET1		; LOOP AS NEEDED
;
	POP	AF			; RECOVER ORIGINAL UNIT NUMBER
	LD	(IDE_UNIT),A		; AND SAVE IT
;
	XOR	A			; SIGNAL SUCCESS
	RET				; AND DONE
;
;
;
IDE_INITUNIT:
	LD	(IDE_UNIT),A		; SET ACTIVE UNIT
	
	CALL	IDE_SELUNIT		; SELECT UNIT
	RET	NZ			; ABORT IF ERROR

	LD	HL,IDE_TIMEOUT		; POINT TO TIMEOUT
	LD	(HL),IDE_TOFAST		; USE FAST TIMEOUT DURING INIT

	CALL	IDE_PROBE		; DO PROBE
	CALL	Z,IDE_INITDEV		; IF FOUND, ATTEMPT TO INIT DEVICE

	LD	HL,IDE_TIMEOUT		; POINT TO TIMEOUT
	LD	(HL),IDE_TONORM		; BACK TO NORMAL TIMEOUT

	RET
;
; TAKE ANY ACTIONS REQUIRED TO SELECT DESIRED PHYSICAL UNIT
; UNIT IS SPECIFIED IN IDE_UNIT
; REGISTER A IS DESTROYED
;
IDE_SELUNIT:
	LD	A,(IDE_UNIT)		; GET UNIT
	CP	IDE_UNITCNT		; CHECK VALIDITY (EXCEED UNIT COUNT?)
	JP	NC,IDE_INVUNIT		; HANDLE INVALID UNIT
;
#IF (IDEMODE == IDEMODE_DIDE)
	; SELECT PRIMARY/SECONDARY INTERFACE FOR DIDE HARDWARE
#ENDIF
;
	; DETERMINE AND SAVE DRIVE/HEAD VALUE FOR SELECTED UNIT
	PUSH	HL			; SAVE HL
	LD	A,(IDE_UNIT)		; GET CURRENT UNIT
	AND	$01			; LS BIT DETERMINES MASTER/SLAVE
	LD	HL,IDE_DRVSEL
	CALL	ADDHLA
	LD	A,(HL)			; LOAD DRIVE/HEAD VALUE
	POP	HL			; RECOVER HL
	LD	(IDE_DRVHD),A		; SAVE IT
;
	XOR	A			; SIGNAL SUCCESS
	RET				; AND DONE
;
;
;
IDE_PROBE:
#IF (IDETRACE >= 3)
	CALL	IDE_PRTPREFIX
	PRTS(" PROBE$")			; LABEL FOR IO ADDRESS
#ENDIF
;
	LD	A,(IDE_DRVHD)
	OUT	(IDE_IO_DRVHD),A
	DCALL	PC_SPACE
	DCALL	PRTHEXBYTE
	
	CALL	DELAY			; DELAY ~16US
;
	DCALL	IDE_REGDUMP
;
	;JR	IDE_PROBE1		; *DEBUG*
;
IDE_PROBE0:
	CALL	IDE_WAITBSY		; WAIT FOR BUSY TO CLEAR
	JP	NZ,IDE_NOMEDIA		; CONVERT TIMEOUT TO NO MEDIA AND RETURN
;
	DCALL	IDE_REGDUMP
;
	; CHECK STATUS
	IN	A,(IDE_IO_STAT)		; GET STATUS
	DCALL	PC_SPACE
	DCALL	PRTHEXBYTE		; IF DEBUG, PRINT STATUS
	OR	A			; SET FLAGS TO TEST FOR ZERO
	JP	Z,IDE_NOMEDIA
;
	; CHECK SIGNATURE
	DCALL	PC_SPACE
	IN	A,(IDE_IO_COUNT)
	DCALL	PRTHEXBYTE
	CP	$01
	JP	NZ,IDE_NOMEDIA
	DCALL	PC_SPACE
	IN	A,(IDE_IO_SECT)
	DCALL	PRTHEXBYTE
	CP	$01
	JP	NZ,IDE_NOMEDIA
	DCALL	PC_SPACE
	IN	A,(IDE_IO_CYLLO)
	DCALL	PRTHEXBYTE
	CP	$00
	JP	NZ,IDE_NOMEDIA
	DCALL	PC_SPACE
	IN	A,(IDE_IO_CYLHI)
	DCALL	PRTHEXBYTE
	CP	$00
	JP	NZ,IDE_NOMEDIA
;
IDE_PROBE1:
	; SIGNATURE MATCHES ATA DEVICE, RECORD TYPE AND RETURN SUCCESS
	IDE_DPTR(IDE_TYPE)		; POINT HL TO UNIT TYPE FIELD, A IS TRASHED
	LD	(HL),IDE_TYPEATA	; SET THE DEVICE TYPE
	XOR	A			; SIGNAL SUCCESS
	RET				; DONE, NOTE THAT A=0 AND Z IS SET
;
; (RE)INITIALIZE DEVICE
;
IDE_INITDEV:
;
	IDE_DPTR(IDE_TYPE)		; POINT HL TO UNIT TYPE FIELD, A IS TRASHED
	LD	A,(HL)			; GET THE DEVICE TYPE
	OR	A			; SET FLAGS
	JP	Z,IDE_NOMEDIA		; EXIT SETTING NO MEDIA STATUS
;
	; CLEAR OUT UNIT SPECIFIC DATA, BUT PRESERVE THE EXISTING
	; VALUE OF THE UNIT TYPE WHICH WAS ESTABLISHED BY THE DEVICE
	; PROBES WHEN THE IDE BUS WAS RESET
	PUSH	AF			; SAVE UNIT TYPE VALUE FROM ABOVE
	PUSH	HL			; SAVE UNIT TYPE FIELD POINTER
	IDE_DPTR(0)			; SET HL TO START OF UNIT DATA
	LD	BC,IDE_UDLEN
	XOR	A
	CALL	FILL
	POP	HL			; RECOVER UNIT TYPE FIELD POINTER
	POP	AF			; RECOVER UNIT TYPE VALUE
	LD	(HL),A			; AND PUT IT BACK
;
#IF (IDE8BIT)
	LD	A,IDE_FEAT_ENABLE8BIT	; FEATURE VALUE = ENABLE 8-BIT PIO
#ELSE
	LD	A,IDE_FEAT_DISABLE8BIT	; FEATURE VALUE = DISABLE 8-BIT PIO
#ENDIF

	CALL	IDE_SETFEAT		; SET FEATURE
	RET	NZ			; BAIL OUT ON ERROR
;
	CALL	IDE_IDENTIFY		; EXECUTE IDENTIFY COMMAND
	RET	NZ			; BAIL OUT ON ERROR
;
	LD	DE,HB_WRKBUF		; POINT TO BUFFER
	DCALL	DUMP_BUFFER		; DUMP IT IF DEBUGGING
;
	; DETERMINE IF CF DEVICE
	LD	HL,HB_WRKBUF		; FIRST WORD OF IDENTIFY DATA HAS CF FLAG
	LD	A,$8A			; FIRST BYTE OF MARKER IS $8A
	CP	(HL)			; COMPARE
	JR	NZ,IDE_INITDEV1		; IF NO MATCH, NOT CF
	INC	HL
	LD	A,$84			; SECOND BYTE OF MARKER IS $84
	CP	(HL)			; COMPARE
	JR	NZ,IDE_INITDEV1		; IF NOT MATCH, NOT CF
	IDE_DPTR(IDE_CFFLAG)		; POINT HL TO CF FLAG FIELD
	LD	A,$FF			; SET FLAG VALUE TO NON-ZERO (TRUE)
	LD	(HL),A			; SAVE IT
;
IDE_INITDEV1:
	; GET DEVICE CAPACITY AND SAVE IT
	IDE_DPTR(IDE_CAPACITY)		; POINT HL TO UNIT CAPACITY FIELD
	PUSH	HL			; SAVE POINTER
	LD	HL,HB_WRKBUF		; POINT TO BUFFER START
	LD	A,120			; OFFSET OF SECTOR COUNT
	CALL	ADDHLA			; POINT TO ADDRESS OF SECTOR COUNT
	CALL	LD32			; LOAD IT TO DE:HL
	POP	BC			; RECOVER POINTER TO CAPACITY ENTRY
	CALL	ST32			; SAVE CAPACITY
;
	; RESET CARD STATUS TO 0 (OK)
	IDE_DPTR(IDE_STAT)		; HL := ADR OF STATUS, AF TRASHED
	XOR	A			; A := 0 (STATUS = OK)
	LD	(HL),A			; SAVE IT
;
	RET				; RETURN, A=0, Z SET
;
;
;
IDE_CHKDEVICE:
	IDE_DPTR(IDE_STAT)
	LD	A,(HL)
	OR	A
	RET	Z			; RETURN IF ALL IS WELL
;
	; ATTEMPT TO REINITIALIZE HERE???
	JP	IDE_ERR
	RET
;
;
;
IDE_WAITRDY:
	LD	A,(IDE_TIMEOUT)		; GET TIMEOUT IN 0.05 SECS
	LD	B,A			; PUT IN OUTER LOOP VAR
IDE_WAITRDY1:
	LD	DE,(IDE_TOSCALER)	; CPU SPPED SCALER TO INNER LOOP VAR
IDE_WAITRDY2:
	IN	A,(IDE_IO_STAT)		; READ STATUS
	LD	C,A			; SAVE IT
	AND	%11000000		; ISOLATE BUSY AND RDY BITS
	XOR	%01000000		; WE WANT BUSY(7) TO BE 0 AND RDY(6) TO BE 1
	RET	Z			; ALL SET, RETURN WITH Z SET
	DEC	DE
	LD	A,D
	OR	E
	JR	NZ,IDE_WAITRDY2		; INNER LOOP RETURN
	DJNZ	IDE_WAITRDY1		; OUTER LOOP RETURN
	JP	IDE_RDYTO		; EXIT WITH RDYTO ERR
;
;
;
IDE_WAITDRQ:
	LD	A,(IDE_TIMEOUT)		; GET TIMEOUT IN 0.05 SECS
	LD	B,A			; PUT IN OUTER LOOP VAR
IDE_WAITDRQ1:
	LD	DE,(IDE_TOSCALER)	; CPU SPPED SCALER TO INNER LOOP VAR
IDE_WAITDRQ2:
	IN	A,(IDE_IO_STAT)		; WAIT FOR DRIVE'S 512 BYTE READ BUFFER
	LD	C,A			; SAVE IT
	AND	%10001000		; TO FILL (OR READY TO FILL)
	XOR	%00001000
	RET	Z
 	DEC	DE
	LD	A,D
	OR	E
	JR	NZ,IDE_WAITDRQ2
	DJNZ	IDE_WAITDRQ1
	JP	IDE_DRQTO		; EXIT WITH BUFTO ERR
;
;
;
IDE_WAITBSY:
	LD	A,(IDE_TIMEOUT)		; GET TIMEOUT IN 0.05 SECS
	LD	B,A			; PUT IN OUTER LOOP VAR
IDE_WAITBSY1:
	LD	DE,(IDE_TOSCALER)	; CPU SPPED SCALER TO INNER LOOP VAR
IDE_WAITBSY2:
	IN	A,(IDE_IO_STAT)		; WAIT FOR DRIVE'S 512 BYTE READ BUFFER		; 11TS
	LD	C,A			; SAVE IT					; 4TS
	AND	%10000000		; TO FILL (OR READY TO FILL)			; 7TS
	RET	Z									; 5TS
	DEC	DE									; 6TS
	LD	A,D									; 4TS
	OR	E									; 4TS
	JR	NZ,IDE_WAITBSY2								; 12TS
	DJNZ	IDE_WAITBSY1								; -----
	JP	IDE_BSYTO		; EXIT WITH BSYTO ERR				; 52TS
;
;=============================================================================
; ERROR HANDLING AND DIAGNOSTICS
;=============================================================================
;
; ERROR HANDLERS
;
IDE_INVUNIT:
	LD	A,IDE_STINVUNIT
	JR	IDE_ERR2		; SPECIAL CASE FOR INVALID UNIT
;
IDE_NOMEDIA:
	LD	A,IDE_STNOMEDIA
	JR	IDE_ERR
;
IDE_CMDERR:
	LD	A,IDE_STCMDERR
	JR	IDE_ERR
;
IDE_IOERR:
	LD	A,IDE_STIOERR
	JR	IDE_ERR
;
IDE_RDYTO:
	LD	A,IDE_STRDYTO
	JR	IDE_ERR
;
IDE_DRQTO:
	LD	A,IDE_STDRQTO
	JR	IDE_ERR
;
IDE_BSYTO:
	LD	A,IDE_STBSYTO
	JR	IDE_ERR
;
IDE_ERR:
	PUSH	HL			; IS THIS NEEDED?
	PUSH	AF			; SAVE INCOMING STATUS
	IDE_DPTR(IDE_STAT)		; GET STATUS ADR IN HL, AF TRASHED
	POP	AF			; RESTORE INCOMING STATUS
	LD	(HL),A			; UPDATE STATUS
	POP	HL			; IS THIS NEEDED?
IDE_ERR2:
#IF (IDETRACE >= 2)
	CALL	IDE_PRTSTAT
	CALL	IDE_REGDUMP
#ENDIF
	OR	A			; SET FLAGS
	RET
;
;
;
IDE_PRTERR:
	RET	Z			; DONE IF NO ERRORS
	; FALL THRU TO IDE_PRTSTAT
;
; PRINT STATUS STRING (STATUS NUM IN A)
;
IDE_PRTSTAT:
	PUSH	AF
	PUSH	DE
	PUSH	HL
	OR	A
	LD	DE,IDE_STR_STOK
	JR	Z,IDE_PRTSTAT1
	INC	A
	LD	DE,IDE_STR_STINVUNIT
	JR	Z,IDE_PRTSTAT2		; INVALID UNIT IS SPECIAL CASE
	INC	A
	LD	DE,IDE_STR_STNOMEDIA
	JR	Z,IDE_PRTSTAT1
	INC	A
	LD	DE,IDE_STR_STCMDERR
	JR	Z,IDE_PRTSTAT1
	INC	A
	LD	DE,IDE_STR_STIOERR
	JR	Z,IDE_PRTSTAT1
	INC	A
	LD	DE,IDE_STR_STRDYTO
	JR	Z,IDE_PRTSTAT1
	INC	A
	LD	DE,IDE_STR_STDRQTO
	JR	Z,IDE_PRTSTAT1
	INC	A
	LD	DE,IDE_STR_STBSYTO
	JR	Z,IDE_PRTSTAT1
	LD	DE,IDE_STR_STUNK
IDE_PRTSTAT1:
	CALL	IDE_PRTPREFIX		; PRINT UNIT PREFIX
	JR	IDE_PRTSTAT3
IDE_PRTSTAT2:
	CALL	NEWLINE
	PRTS("IDE:$")			; NO UNIT NUM IN PREFIX FOR INVALID UNIT
IDE_PRTSTAT3:
	CALL	PC_SPACE		; FORMATTING
	CALL	WRITESTR
	POP	HL
	POP	DE
	POP	AF
	RET
;
; PRINT ALL REGISTERS DIRECTLY FROM DEVICE
; DEVICE MUST BE SELECTED PRIOR TO CALL
;
IDE_REGDUMP:
	PUSH	AF
	PUSH	BC
	CALL	PC_SPACE
	CALL	PC_LBKT
	LD	C,IDE_IO_CMD
	LD	B,7
IDE_REGDUMP1:
	IN	A,(C)
	CALL	PRTHEXBYTE
	DEC	C
	DEC	B
	CALL	NZ,PC_SPACE
	JR	NZ,IDE_REGDUMP1
	CALL	PC_RBKT
	POP	BC
	POP	AF
	RET
;
; PRINT DIAGNONSTIC PREFIX
;
IDE_PRTPREFIX:
	PUSH	AF
	CALL	NEWLINE
	PRTS("IDE$")
	LD	A,(IDE_UNIT)
	ADD	A,'0'
	CALL	COUT
	CALL	PC_COLON
	POP	AF
	RET
;
;
;
#IF (DSKYENABLE)
IDE_DSKY:
	LD	HL,DSKY_HEXBUF		; POINT TO DSKY BUFFER
	IN	A,(IDE_IO_DRVHD)	; GET DRIVE/HEAD
	LD	(HL),A			; SAVE IN BUFFER
	INC	HL			; INCREMENT BUFFER POINTER
	IN	A,(IDE_IO_CYLHI)	; GET DRIVE/HEAD
	LD	(HL),A                  ; SAVE IN BUFFER
	INC	HL                      ; INCREMENT BUFFER POINTER
	IN	A,(IDE_IO_CYLLO)	; GET DRIVE/HEAD
	LD	(HL),A                  ; SAVE IN BUFFER
	INC	HL                      ; INCREMENT BUFFER POINTER
	IN	A,(IDE_IO_SECT)		; GET DRIVE/HEAD
	LD	(HL),A                  ; SAVE IN BUFFER
	CALL	DSKY_HEXOUT             ; SEND IT TO DSKY
	RET
#ENDIF
;
;=============================================================================
; STRING DATA
;=============================================================================
;
IDE_STR_STOK		.TEXT	"OK$"
IDE_STR_STINVUNIT	.TEXT	"INVALID UNIT$"
IDE_STR_STNOMEDIA	.TEXT	"NO MEDIA$"
IDE_STR_STCMDERR	.TEXT	"COMMAND ERROR$"
IDE_STR_STIOERR		.TEXT	"IO ERROR$"
IDE_STR_STRDYTO		.TEXT	"READY TIMEOUT$"
IDE_STR_STDRQTO		.TEXT	"DRQ TIMEOUT$"
IDE_STR_STBSYTO		.TEXT	"BUSY TIMEOUT$"
IDE_STR_STUNK		.TEXT	"UNKNOWN ERROR$"
;
IDE_STR_NO		.TEXT	"NO$"
;
;=============================================================================
; DATA STORAGE
;=============================================================================
;
IDE_TIMEOUT	.DB	IDE_TONORM		; WAIT FUNCS TIMEOUT IN TENTHS OF SEC
IDE_TOSCALER	.DW	CPUMHZ * 961		; WAIT FUNCS SCALER FOR CPU SPEED
;
IDE_CMD		.DB	0			; PENDING COMMAND TO PROCESS
IDE_DRVHD	.DB	0			; CURRENT DRIVE/HEAD MASK
;
IDE_UNIT	.DB	0			; ACTIVE UNIT, DEFAULT TO ZERO
IDE_DSKBUF	.DW	0			; ACTIVE DISK BUFFER
;
; UNIT SPECIFIC DATA STORAGE
;
IDE_UDATA	.FILL	IDE_UNITCNT*8,0		; PER UNIT DATA, 8 BYTES
IDE_DLEN	.EQU	$ - IDE_UDATA		; LENGTH OF ENTIRE DATA STORAGE FOR ALL UNITS
IDE_UDLEN	.EQU	IDE_DLEN / IDE_UNITCNT	; LENGTH OF PER UNIT DATA
;
;=============================================================================
; HELPER ROUTINES
;=============================================================================
;
; IMPLEMENTATION FOR MACRO IDE_DPTR
; SET HL TO ADDRESS OF FIELD WITHIN PER UNIT DATA
;   HL := ADR OF IDE_UNITDATA[(IDE_UNIT)][(SP)]
; ENTER WITH TOP-OF-STACK = ADDRESS OF FIELD OFFSET
; AF IS TRASHED
;
IDE_DPTRIMP:
	LD	HL,IDE_UDATA		; POINT TO START OF UNIT DATA ARRAY
	LD	A,(IDE_UNIT)		; GET CURRENT UNIT NUM
	RLCA				; MULTIPLY BY
	RLCA				; ... SIZE OF PER UNIT DATA
	RLCA				; ... (8 BYTES)
	EX	(SP),HL			; GET PTR TO FIELD OFFSET VALUE FROM TOS
	ADD	A,(HL)			; ADD IT TO START OF UNIT DATA IN ACCUM
	INC	HL			; BUMP HL TO NEXT REAL INSTRUCTION
	EX	(SP),HL			; AND PUT IT BACK ON STACK, HL GETS ADR OF START OF DATA
	JP	ADDHLA			; CALC FINAL ADR IN HL AND RETURN
