; ****************************************************************************
; playwav7.s (for TRDOS 386)
; ----------------------------------------------------------------------------
; PLAYWAV7.PRG ! AC'97 (ICH) .WAV PLAYER program by Erdogan TAN
;
; 29/05/2024
;
; [ Last Modification: 31/05/2024 ]
;
; Modified from PLAYWAV6.PRG .wav player program by Erdogan Tan, 27/11/2023
; Modified from PLAYWAV4.COM .wav player program by Erdogan Tan, 19/05/2024
;
; Assembler: NASM version 2.15
;	     nasm playwav7.s -l playwav7.txt -o PLAYWAV7.PRG	
; ----------------------------------------------------------------------------
; Derived from '.wav file player for DOS' Jeff Leyda, Sep 02, 2002

; tuneloop (user mode) version (29/05/2024

; previous version: playwav6.s (27/11/2023)

; CODE

; 14/07/2020
; 31/12/2017
; TRDOS 386 (v2.0) system calls
_ver 	equ 0
_exit 	equ 1
_fork 	equ 2
_read 	equ 3
_write	equ 4
_open	equ 5
_close 	equ 6
_wait 	equ 7
_create	equ 8
_rename	equ 9
_delete	equ 10
_exec	equ 11
_chdir	equ 12
_time 	equ 13
_mkdir 	equ 14
_chmod	equ 15
_rmdir	equ 16
_break	equ 17
_drive	equ 18
_seek	equ 19
_tell 	equ 20
_memory	equ 21
_prompt	equ 22
_path	equ 23
_env	equ 24
_stime	equ 25
_quit	equ 26
_intr	equ 27
_dir	equ 28
_emt 	equ 29
_ldrvt 	equ 30
_video 	equ 31
_audio	equ 32
_timer	equ 33
_sleep	equ 34
_msg    equ 35
_geterr	equ 36
_fpstat	equ 37
_pri	equ 38
_rele	equ 39
_fff	equ 40
_fnf	equ 41
_alloc	equ 42
_dalloc equ 43
_calbac equ 44
_dma	equ 45

%macro sys 1-4
    ; 29/04/2016 - TRDOS 386 (TRDOS v2.0)	
    ; 03/09/2015	
    ; 13/04/2015
    ; Retro UNIX 386 v1 system call.	
    %if %0 >= 2   
        mov ebx, %2
        %if %0 >= 3    
            mov ecx, %3
            %if %0 = 4
               mov edx, %4   
            %endif
        %endif
    %endif
    mov eax, %1
    ;int 30h
    int 40h ; TRDOS 386 (TRDOS v2.0)	   
%endmacro

; TRDOS 386 (and Retro UNIX 386 v1) system call format:
; sys systemcall (eax) <arg1 (ebx)>, <arg2 (ecx)>, <arg3 (edx)>

;BUFFERSIZE	equ	32768	; audio buffer size 
ENDOFFILE       equ     1	; flag for knowing end of file

[BITS 32]

[ORG 0]

	; 29/05/2024
	%include 'ac97.inc' ; 17/02/2017 

_STARTUP:
	; Prints the Credits Text.
	sys	_msg, Credits, 255, 0Bh

	; clear bss
	mov	ecx, bss_end
	mov	edi, bss_start
	sub	ecx, edi
	shr	ecx, 1
	xor	eax, eax
	rep	stosw

	; Detect (& Enable) AC'97 Audio Device
	call	DetectAC97
	jnc     short GetFileName

_dev_not_ready:
	; couldn't find the audio device!
	sys	_msg, noDevMsg, 255, 0Fh
        jmp     Exit

GetFileName:  
	mov	esi, esp
	lodsd
	cmp	eax, 2 ; two arguments 
	       ; (program file name & mod file name)
	jb	pmsg_usage ; nothing to do

	lodsd ; program file name address 
	lodsd ; mod file name address (file to be read)
	mov	esi, eax
	mov	edi, wav_file_name
ScanName:       
	lodsb
	test	al, al
	je	pmsg_usage
	cmp	al, 20h
	je	short ScanName	; scan start of name.
	stosb
	mov	ah, 0FFh
a_0:	
	inc	ah
a_1:
	lodsb
	stosb
	cmp	al, '.'
	je	short a_0	
	and	al, al
	jnz	short a_1

	or	ah, ah		; if period NOT found,
	jnz	short _1 	; then add a .WAV extension.
SetExt:
	dec	edi
	mov	dword [edi], '.WAV'
	mov	byte [edi+4], 0

_1:
	call	write_audio_dev_info 

; open the file
        ; open existing file
        call    openFile ; no error? ok.
        jnc     short _gsr

; file not found!
	sys	_msg, noFileErrMsg, 255, 0Fh
_exit_:
        jmp     Exit

_gsr:  
       	call    getSampleRate		; read the sample rate
                                        ; pass it onto codec.
	; 25/11/2023
	jc	short _exit_		; nothing to do

	mov	[sample_rate], ax
	mov	[stmo], cl
	mov	[bps], dl

	; 26/11/2023
	mov	byte [fbs_shift], 0 ; 0 = stereo and 16 bit 
	dec	cl
	jnz	short _gsr_1 ; stereo
	inc	byte [fbs_shift] ; 1 = mono or 8 bit		
_gsr_1:	
	cmp	dl, 8 
	ja	short _gsr_2 ; 16 bit samples
	inc	byte [fbs_shift] ; 2 = mono and 8 bit
_gsr_2:	
	; 29/05/2024
	call	write_ac97_pci_dev_info

	; 31/05/2024
	; 30/05/2024
	;call	check_vra

	; 30/05/2024
	call	codecConfig		; unmute codec, set rates.
	jc	init_err

	; 25/11/2023
	call	write_VRA_info

	; 01/05/2017
	call	write_wav_file_info

	; 25/11/2023
	; ------------------------------------------

	cmp	byte [VRA], 1
	jb	short chk_sample_rate

playwav_48_khz:	
	;mov	dword [loadfromwavfile], loadFromFile
	;mov	dword [buffersize], 65536
	jmp	PlayNow

chk_sample_rate:
	; set conversion parameters
	; (for 8, 11.025, 16, 22.050, 24, 32 kHZ)
	mov	ax, [sample_rate]
	cmp	ax, 48000
	je	short playwav_48_khz
chk_22khz:
	cmp	ax, 22050
	jne	short chk_11khz
	cmp	byte [bps], 8
	jna	short chk_22khz_1
	mov	ebx, load_22khz_stereo_16_bit
	cmp	byte [stmo], 1 
	jne	short chk_22khz_2
	mov	ebx, load_22khz_mono_16_bit
	jmp	short chk_22khz_2
chk_22khz_1:
	mov	ebx, load_22khz_stereo_8_bit
	cmp	byte [stmo], 1 
	jne	short chk_22khz_2
	mov	ebx, load_22khz_mono_8_bit
chk_22khz_2:
	mov	eax, 7514  ; (442*17)
	mov	edx, 37
	mov	ecx, 17 
	jmp	set_sizes	
chk_11khz:
	cmp	ax, 11025
	jne	short chk_44khz
	cmp	byte [bps], 8
	jna	short chk_11khz_1
	mov	ebx, load_11khz_stereo_16_bit
	cmp	byte [stmo], 1 
	jne	short chk_11khz_2
	mov	ebx, load_11khz_mono_16_bit
	jmp	short chk_11khz_2
chk_11khz_1:
	mov	ebx, load_11khz_stereo_8_bit
	cmp	byte [stmo], 1 
	jne	short chk_11khz_2
	mov	ebx, load_11khz_mono_8_bit
chk_11khz_2:
	mov	eax, 3757  ; (221*17)
	mov	edx, 74
	mov	ecx, 17
	jmp	set_sizes 
chk_44khz:
	cmp	ax, 44100
	jne	short chk_16khz
	cmp	byte [bps], 8
	jna	short chk_44khz_1
	mov	ebx, load_44khz_stereo_16_bit
	cmp	byte [stmo], 1 
	jne	short chk_44khz_2
	mov	ebx, load_44khz_mono_16_bit
	jmp	short chk_44khz_2
chk_44khz_1:
	mov	ebx, load_44khz_stereo_8_bit
	cmp	byte [stmo], 1 
	jne	short chk_44khz_2
	mov	ebx, load_44khz_mono_8_bit
chk_44khz_2:
	mov	eax, 15065 ; (655*23)
	mov	edx, 25
	mov	ecx, 23
	jmp	set_sizes 
chk_16khz:
	cmp	ax, 16000
	jne	short chk_8khz
	cmp	byte [bps], 8
	jna	short chk_16khz_1
	mov	ebx, load_16khz_stereo_16_bit
	cmp	byte [stmo], 1 
	jne	short chk_16khz_2
	mov	ebx, load_16khz_mono_16_bit
	jmp	short chk_16khz_2
chk_16khz_1:
	mov	ebx, load_16khz_stereo_8_bit
	cmp	byte [stmo], 1 
	jne	short chk_16khz_2
	mov	ebx, load_16khz_mono_8_bit
chk_16khz_2:
	mov	eax, 5461
	mov	edx, 3
	mov	ecx, 1
	jmp	set_sizes 
chk_8khz:
	cmp	ax, 8000
	jne	short chk_24khz
	cmp	byte [bps], 8
	jna	short chk_8khz_1
	mov	ebx, load_8khz_stereo_16_bit
	cmp	byte [stmo], 1 
	jne	short chk_8khz_2
	mov	ebx, load_8khz_mono_16_bit
	jmp	short chk_8khz_2
chk_8khz_1:
	mov	ebx, load_8khz_stereo_8_bit
	cmp	byte [stmo], 1 
	jne	short chk_8khz_2
	mov	ebx, load_8khz_mono_8_bit
chk_8khz_2:
	mov	eax, 2730
	mov	edx, 6
	mov	ecx, 1
	jmp	set_sizes 
chk_24khz:
	cmp	ax, 24000
	jne	short chk_32khz
	cmp	byte [bps], 8
	jna	short chk_24khz_1
	mov	ebx, load_24khz_stereo_16_bit
	cmp	byte [stmo], 1 
	jne	short chk_24khz_2
	mov	ebx, load_24khz_mono_16_bit
	jmp	short chk_24khz_2
chk_24khz_1:
	mov	ebx, load_24khz_stereo_8_bit
	cmp	byte [stmo], 1 
	jne	short chk_24khz_2
	mov	ebx, load_24khz_mono_8_bit
chk_24khz_2:
	mov	eax, 8192
	mov	edx, 2
	mov	ecx, 1
	jmp	short set_sizes 
chk_32khz:
	cmp	ax, 32000
	jne	short vra_needed
	cmp	byte [bps], 8
	jna	short chk_32khz_1
	mov	ebx, load_32khz_stereo_16_bit
	cmp	byte [stmo], 1 
	jne	short chk_32khz_2
	mov	ebx, load_32khz_mono_16_bit
	jmp	short chk_32khz_2
chk_32khz_1:
	mov	ebx, load_32khz_stereo_8_bit
	cmp	byte [stmo], 1 
	jne	short chk_32khz_2
	mov	ebx, load_32khz_mono_8_bit
chk_32khz_2:
	mov	eax, 10922
	mov	edx, 3
	mov	ecx, 2
	;jmp	short set_sizes 
set_sizes:
	cmp	byte [stmo], 1
	je	short ss_1
	shl	eax, 1
ss_1:
	cmp	byte [bps], 8
	jna	short ss_2
	; 16 bit samples
	shl	eax, 1
ss_2:
	mov	[loadsize], eax
	mul	edx
	;cmp	ecx, 1
	;je	short ss_3
;ss_3:
	div	ecx
	mov	cl, [fbs_shift]
	shl	eax, cl
	; 26/11/2023
	;shr	eax, 1	; buffer size is 16 bit sample count
	mov	[buffersize], eax ; buffer size in bytes 
	mov	[loadfromwavfile], ebx
	jmp	short PlayNow

vra_needed:
	sys	_msg, msg_no_vra, 255, 07h
	jmp	Exit

	; 26/11/2023
	; 13/11/2023
loadfromwavfile:
	dd	loadFromFile
loadsize:	; read from wav file
	dd	0
buffersize:	; write to DMA buffer
	dd	65536 ; bytes

PlayNow: 

; 26/11/2023
%if 0
	; Allocate Audio Buffer (for user)
	;sys	_audio, 0200h, BUFFERSIZE, audio_buffer
	; 26/11/2023
	sys	_audio, 0200h, [buffersize], audio_buffer
	jnc	short _2

	; 26/11/2023 - temporary
	;sys	_msg, test_1, 255, 0Ch

error_exit:
	sys	_msg, trdos386_err_msg, 255, 0Eh
	jmp	Exit
_2:
	; DIRECT CGA (TEXT MODE) MEMORY ACCESS
	; bl = 0, bh = 4
	; Direct access/map to CGA (Text) memory (0B8000h)

	sys	_video, 0400h
	cmp	eax, 0B8000h
	jne	short error_exit

	; Initialize Audio Device (bh = 3)
	sys	_audio, 0301h, 0, audio_int_handler 
;	jc	short error_exit
_3:

%else
	; 29/05/2024
	; playwav4.asm
_2:	
	call	check4keyboardstop	; flush keyboard buffer
	jc	short _2		; 07/11/2023

 	;call	codecConfig		; unmute codec, set rates.
	; 11/11/2023
	;jc	short init_err
%endif

;
; position file pointer to start in actual wav data
; MUCH improvement should really be done here to check if sample size is
; supported, make sure there are 2 channels, etc.  
;
        ;mov     ah, 42h
        ;mov     al, 0	; from start of file
        ;mov     bx, [FileHandle]
        ;xor     cx, cx
        ;mov     dx, 44	; jump past .wav/riff header
        ;int     21h

	sys	_seek, [FileHandle], 44, 0

	sys	_msg, nextline, 255, 07h ; 01/05/2017

	; 29/05/2024
	; ----
	; DIRECT CGA (TEXT MODE) MEMORY ACCESS
	; bl = 0, bh = 4
	; Direct access/map to CGA (Text) memory (0B8000h)

	sys	_video, 0400h
	cmp	eax, 0B8000h
	jne	short error_exit
	; ----

; play the .wav file. Most of the good stuff is in here.

	call    PlayWav

; close the .wav file and exit.

; 29/05/2024
%if 0
StopPlaying:
	; Stop Playing
	sys	_audio, 0700h
	; Cancel callback service (for user)
	sys	_audio, 0900h
	; Deallocate Audio Buffer (for user)
	sys	_audio, 0A00h
	; Disable Audio Device
	sys	_audio, 0C00h
%endif

Exit:  
        call    closeFile
         
	sys	_exit	; Bye!
here:
	jmp	short here

pmsg_usage:
	sys	_msg, msg_usage, 255, 0Bh
	jmp	short Exit

	; 29/05/2024
init_err:
	sys	_msg, msg_init_err, 255, 0Fh
	jmp	short Exit

	; 29/05/2024
error_exit:
	sys	_msg, msg_error, 255, 0Eh
	jmp	short Exit

	; --------------------------------------------
	
	; 29/05/2024 (TYRDOS 386, playwav7.s)
	; ((Modified from playwav4.asm, ich_wav4.asm))
	; ------------------
;playwav_vra:
PlayWav:
	; create Buffer Descriptor List

	;  Generic Form of Buffer Descriptor
	;  ---------------------------------
	;  63   62    61-48    47-32   31-0
	;  ---  ---  --------  ------- -----
	;  IOC  BUP -reserved- Buffer  Buffer
	;		      Length   Pointer
	;		      [15:0]   [31:0]

	; 29/05/2024
	; Allocate memory block (33 pages)
	sys	_alloc, BDL_BUFFER, 33*4096, 0 ; no upper limit
	jc	short error_exit
	
	;mov	esi, eax

	mov	[_bdl_buffer], eax ; BDL_BUFFER physical address 

	add	eax, 4096	; WAVBUFFER_1 physical address
	mov	ebx, eax
	;mov	[wav_buffer1], eax
	;add	eax, 65536	; WAVBUFFER_2 physical address
	;mov	[wav_buffer2], eax

	mov	edi, BDL_BUFFER
	mov	ecx, 16
_0:
	;mov	eax, WAVBUFFER_1
	mov	eax, ebx	; WAVBUFFER_1 physical address
	stosd

	mov	eax, [buffersize]
	shr	eax, 1 ; buffer size in word
	or	eax, BUP	; tuneloop (without interrupt)
	stosd

	;mov	eax, WAVBUFFER_2
	mov	eax, ebx
	add	eax, 65536	; WAVBUFFER_2 physical address
	stosd

	mov	eax, [buffersize]
	shr	eax, 1 ; buffer size in word
	or	eax, BUP	; tuneloop (without interrupt)
	stosd

	loop	_0

	;push	esi

	; load 64k into buffer 1
	mov	dword [audio_buffer], WAVBUFFER_1
	call	dword [loadfromwavfile]

	; and 64k into buffer 2
	mov	dword [audio_buffer], WAVBUFFER_2
	call	dword [loadfromwavfile]

	;pop	esi
	
	; write NABMBAR+10h with offset of buffer descriptor list

       	;;mov	eax, BDL_BUFFER
        ;mov	eax, esi	; BDL_BUFFER physical address

	mov	eax, [_bdl_buffer] ; BDL_BUFFER physical address

	mov	dx, [NABMBAR]
        add     dx, PO_BDBAR_REG	; set pointer to BDL
	;out	dx, eax 		; write to AC97 controller
	; 29/05/2024
	mov	ebx, eax ; data, dword
	mov	ah, 5	; write port dword
	int	34h

	; 31/05/2024
	; 19/05/2024
	;call	delay1_4ms

        mov	al, 31
	call	setLastValidIndex

	; 31/05/2024
	; 19/05/2024
	;call	delay1_4ms

	; 17/02/2017
        mov	dx, [NABMBAR]
        add	dx, PO_CR_REG		; PCM out Control Register
        ;mov	al, IOCE + RPBM	; Enable 'Interrupt On Completion' + run
	;			; (LVBI interrupt will not be enabled)
	; 06/11/2023 (TUNELOOP version, without interrupt)
	mov	al, RPBM
	;out	dx, al			; Start bus master operation.
	; 29/05/2024
	; al = data, byte
	mov	ah, 1 ; write port, byte
	int	34h

	; 19/05/2024
	; 06/11/2023
	;call	delay1_4ms	; 31/05/2024
	;call	delay1_4ms
	;call	delay1_4ms
	;call	delay1_4ms

; while DMA engine is running, examine current index and wait until it hits 1
; as soon as it's 1, we need to refresh the data in wavbuffer1 with another
; 64k. Likewise when it's playing buffer 2, refresh buffer 1 and repeat.

; 18/11/2023
; 08/11/2023
; 07/11/2023

tuneLoop:
	; 18/11/2023 (ich_wav4.asm)
	; 08/11/2023
	; 06/11/2023
	mov	al, '1'
	call	tL0
tL1:
	call	updateLVI	; /set LVI != CIV/
	jz	short _exitt_	; 08/11/2023
	call	check4keyboardstop
	jc	short _exitt_
	call	getCurrentIndex
	test	al, BIT0
	jz	short tL1	; loop if buffer 2 is not playing

	; 29/05/2024
	; load buffer 1
	mov	dword [audio_buffer], WAVBUFFER_1
	call	dword [loadfromwavfile]
	jc	short _exitt_	; end of file

	mov	al, '2'
	call	tL0
tL2:
	call    updateLVI
	jz	short _exitt_	; 08/11/2023
	call    check4keyboardstop
	jc	short _exitt_
	call    getCurrentIndex
	test	al, BIT0
	jnz	short tL2	; loop if buffer 1 is not playing

	; 29/05/2024
	; load buffer 2
	mov	dword [audio_buffer], WAVBUFFER_2
	call	dword [loadfromwavfile]
	jnc	short tuneLoop
_exitt_:
	mov	dx, [NABMBAR]		
	add	dx, PO_CR_REG	; PCM out Control Register
	mov	al, 0
	;out	dx, al		; stop player
	; 29/05/2024
	; al = data, byte
	mov	ah, 1  ; write port, byte
	int	34h	

	; 29/05/2024
	mov	al, '0'

	;add	al, '0'
	;call	tL0
	;
	;retn
	; 06/11/2023
	;jmp	short tL0
	;retn

	; 06/11/2023
tL0:
	; 29/05/2024 (TRDOS 386)
	; 08/11/2023
	; 05/11/2023
	; 17/02/2017 - Buffer switch test (temporary)
	; 06/11/2023
	; al = buffer indicator ('1', '2' or '0' -stop- )
	
	mov	ebx, 0B8000h ; video display page address
	mov	ah, 4Eh
	mov	[ebx], ax ; show current play buffer (1, 2)
	retn

	; ------------------

; 29/05/2024
%if 0
	; 25/11/2023
DetectAC97:
	; Detect (BH=1) AC'97 (BL=2) Audio Device
        sys	_audio, 0102h
	jc	short DetectAC97_retn

	; 25/11/2023
	; Get AC'97 Codec info
	; (Function 14, sub function 1)
	sys	_audio, 0E01h
	; Save Variable Rate Audio support bit
	and	al, 1
	mov	[VRA], al

DetectAC97_retn:
	retn
%else
	; 29/05/2024
DetectAC97:
DetectICH:
	; 22/11/2023
	; 19/11/2023
	; 01/11/2023 - TRDOS 386 Kernel v2.0.7
	;; 10/06/2017
	;; 05/06/2017
	;; 29/05/2017
	;; 28/05/2017

	; 19/11/2023
	mov	esi, valid_ids	; address of Valid ICH (AC97) Device IDs
	mov	ecx, valid_id_count
pfd_1:
	lodsd
	call	pciFindDevice
	jnc	short d_ac97_1
	loop	pfd_1

	;stc
	retn

d_ac97_1:
	; eax = BUS/DEV/FN
	;	00000000BBBBBBBBDDDDDFFF00000000
	; edx = DEV/VENDOR
	;	DDDDDDDDDDDDDDDDVVVVVVVVVVVVVVVV

	; playwav4.asm - 19/05/2024

	mov	[bus_dev_fn], eax
	mov	[dev_vendor], edx

	; get ICH base address regs for mixer and bus master

        mov     al, NAMBAR_REG
        call    pciRegRead16			; read PCI registers 10-11
        ;and    dx, IO_ADDR_MASK 		; mask off BIT0
	; 19/05/2024
	and	dl, 0FEh

        mov     [NAMBAR], dx			; save audio mixer base addr

	mov     al, NABMBAR_REG
        call    pciRegRead16
        ;and    dx, IO_ADDR_MASK
	; 19/05/2024
	and	dl, 0C0h

        mov     [NABMBAR], dx			; save bus master base addr

	mov	al, AC97_INT_LINE ; Interrupt line register (3Ch)
	call	pciRegRead8 ; 17/02/2017

	mov     [ac97_int_ln_reg], dl

	;clc

	retn
%endif

;open or create file
;
;input: ds:dx-->filename (asciiz)
;       al=file Mode (create or open)
;output: none  cs:[FileHandle] filled
;
openFile:
	;mov	ah, 3Bh	; start with a mode
	;add	ah, al	; add in create or open mode
	;xor	ecx, ecx
	;int	21h
	;jc	short _of1
	;;mov	[cs:FileHandle], ax

	sys	_open, wav_file_name, 0
	jc	short _of1

	mov	[FileHandle], eax
_of1:
	retn

; close the currently open file
; input: none, uses cs:[FileHandle]
closeFile:
	cmp	dword [FileHandle], -1
	je	short _cf1
	;mov    bx, [FileHandle]  
	;mov    ax, 3E00h
        ;int    21h              ;close file

	sys	_close, [FileHandle]
	mov 	dword [FileHandle], -1
_cf1:
	retn

getSampleRate:
	
; reads the sample rate from the .wav file.
; entry: none - assumes file is already open
; exit: ax = sample rate (11025, 22050, 44100, 48000)
;	cx = number of channels (mono=1, stereo=2)
;	dx = bits per sample (8, 16)

	push    ebx

        ;mov	ah, 42h
        ;mov	al, 0	; from start of file
        ;mov	bx, [FileHandle]
        ;xor	ecx, ecx
        ;mov	dx, 08h	; "WAVE"
        ;int	21h
	
	sys	_seek, [FileHandle], 8, 0

        ;mov	dx, smpRBuff
        ;mov	cx, 28	; 28 bytes
	;mov	ah, 3fh
        ;int	21h

	sys	_read, [FileHandle], smpRBuff, 28

	cmp	dword [smpRBuff], 'WAVE'
	jne	short gsr_stc

	cmp	word [smpRBuff+12], 1	; Offset 20, must be 1 (= PCM)
	jne	short gsr_stc

	mov	cx, [smpRBuff+14]	; return num of channels in CX
        mov     ax, [smpRBuff+16]	; return sample rate in AX
	mov	dx, [smpRBuff+26]	; return bits per sample value in DX
gsr_retn:
        pop     ebx
        retn
gsr_stc:
	stc
	jmp	short gsr_retn

; 29/05/2024
%if 0
audio_int_handler:
	; 18/08/2020 (14/10/2020, 'wavplay2.s')

	;mov	byte [srb], 1 ; interrupt (or signal response byte)
	
	;cmp	byte [cbs_busy], 1
	;jnb	short _callback_bsy_retn
	
	;mov	byte [cbs_busy], 1

	mov	al, [half_buff]

	cmp	al, 1
	jb	short _callback_retn

	; 18/08/2020
	mov	byte [srb], 1

	xor	byte [half_buff], 3 ; 2->1, 1->2

	add	al, '0'
tL0:	; 26/11/2023
	mov	ah, 4Eh
	mov	ebx, 0B8000h ; video display page address
	mov	[ebx], ax ; show playing buffer (1, 2)
_callback_retn:
	;mov	byte [cbs_busy], 0
_callback_bsy_retn:
	sys	_rele ; return from callback service 
	; we must not come here !
	sys	_exit
%endif
	
loadFromFile:
	; 26/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff_0		; no
	stc
	retn
lff_0:
	; 13/06/2017
	;mov	edx, BUFFERSIZE
	; 26/11/2023
	;mov	edi, audio_buffer
	; 29/05/2024
	mov	edi, [audio_buffer]
	mov	edx, [buffersize]	; bytes
	mov	cl, [fbs_shift]   
	and	cl, cl
	jz	short lff_1 ; stereo, 16 bit

	; fbs_shift =
	;	2 for mono and 8 bit sample (multiplier = 4)
	;	1 for mono or 8 bit sample (multiplier = 2)
	shr	edx, cl
	;inc	edx

	mov     esi, temp_buffer
	jmp	short lff_2
lff_1:
	;;mov	esi, audio_buffer
	; 29/05/2024
	;mov	esi, [audio_buffer]
	mov	esi, edi ; audio_buffer
lff_2:
	; 17/03/2017
	; esi = buffer address
	; edx = buffer size
 
	; 26/11/2023
	; load file into memory
	sys 	_read, [FileHandle], esi
	mov	ecx, edx
	jc	short padfill ; error !

	and	eax, eax
	jz	short padfill
lff_3:
	; 26/11/2023
	mov	bl, [fbs_shift]
	and	bl, bl
	jz	short lff_11

	sub	ecx, eax
	mov	ebp, ecx

	;mov	esi, temp_buffer
	;mov	edi, audio_buffer
	mov	ecx, eax   ; byte count

	cmp	byte [bps], 8 ; bits per sample (8 or 16)
	jne	short lff_6 ; 16 bit samples
	; 8 bit samples
	dec	bl  ; shift count, 1 = stereo, 2 = mono
	jz	short lff_5 ; 8 bit, stereo
lff_4:
	; mono & 8 bit
	lodsb
	sub	al, 80h ; 08/11/2023
	shl	eax, 8 ; convert 8 bit sample to 16 bit sample
	stosw	; left channel
	stosw	; right channel
	loop	lff_4
	jmp	short lff_8
lff_5:
	; stereo & 8 bit
	lodsb
	sub	al, 80h ; 08/11/2023
	shl	eax, 8 ; convert 8 bit sample to 16 bit sample
	stosw
	loop	lff_5			
	jmp	short lff_8
lff_6:
	shr	ecx, 1 ; word count
lff_7:
	lodsw
	stosw	; left channel
	stosw	; right channel
	loop	lff_7
lff_8:
	; 27/11/2023
	clc
	mov	ecx, ebp
	jecxz	endLFF_retn
	
padfill:
	cmp 	byte [bps], 16
	je	short lff_10
	; Minimum Value = 0
        xor     al, al
	rep	stosb
lff_9:
        or	byte [flags], ENDOFFILE	; end of file flag
endLFF_retn:
        retn
lff_10:
	xor	eax, eax
	; Minimum value = 8000h (-32768)
	shr	ecx, 1 
	mov	ah, 80h ; ax = -32768
	rep	stosw
	jmp	short lff_9

lff_11:
	; 16 bit stereo
	; ecx = buffer size
	; eax = read count
	sub	ecx, eax
	jna	short endLFF_retn
	add	edi, eax  ; audio_buffer + eax
	jmp	short lff_10 ; padfill

error_exit_2:
	; 26/11/2023 - temporary
	;sys	_msg, test_2, 255, 0Ch
	jmp	error_exit
	
	; 26/11/2023 - temporary
;test_1:
;	db 13, 10, 'Test 1', 13,10, 0
;test_2:
;	db 13, 10, 'Test 2', 13,10, 0
	
; 29/05/2024
%if 0

PlayWav:
	; 26/11/2023
	; 18/08/2020 (27/07/2020, 'wavplay2.s')
	; 13/06/2017
	; Convert 8 bit samples to 16 bit samples
	; and convert mono samples to stereo samples

	; 26/11/2023
	; load 32768 bytes into audio buffer
	;mov	edi, audio_buffer
	;;mov	edx, BUFFERSIZE
	; 26/11/2023
	;mov	edx, [buffersize]
	;call	loadFromFile
	; 26/11/2023
	call	dword [loadfromwavfile]
	jc	short error_exit_2
	mov	byte [half_buff], 1 ; (DMA) Buffer 1

	; 18/08/2020 (27/07/2020, 'wavplay2.s')
	test    byte [flags], ENDOFFILE  ; end of file
	jnz	short _6 ; yes
			 ; bypass filling dma half buffer 2

	; bh = 16 : update (current, first) dma half buffer
	; bl = 0  : then switch to the next (second) half buffer
	sys	_audio, 1000h

	; 18/08/2020
	; [audio_flag] = 1 (in TRDOS 386 kernel)

	; audio_buffer must be filled again after above system call 
	; (Because audio interrupt will be generated by AC97 hardware
	; at the end of the first half of dma buffer.. so, 
	; the second half must be ready. 'sound_play' will use it.)

	; 26/11/2023
	;mov	edi, audio_buffer
	;;mov	edx, BUFFERSIZE
	; 26/11/2023
	;mov	edx, [buffersize]
	;call	loadFromFile
	; 26/11/2023
	call	dword [loadfromwavfile]
	;jc	short p_return
_6:
	; Set Master Volume Level (BL=0 or 80h)
	; 	for next playing (BL>=80h)
	;sys	_audio, 0B80h, 1D1Dh
	sys	_audio, 0B00h, 1D1Dh

	; 18/08/2020
	;mov	byte [volume_level], 1Dh
	mov	[volume_level], cl

	; Start	to play
	mov	al, [bps]
	shr	al, 4 ; 8 -> 0, 16 -> 1
	shl	al, 1 ; 16 -> 2, 8 -> 0
	mov	bl, [stmo]
	dec	bl
	or	bl, al
	mov	cx, [sample_rate] 
	mov	bh, 4 ; start to play	
	sys	_audio

	;mov	ebx, 0B8000h ; video display page address
	;mov	ah, 4Eh
	;mov	al, [half_buffer]
	;mov	[ebx], ax ; show playing buffer (1, 2)

	; 18/08/2020 (27/07/2020, 'wavplay2.s')
	; Here..
	; If byte [flags] <> ENDOFFILE ...
	; user's audio_buffer has been copied to dma half buffer 2

	; [audio_flag] = 0 (in TRDOS 386 kernel)

	; audio_buffer must be filled again after above system call 
	; (Because, audio interrupt will be generated by VT8237R
	; at the end of the first half of dma buffer.. so, 
	; the 2nd half of dma buffer is ready but the 1st half
	; must be filled again.)

	; 18/08/2020
	test    byte [flags], ENDOFFILE  ; end of file
	jnz	short p_loop ; yes

	; 18/08/2020
	; load 32768 bytes into audio buffer
	;; (for the second half of DMA buffer)
	; 27/11/2023
	; 20/05/2017
	;mov	edi, audio_buffer
	;mov	edx, BUFFERSIZE
	; 26/11/2023
	;mov	edx, [buffersize]
	;call	loadFromFile
	; 26/11/2023
	call	dword [loadfromwavfile]
	;jc	short p_return
	;mov	byte [half_buff], 2 ; (DMA) Buffer 2

	; we need to wait for 'SRB' (audio interrupt)
	; (we can not return from 'PlayWav' here 
	;  even if we have got an error from file reading)
	; ((!!current audio data must be played!!))

	; 18/08/2020
	;mov	byte [srb], 1

p_loop:
	;mov	ah, 1		; any key pressed?
	;int	32h		; no, Loop.
	;jz	short q_loop
	;
	;mov	ah, 0		; flush key buffer...
	;int	32h

	; 18/08/2020 (14/10/2017, 'wavplay2.s')
	cmp	byte [srb], 0
	jna	short q_loop
	mov	byte [srb], 0
	; 27/11/2023
	;mov	edi, audio_buffer
	;mov	edx, BUFFERSIZE
	; 26/11/2023
	;mov	edx, [buffersize]
	;call	loadFromFile
	; 26/11/2023
	call	dword [loadfromwavfile]
	jc	short p_return
q_loop:
	mov     ah, 1		; any key pressed?
	int     32h		; no, Loop.
	jz	short p_loop

	mov     ah, 0		; flush key buffer...
	int     32h
	
	cmp	al, '+' ; increase sound volume
	je	short inc_volume_level
	cmp	al, '-'
	je	short dec_volume_level

p_return:
	mov	byte [half_buff], 0
	retn

	; 18/08/2020 (14/10/2017, 'wavplay2.s')
inc_volume_level:
	mov	cl, [volume_level]
	cmp	cl, 1Fh ; 31
	jnb	short q_loop
	inc	cl
change_volume_level:
	mov	[volume_level], cl
	mov	ch, cl
	; Set Master Volume Level
	sys	_audio, 0B00h
	jmp	short p_loop
dec_volume_level:
	mov	cl, [volume_level]
	cmp	cl, 1 ; 1
	jna	short p_loop
	dec	cl
	jmp	short change_volume_level
%endif

write_audio_dev_info:
	; EBX = Message address
	; ECX = Max. message length (or stop on ZERO character)
	;	(1 to 255)
	; DL  = Message color (07h = light gray, 0Fh = white) 
     	sys 	_msg, msgAudioCardInfo, 255, 0Fh
	retn

write_wav_file_info:
	; 01/05/2017
	sys	_msg, msgWavFileName, 255, 0Fh
	sys	_msg, wav_file_name, 255, 0Fh

write_sample_rate:
	; 01/05/2017
	mov	ax, [sample_rate]
	; ax = sample rate (hertz)
	xor	edx, edx
	mov	cx, 10
	div	cx
	add	[msgHertz+4], dl
	sub	edx, edx
	div	cx
	add	[msgHertz+3], dl
	sub	edx, edx
	div	cx
	add	[msgHertz+2], dl
	sub	edx, edx
	div	cx
	add	[msgHertz+1], dl
	add	[msgHertz], al
	
	sys	_msg, msgSampleRate, 255, 0Fh

	mov	esi, msg16Bits
	cmp	byte [bps], 16
	je	short wsr_1
	mov	esi, msg8Bits
wsr_1:
	sys	_msg, esi, 255, 0Fh

	mov	esi, msgMono
	cmp	byte [stmo], 1
	je	short wsr_2
	mov	esi, msgStereo		
wsr_2:
	sys	_msg, esi, 255, 0Fh
        retn

write_ac97_pci_dev_info:
	; 06/06/2017
	; 03/06/2017
	; BUS/DEV/FN
	;	00000000BBBBBBBBDDDDDFFF00000000
	; DEV/VENDOR
	;	DDDDDDDDDDDDDDDDVVVVVVVVVVVVVVVV

	;mov	esi, [dev_vendor]
	;mov	eax, esi
	; 31/05/2024
	mov	eax, [dev_vendor]
	movzx	ebx, al
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [ebx+hex_chars]
	mov	[msgVendorId+3], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [ebx+hex_chars]
	mov	[msgVendorId+2], al
	mov	bl, ah
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [ebx+hex_chars]
	mov	[msgVendorId+1], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [ebx+hex_chars]
	mov	[msgVendorId], al
	shr	eax, 16
	mov	bl, al
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [ebx+hex_chars]
	mov	[msgDevId+3], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [ebx+hex_chars]
	mov	[msgDevId+2], al
	mov	bl, ah
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [ebx+hex_chars]
	mov	[msgDevId+1], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [ebx+hex_chars]
	mov	[msgDevId], al

	;mov	esi, [bus_dev_fn]
	;shr	esi, 8
	;mov	ax, si
	; 31/05/2024
	mov	eax, [bus_dev_fn]
	shr	eax, 8
	mov	bl, al
	mov	dl, bl
	and	bl, 7 ; bit 0,1,2
	mov	al, [ebx+hex_chars]
	mov	[msgFncNo+1], al
	mov	bl, dl
	shr	bl, 3
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [ebx+hex_chars]
	mov	[msgDevNo+1], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [ebx+hex_chars]
	mov	[msgDevNo], al
	mov	bl, ah
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [ebx+hex_chars]
	mov	[msgBusNo+1], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [ebx+hex_chars]
	mov	[msgBusNo], al

	;mov	ax, [ac97_NamBar]
	mov	ax, [NAMBAR]	; 29/05/2024
	mov	bl, al
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [ebx+hex_chars]
	mov	[msgNamBar+3], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [ebx+hex_chars]
	mov	[msgNamBar+2], al
	mov	bl, ah
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [ebx+hex_chars]
	mov	[msgNamBar+1], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [ebx+hex_chars]
	mov	[msgNamBar], al

	;mov	ax, [ac97_NabmBar]
	mov	ax, [NABMBAR]	; 29/05/2024
	mov	bl, al
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [ebx+hex_chars]
	mov	[msgNabmBar+3], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [ebx+hex_chars]
	mov	[msgNabmBar+2], al
	mov	bl, ah
	mov	dl, bl
	and	bl, 0Fh
	mov	al, [ebx+hex_chars]
	mov	[msgNabmBar+1], al
	mov	bl, dl
	shr	bl, 4
	mov	al, [ebx+hex_chars]
	mov	[msgNabmBar], al

	;xor	ah, ah
	xor	eax, eax ; 31/05/2024
	mov	al, [ac97_int_ln_reg]
	mov	cl, 10
	div	cl
	add	[msgIRQ], ax
	and	al, al
	jnz	short _w_ac97imsg_
	mov	al, [msgIRQ+1]
	mov	ah, ' '
	mov	[msgIRQ], ax
_w_ac97imsg_:
	sys	_msg, msgAC97Info, 255, 07h

        retn

write_VRA_info:
	; 25/11/2023
	sys	_msg, msgVRAheader, 255, 07h
	cmp	byte [VRA], 0
	jna	short _w_VRAi_no
_w_VRAi_yes:
	sys	_msg, msgVRAyes, 255, 07h
	retn
_w_VRAi_no:
	sys	_msg, msgVRAno, 255, 07h
	retn

; 26/11/2023
; 25/11/2023 - playwav6.s (32 bit registers, TRDOS 386 adaption)
; 15/11/2023 - PLAYWAV5.COM, ich_wav5.asm
; 14/11/2023
; 13/11/2023 - Erdogan Tan - (VRA, sample rate conversion)
; --------------------------------------------------------

;;Note:	At the end of every buffer load,
;;	during buffer switch/swap, there will be discontinuity
;;	between the last converted sample and the 1st sample
;;	of the next buffer.
;;	(like as a dot noises vaguely between normal sound samples)
;;	-To avoid this defect, the 1st sample of
;;	the next buffer may be read from the wav file but
;;	the file pointer would need to be set to 1 sample back
;;	again via seek system call. Time comsumption problem! -
;;
;;	Erdogan Tan - 15/11/2023
;;
;;	((If entire wav data would be loaded at once.. conversion
;;	defect/noise would disappear.. but for DOS, to keep
;;	64KB buffer limit is important also it is important
;;	for running under 1MB barrier without HIMEM.SYS or DPMI.
;;	I have tested this program by using 2-30MB wav files.))
;;
;;	Test Computer:	ASUS desktop/mainboard, M2N4-SLI, 2010.
;;			AMD Athlon 64 X2 2200 MHZ CPU.
;;		       	NFORCE4 (CK804) AC97 audio hardware.
;;			Realtek ALC850 codec.
;;		       	Retro DOS v4.2 (MSDOS 6.22) operating system.

load_8khz_mono_8_bit:
	; 15/11/2023
	; 14/11/2023
	; 13/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff8m_0		; no
	stc
	retn

lff8m_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jnc	short lff8m_6
	jmp	lff8m_5  ; error !

lff8m_6:
	;mov	edi, audio_buffer
	; 29/05/2024
	mov	edi, [audio_buffer]
	and	eax, eax
	jz	lff8_eof

	mov	ecx, eax		; byte count
lff8m_1:
	lodsb
	mov	[previous_val], al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (left channel)
	stosw		; original sample (right channel)
	;xor	eax, eax
	mov	al, 80h
	dec	ecx
	jz	short lff8m_2
	mov	al, [esi]
lff8m_2:
	;mov	[next_val], ax
	mov	bh, al	; [next_val]
	mov	ah, [previous_val]
	add	al, ah	; [previous_val]
	rcr	al, 1
	mov	dl, al	; this is interpolated middle (3th) sample
	add	al, ah	; [previous_val]
	rcr	al, 1	
	mov	bl, al 	; this is temporary interpolation value	
	add	al, ah	; [previous_val]
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	
	stosw		; this is 1st interpolated sample (L)
	stosw		; this is 1st interpolated sample (R)
	mov	al, bl
	add	al, dl
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is 2nd interpolated sample (L)
	stosw		; this is 2nd interpolated sample (R)
	mov	al, dl
	sub	al, 80h
	shl	ax, 8
	stosw		; this is middle (3th) interpolated sample (L)
	stosw		; this is middle (3th) interpolated sample (R)
	;mov	al, [next_val]
	mov	al, bh
	add	al, dl
	rcr	al, 1
	mov	bl, al	; this is temporary interpolation value
	add	al, dl
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is 4th interpolated sample (L)
	stosw		; this is 4th interpolated sample (R)
	;mov	al, [next_val]
	mov	al, bh
	add	al, bl
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is 5th interpolated sample (L)
	stosw		; this is 5th interpolated sample (R)
	; 8 kHZ mono to 48 kHZ stereo conversion of the sample is OK
	or	ecx, ecx
	jnz	short lff8m_1

	; --------------

lff8s_3:
lff8m_3:
lff8s2_3:
lff8m2_3:
lff16s_3:
lff16m_3:
lff16s2_3:
lff16m2_3:
lff24_3:
lff32_3:
lff44_3:
lff22_3:
lff11_3:
	; 31/05/2024 (BugFix)
	mov	ecx, [buffersize] ; buffer size in bytes
	;shl	ecx, 1 ; Bug !
	sub	ecx, edi
	jna	short lff8m_4
	;inc	ecx
	shr	ecx, 2
	xor	eax, eax ; fill (remain part of) buffer with zeros	
	rep	stosd
lff8m_4:
	; 31/05/2024 (BugFix)
	; cf=1 ; Bug !
	clc
	retn

lff8_eof:
lff16_eof:
lff24_eof:
lff32_eof:
lff44_eof:
lff22_eof:
lff11_eof:
	; 15/11/2023
	mov	byte [flags], ENDOFFILE
	jmp	short lff8m_3

lff8s_5:
lff8m_5:
lff8s2_5:
lff8m2_5:
lff16s_5:
lff16m_5:
lff16s2_5:
lff16m2_5:
lff24_5:
lff32_5:
lff44_5:
lff22_5:
lff11_5:
	mov	al, '!'  ; error
	call	tL0
	
	;jmp	short lff8m_3
	; 15/11/2023
	jmp	lff8_eof

	; --------------

load_8khz_stereo_8_bit:
	; 15/11/2023
	; 14/11/2023
	; 13/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff8s_0		; no
	stc
	retn

lff8s_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff8s_5 ; error !

	;mov	edi, audio_buffer
	; 29/05/2024
	mov	edi, [audio_buffer]
	
	shr	eax, 1
	jz	short lff8_eof

	mov	ecx, eax	; word count
lff8s_1:
	lodsb
	mov	[previous_val_l], al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (L)
	lodsb
	mov	[previous_val_r], al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (R)

	;xor	eax, eax
	mov	ax, 8080h
	dec	ecx
	jz	short lff8s_2
		; convert 8 bit sample to 16 bit sample
	mov	ax, [esi]
lff8s_2:
	mov	[next_val_l], al
	mov	[next_val_r], ah
	mov	ah, [previous_val_l]
	add	al, ah
	rcr	al, 1
	mov	dl, al	; this is interpolated middle (3th) sample (L)
	add	al, ah
	rcr	al, 1	
	mov	bl, al	; this is temporary interpolation value (L)
	add	al, ah
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is 1st interpolated sample (L)
	mov	al, [next_val_r]
	mov	ah, [previous_val_r]
	add	al, ah
	rcr	al, 1
	mov	dh, al	; this is interpolated middle (3th) sample (R)
	add	al, ah
	rcr	al, 1
	mov	bh, al	; this is temporary interpolation value (R)
	add	al, ah
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is 1st interpolated sample (R)
	mov	al, bl
	add	al, dl
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is 2nd interpolated sample (L)
	mov	al, bh
	add	al, dh
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw 		; this is 2nd interpolated sample (R)
	mov	al, dl
	sub	al, 80h
	shl	ax, 8
	stosw		; this is middle (3th) interpolated sample (L)
	mov	al, dh
	sub	al, 80h
	shl	ax, 8
	stosw		; this is middle (3th) interpolated sample (R)
	mov	al, [next_val_l]
	add	al, dl
	rcr	al, 1
	mov	bl, al	; this is temporary interpolation value (L)
	add	al, dl
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is 4th interpolated sample (L)
	mov	al, [next_val_r]
	add	al, dh
	rcr	al, 1
	mov	bh, al	; this is temporary interpolation value (R)
	add	al, dh
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is 4th interpolated sample (R)
	mov	al, [next_val_l]
	add	al, bl
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is 5th interpolated sample (L)
	mov	al, [next_val_r]
	add	al, bh
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is 5th interpolated sample (R)
	; 8 kHZ stereo to 48 kHZ stereo conversion of the sample is OK
	jecxz	lff8s_6
	jmp	lff8s_1
lff8s_6:
	jmp	lff8s_3

load_8khz_mono_16_bit:
	; 13/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff8m2_0		; no
	stc
	retn

lff8m2_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	lff8m2_7 ; error !

	;mov	edi, audio_buffer
	; 29/05/2024
	mov	edi, [audio_buffer]
	
	shr	eax, 1
	jnz	short lff8m2_8
	jmp	lff8_eof

lff8m2_8:
	mov	ecx, eax	; word count
lff8m2_1:
	lodsw
	stosw		; original sample (left channel)
	stosw		; original sample (right channel)
	add	ah, 80h	; convert sound level to 0-65535 format
	mov	[previous_val], ax
	xor	eax, eax
	dec	ecx
	jz	short lff8m2_2
	mov	ax, [esi]
lff8m2_2:
	add	ah, 80h ; convert sound level to 0-65535 format
	mov	ebp, eax	; [next_val]
	add	ax, [previous_val]
	rcr	ax, 1
	mov	edx, eax ; this is interpolated middle (3th) sample
	add	ax, [previous_val]
	rcr	ax, 1	; this is temporary interpolation value
	mov	ebx, eax 		
	add	ax, [previous_val]
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; this is 1st interpolated sample (L)
	stosw		; this is 1st interpolated sample (R)
	mov	eax, ebx
	add	ax, dx
	rcr	ax, 1
	sub	ah, 80h
	stosw		; this is 2nd interpolated sample (L)
	stosw		; this is 2nd interpolated sample (R)
	mov	eax, edx
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; this is middle (3th) interpolated sample (L)
	stosw		; this is middle (3th) interpolated sample (R)
	mov	eax, ebp
	add	ax, dx
	rcr	ax, 1
	mov	ebx, eax ; this is temporary interpolation value
	add	ax, dx
	rcr	ax, 1
	sub	ah, 80h
	stosw		; this is 4th interpolated sample (L)
	stosw		; this is 4th interpolated sample (R)
	mov	eax, ebp
	add	ax, bx
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; this is 5th interpolated sample (L)
	stosw		; this is 5th interpolated sample (R)
	; 8 kHZ mono to 48 kHZ stereo conversion of the sample is OK
	or	ecx, ecx
	jnz	lff8m2_1
	jmp	lff8m2_3

lff8m2_7:
lff8s2_7:
	jmp	lff8m2_5  ; error

load_8khz_stereo_16_bit:
	; 16/11/2023
	; 15/11/2023
	; 13/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff8s2_0		; no
	stc
	retn

lff8s2_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff8s2_7 ; error !

	;mov	edi, audio_buffer
	; 29/05/2024
	mov	edi, [audio_buffer]
	
	shr	eax, 2
	jnz	short lff8s2_8
	jmp	lff8_eof

lff8s2_8:
	mov	ecx, eax ; dword count
lff8s2_1:
	lodsw
	stosw		; original sample (L)
	; 15/11/2023
	add	ah, 80h	; convert sound level to 0-65535 format
	mov	[previous_val_l], ax
	lodsw
	stosw		; original sample (R)
	add	ah, 80h	; convert sound level to 0-65535 format
	mov	[previous_val_r], ax
	xor	edx, edx
	xor	eax, eax
	; 16/11/2023
	dec	ecx
	jz	short lff8s2_2
	mov	ax, [esi]
	mov	dx, [esi+2]
lff8s2_2:
	add	ah, 80h	; convert sound level to 0-65535 format
	mov	[next_val_l], ax
	add	dh, 80h	; convert sound level to 0-65535 format
	mov	[next_val_r], dx
	add	ax, [previous_val_l]
	rcr	ax, 1
	mov	edx, eax ; this is interpolated middle (3th) sample (L)
	add	ax, [previous_val_l]
	rcr	ax, 1	
	mov	ebx, eax ; this is temporary interpolation value (L)
	add	ax, [previous_val_l]
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; this is 1st interpolated sample (L)
	mov	ax, [next_val_r]
	add	ax, [previous_val_r]
	rcr	ax, 1
	mov	ebp, eax ; this is interpolated middle (3th) sample (R)
	add	ax, [previous_val_r]
	rcr	ax, 1
	push	eax ; *	; this is temporary interpolation value (R)
	add	ax, [previous_val_r]
	rcr	ax, 1
	sub	ah, 80h
	stosw		; this is 1st interpolated sample (R)
	mov	eax, ebx
	add	ax, dx
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; this is 2nd interpolated sample (L)
	pop	eax ; *
	add	ax, bp
	rcr	ax, 1
	sub	ah, 80h
	stosw 		; this is 2nd interpolated sample (R)
	mov	eax, edx
	sub	ah, 80h
	stosw		; this is middle (3th) interpolated sample (L)
	mov	eax, ebp
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; this is middle (3th) interpolated sample (R)
	mov	ax, [next_val_l]
	add	ax, dx
	rcr	ax, 1
	mov	ebx, eax ; this is temporary interpolation value (L)
	add	ax, dx
	rcr	ax, 1
	sub	ah, 80h
	stosw		; this is 4th interpolated sample (L)
	mov	ax, [next_val_r]
	add	ax, bp
	rcr	ax, 1
	push	eax ; ** ; this is temporary interpolation value (R)
	add	ax, bp
	rcr	ax, 1
	sub	ah, 80h
	stosw		; this is 4th interpolated sample (R)
	mov	ax, [next_val_l]
	add	ax, bx
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; this is 5th interpolated sample (L)
	pop	eax ; **
	add	ax, [next_val_r]
	rcr	ax, 1
	sub	ah, 80h
	stosw		; this is 5th interpolated sample (R)
	; 8 kHZ stereo to 48 kHZ stereo conversion of the sample is OK
	jecxz	lff8_s2_9
	jmp	lff8s2_1
lff8_s2_9:
	jmp	lff8s2_3

; .....................

load_16khz_mono_8_bit:
	; 14/11/2023
	; 13/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff16m_0		; no
	stc
	retn

lff16m_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff16m_7 ; error !

	;mov	edi, audio_buffer
	; 29/05/2024
	mov	edi, [audio_buffer]
	
	and	eax, eax
	jnz	short lff16m_8
	jmp	lff16_eof

lff16m_8:
	mov	ecx, eax		; byte count
lff16m_1:
	lodsb
	;mov	[previous_val], al
	mov	bl, al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (left channel)
	stosw		; original sample (right channel)
	;xor	ax, ax
	; 14/11/22023
	mov	al, 80h
	dec	ecx
	jz	short lff16m_2
	mov	al, [esi]
lff16m_2:
	;mov	[next_val], al
	mov	bh, al
	;add	al, [previous_val]
	add	al, bl
	rcr	al, 1
	mov	dl, al	; this is interpolated middle (temp) sample
	;add	al, [previous_val]
	add	al, bl
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is 1st interpolated sample (L)
	stosw		; this is 1st interpolated sample (R)
	;mov	al, [next_val]
	mov	al, bh
	add	al, dl
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is 2nd interpolated sample (L)
	stosw		; this is 2nd interpolated sample (R)
	
	; 16 kHZ mono to 48 kHZ stereo conversion of the sample is OK
	or	ecx, ecx
	jnz	short lff16m_1
	jmp	lff16m_3

lff16m_7:
lff16s_7:
	jmp	lff16m_5  ; error

load_16khz_stereo_8_bit:
	; 14/11/2023
	; 13/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff16s_0		; no
	stc
	retn

lff16s_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff16s_7 ; error !

	;mov	edi, audio_buffer
	; 29/05/2024
	mov	edi, [audio_buffer]
	
	shr	eax, 1
	jnz	short lff16s_8
	jmp	lff16_eof

lff16s_8:
	mov	ecx, eax	; word count
lff16s_1:
	lodsb
	mov	[previous_val_l], al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (L)
	lodsb
	mov	[previous_val_r], al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (R)

	;xor	eax, eax
	mov	ax, 8080h
	dec	ecx
	jz	short lff16s_2
		; convert 8 bit sample to 16 bit sample
	mov	ax, [esi]
lff16s_2:
	;mov	[next_val_l], al
	;mov	[next_val_r], ah
	mov	ebx, eax
	add	al, [previous_val_l]
	rcr	al, 1
	mov	dl, al	; this is temporary interpolation value (L)
	add	al, [previous_val_l]
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is 1st interpolated sample (L)
	mov	al, bh	; [next_val_r]
	add	al, [previous_val_r]
	rcr	al, 1
	mov	dh, al	; this is temporary interpolation value (R)
	add	al, [previous_val_r]
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is 1st interpolated sample (R)
	mov	al, dl
	add	al, bl	; [next_val_l]
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is 2nd interpolated sample (L)
	mov	al, dh
	add	al, bh	; [next_val_r]
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw 		; this is 2nd interpolated sample (R)
	
	; 16 kHZ stereo to 48 kHZ stereo conversion of the sample is OK
	or	ecx, ecx
	jnz	short lff16s_1
	jmp	lff16s_3

load_16khz_mono_16_bit:
	; 15/11/2023
	; 13/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff16m2_0		; no
	stc
	retn

lff16m2_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff16m2_7 ; error !

	;mov	edi, audio_buffer
	; 29/05/2024
	mov	edi, [audio_buffer]
	
	shr	eax, 1
	jnz	short lff16m2_8
	jmp	lff16_eof

lff16m2_8:
	mov	ecx, eax  ; word count
lff16m2_1:
	lodsw
	stosw		; original sample (left channel)
	stosw		; original sample (right channel)
	add	ah, 80h ; convert sound level 0 to 65535 format
	;mov	[previous_val], ax
	mov	ebx, eax	
	xor	eax, eax
	dec	ecx
	jz	short lff16m2_2
	mov	ax, [esi]
lff16m2_2:
	add	ah, 80h ; convert sound level 0 to 65535 format
	mov	ebp, eax	; [next_val]
	;add	ax, [previous_val]
	add	ax, bx
	rcr	ax, 1
	mov	edx, eax ; this is temporary interpolation value
	;add	ax, [previous_val]
	add	ax, bx
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; this is 1st interpolated sample (L)
	stosw		; this is 1st interpolated sample (R)
	mov	eax, ebp 
	add	ax, dx
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; this is 2nd interpolated sample (L)
	stosw		; this is 2nd interpolated sample (R)
	; 16 kHZ mono to 48 kHZ stereo conversion of the sample is OK
	or	ecx, ecx
	jnz	short lff16m2_1
	jmp	lff16m2_3

lff16m2_7:
lff16s2_7:
	jmp	lff16m2_5  ; error

load_16khz_stereo_16_bit:
	; 16/11/2023
	; 15/11/2023
	; 13/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff16s2_0		; no
	stc
	retn

lff16s2_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff16s2_7 ; error !

	;mov	edi, audio_buffer
	; 29/05/2024
	mov	edi, [audio_buffer]
	
	shr	eax, 2
	jnz	short lff16s2_8
	jmp	lff16_eof

lff16s2_8:
	mov	ecx, eax  ; dword count
lff16s2_1:
	lodsw
	stosw		; original sample (L)
	add	ah, 80h	; convert sound level 0 to 65535 format 
	mov	[previous_val_l], ax
	lodsw
	stosw		; original sample (R)
	add	ah, 80h	; convert sound level 0 to 65535 format 
	mov	[previous_val_r], ax
	xor	edx, edx
	xor	eax, eax
	; 16/11/2023
	dec	ecx
	jz	short lff16s2_2
	mov	ax, [esi]
	mov	dx, [esi+2]
lff16s2_2:
	add	ah, 80h	; convert sound level 0 to 65535 format 
	;mov	[next_val_l], ax
	mov	ebp, eax
	add	dh, 80h	; convert sound level 0 to 65535 format 
	mov	[next_val_r], dx
	add	ax, [previous_val_l]
	rcr	ax, 1
	mov	edx, eax ; this is temporary interpolation value (L)
	add	ax, [previous_val_l]
	rcr	ax, 1
	sub	ah, 80h ; -32768 to +32767 format again
	stosw		; this is 1st interpolated sample (L)
	mov	ax, [next_val_r]
	add	ax, [previous_val_r]
	rcr	ax, 1
	mov	ebx, eax ; this is temporary interpolation value (R)
	add	ax, [previous_val_r]
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; this is 1st interpolated sample (R)
	;mov	ax, [next_val_l]
	mov	eax, ebp
	add	ax, dx
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; this is 2nd interpolated sample (L)
	mov	ax, [next_val_r]
	add	ax, bx
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; this is 2nd interpolated sample (R)
	
	; 16 kHZ stereo to 48 kHZ stereo conversion of the sample is OK
	or	ecx, ecx
	jnz	lff16s2_1
	jmp	lff16s2_3

; .....................

load_24khz_mono_8_bit:
	; 15/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff24m_0		; no
	stc
	retn

lff24m_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff24m_7 ; error !

	;mov	edi, audio_buffer
	; 29/05/2024
	mov	edi, [audio_buffer]
	
	and	eax, eax
	jnz	short lff24m_8
	jmp	lff24_eof

lff24m_8:
	mov	ecx, eax	; byte count
lff24m_1:
	lodsb
	;mov	[previous_val], al
	mov	bl, al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (left channel)
	stosw		; original sample (right channel)
	;xor	eax, eax
	mov	al, 80h
	dec	ecx
	jz	short lff24m_2
	mov	al, [esi]
lff24m_2:
	;;mov	[next_val], al
	;mov	bh, al
	;add	al, [previous_val]
	add	al, bl
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is interpolated sample (L)
	stosw		; this is interpolated sample (R)
	
	; 24 kHZ mono to 48 kHZ stereo conversion of the sample is OK
	or	ecx, ecx
	jnz	short lff24m_1
	jmp	lff24_3

lff24m_7:
lff24s_7:
	jmp	lff24_5  ; error

load_24khz_stereo_8_bit:
	; 15/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff24s_0		; no
	stc
	retn

lff24s_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff24s_7 ; error !

	;mov	edi, audio_buffer
	; 29/05/2024
	mov	edi, [audio_buffer]
	
	shr	eax, 1
	jnz	short lff24s_8
	jmp	lff24_eof

lff24s_8:
	mov	ecx, eax  ; word count
lff24s_1:
	lodsb
	mov	[previous_val_l], al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (L)
	lodsb
	mov	[previous_val_r], al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (R)

	;xor	eax, eax
	mov	ax, 8080h
	dec	ecx
	jz	short lff24s_2
		; convert 8 bit sample to 16 bit sample
	mov	ax, [esi]
lff24s_2:
	;;mov	[next_val_l], al
	;;mov	[next_val_r], ah
	;mov	bx, ax
	mov	bh, ah
	add	al, [previous_val_l]
	rcr	al, 1
	;mov	dl, al
	sub	al, 80h
	shl	ax, 8
	stosw		; this is interpolated sample (L)
	mov	al, bh	; [next_val_r]
	add	al, [previous_val_r]
	rcr	al, 1
	;mov	dh, al
	sub	al, 80h
	shl	ax, 8
	stosw		; this is interpolated sample (R)
		
	; 24 kHZ stereo to 48 kHZ stereo conversion of the sample is OK
	or	ecx, ecx
	jnz	short lff24s_1
	jmp	lff24_3

load_24khz_mono_16_bit:
	; 15/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff24m2_0		; no
	stc
	retn

lff24m2_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff24m2_7 ; error !

	;mov	edi, audio_buffer
	; 29/05/2024
	mov	edi, [audio_buffer]
	
	shr	eax, 1
	jnz	short lff24m2_8
	jmp	lff24_eof

lff24m2_8:
	mov	ecx, eax  ; word count
lff24m2_1:
	lodsw
	stosw		; original sample (left channel)
	stosw		; original sample (right channel)
	add	ah, 80h ; convert sound level 0 to 65535 format
	;mov	[previous_val], ax
	;mov	ebx, eax	
	;xor	eax, eax
	xor	ebx, ebx
	dec	ecx
	jz	short lff24m2_2
	;mov	ax, [esi]
	mov	bx, [esi]
lff24m2_2:
	;add	ah, 80h ; convert sound level 0 to 65535 format
	;mov	ebp, eax	; [next_val]
	;add	ax, [previous_val]
	; ax = [previous_val]
	; bx = [next_val]
	add	ax, bx
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; this is interpolated sample (L)
	stosw		; this is interpolated sample (R)
	; 24 kHZ mono to 48 kHZ stereo conversion of the sample is OK
	or	ecx, ecx
	jnz	short lff24m2_1
	jmp	lff24_3

lff24m2_7:
lff24s2_7:
	jmp	lff24_5  ; error

load_24khz_stereo_16_bit:
	; 16/11/2023
	; 15/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff24s2_0		; no
	stc
	retn

lff24s2_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff24s2_7 ; error !

	;mov	edi, audio_buffer
	; 29/05/2024
	mov	edi, [audio_buffer]
	
	shr	eax, 2
	jnz	short lff24s2_8
	jmp	lff24_eof

lff24s2_8:
	mov	ecx, eax  ; dword count
lff24s2_1:
	lodsw
	stosw		; original sample (L)
	add	ah, 80h	; convert sound level 0 to 65535 format 
	mov	[previous_val_l], ax
	lodsw
	stosw		; original sample (R)
	add	ah, 80h	; convert sound level 0 to 65535 format 
	;mov	[previous_val_r], ax
	mov	ebx, eax
	xor	edx, edx
	xor	eax, eax
	; 16/11/2023
	dec	ecx
	jz	short lff24s2_2
	mov	ax, [esi]
	mov	dx, [esi+2]
lff24s2_2:
	add	ah, 80h	; convert sound level 0 to 65535 format 
	;;mov	[next_val_l], ax
	;mov	ebp, eax
	add	dh, 80h	; convert sound level 0 to 65535 format 
	;mov	[next_val_r], dx
	add	ax, [previous_val_l]
	rcr	ax, 1
	sub	ah, 80h ; -32768 to +32767 format again
	stosw		; this is interpolated sample (L)
	;mov	ax, [next_val_r]
	mov	eax, edx
	;add	ax, [previous_val_r]
	add	ax, bx
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; this is interpolated sample (R)
	
	; 24 kHZ stereo to 48 kHZ stereo conversion of the sample is OK
	or	ecx, ecx
	jnz	short lff24s2_1
	jmp	lff24_3

; .....................

load_32khz_mono_8_bit:
	; 15/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff32m_0		; no
	stc
	retn

lff32m_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff32m_7 ; error !

	;mov	edi, audio_buffer
	; 29/05/2024
	mov	edi, [audio_buffer]
	
	and	eax, eax
	jnz	short lff32m_8
	jmp	lff32_eof

lff32m_8:
	mov	ecx, eax	; byte count
lff32m_1:
	lodsb
	;mov	[previous_val], al
	mov	bl, al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (left channel)
	stosw		; original sample (right channel)
	;xor	eax, eax
	mov	al, 80h
	dec	ecx
	jz	short lff32m_2
	mov	al, [esi]
lff32m_2:
	;;mov	[next_val], al
	;mov	bh, al
	;add	al, [previous_val]
	add	al, bl
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8
	stosw		; this is interpolated sample (L)
	stosw		; this is interpolated sample (R)
	
	; different than 8-16-24 kHZ !
	; 'original-interpolated-original' trio samples 
	jecxz	lff32m_3

	lodsb
	sub	al, 80h
	shl	ax, 8
	stosw		; original sample (left channel)
	stosw		; original sample (right channel)

	; 32 kHZ mono to 48 kHZ stereo conversion of the sample is OK
	dec	ecx
	jnz	short lff32m_1
lff32m_3:
	jmp	lff32_3

lff32m_7:
lff32s_7:
	jmp	lff32_5  ; error

load_32khz_stereo_8_bit:
	; 15/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff32s_0		; no
	stc
	retn

lff32s_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff32s_7 ; error !

	;mov	edi, audio_buffer
	; 29/05/2024
	mov	edi, [audio_buffer]
	
	shr	eax, 1
	jnz	short lff32s_8
	jmp	lff32_eof

lff32s_8:
	mov	ecx, eax  ; word count
lff32s_1:
	lodsb
	mov	[previous_val_l], al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (L)
	lodsb
	mov	[previous_val_r], al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (R)

	;xor	eax, eax
	mov	ax, 8080h
	dec	ecx
	jz	short lff32s_2
		; convert 8 bit sample to 16 bit sample
	mov	ax, [esi]
lff32s_2:
	;;mov	[next_val_l], al
	;;mov	[next_val_r], ah
	;mov	bx, ax
	mov	bh, ah
	add	al, [previous_val_l]
	rcr	al, 1
	;mov	dl, al
	sub	al, 80h
	shl	ax, 8
	stosw		; this is interpolated sample (L)
	mov	al, bh	; [next_val_r]
	add	al, [previous_val_r]
	rcr	al, 1
	;mov	dh, al
	sub	al, 80h
	shl	ax, 8
	stosw		; this is interpolated sample (R)

	; different than 8-16-24 kHZ !
	; 'original-interpolated-original' trio samples 
	jecxz	lff32s_3

	lodsb
	sub	al, 80h
	shl	ax, 8
	stosw		; original sample (left channel)

	lodsb
	sub	al, 80h
	shl	ax, 8
	stosw		; original sample (right channel)
		
	; 32 kHZ stereo to 48 kHZ stereo conversion of the sample is OK
	dec	ecx
	jnz	short lff32s_1
lff32s_3:
	jmp	lff32_3

load_32khz_mono_16_bit:
	; 15/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff32m2_0		; no
	stc
	retn

lff32m2_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff32m2_7 ; error !

	;mov	edi, audio_buffer
	; 29/05/2024
	mov	edi, [audio_buffer]
	
	shr	eax, 1
	jnz	short lff32m2_8
	jmp	lff32_eof

lff32m2_8:
	mov	ecx, eax  ; word count
lff32m2_1:
	lodsw
	stosw		; original sample (left channel)
	stosw		; original sample (right channel)
	add	ah, 80h ; convert sound level 0 to 65535 format
	;mov	[previous_val], ax
	;mov	ebx, eax	
	;xor	eax, eax
	xor	ebx, ebx
	dec	ecx
	jz	short lff32m2_2
	;mov	ax, [esi]
	mov	bx, [esi]
lff32m2_2:
	;add	ah, 80h ; convert sound level 0 to 65535 format
	;mov	ebp, eax	; [next_val]
	;add	ax, [previous_val]
	; ax = [previous_val]
	; bx = [next_val]
	add	ax, bx
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; this is interpolated sample (L)
	stosw		; this is interpolated sample (R)

	; different than 8-16-24 kHZ !
	; 'original-interpolated-original' trio samples 
	jecxz	lff32m2_3

	lodsw
	stosw		; original sample (left channel)
	stosw		; original sample (right channel)

	; 32 kHZ mono to 48 kHZ stereo conversion of the sample is OK
	dec	ecx
	jnz	short lff32m2_1
lff32m2_3:
	jmp	lff32_3

lff32m2_7:
lff32s2_7:
	jmp	lff32_5  ; error

load_32khz_stereo_16_bit:
	; 16/11/2023
	; 15/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff32s2_0		; no
	stc
	retn

lff32s2_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff32s2_7 ; error !

	;mov	edi, audio_buffer
	; 29/05/2024
	mov	edi, [audio_buffer]
	
	shr	eax, 2
	jnz	short lff32s2_8
	jmp	lff32_eof

lff32s2_8:
	mov	ecx, eax ; dword count
lff32s2_1:
	lodsw
	stosw		; original sample (L)
	add	ah, 80h	; convert sound level 0 to 65535 format 
	mov	[previous_val_l], ax
	lodsw
	stosw		; original sample (R)
	add	ah, 80h	; convert sound level 0 to 65535 format 
	;mov	[previous_val_r], ax
	mov	ebx, eax
	xor	edx, edx
	xor	eax, eax
	; 16/11/2023
	dec	ecx
	jz	short lff32s2_2
	mov	ax, [esi]
	mov	dx, [esi+2]
lff32s2_2:
	add	ah, 80h	; convert sound level 0 to 65535 format 
	;;mov	[next_val_l], ax
	;mov	ebp, eax
	add	dh, 80h	; convert sound level 0 to 65535 format 
	;mov	[next_val_r], dx
	add	ax, [previous_val_l]
	rcr	ax, 1
	sub	ah, 80h ; -32768 to +32767 format again
	stosw		; this is interpolated sample (L)
	;mov	ax, [next_val_r]
	mov	eax, edx
	;add	ax, [previous_val_r]
	add	ax, bx
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; this is interpolated sample (R)

	; different than 8-16-24 kHZ !
	; 'original-interpolated-original' trio samples 
	jecxz	lff32s2_3

	lodsw
	stosw	; original sample (L)
	lodsw
	stosw	; original sample (R)
	
	; 32 kHZ stereo to 48 kHZ stereo conversion of the sample is OK
	dec	ecx
	jnz	short lff32s2_1
lff32s2_3:
	jmp	lff32_3

; .....................

load_22khz_mono_8_bit:
	; 16/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff22m_0		; no
	stc
	retn

lff22m_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff22m_7 ; error !

	;mov	edi, audio_buffer
	; 29/05/2024
	mov	edi, [audio_buffer]
	
	and	eax, eax
	jnz	short lff22m_8
	jmp	lff22_eof

lff22m_8:
	mov	ecx, eax	; byte count
lff22m_9:
	mov	ebp, 5 ; interpolation (one step) loop count
	mov	byte [faz], 3  ; 3 steps/phases
lff22m_1:
	; 3:2:2:2:2:2::3:2:2:2:2::3:2:2:2:2:2  ; 37/17
	lodsb
	mov	dl, 80h
	dec	ecx
	jz	short lff22m_2_1
	mov	dl, [esi]
lff22m_2_1:	
	; al = [previous_val]
	; dl = [next_val]
	call	interpolating_3_8bit_mono ; 1 of 17
	jecxz	lff22m_3
lff22m_2_2:
	lodsb
	mov	dl, 80h
	dec	ecx
	jz	short lff22m_2_3
	mov	dl, [esi]
lff22m_2_3:
 	call	interpolating_2_8bit_mono ; 2 of 17 .. 6 of 17
	jecxz	lff22m_3
	dec	ebp
	jnz	short lff22m_2_2

	mov	al, [faz]
	dec	al
	jz	short lff22m_9
	dec	byte [faz]
	mov	ebp, 4
	dec	al
	jnz	short lff22m_1 ; 3:2:2:2:2 ; 7-11 of 17
	inc	ebp ; 5
	jmp	short lff22m_1 ; 3:2:2:2:2:2 ; 12-17 of 17

lff22m_3:
lff22s_3:
	jmp	lff22_3	; padfill
		; (put zeros in the remain words of the buffer)
lff22m_7:
lff22s_7:
	jmp	lff22_5  ; error

load_22khz_stereo_8_bit:
	; 16/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff22s_0		; no
	stc
	retn

lff22s_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff22s_7 ; error !

	;mov	edi, audio_buffer
	; 29/05/2024
	mov	edi, [audio_buffer]
	
	shr	eax, 1
	jnz	short lff22s_8
	jmp	lff22_eof

lff22s_8:
	mov	ecx, eax	; word count
lff22s_9:
	mov	ebp, 5 ; interpolation (one step) loop count
	mov	byte [faz], 3  ; 3 steps/phase
lff22s_1:
	; 3:2:2:2:2:2::3:2:2:2:2::3:2:2:2:2:2  ; 37/17
	lodsw
	mov	dx, 8080h
	dec	ecx
	jz	short lff22s_2_1 
	mov	dx, [esi]
lff22s_2_1:	
	; al = [previous_val_l]
	; ah = [previous_val_r]
	; dl = [next_val_l]
	; dh = [next_val_r]	
	call	interpolating_3_8bit_stereo ; 1 of 17 
	jecxz	lff22s_3
lff22s_2_2:
	lodsw
	mov	dx, 8080h
	dec	ecx
	jz	short lff22s_2_3
	mov	dx, [esi]
lff22s_2_3:
 	call	interpolating_2_8bit_stereo ; 2 of 17 .. 6 of 17
	jecxz	lff22s_3
	dec	ebp
	jnz	short lff22s_2_2

	mov	al, [faz]
	dec	al
	jz	short lff22s_9
	dec	byte [faz]
	mov	ebp, 4
	dec	al
	jnz	short lff22s_1 ; 3:2:2:2:2 ; 7-11 of 17
	inc	ebp ; 5
	jmp	short lff22s_1 ; 3:2:2:2:2:2 ; 12-17 of 17

load_22khz_mono_16_bit:
	; 16/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff22m2_0		; no
	stc
	retn

lff22m2_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff22m2_7 ; error !

	;mov	edi, audio_buffer
	; 29/05/2024
	mov	edi, [audio_buffer]
	
	shr	eax, 1
	jnz	short lff22m2_8
	jmp	lff22_eof

lff22m2_8:
	mov	ecx, eax	; word count
lff22m2_9:
	mov	ebp, 5 ; interpolation (one step) loop count
	mov	byte [faz], 3  ; 3 steps/phases
lff22m2_1:
	; 3:2:2:2:2:2::3:2:2:2:2::3:2:2:2:2:2  ; 37/17
	lodsw
	xor	edx, edx
	dec	ecx
	jz	short lff22m2_2_1
	mov	dx, [esi]
lff22m2_2_1:	
	; ax = [previous_val]
	; dx = [next_val]
	call	interpolating_3_16bit_mono ; 1 of 17
	jecxz	lff22m2_3
lff22m2_2_2:
	lodsw
	xor	edx, edx
	dec	ecx
	jz	short lff22m2_2_3
	mov	dx, [esi]
lff22m2_2_3:
 	call	interpolating_2_16bit_mono ; 2 of 17 .. 6 of 17
	jecxz	lff22m2_3
	dec	ebp
	jnz	short lff22m2_2_2

	mov	al, [faz]
	dec	al
	jz	short lff22m2_9
	dec	byte [faz]
	mov	ebp, 4
	dec	al
	jnz	short lff22m2_1 ; 3:2:2:2:2 ; 7-11 of 17
	inc	ebp ; 5
	jmp	short lff22m2_1 ; 3:2:2:2:2:2 ; 12-17 of 17

lff22m2_3:
lff22s2_3:
	jmp	lff22_3	; padfill
		; (put zeros in the remain words of the buffer)
lff22m2_7:
lff22s2_7:
	jmp	lff22_5  ; error

load_22khz_stereo_16_bit:
	; 16/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff22s2_0		; no
	stc
	retn

lff22s2_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff22s2_7 ; error !

	;mov	edi, audio_buffer
	; 29/05/2024
	mov	edi, [audio_buffer]
	
	shr	eax, 2	; dword (left chan word + right chan word)
	jnz	short lff22s2_8
	jmp	lff22_eof

lff22s2_8:
	mov	ecx, eax	; dword count
lff22s2_9:
	mov	ebp, 5 ; interpolation (one step) loop count
	mov	byte [faz], 3  ; 3 steps/phase
lff22s2_1:
	; 3:2:2:2:2:2::3:2:2:2:2::3:2:2:2:2:2  ; 37/17
	lodsw
	mov	ebx, eax
	lodsw
	mov	edx, [esi]
	mov	[next_val_l], dx
	; 26/11/2023
	shr	edx, 16
	dec	ecx
	jnz	short lff22s2_2_1
	xor	edx, edx ; 0
	mov	[next_val_l], dx
lff22s2_2_1:
	; bx = [previous_val_l]
	; ax = [previous_val_r]
	; [next_val_l]
	; dx = [next_val_r]
	call	interpolating_3_16bit_stereo ; 1 of 17 
	jecxz	lff22s2_3
lff22s2_2_2:
	lodsw
	mov	ebx, eax
	lodsw
	mov	edx, [esi]
	mov	[next_val_l], dx
	; 26/11/2023
	shr	edx, 16
	dec	ecx
	jnz	short lff22s2_2_3
	xor	edx, edx ; 0
	mov	[next_val_l], dx
lff22s2_2_3:
 	call	interpolating_2_16bit_stereo ; 2 of 17 .. 6 of 17
	jecxz	lff22s2_2_4

	dec	ebp
	jnz	short lff22s2_2_2

	mov	al, [faz]
	dec	al
	jz	short lff22s2_9
	dec	byte [faz]
	mov	ebp, 4
	dec	al
	jnz	short lff22s2_1 ; 3:2:2:2:2 ; 7-11 of 17
	inc	ebp ; 5
	jmp	short lff22s2_1 ; 3:2:2:2:2:2 ; 12-17 of 17

lff22s2_2_4:
	; 26/11/2023
	jmp	lff22_3	; padfill

; .....................

load_11khz_mono_8_bit:
	; 18/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff11m_0		; no
	stc
	retn

lff11m_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff11m_7 ; error !

	;mov	edi, audio_buffer
	; 29/05/2024
	mov	edi, [audio_buffer]
	
	and	eax, eax
	jnz	short lff11m_8
	jmp	lff11_eof

lff11m_8:
	mov	ecx, eax		; byte count
lff11m_9:
	mov	ebp, 6 ; interpolation (one step) loop count
lff11m_1:
	; 5:4:4::5:4:4::5:4:4::5:4:4::5:4:4::5:4  ; 74/17
	lodsb
	mov	dl, 80h
	dec	ecx
	jz	short lff11m_2_1
	mov	dl, [esi]
lff11m_2_1:	
	; al = [previous_val]
	; dl = [next_val]
	call	interpolating_5_8bit_mono
	jecxz	lff11m_3
lff11m_2_2:
	lodsb
	mov	dl, 80h
	dec	ecx
	jz	short lff11m_2_3
	mov	dl, [esi]
lff11m_2_3:
 	call	interpolating_4_8bit_mono
	jecxz	lff11m_3

	dec	ebp
	jz	short lff11m_9

	lodsb
	mov	dl, 80h
	dec	ecx
	jz	short lff11m_2_4
	mov	dl, [esi]
lff11m_2_4:
	call	interpolating_4_8bit_mono
	jecxz	lff11m_3
	jmp	short lff11m_1

lff11m_7:
lff11s_7:
	jmp	lff11_5  ; error

lff11m_3:
lff11s_3:
	jmp	lff11_3	; padfill
		; (put zeros in the remain words of the buffer)

load_11khz_stereo_8_bit:
	; 18/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff11s_0		; no
	stc
	retn

lff11s_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff11s_7 ; error !

	;mov	edi, audio_buffer
	; 29/05/2024
	mov	edi, [audio_buffer]
	
	shr	eax, 1
	jnz	short lff11s_8
	jmp	lff11_eof

lff11s_8:
	mov	ecx, eax	; word count
lff11s_9:
	mov	ebp, 6 ; interpolation (one step) loop count
lff11s_1:
	; 5:4:4::5:4:4::5:4:4::5:4:4::5:4:4::5:4  ; 74/17
	lodsw
	mov	dx, 8080h
	dec	ecx
	jz	short lff11s_2_1 
	mov	dx, [esi]
lff11s_2_1:	
	; al = [previous_val_l]
	; ah = [previous_val_r]
	; dl = [next_val_l]
	; dh = [next_val_r]	
	call	interpolating_5_8bit_stereo
	jecxz	lff11s_3
lff11s_2_2:
	lodsw
	mov	dx, 8080h
	dec	ecx
	jz	short lff11s_2_3
	mov	dx, [esi]
lff11s_2_3:
 	call	interpolating_4_8bit_stereo
	jecxz	lff11s_3
	
	dec	ebp
	jz	short lff11s_9

	lodsw
	mov	dx, 8080h
	dec	ecx
	jz	short lff11s_2_4
	mov	dx, [esi]
lff11s_2_4:
	call	interpolating_4_8bit_stereo
	jecxz	lff11s_3
	jmp	short lff11s_1

load_11khz_mono_16_bit:
	; 18/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff11m2_0		; no
	stc
	retn

lff11m2_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff11m2_7 ; error !

	;mov	edi, audio_buffer
	; 29/05/2024
	mov	edi, [audio_buffer]
	
	shr	eax, 1
	jnz	short lff11m2_8
	jmp	lff11_eof

lff11m2_8:
	mov	ecx, eax	; word count
lff11m2_9:
	mov	ebp, 6 ; interpolation (one step) loop count
lff11m2_1:
	; 5:4:4::5:4:4::5:4:4::5:4:4::5:4:4::5:4  ; 74/17
	lodsw
	xor	edx, edx
	dec	ecx
	jz	short lff11m2_2_1
	mov	dx, [esi]
lff11m2_2_1:	
	; ax = [previous_val]
	; dx = [next_val]
	call	interpolating_5_16bit_mono
	jecxz	lff11m2_3
lff11m2_2_2:
	lodsw
	xor	edx, edx
	dec	ecx
	jz	short lff11m2_2_3
	mov	dx, [esi]
lff11m2_2_3:
 	call	interpolating_4_16bit_mono
	jecxz	lff11m2_3

	dec	ebp
	jz	short lff11m2_9

	lodsw
	xor	edx, edx
	dec	ecx
	jz	short lff11m2_2_4
	mov	dx, [esi]
lff11m2_2_4:
 	call	interpolating_4_16bit_mono
	jecxz	lff11m2_3
	jmp	short lff11m2_1

lff11m2_7:
lff11s2_7:
	jmp	lff11_5  ; error

load_11khz_stereo_16_bit:
	; 18/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff11s2_0		; no
	stc
	retn

lff11s2_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff11s2_7 ; error !

	;mov	edi, audio_buffer
	; 29/05/2024
	mov	edi, [audio_buffer]
	
	shr	eax, 2	; dword (left chan word + right chan word)
	jnz	short lff11s2_8
	jmp	lff11_eof

lff11m2_3:
lff11s2_3:
	jmp	lff11_3	; padfill
		; (put zeros in the remain words of the buffer)

lff11s2_8:
	mov	ecx, eax	; dword count
lff11s2_9:
	mov	ebp, 6 ; interpolation (one step) loop count
lff11s2_1:
	; 5:4:4::5:4:4::5:4:4::5:4:4::5:4:4::5:4  ; 74/17
	lodsw
	mov	ebx, eax
	lodsw
	mov	edx, [esi]
	mov	[next_val_l], edx
	; 26/11/2023
	shr	edx, 16
	;mov	[next_val_r], dx
	dec	ecx
	jnz	short lff11s2_2_1
	xor	edx, edx ; 0
	mov	[next_val_l], dx
	;mov	[next_val_r], dx
lff11s2_2_1:
	; bx = [previous_val_l]
	; ax = [previous_val_r]
	; [next_val_l]
	; dx = [next_val_r]
	call	interpolating_5_16bit_stereo
	jecxz	lff11s2_3
lff11s2_2_2:
	lodsw
	mov	ebx, eax
	lodsw
	mov	edx, [esi]
	mov	[next_val_l], dx
	; 26/11/2023
	shr	edx, 16
	;mov	[next_val_r], dx
	dec	ecx
	jnz	short lff11s2_2_3
	xor	edx, edx ; 0
	mov	[next_val_l], dx
	;mov	[next_val_r], dx
lff11s2_2_3:
 	call	interpolating_4_16bit_stereo
	jecxz	lff11s2_3
	
	dec	ebp
	jz	short lff11s2_9

	lodsw
	mov	ebx, eax
	lodsw
	mov	edx, [esi]
	mov	[next_val_l], dx
	; 26/11/2023
	shr	edx, 16
	;mov	[next_val_r], dx
	dec	ecx
	jnz	short lff11s2_2_4
	xor	edx, edx ; 0
	mov	[next_val_l], dx
	;mov	[next_val_r], dx
lff11s2_2_4:
 	call	interpolating_4_16bit_stereo
	jecxz	lff11s2_3
	jmp	short lff11s2_1

; .....................

load_44khz_mono_8_bit:
	; 18/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff44m_0		; no
	stc
	retn

lff44m_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff44m_7 ; error !

	;mov	edi, audio_buffer
	; 29/05/2024
	mov	edi, [audio_buffer]
	
	and	eax, eax
	jnz	short lff44m_8
	jmp	lff44_eof

lff44m_8:
	mov	ecx, eax	; byte count
lff44m_9:
	mov	ebp, 10 ; interpolation (one step) loop count
	mov	byte [faz], 2  ; 2 steps/phases
lff44m_1:
	; 2:1:1:1:1:1:1:1:1:1:1::	; 25/23
	; 2:1:1:1:1:1:1:1:1:1:1:1
	lodsb
	mov	dl, 80h
	dec	ecx
	jz	short lff44m_2_1
	mov	dl, [esi]
lff44m_2_1:	
	; al = [previous_val]
	; dl = [next_val]
	call	interpolating_2_8bit_mono
	jecxz	lff44m_3
lff44m_2_2:
	lodsb
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; (L)
	stosw		; (R)	

	dec	ecx
	jz	short lff44m_3	
	dec	ebp
	jnz	short lff44m_2_2
	
	dec	byte [faz]
	jz	short lff44m_9 
	mov	ebp, 11
	jmp	short lff44m_1

lff44m_3:
lff44s_3:
	jmp	lff44_3	; padfill
		; (put zeros in the remain words of the buffer)
lff44m_7:
lff44s_7:
	jmp	lff44_5  ; error

load_44khz_stereo_8_bit:
	; 16/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff44s_0		; no
	stc
	retn

lff44s_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff44s_7 ; error !

	;mov	edi, audio_buffer
	; 29/05/2024
	mov	edi, [audio_buffer]
	
	shr	eax, 1
	jnz	short lff44s_8
	jmp	lff44_eof

lff44s_8:
	mov	ecx, eax	; word count
lff44s_9:
	mov	ebp, 10 ; interpolation (one step) loop count
	mov	byte [faz], 2  ; 2 steps/phase
lff44s_1:
	; 2:1:1:1:1:1:1:1:1:1:1::	; 25/23
	; 2:1:1:1:1:1:1:1:1:1:1:1
	lodsw
	mov	dx, 8080h
	dec	ecx
	jz	short lff44s_2_1 
	mov	dx, [esi]
lff44s_2_1:	
	; al = [previous_val_l]
	; ah = [previous_val_r]
	; dl = [next_val_l]
	; dh = [next_val_r]	
	call	interpolating_2_8bit_stereo
	jecxz	lff44s_3
lff44s_2_2:
	lodsb
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; (L)
	lodsb
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; (R)

	dec	ecx
	jz	short lff44s_3	
	dec	ebp
	jnz	short lff44s_2_2
	
	dec	byte [faz]
	jz	short lff44s_9 
	mov	ebp, 11
	jmp	short lff44s_1

load_44khz_mono_16_bit:
	; 18/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff44m2_0		; no
	stc
	retn

lff44m2_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff44m2_7 ; error !

	;mov	edi, audio_buffer
	; 29/05/2024
	mov	edi, [audio_buffer]
	
	shr	eax, 1
	jnz	short lff44m2_8
	jmp	lff44_eof

lff44m2_8:
	mov	ecx, eax	; word count
lff44m2_9:
	mov	ebp, 10 ; interpolation (one step) loop count
	mov	byte [faz], 2  ; 2 steps/phases
lff44m2_1:
	; 2:1:1:1:1:1:1:1:1:1:1::	; 25/23
	; 2:1:1:1:1:1:1:1:1:1:1:1
	lodsw
	xor	edx, edx
	dec	ecx
	jz	short lff44m2_2_1
	mov	dx, [esi]
lff44m2_2_1:	
	; ax = [previous_val]
	; dx = [next_val]
	call	interpolating_2_16bit_mono
	jecxz	lff44m2_3
lff44m2_2_2:
	lodsw
	stosw		; (L)eft Channel
	stosw		; (R)ight Channel

	dec	ecx
	jz	short lff44m2_3	
	dec	ebp
	jnz	short lff44m2_2_2
	
	dec	byte [faz]
	jz	short lff44m2_9 
	mov	ebp, 11
	jmp	short lff44m2_1

lff44m2_3:
lff44s2_3:
	jmp	lff44_3	; padfill
		; (put zeros in the remain words of the buffer)
lff44m2_7:
lff44s2_7:
	jmp	lff44_5  ; error

load_44khz_stereo_16_bit:
	; 18/11/2023
        test    byte [flags], ENDOFFILE	; have we already read the
					; last of the file?
	jz	short lff44s2_0		; no
	stc
	retn

lff44s2_0:
	mov	esi, temp_buffer ; temporary buffer for wav data
        ;mov	edx, [loadsize]

	; esi = buffer address
	;; edx = buffer size

	; load file into memory
	sys 	_read, [FileHandle], esi, [loadsize]
	jc	short lff44s2_7 ; error !

	;mov	edi, audio_buffer
	; 29/05/2024
	mov	edi, [audio_buffer]
	
	shr	eax, 2	; dword (left chan word + right chan word)
	jnz	short lff44s2_8
	jmp	lff44_eof

lff44s2_8:
	mov	ecx, eax	; dword count
lff44s2_9:
	mov	ebp, 10 ; interpolation (one step) loop count
	mov	byte [faz], 2  ; 2 steps/phase
lff44s2_1:
	; 2:1:1:1:1:1:1:1:1:1:1::	; 25/23
	; 2:1:1:1:1:1:1:1:1:1:1:1
	lodsw
	mov	ebx, eax
	lodsw
	;mov	dx, [esi]
	;mov	[next_val_l], dx
	;mov	dx, [esi+2]
	; 26/11/2023
	mov	edx, [esi]
	mov	[next_val_l], dx
	shr	edx, 16
	dec	ecx
	jnz	short lff44s2_2_1
	xor	edx, edx ; 0
	mov	[next_val_l], dx
lff44s2_2_1:
	; bx = [previous_val_l]
	; ax = [previous_val_r]
	; [next_val_l]
	; dx = [next_val_r]
	call	interpolating_2_16bit_stereo
	jecxz	lff44s2_3
lff44s2_2_2:
	;movsw		; (L)eft Channel
	;movsw		; (R)ight Channel
	movsd

	dec	ecx
	jz	short lff44s2_3	
	dec	ebp
	jnz	short lff44s2_2_2
	
	dec	byte [faz]
	jz	short lff44s2_9 
	mov	ebp, 11
	jmp	short lff44s2_1

; .....................

interpolating_3_8bit_mono:
	; 16/11/2023
	; al = [previous_val]
	; dl = [next_val]
	; original-interpolated-interpolated
	mov	bl, al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (L)
	stosw		; original sample (R)
	mov	al, bl
	add	al, dl	
	rcr	al, 1
	mov	bh, al	; interpolated middle (temporary)
	add	al, bl
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 1 (L)
	stosw		; interpolated sample 1 (R)
	mov	al, bh
	add	al, dl	; [next_val]
	rcr	al, 1
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 2 (L)
	stosw		; interpolated sample 2 (R)
	retn

interpolating_3_8bit_stereo:
	; 16/11/2023
	; al = [previous_val_l]
	; ah = [previous_val_r]
	; dl = [next_val_l]
	; dh = [next_val_r]	
	; original-interpolated-interpolated
	mov	ebx, eax
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (L)
	mov	al, bh
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (R)
	mov	al, bl
	add	al, dl	; [next_val_l]	
	rcr	al, 1
	push	eax ; *	; al = interpolated middle (L) (temporary)
	add	al, bl	; [previous_val_l]
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 1 (L)
	mov	al, bh
	add	al, dh	; [next_val_r]
	rcr	al, 1
	push	eax ; ** ; al = interpolated middle (R) (temporary)
	add	al, bh	; [previous_val_r]
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 1 (R)
	pop	ebx ; **
	pop	eax ; *
	add	al, dl	; [next_val_l]
	rcr	al, 1
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 2 (L)
	mov	al, bl
	add	al, dh	; [next_val_r]
	rcr	al, 1
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 2 (R)
	retn

interpolating_2_8bit_mono:
	; 16/11/2023
	; al = [previous_val]
	; dl = [next_val]
	; original-interpolated
	mov	bl, al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (L)
	stosw		; original sample (R)
	mov	al, bl
	add	al, dl	
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample (L)
	stosw		; interpolated sample (R)
	retn

interpolating_2_8bit_stereo:
	; 16/11/2023
	; al = [previous_val_l]
	; ah = [previous_val_r]
	; dl = [next_val_l]
	; dh = [next_val_r]	
	; original-interpolated
	mov	ebx, eax
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (L)
	mov	al, bh
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (R)
	mov	al, bl	; [previous_val_l]
	add	al, dl	; [next_val_l]	
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample (L)
	mov	al, bh
	add	al, dh	; [next_val_r]
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample (R)
	retn

interpolating_3_16bit_mono:
	; 16/11/2023
	; ax = [previous_val]
	; dx = [next_val]
	; original-interpolated-interpolated

	stosw		; original sample (L)
	stosw		; original sample (R)
	add	ah, 80h ; convert sound level 0 to 65535 format
	push	eax ; *	; [previous_val]
	add	dh, 80h
	add	ax, dx
	rcr	ax, 1
	pop	ebx ; *		
	xchg	ebx, eax ; bx  = interpolated middle (temporary)
	add	ax, bx	; [previous_val] + interpolated middle
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 1 (L)
	stosw		; interpolated sample 1 (R)
	mov	eax, ebx
	add	ax, dx	 ;interpolated middle + [next_val]
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; interpolated sample 2 (L)
	stosw		; interpolated sample 2 (R)
	retn

interpolating_3_16bit_stereo:
	; 16/11/2023
	; bx = [previous_val_l]
	; ax = [previous_val_r]
	; [next_val_l]
	; dx = [next_val_r]
	; original-interpolated-interpolated

	xchg	eax, ebx
	stosw		; original sample (L)
	xchg	eax, ebx
	stosw		; original sample (R)
	add	ah, 80h ; convert sound level 0 to 65535 format
	push	eax ; *	; [previous_val_r]
	add	bh, 80h
	add	byte [next_val_l+1], 80h
	mov	ax, [next_val_l]
	add	ax, bx	; [previous_val_l]
	rcr	ax, 1
	xchg	eax, ebx ; ax = [previous_val_l]	
	add	ax, bx	; bx = interpolated middle (L)
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 1 (L)
	pop	eax  ; *
	add	dh, 80h ; convert sound level 0 to 65535 format
	push	edx  ; * ; [next_val_r]
	xchg	eax, edx
	add	ax, dx	; [next_val_r] + [previous_val_r]
	rcr	ax, 1	; / 2
	push	eax ; ** ; interpolated middle (R)
	add	ax, dx	; + [previous_val_r]
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 1 (R)
	mov	ax, [next_val_l]
	add	ax, bx	; + interpolated middle (L)
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 2 (L)
	pop	eax ; **
	pop	edx ; *	
	add	ax, dx	; interpolated middle + [next_val_r]
	rcr	ax, 1	; / 2
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 2 (L)
	retn

interpolating_2_16bit_mono:
	; 16/11/2023
	; ax = [previous_val]
	; dx = [next_val]
	; original-interpolated

	stosw		; original sample (L)
	stosw		; original sample (R)
	add	ah, 80h ; convert sound level 0 to 65535 format
	add	dh, 80h
	add	ax, dx
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; interpolated sample (L)
	stosw		; interpolated sample (R)
	retn

interpolating_2_16bit_stereo:
	; 16/11/2023
	; bx = [previous_val_l]
	; ax = [previous_val_r]
	; [next_val_l]
	; dx = [next_val_r]
	; original-interpolated

	xchg	eax, ebx
	stosw		; original sample (L)
	xchg	eax, ebx
	stosw		; original sample (R)
	add	ah, 80h ; convert sound level 0 to 65535 format
	add	dh, 80h
	add	ax, dx	; [previous_val_r] + [next_val_r]
	rcr	ax, 1	; / 2
	push	eax ; *	; interpolated sample (R)
	mov	ax, [next_val_l]
	add	ah, 80h
	add	bh, 80h
	add	ax, bx	; [next_val_l] + [previous_val_l]
	rcr	ax, 1	; / 2		
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample (L)
	pop	eax ; *	
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample (R)
	retn

interpolating_5_8bit_mono:
	; 17/11/2023
	; al = [previous_val]
	; dl = [next_val]
	; original-interpltd-interpltd-interpltd-interpltd
	mov	bl, al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (L)
	stosw		; original sample (R)
	mov	al, bl
	add	al, dl	
	rcr	al, 1
	mov	bh, al	; interpolated middle (temporary)
	add	al, bl  ; [previous_val]
	rcr	al, 1 	
	mov	dh, al	; interpolated 1st quarter (temporary)
	add	al, bl
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 1 (L)
	stosw		; interpolated sample 1 (R)
	mov	al, bh
	add	al, dh
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 2 (L)
	stosw		; interpolated sample 2 (R)
	mov	al, bh
	add	al, dl	; [next_val]
	rcr	al, 1
	mov	dh, al	; interpolated 3rd quarter (temporary)
	add	al, bh
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 3 (L)
	stosw		; interpolated sample 3 (R)
	mov	al, dh
	add	al, dl
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 4 (L)
	stosw		; interpolated sample 4 (R)
	retn

interpolating_5_8bit_stereo:
	; 17/11/2023
	; al = [previous_val_l]
	; ah = [previous_val_r]
	; dl = [next_val_l]
	; dh = [next_val_r]	
	; original-interpltd-interpltd-interpltd-interpltd
	mov	ebx, eax
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (L)
	mov	al, bh
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (R)
	push	edx ; *
	mov	al, bl
	add	al, dl	; [next_val_l]
	rcr	al, 1
	push	eax ; **	; al = interpolated middle (L) (temporary)
	add	al, bl	; [previous_val_l]
	rcr	al, 1
	xchg	al, bl	
	add	al, bl	; bl = interpolated 1st quarter (L) (temp)
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 1 (L)
	mov	al, bh
	add	al, dh	; [next_val_r]
	rcr	al, 1
	push	eax ; *** ; al = interpolated middle (R) (temporary)
	add	al, bh	; [previous_val_r]
	rcr	al, 1
	xchg	al, bh	
	add	al, bh	; bh = interpolated 1st quarter (R) (temp)
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 1 (R)
	pop	edx ; ***
	pop	eax ; **	; al = interpolated middle (L) (temporary)
	xchg	al, bl	; al = interpolated 1st quarter (L) (temp)
	add	al, bl	; bl = interpolated middle (L) (temporary)
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 2 (L)	
	mov	al, dl 	; interpolated middle (R) (temporary)
	xchg	al, bh	; al = interpolated 1st quarter (R) (temp)
	add	al, bh	; bh = interpolated middle (R) (temporary)
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 2 (R)
	pop	edx ; *
	mov	al, bl	; interpolated middle (L) (temporary)
	add	al, dl	; [next_val_l]
	rcr	al, 1
	xchg	al, bl	; al = interpolated middle (R) (temporary)	
	add	al, bl	; bl = interpolated 3rd quarter (L) (temp) 
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 3 (L)
	mov	al, bh	
	add	al, dh	; interpolated middle (R) + [next_val_r]
	rcr	al, 1
	xchg	al, bh	; al = interpolated middle (R)
	add	al, bh	; bh = interpolated 3rd quarter (R) (temp)
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 3 (R)
	mov	al, bl
	add	al, dl	; [next_val_l]
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 4 (L)
	mov	al, bh
	add	al, dh	; [next_val_r]
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 4 (R)
	retn

interpolating_4_8bit_mono:
	; 17/11/2023
	; al = [previous_val]
	; dl = [next_val]
	; original-interpolated-interpolated-interpolated
	mov	bl, al
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (L)
	stosw		; original sample (R)
	mov	al, bl
	add	al, dl	
	rcr	al, 1
	xchg	al, bl  ; al = [previous_val]
	add	al, bl	; bl = interpolated middle (sample 2)
	rcr	al, 1 	
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 1 (L)
	stosw		; interpolated sample 1 (R)
	mov	al, bl	; interpolated middle (sample 2)
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 2 (L)
	stosw		; interpolated sample 2 (R)
	mov	al, bl
	add	al, dl	; [next_val]
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 3 (L)
	stosw		; interpolated sample 3 (R)
	retn

interpolating_4_8bit_stereo:
	; 17/11/2023
	; al = [previous_val_l]
	; ah = [previous_val_r]
	; dl = [next_val_l]
	; dh = [next_val_r]	
	; original-interpolated-interpolated-interpolated
	mov	ebx, eax
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (L)
	mov	al, bh
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; original sample (R)
	mov	al, bl
	add	al, dl	; [next_val_l]
	rcr	al, 1
	xchg	al, bl	; al = [previous_val_l]
	add	al, bl	; bl = interpolated middle (L) (sample 2)
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 1 (L)
	mov	al, bh
	add	al, dh	; [next_val_r]
	rcr	al, 1
	xchg	al, bh	; al = [previous_val_h]
	add	al, bh	; bh = interpolated middle (R) (sample 2)
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 1 (R)
	mov	al, bl	; interpolated middle (L) (sample 2)
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 2 (L)
	mov	al, bh	; interpolated middle (L) (sample 2)
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 2 (L)
	mov	al, bl
	add	al, dl	; [next_val_l]
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 3 (L)
	mov	al, bh
	add	al, dh	; [next_val_r]
	rcr	al, 1
	sub	al, 80h
	shl	ax, 8	; convert 8 bit sample to 16 bit sample
	stosw		; interpolated sample 3 (R)
	retn

interpolating_5_16bit_mono:
	; 18/11/2023
	; ax = [previous_val]
	; dx = [next_val]
	; original-interpltd-interpltd-interpltd-interpltd
	stosw		; original sample (L)
	stosw		; original sample (R)
	add	ah, 80h ; convert sound level 0 to 65535 format
	mov	ebx, eax ; [previous_val]
	add	dh, 80h
	add	ax, dx
	rcr	ax, 1
	push	eax ; *	; interpolated middle (temporary)
	add	ax, bx	; interpolated middle + [previous_val] 
	rcr	ax, 1
	push	eax ; **	; interpolated 1st quarter (temporary)
	add	ax, bx	; 1st quarter + [previous_val]
	rcr	ax, 1	
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 1 (L)
	stosw		; interpolated sample 1 (R)
	pop	eax ; **	
	pop	ebx ; *
	add	ax, bx	; 1st quarter + middle
	rcr	ax, 1	; / 2
	sub	ah, 80h	; -32768 to +32767 format again	
	stosw		; interpolated sample 2 (L)
	stosw		; interpolated sample 2 (R)		
	mov	eax, ebx
	add	ax, dx	; interpolated middle + [next_val]
	rcr	ax, 1
	push	eax ; *	; interpolated 3rd quarter (temporary)
	add	ax, bx	; + interpolated middle
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; interpolated sample 3 (L)
	stosw		; interpolated sample 3 (R)
	pop	eax ; *	
	add	ax, dx	; 3rd quarter + [next_val]
	rcr	ax, 1	; / 2
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; interpolated sample 4 (L)
	stosw		; interpolated sample 4 (R)
	retn

interpolating_5_16bit_stereo:
	; 18/11/2023
	; bx = [previous_val_l]
	; ax = [previous_val_r]
	; [next_val_l]
	; [next_val_r]
	; original-interpltd-interpltd-interpltd-interpltd
	push	ecx ; !
	xchg	eax, ebx
	stosw		; original sample (L)
	xchg	eax, ebx
	stosw		; original sample (R)
	add	ah, 80h ; convert sound level 0 to 65535 format
	push	eax ; *	; [previous_val_r]
	add	bh, 80h
	add	byte [next_val_l+1], 80h
	mov	ax, [next_val_l]
	add	ax, bx	; [previous_val_l]
	rcr	ax, 1
	mov	ecx, eax ; interpolated middle (L)
	add	ax, bx	
	rcr	ax, 1
	mov	edx, eax ; interpolated 1st quarter (L)	
	add	ax, bx	; [previous_val_l]
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 1 (L)
	mov	eax, ecx
	add	ax, dx	; middle (L) + 1st quarter (L) 
	rcr	ax, 1	; / 2
	mov	ebx, eax  ; interpolated sample 2 (L)
	pop	edx ; *	; [previous_val_r]
	mov	eax, edx
	add	byte [next_val_r+1], 80h
	add	ax, [next_val_r]
	rcr	ax, 1
	push	eax ; *	; interpolated middle (R)
	add	ax, dx
	rcr	ax, 1
	push	eax ; ** ; interpolated 1st quarter (R)
	add	ax, dx	; [previous_val_r]
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 1 (R)
	mov	eax, ebx
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 2 (L)
	pop	eax ; **
	pop	edx ; *
	add	ax, dx	; 1st quarter (R) + middle (R)
	rcr	ax, 1	; / 2
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 2 (R)
	mov	eax, ecx
	add	ax, [next_val_l]
	rcr	ax, 1
	push	eax ; * ; interpolated 3rd quarter (L)
	add	ax, cx	; interpolated middle (L)
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 3 (L)
	mov	eax, edx
	add	ax, [next_val_r]
	rcr	ax, 1
	push	eax ; ** ; interpolated 3rd quarter (R)
	add	ax, dx	; interpolated middle (R)
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 3 (R)
	pop	ebx ; **
	pop	eax ; *
	add	ax, [next_val_l]
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 4 (L)
	mov	eax, ebx	
	add	ax, [next_val_r]
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 4 (R)
	pop	ecx ; !
	retn

interpolating_4_16bit_mono:
	; 18/11/2023
	; ax = [previous_val]
	; dx = [next_val]
	; original-interpolated

	stosw		; original sample (L)
	stosw		; original sample (R)
	add	ah, 80h ; convert sound level 0 to 65535 format
	mov	ebx, eax ; [previous_val]
	add	dh, 80h
	add	ax, dx	; [previous_val] + [next_val]
	rcr	ax, 1
	xchg	eax, ebx	
	add	ax, bx	; [previous_val] + interpolated middle
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 1 (L)
	stosw		; interpolated sample 1 (R)
	mov	eax, ebx ; interpolated middle
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 2 (L)
	stosw		; interpolated sample 2 (R)
	mov	eax, ebx
	add	ax, dx	; interpolated middle + [next_val]
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw		; interpolated sample 3 (L)
	stosw		; interpolated sample 3 (R)
	retn

interpolating_4_16bit_stereo:
	; 18/11/2023
	; bx = [previous_val_l]
	; ax = [previous_val_r]
	; [next_val_l]
	; [next_val_r]
	; original-interpolated-interpolated-interpolated
	xchg	eax, ebx
	stosw		; original sample (L)
	xchg	eax, ebx
	stosw		; original sample (R)
	add	ah, 80h ; convert sound level 0 to 65535 format
	mov	edx, eax ; [previous_val_r]
	add	bh, 80h
	add	byte [next_val_l+1], 80h
	mov	ax, [next_val_l]
	add	ax, bx	; [previous_val_l]
	rcr	ax, 1
	xchg	eax, ebx	
	add	ax, bx	; bx = interpolated middle (L)
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 1 (L)
	add	byte [next_val_r+1], 80h
	mov	eax, edx ; [previous_val_r]
	add	ax, [next_val_r]
	rcr	ax, 1
	xchg	eax, edx	
	add	ax, dx	; dx = interpolated middle (R)
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 1 (R)
	mov	eax, ebx
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 2 (L)
	mov	eax, edx
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 2 (R)
	mov	eax, ebx
	add	ax, [next_val_l]
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 3 (L)
	mov	eax, edx
	add	ax, [next_val_r]
	rcr	ax, 1
	sub	ah, 80h	; -32768 to +32767 format again
	stosw 		; interpolated sample 3 (R)
	retn

; 13/11/2023
previous_val:
previous_val_l: dw 0
previous_val_r: dw 0
next_val:
next_val_l: dw 0
next_val_r: dw 0

; 16/11/2023
faz:	db 0	
	
; --------------------------------------------------------
; 27/05/2024 - (TRDOS 386 Kernel) audio.s
; --------------------------------------------------------

NOT_PCI32_PCI16	EQU 03FFFFFFFh ; NOT BIT31+BIT30 ; 19/03/2017
NOT_BIT31 EQU 7FFFFFFFh

pciFindDevice:
	; 19/11/2023
	; 03/04/2017 ('pci.asm', 20/03/2017)
	;
	; scan through PCI space looking for a device+vendor ID
	;
	; Entry: EAX=Device+Vendor ID
	;
	; Exit: EAX=PCI address if device found
	;	EDX=Device+Vendor ID
	;       CY clear if found, set if not found. EAX invalid if CY set.
	;
	; Destroys: ebx, edi ; 19/11/2023

        ; 19/11/2023
	mov	ebx, eax
	mov	edi, 80000000h
nextPCIdevice:
	mov 	eax, edi		; read PCI registers
	call	pciRegRead32
	; 19/11/2023
	cmp	edx, ebx
	je	short PCIScanExit	; found
	; 19/11/2023
	cmp	edi, 80FFF800h
	jnb	short pfd_nf		; not found
	add	edi, 100h
	jmp	short nextPCIdevice
pfd_nf:
	stc
	retn
PCIScanExit:
	;pushf
	mov	eax, NOT_BIT31 	; 19/03/2017
	and	eax, edi	; return only bus/dev/fn #
	retn

pciRegRead:
	; 03/04/2017 ('pci.asm', 20/03/2017)
	;
	; 8/16/32bit PCI reader
	;
	; Entry: EAX=PCI Bus/Device/fn/register number
	;           BIT30 set if 32 bit access requested
	;           BIT29 set if 16 bit access requested
	;           otherwise defaults to 8 bit read
	;
	; Exit:  DL,DX,EDX register data depending on requested read size
	;
	; Note1: this routine is meant to be called via pciRegRead8,
	;	 pciRegread16 or pciRegRead32, listed below.
	;
	; Note2: don't attempt to read 32 bits of data from a non dword
	;	 aligned reg number. Likewise, don't do 16 bit reads from
	;	 non word aligned reg #
	
	push	ebx
	push	ecx
        mov     ebx, eax		; save eax, dh
        mov     cl, dh

        and     eax, NOT_PCI32_PCI16	; clear out data size request
        or      eax, BIT31		; make a PCI access request
        and     al, ~3 ; NOT 3		; force index to be dword

        mov     dx, PCI_INDEX_PORT
        ;out	dx, eax			; write PCI selector
	; 29/05/2024
	push	ebx
	mov	ebx, eax ; data, dword
	mov	ah, 5 ; write port, dword
	; dx = port number
	int	34h
	pop	ebx
	
        mov     dx, PCI_DATA_PORT
        mov     al, bl
        and     al, 3			; figure out which port to
        add     dl, al			; read to

	test    ebx, PCI32+PCI16
        jnz     short _pregr0

	;in	al, dx			; return 8 bits of data
	; 29/05/2024
	mov	ah, 0 ; read port, byte
	; dx = port number
	int	34h
        
	mov	dl, al
	mov     dh, cl			; restore dh for 8 bit read
	jmp	short _pregr2
_pregr0:	
	test    ebx, PCI32
        jnz	short _pregr1

	;in	ax, dx
	; 29/05/2024
	mov	ah, 2 ; read port, word
	; dx = port number
	int	34h	        

	mov     dx, ax			; return 16 bits of data
	jmp	short _pregr2
_pregr1:
	;in	eax, dx			; return 32 bits of data
	; 29/05/2024
	mov	ah, 4 ; read port, dword
	; dx = port number
	int	34h

	mov	edx, eax
_pregr2:
	mov     eax, ebx		; restore eax
        and     eax, NOT_PCI32_PCI16	; clear out data size request
	pop	ecx
	pop	ebx
	retn

pciRegRead8:
        and     eax, NOT_PCI32_PCI16	; set up 8 bit read size
        jmp     short pciRegRead	; call generic PCI access

pciRegRead16:
        and     eax, NOT_PCI32_PCI16	; set up 16 bit read size
        or      eax, PCI16		; call generic PCI access
        jmp     short pciRegRead

pciRegRead32:
        and     eax, NOT_PCI32_PCI16	; set up 32 bit read size
        or      eax, PCI32		; call generic PCI access
        jmp     pciRegRead

pciRegWrite:
	; 03/04/2017 ('pci.asm', 29/11/2016)
	;
	; 8/16/32bit PCI writer
	;
	; Entry: EAX=PCI Bus/Device/fn/register number
	;           BIT31 set if 32 bit access requested
	;           BIT30 set if 16 bit access requested
	;           otherwise defaults to 8bit read
	;        DL/DX/EDX data to write depending on size
	;
	; Note1: this routine is meant to be called via pciRegWrite8, 
	;	 pciRegWrite16 or pciRegWrite32 as detailed below.
	;
	; Note2: don't attempt to write 32bits of data from a non dword
	;	 aligned reg number. Likewise, don't do 16 bit writes from
	;	 non word aligned reg #

	push	ebx
	push	ecx
        mov     ebx, eax		; save eax, edx
        mov     ecx, edx
	and     eax, NOT_PCI32_PCI16	; clear out data size request
        or      eax, BIT31		; make a PCI access request
        and     al, ~3 ; NOT 3		; force index to be dword

        mov     dx, PCI_INDEX_PORT
	;out	dx, eax			; write PCI selector
	; 29/05/2024
	push	ebx
	mov	ebx, eax ; data, dword
	mov	ah, 5 ; write port, dword
	; dx = port number
	int	34h
	pop	ebx
	
        mov     dx, PCI_DATA_PORT
        mov     al, bl
        and     al, 3			; figure out which port to
        add     dl, al			; write to

	test    ebx, PCI32+PCI16
        jnz     short _pregw0
	mov	al, cl 			; put data into al
	;out	dx, al
	; 29/05/2024
	; al = data, byte
	mov	ah, 1 ; write port, byte
	; dx = port number
	int	34h

	jmp	short _pregw2
_pregw0:
	test    ebx, PCI32
        jnz     short _pregw1
	mov	ax, cx			; put data into ax
	;out	dx, ax
	; 29/05/2024
	push	ebx
	mov	ebx, eax ; data, word
	mov	ah, 3 ; write port, word
	; dx = port number
	int	34h
	pop	ebx

	jmp	short _pregw2
_pregw1:
	mov	eax, ecx		; put data into eax
	;out	dx, eax
	; 29/05/2024
	push	ebx
	mov	ebx, eax ; data, dword
	mov	ah, 5 ; write port, dword
	; dx = port number
	int	34h
	pop	ebx
_pregw2:
        mov     eax, ebx		; restore eax
        and     eax, NOT_PCI32_PCI16	; clear out data size request
        mov     edx, ecx		; restore dx
	pop	ecx
	pop	ebx
	retn

pciRegWrite8:
        and     eax, NOT_PCI32_PCI16	; set up 8 bit write size
        jmp	short pciRegWrite	; call generic PCI access

pciRegWrite16:
        and     eax, NOT_PCI32_PCI16	; set up 16 bit write size
        or      eax, PCI16		; call generic PCI access
        jmp	short pciRegWrite

pciRegWrite32:
        and     eax, NOT_PCI32_PCI16	; set up 32 bit write size
        or      eax, PCI32		; call generic PCI access
        jmp	pciRegWrite

; --------------------------------------------------------
; 19/05/2024 - (playwav4.asm) ac97_vra.asm
; --------------------------------------------------------

	; 13/11/2023

;VRA:	db 1

codecConfig:
	; 29/05/2024 (playwav7.s modification)
	; 19/05/2024
	; 19/11/2023
	; 15/11/2023
	; 04/11/2023
	; 17/02/2017 
	; 07/11/2016 (Erdogan Tan)

	;AC97_EA_VRA equ 1
	AC97_EA_VRA equ BIT0

	; 04/11/2023
init_ac97_controller:
	mov	eax, [bus_dev_fn]
	mov	al, PCI_CMD_REG
	call	pciRegRead16		; read PCI command register
	or      dl, IO_ENA+BM_ENA	; enable IO and bus master
	call	pciRegWrite16

	;call	delay_100ms

	; 19/05/2024
	; ('PLAYMOD3.ASM', Erdogan Tan, 18/05/2024)

init_ac97_codec:
	; 18/11/2023
	mov	ebp, 40
	; 29/05/2024
	;mov	ebp, 1000
_initc_1:
	; 29/05/2024
	mov	dx, GLOB_STS_REG ; 30h
	add	dx, [NABMBAR]
	;in	eax, dx
	mov	ah, 4	; read port, dword
	int	34h

	; 19/05/2024
	;call	delay1_4ms

	cmp	eax, 0FFFFFFFFh ; -1
	jne	short _initc_3
_initc_2:
	dec	ebp
	jz	short _ac97_codec_ready

	; 31/05/2024
	call	delay_100ms
	jmp	short _initc_1
_initc_3:
	test	eax, CTRL_ST_CREADY
	jnz	short _ac97_codec_ready

	; 30/05/2024
	cmp	byte [reset], 1
	jnb	short _initc_2

	call	reset_ac97_codec
	; 30/05/2024
	mov	byte [reset], 1
	; 19/05/2024
	jmp	short _initc_2

_ac97_codec_ready:
	mov	dx, [NAMBAR]
	;add	dx, 0 ; ac_reg_0 ; reset register
	;out	dx, ax
	; 29/05/2024
	push	ebx
	mov	ebx, eax ; bx = data, word
	mov	ah, 3	; write port, word
	int	34h
	pop	ebx

	; 31/05/2024
	; 29/05/2024
	;call	delay_100ms

	; 19/11/2023
	or	ebp, ebp
	jnz	short _ac97_codec_init_ok

	xor	eax, eax ; 0
	mov	dx, [NAMBAR]
	add	dx, CODEC_REG_POWERDOWN
	;out	dx, ax
	; 29/05/2024
	push	ebx
	mov	ebx, eax
	mov	ah, 3	; write port, word
	int	34h
	pop	ebx
	
	; 19/11/2023
	; wait for 1 second
	; 19/05/2024
	mov	ecx, 1000 ; 1000*4*0.25ms = 1s
	;;mov	ecx, 10
	; 30/05/2024
	;mov	ecx, 40
_ac97_codec_rloop:
	;call	delay_100ms
	; 31/05/2024
	call	delay1_4ms

	;mov	dx, [NAMBAR]
	;add	dx, CODEC_REG_POWERDOWN
	;in	ax, dx
	; 29/05/2024
	mov	dx, [NAMBAR]
	add	dx, CODEC_REG_POWERDOWN
	; 31/05/2024
	mov	ah, 2	; read port, word
	int	34h

	; 31/05/2024
	;call	delay1_4ms
	
	and	ax, 0Fh
	cmp	al, 0Fh
	je	short _ac97_codec_init_ok
	loop	_ac97_codec_rloop 

init_ac97_codec_err1:
	;stc	; cf = 1 ; 19/05/2024
init_ac97_codec_err2:
	retn

_ac97_codec_init_ok:
	call 	reset_ac97_controller

	; 31/05/2024
	; 30/05/2024
	; 19/05/2024
	;call	delay_100ms

	; 30/05/2024
	;call	delay1_4ms
	;call	delay1_4ms
	;call	delay1_4ms
	;call	delay1_4ms

setup_ac97_codec:
	; 12/11/2023
	cmp	word [sample_rate], 48000
	je	skip_rate
	
	; 31/05/2024
	; 30/05/2024
	; 29/05/2024
	;cmp	byte [VRA], 0
	;jna	short skip_rate

	; 11/11/2023
	mov	dx, [NAMBAR]
	add	dx, CODEC_EXT_AUDIO_CTRL_REG  	; 2Ah
	;in	ax, dx
	; 29/05/2024
	mov	ah, 2 ; read port, word
	int	34h

	; 30/05/2024
	; 19/05/2024
	call	delay1_4ms

	;and	al, ~BIT1 ; Clear DRA
	;;;
	; 30/05/2024
	and	al, ~(BIT1+BIT0) ; Clear DRA+VRA
	;out	dx, ax
	; 31/05/2024
	push	ebx
	mov	ebx, eax
	mov	dx, [NAMBAR]
	add	dx, CODEC_EXT_AUDIO_CTRL_REG  	; 2Ah
	mov	ah, 3 ; write port, word
	int	34h
	pop	ebx

	; 31/05/2024
	call	check_vra

	; 31/05/2024 - temporary (interpolated sample rate test)
	;mov	byte [VRA], 0

	; 31/05/2024
	cmp	byte [VRA], 0
	jna	short skip_rate

	mov	dx, [NAMBAR]
	add	dx, CODEC_EXT_AUDIO_CTRL_REG  	; 2Ah
	;in	ax, dx
	; 31/05/2024
	mov	ah, 2 ; read port, word
	int	34h

	;and	al, ~BIT1 ; Clear DRA
	;;;

	or	al, AC97_EA_VRA ; 1 ; 04/11/2023
	;out	dx, ax			; Enable variable rate audio
	; 29/05/2024
	push	ebx
	mov	ebx, eax
	;
	; 30/05/2024
	mov	dx, [NAMBAR]
	add	dx, CODEC_EXT_AUDIO_CTRL_REG  	; 2Ah
	;
	mov	ah, 3 ; write port, word
	int	34h
	pop	ebx

	;mov	cx, 10
	mov	ecx, 10 ; 30/05/2024
check_vra_loop:
	; 31/05/2024
	;call	delay_100ms
	; 30/05/2024
	call	delay1_4ms

	; 11/11/2023
	;in	ax, dx
	; 29/05/2024
	mov	dx, [NAMBAR]
	add	dx, CODEC_EXT_AUDIO_CTRL_REG  	; 2Ah
	mov	ah, 2 ; read port, word
	int	34h

	test	al, AC97_EA_VRA ; 1
	jnz	short set_rate

	; 11/11/2023
	loop	check_vra_loop

;vra_not_supported:	; 19/05/2024
	mov	byte [VRA], 0
	jmp	short skip_rate

set_rate:
	mov	ax, [sample_rate] ; 17/02/2017 (Erdogan Tan)

	mov    	dx, [NAMBAR]               	
	add    	dx, CODEC_PCM_FRONT_DACRATE_REG	; 2Ch  	  
	;out	dx, ax 			; PCM Front/Center Output Sample Rate
	; 29/05/2024
	push	ebx
	mov	ebx, eax  ; bx = data, word
	mov	ah, 3 ; write port, word
	int	34h
	pop	ebx

	; 29/05/2024
	;call	delay_100ms
	; 30/05/2024
	;call	delay1_4ms

	; 12/11/2023
skip_rate:
	mov	ax, 0202h
  	mov	dx, [NAMBAR]
  	add	dx, CODEC_MASTER_VOL_REG	;02h 
	;out	dx, ax
	; 29/05/2024
	push	ebx
	mov	ebx, eax  ; bx = data, word
	mov	ah, 3 ; write port, word
	int	34h
	pop	ebx

	; 29/05/2024
	;call	delay1_4ms
	;call	delay1_4ms
	;call	delay1_4ms
	;call	delay1_4ms

	mov	ax, 0202h
  	mov	dx, [NAMBAR]
  	add	dx, CODEC_PCM_OUT_REG		;18h 
  	;out	dx, ax
	; 29/05/2024
	push	ebx
	mov	ebx, eax  ; bx = data, word
	mov	ah, 3 ; write port, word
	int	34h
	pop	ebx

 	; 29/05/2024
	;call	delay1_4ms
	;call	delay1_4ms
	;call	delay1_4ms
	;call	delay1_4ms

	; 19/05/2024
	;clc

        retn

reset_ac97_controller:
	; 29/05/2024 (TRDOS 386)
	; 19/05/2024
	; 11/11/2023
	; 10/06/2017
	; 29/05/2017
	; 28/05/2017
	; reset AC97 audio controller registers
	xor	eax, eax
        mov	dx, PI_CR_REG
	add	dx, [NABMBAR]
	;out	dx, al
	; 29/05/2024
	; al = data, byte
	mov	ah, 1 ; write port, byte
	int	34h

	; 19/05/2024
	;call	delay1_4ms

        mov     dx, PO_CR_REG
	add	dx, [NABMBAR]
	;out	dx, al
	; 29/05/2024
	; al = data, byte
	mov	ah, 1 ; write port, byte
	int	34h

	; 19/05/2024
	;call	delay1_4ms

        mov     dx, MC_CR_REG
	add	dx, [NABMBAR]
	;out	dx, al
	; 29/05/2024
	; al = data, byte
	mov	ah, 1 ; write port, byte
	int	34h

	; 19/05/2024
	;call	delay1_4ms

        mov	al, RR
        mov	dx, PI_CR_REG
	add	dx, [NABMBAR]
	;out	dx, al
	; 29/05/2024
	; al = data, byte
	mov	ah, 1 ; write port, byte
	int	34h

	; 19/05/2024
	;call	delay1_4ms

        mov	dx, PO_CR_REG
	add	dx, [NABMBAR]
	;out	dx, al
	; 29/05/2024
	; al = data, byte
	mov	ah, 1 ; write port, byte
	int	34h

	; 19/05/2024
	;call	delay1_4ms

        mov	dx, MC_CR_REG
	add	dx, [NABMBAR]
	;out	dx, al
	; 29/05/2024
	; al = data, byte
	mov	ah, 1 ; write port, byte
	int	34h

	; 19/05/2024
	;call	delay1_4ms

	retn

reset_ac97_codec:
	; 29/05/2024 (TRDOS 386)
	; 11/11/2023
	; 28/05/2017 - Erdogan Tan (Ref: KolibriOS, intelac97.asm)
	mov	dx, GLOB_CNT_REG ; 2Ch
	add	dx, [NABMBAR]
	;in	eax, dx
	; 29/05/2024
	mov	ah, 4 ; read port, dword
	int	34h

	;test	eax, 2
	; 06/08/2022
	test	al, 2
	jz	short _r_ac97codec_cold	

	call	warm_ac97codec_reset
	jnc	short _r_ac97codec_ok
_r_ac97codec_cold:
        call	cold_ac97codec_reset
        jnc	short _r_ac97codec_ok
	
	; 16/04/2017
        ;xor	eax, eax	; timeout error
       	;stc
	retn

_r_ac97codec_ok:
        xor     eax, eax
        ;mov	al, VIA_ACLINK_C00_READY ; 1
        inc	al
	retn

warm_ac97codec_reset:
	; 29/05/2024 (TRDOS 386)
	; 11/11/2023
	; 06/08/2022 - TRDOS 386 v2.0.5
	; 28/05/2017 - Erdogan Tan (Ref: KolibriOS, intelac97.asm)
	mov	eax, 6
	mov	dx, GLOB_CNT_REG ; 2Ch
	add	dx, [NABMBAR]
	;out	dx, eax
	; 29/05/2024
	push	ebx
	mov	ebx, eax  ; ebx = data, dword
	mov	ah, 5 ; write port, dword
	int	34h
	pop	ebx

	; 30/05/2024
	mov	ecx, 10	; total 1s
	; 29/05/2024
	;mov	ecx, 4000
_warm_ac97c_rst_wait:
	; 30/05/2024
	call	delay_100ms

	mov	dx, GLOB_STS_REG ; 30h
	add	dx, [NABMBAR]
	;in	eax, dx
	; 29/05/2024
	mov	ah, 4 ; read port, dword
	int	34h

	test	eax, CTRL_ST_CREADY
	jnz	short _warm_ac97c_rst_ok

	dec	ecx
	jnz	short _warm_ac97c_rst_wait

_warm_ac97c_rst_fail:
        stc
_warm_ac97c_rst_ok:
	retn

cold_ac97codec_reset:
	; 11/11/2023
	; 06/08/2022 - TRDOS 386 v2.0.5
	; 28/05/2017 - Erdogan Tan (Ref: KolibriOS, intelac97.asm)
        mov	eax, 2
	mov	dx, GLOB_CNT_REG ; 2Ch
	add	dx, [NABMBAR]
	;out	dx, eax
	; 29/05/2024
	push	ebx
	mov	ebx, eax  ; ebx = data, dword
	mov	ah, 5 ; write port, dword
	int	34h
	pop	ebx

	; 30/05/2024
	call	delay_100ms 	; wait 100 ms
	call	delay_100ms 	; wait 100 ms
	call	delay_100ms 	; wait 100 ms
	call	delay_100ms 	; wait 100 ms

	; 30/05/2024
	mov	ecx, 16	; total 20*100 ms = 2s
	; 29/05/2024
	;mov	ecx, 16000
_cold_ac97c_rst_wait:
	mov	dx, GLOB_STS_REG ; 30h
	add	dx, [NABMBAR]
	;in	eax, dx
	; 29/05/2024
	mov	ah, 4 ; read port, dword
	int	34h

	test	eax, CTRL_ST_CREADY
	jnz	short _cold_ac97c_rst_ok

	; 30/05/2024
	; 29/05/2024
	call	delay_100ms

	dec	ecx
	jnz	short _cold_ac97c_rst_wait

_cold_ac97c_rst_fail:
        stc
_cold_ac97c_rst_ok:
	retn

; 30/05/2024
%if 1
check_vra:
	; 29/05/2024
	mov	byte [VRA], 1

	; 29/05/2024 - audio.s (TRDOS 386 Kernel) - 27/05/2024
	; 24/05/2024
	; 23/05/2024
	mov	dx, [NAMBAR]
	add	dx, CODEC_EXT_AUDIO_REG	; 28h
	;in	ax, dx
	; 29/05/2024
	mov	ah, 2 ; read port, word
	int	34h

	; 30/05/2024
	; 23/05/2024
	call	delay1_4ms

	; 29/05/2024
	test	al, BIT0
	;test	al, 1 ; BIT0 ; Variable Rate Audio bit
	jnz	short check_vra_ok

vra_not_supported:
	; 13/11/2023
	mov	byte [VRA], 0
check_vra_ok:
	retn
%endif

; --------------------------------------------------------

PORTB		EQU 061h
REFRESH_STATUS	EQU 010h	; Refresh signal status

delay_100ms:
	push	ecx
	mov	ecx, 400  ; 400*0.25ms
_delay_x_ms:
	call	delay1_4ms
        loop	_delay_x_ms
	pop	ecx
	retn

delay1_4ms:
	; 30/05/2024 (TRDOS 386)
        push    eax 
        push    ecx
	push	ebx
	push	edx
        mov     ecx, 16			; close enough.
	;in	al, PORTB
	; 30/05/2024
	mov	dx, PORTB
	mov	ah, 0  ; read port, byte
	int	34h

	and	al, REFRESH_STATUS
	;mov	ah, al			; Start toggle state
	mov	bl, al
	or	ecx, ecx
	jz	short _d4ms1
	inc	ecx			; Throwaway first toggle
_d4ms1:	
	;in	al, PORTB		; Read system control port
	; 30/05/2024
	mov	dx, PORTB
	mov	ah, 0  ; read port, byte
	int	34h

	and	al, REFRESH_STATUS	; Refresh toggles 15.085 microseconds
	;cmp	ah, al
	cmp	bl, al
	je	short _d4ms1		; Wait for state change

	;mov	ah, al			; Update with new state
	mov	bl, al
	dec	ecx
	jnz	short _d4ms1

	pop	edx
        pop	ebx
	pop	ecx
        pop	eax
        retn

; --------------------------------------------------------
; 19/05/2024 - (playwav4.asm) ich_wav4.asm
; --------------------------------------------------------

check4keyboardstop:
	; 29/05/2024 (TRDOS 386)
	; 19/05/2024
	; 08/11/2023
	; 06/11/2023
	; 04/11/2023
	mov	ah, 1
	;int	16h
	int	32h	; TRDOS 386
	;clc
	jz	short _cksr

	xor	ah, ah
	;int	16h
	int	32h	; TRDOS 386

	;;;
	; 19/05/2024 (change PCM out volume)
	cmp	al, '+'
	jne	short p_1
	
	mov	al, [volume]
	cmp	al, 0
	jna	short p_3
	dec	al
	jmp	short p_2
p_1:
	cmp	al, '-'
	jne	short p_4

	mov	al, [volume]
	cmp	al, 31
	jnb	short p_3
	inc	al
p_2:
	mov	[volume], al
	mov	ah, al
	mov     dx, [NAMBAR]
  	;add    dx, CODEC_MASTER_VOL_REG
	add	dx, CODEC_PCM_OUT_REG
	;out	dx, ax
	; 29/05/2024
	push	ebx
	mov	ebx, eax ; bx = data, word
	mov	ah, 3 ; write port, word
	int	34h
	pop	ebx

	;call	delay1_4ms
        ;call	delay1_4ms
        ;call	delay1_4ms
        ;call	delay1_4ms
_cksr:		; 19/05/2024
	clc
p_3:
	retn
p_4:
	;;;
;_cskr:	
	stc
	retn

; returns AL = current index value
getCurrentIndex:
	; 29/05/2024 (TRDOS 386)
	; 08/11/2023
	mov	dx, [NABMBAR]
	add	dx, PO_CIV_REG
	;in	al, dx
	; 29/05/2024
	mov	ah, 0 ; read port, byte
	int	34h
uLVI2:	;	06/11/2023
	retn

updateLVI:
	; 29/05/2024 (TRDOS 386)
	; 08/11/2023
	; 07/11/2023
	; 06/11/2023
	mov	dx, [NABMBAR]
	add	dx, PO_CIV_REG
	; (Current Index Value and Last Valid Index value)
	;in	ax, dx
	; 29/05/2024
	mov	ah, 2 ; read port, word
	int	34h

	cmp	al, ah ; is current index = last index ?
	jne	short uLVI2

	; 08/11/2023	
	call	getCurrentIndex
 
	test	byte [flags], ENDOFFILE
	;jnz	short uLVI1
	jz	short uLVI0  ; 08/11/2023

	; 08/11/2023
	push	eax	; 29/05/2024 (32 bit)
	mov	dx, [NABMBAR]
	add	dx, PO_SR_REG  ; PCM out status register
	;in	ax, dx
	; 29/05/2024
	mov	ah, 2 ; read port, word
	int	34h

	test	al, 3 ; bit 1 = Current Equals Last Valid (CELV)
		      ; (has been processed)
		      ; bit 0 = 1 -> DMA Controller Halted (DCH)
	pop	eax
	jz	short uLVI1
uLVI3:
	xor	eax, eax
	; zf = 1
	retn
uLVI0:
        ; not at the end of the file yet.
	dec	al
	and	al, 1Fh
uLVI1:
	;call	setLastValidIndex
;uLVI2:
	;retn

;input AL = index # to stop on
setLastValidIndex:
	; 29/05/2024 (TRDOS 386)
	; 08/11/2023
	mov	dx, [NABMBAR]
	add	dx, PO_LVI_REG
        ;out	dx, al
	; 29/05/2024
	; al = data, byte
	mov	ah, 1 ; write port, byte
	int	34h
	retn

; 29/05/2024
; 19/05/2024
volume: db	02h
	
; --------------------------------------------------------

; DATA

FileHandle:	
	dd	-1

; 30/05/2024
reset:	db	0

Credits:
	db	'Tiny WAV Player for TRDOS 386 by Erdogan Tan. '
	;db	'August 2020.',10,13,0
	db	'May 2024.',10,13,0
	db	'17/06/2017', 10,13,0
	db	'18/08/2020', 10,13,0
	db	'27/11/2023', 10,13,0
	db	'29/05/2024', 10,13,0

msgAudioCardInfo:
	db 	'for Intel AC97 (ICH) Audio Controller.', 10,13,0

msg_usage:
	db	'usage: playwav7 filename.wav',10,13,0 ; 29/05/2024

noDevMsg:
	db	'Error: Unable to find AC97 audio device!'
	db	10,13,0

noFileErrMsg:
	db	'Error: file not found.',10,13,0

msg_error:	; 29/05/2024
trdos386_err_msg:
	db	'TRDOS 386 System call error !',10,13,0

; 29/05/2024
; 11/11/2023
msg_init_err:
	db	CR, LF
	db	"AC97 Controller/Codec initialization error !"
	db	CR, LF, "$"

; 25/11/2023
msg_no_vra:
	db	10,13
	db	"No VRA support ! Only 48 kHZ sample rate supported !"
	db	10,13,0

; 29/05/2024 (TRDOS 386)
; 17/02/2017
; Valid ICH device IDs

valid_ids:
dd	(ICH_DID << 16) + INTEL_VID  	 ; 8086h:2415h
dd	(ICH0_DID << 16) + INTEL_VID 	 ; 8086h:2425h
dd	(ICH2_DID << 16) + INTEL_VID 	 ; 8086h:2445h
dd	(ICH3_DID << 16) + INTEL_VID 	 ; 8086h:2485h
dd	(ICH4_DID << 16) + INTEL_VID 	 ; 8086h:24C5h
dd	(ICH5_DID << 16) + INTEL_VID 	 ; 8086h:24D5h
dd	(ICH6_DID << 16) + INTEL_VID 	 ; 8086h:266Eh
dd	(ESB6300_DID << 16) + INTEL_VID  ; 8086h:25A6h
dd	(ESB631X_DID << 16) + INTEL_VID  ; 8086h:2698h
dd	(ICH7_DID << 16) + INTEL_VID 	 ; 8086h:27DEh
; 03/11/2023 - Erdogan Tan
dd	(MX82440_DID << 16) + INTEL_VID  ; 8086h:7195h
dd	(SI7012_DID << 16)  + SIS_VID	 ; 1039h:7012h
dd 	(NFORCE_DID << 16)  + NVIDIA_VID ; 10DEh:01B1h
dd 	(NFORCE2_DID << 16) + NVIDIA_VID ; 10DEh:006Ah
dd 	(AMD8111_DID << 16) + AMD_VID 	 ; 1022h:746Dh
dd 	(AMD768_DID << 16)  + AMD_VID 	 ; 1022h:7445h
dd 	(CK804_DID << 16) + NVIDIA_VID	 ; 10DEh:0059h
dd 	(MCP04_DID << 16) + NVIDIA_VID	 ; 10DEh:003Ah
dd 	(CK8_DID << 16) + NVIDIA_VID	 ; 1022h:008Ah
dd 	(NFORCE3_DID << 16) + NVIDIA_VID ; 10DEh:00DAh
dd 	(CK8S_DID << 16) + NVIDIA_VID	 ; 10DEh:00EAh

valid_id_count:	equ ($ - valid_ids)>>2 ; 05/11/2023

msgWavFileName:	db 0Dh, 0Ah, "WAV File Name: ",0
msgSampleRate:	db 0Dh, 0Ah, "Sample Rate: "
msgHertz:	db "00000 Hz, ", 0 
msg8Bits:	db "8 bits, ", 0 
msgMono:	db "Mono", 0Dh, 0Ah, 0
msg16Bits:	db "16 bits, ", 0 
msgStereo:	db "Stereo"
nextline:	db 0Dh, 0Ah, 0

; 03/06/2017
hex_chars	db "0123456789ABCDEF", 0
msgAC97Info	db 0Dh, 0Ah
		db "AC97 Audio Controller & Codec Info", 0Dh, 0Ah 
		db "Vendor ID: "
msgVendorId	db "0000h Device ID: "
msgDevId	db "0000h", 0Dh, 0Ah
		db "Bus: "
msgBusNo	db "00h Device: "
msgDevNo	db "00h Function: "
msgFncNo	db "00h"
		db 0Dh, 0Ah
		db "NAMBAR: "
msgNamBar	db "0000h  "
		db "NABMBAR: "
msgNabmBar	db "0000h  IRQ: "
msgIRQ		dw 3030h
		db 0Dh, 0Ah, 0
; 25/11/2023
msgVRAheader:	db "VRA support: "
		db 0	
msgVRAyes:	db "YES", 0Dh, 0Ah, 0
msgVRAno:	db "NO ", 0Dh, 0Ah
		db "(Interpolated sample rate playing method)"
		db 0Dh, 0Ah, 0
EOF: 

; BSS

bss_start:

ABSOLUTE bss_start

alignb 4

stmo:		resb 1 ; stereo or mono (1=stereo) 
bps:		resb 1 ; bits per sample (8,16)
sample_rate:	resw 1 ; Sample Frequency (Hz)

; 31/05/2024
; 25/11/2023
;bufferSize:	resd 1

flags:		resb 1

; 29/05/2024
;;cbs_busy:	resb 1
;half_buff:	resb 1
;srb:		resb 1

; 30/05/2024
; 18/08/2020
;volume_level:	resb 1
; 25/11/2023
VRA:		resb 1	; Variable Rate Audio Support Status

smpRBuff:	resw 14 

wav_file_name:
		resb 80 ; wave file, path name (<= 80 bytes)

		resw 1
ac97_int_ln_reg: resb 1
fbs_shift:	resb 1 ; 26/11/2023
dev_vendor:	resd 1
bus_dev_fn:	resd 1
;ac97_NamBar:	resw 1
;ac97_NabmBar:	resw 1

; 29/05/2024
; 17/02/2017
; NAMBAR:  Native Audio Mixer Base Address Register
;    (ICH, Audio D31:F5, PCI Config Space) Address offset: 10h-13h
; NABMBAR: Native Audio Bus Mastering Base Address register
;    (ICH, Audio D31:F5, PCI Config Space) Address offset: 14h-17h
NAMBAR:		resw 1			; BAR for mixer
NABMBAR:	resw 1			; BAR for bus master regs

; 29/05/2024
audio_buffer:	resd 1
; 29/05/2024
_bdl_buffer:	resd 1
;wav_buffer1:	resd 1
;wav_buffer2:	resd 1

bss_end:

alignb 4096
		; 256 byte buffer for descriptor list
BDL_BUFFER:	resb 256

alignb 4096

;audio_buffer:	resb BUFFERSIZE ; DMA Buffer Size / 2 (32768)
; 29/05/2024
; 26/11/2023
;audio_buffer:	resb 65536
; 29/05/2024
WAVBUFFER_1:	resb 65536
WAVBUFFER_2:	resb 65536
; 13/06/2017
;temp_buffer:	resb BUFFERSIZE
; 26/11/2023
temp_buffer:	resb 65536
