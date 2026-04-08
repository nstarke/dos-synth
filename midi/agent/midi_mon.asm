; midi_mon.asm
; compile: nasm -f bin -o midi_mon.com midi_mon.asm
;
; Foreground MIDI monitor.  Initialises the MPU-401 at I/O 0x330 in UART
; mode and prints every complete MIDI message to stdout.  Press any key
; to quit.  Useful for verifying that the MIDI bridge → 86Box → MPU-401
; chain is working before running midi_inject.com with a synthesizer.
;
; Example output:
;   NoteOn   ch:1  note:60(C4)   vel:127
;   NoteOff  ch:1  note:60(C4)   vel:0
;   CC       ch:1  ctrl:7  val:100
;   PrgChg   ch:1  val:0
;   PitchBd  ch:1  lsb:00  msb:40
;   RT       F8

    org 0x100

%define MPU_DATA  0x330
%define MPU_CMD   0x331
%define MPU_STAT  0x331
%define MPU_ONR   0x40      ; bit 6: set = MPU not ready for command
%define MPU_INR   0x80      ; bit 7: set = no incoming MIDI data

%define STATE_IDLE   0
%define STATE_D1     1      ; 2-data-byte msg: awaiting first data byte
%define STATE_D2     2      ; 2-data-byte msg: first byte saved, awaiting second
%define STATE_1BYTE  3      ; 1-data-byte msg: awaiting single data byte
%define STATE_SYSEX  4      ; inside SysEx stream

midi_status  db 0
midi_d1      db 0
midi_d2      db 0
midi_state   db STATE_IDLE

; ============================================================
; Entry point
; ============================================================
start:
    mov dx, msg_banner
    mov ah, 9
    int 21h

    call mpu_init
    jc .no_mpu

    mov dx, msg_ready
    mov ah, 9
    int 21h

.loop:
    ; Non-blocking keyboard check (INT 16h AH=1 sets ZF if no key)
    mov ah, 1
    int 16h
    jnz .quit

    ; Poll MPU-401 data port
    mov dx, MPU_STAT
    in al, dx
    test al, MPU_INR        ; bit 7 set = no data yet
    jnz .loop

    mov dx, MPU_DATA
    in al, dx
    call proc_byte
    jmp .loop

.quit:
    mov ah, 0               ; consume the keypress
    int 16h
    mov dx, msg_done
    mov ah, 9
    int 21h
    mov ax, 0x4C00
    int 21h

.no_mpu:
    mov dx, msg_no_mpu
    mov ah, 9
    int 21h
    mov ax, 0x4C01
    int 21h

; ============================================================
; mpu_init: enter UART mode.  Returns CF clear on success.
;
; 86Box starts the MPU-401 in UART mode by default.  Sending
; RESET (0xFF) in UART mode causes 86Box to return WITHOUT
; queuing an ACK, and sending 0x3F while still in UART mode
; is silently ignored (per spec: only 0xFF is accepted in
; UART mode).  So we skip the reset and send 0x3F directly:
;   - If in intelligent mode → ACK arrives, we verify it.
;   - If already in UART mode → 0x3F is ignored, no ACK;
;     that is the normal 86Box startup case, so we proceed.
;
; We only report failure if the status port doesn't look like
; an MPU-401 at all (bits 0-5 must always read as 1).
; ============================================================
mpu_init:
    ; Presence check: bits 0-5 of status are always 1 on a real MPU-401.
    mov dx, MPU_STAT
    in al, dx
    and al, 0x3F
    cmp al, 0x3F
    jne .fail               ; port absent or wrong device

    ; Wait until output ready (bit 6 clear)
    mov cx, 0xFFFF
.w: mov dx, MPU_STAT
    in al, dx
    test al, MPU_ONR
    loopnz .w

    ; Send UART mode command
    mov al, 0x3F
    mov dx, MPU_CMD
    out dx, al

    ; Wait for ACK with generous timeout
    mov cx, 0xFFFF
.r: mov dx, MPU_STAT
    in al, dx
    test al, MPU_INR        ; bit 7: set = no data
    loopnz .r
    jnz .no_ack             ; timeout → already in UART mode, proceed

    mov dx, MPU_DATA
    in al, dx               ; read and discard ACK (0xFE)

.no_ack:
    clc
    ret
.fail:
    stc
    ret

; ============================================================
; proc_byte: feed one MIDI byte in AL through the state machine.
; Prints complete messages to stdout.
; ============================================================
proc_byte:
    ; Real-time messages (0xF8-0xFF): single byte, print, no state change
    cmp al, 0xF8
    jae .realtime

    ; SysEx end (0xF7)
    cmp al, 0xF7
    jne .not_f7
    mov byte [midi_state], STATE_IDLE
    mov si, str_eox
    call puts
    call crlf
    ret
.not_f7:

    ; Status byte (bit 7 set)?
    test al, 0x80
    jz .data

    ; ── New status byte ──
    mov [midi_status], al
    mov ah, al
    and ah, 0xF0

    cmp al, 0xF0
    je .sysex_start

    ; 1-data-byte messages
    cmp ah, 0xC0            ; Program Change
    je .set_1byte
    cmp ah, 0xD0            ; Channel Pressure
    je .set_1byte
    cmp al, 0xF1            ; MIDI Time Code
    je .set_1byte
    cmp al, 0xF3            ; Song Select
    je .set_1byte

    ; All others (NoteOn/Off, Aftertouch, CC, Pitch Bend, SPP): 2 data bytes
    mov byte [midi_state], STATE_D1
    ret

.set_1byte:
    mov byte [midi_state], STATE_1BYTE
    ret

.sysex_start:
    mov byte [midi_state], STATE_SYSEX
    mov si, str_sysex
    call puts               ; print "SysEx   " prefix; bytes follow on same line
    ret

.realtime:
    mov si, str_rt
    call puts
    call print_hex8         ; print the byte as hex
    call crlf
    ret

    ; ── Data byte ──
.data:
    mov bl, [midi_state]

    cmp bl, STATE_SYSEX
    jne .chk_d1
    call print_hex8         ; print SysEx byte in-line
    mov al, ' '
    call putc
    ret

.chk_d1:
    cmp bl, STATE_D1
    jne .chk_d2
    mov [midi_d1], al
    mov byte [midi_state], STATE_D2
    ret

.chk_d2:
    cmp bl, STATE_D2
    jne .chk_1b
    mov [midi_d2], al
    call print_msg2
    mov byte [midi_state], STATE_D1   ; running status: wait for next D1
    ret

.chk_1b:
    cmp bl, STATE_1BYTE
    jne .pb_done
    mov [midi_d1], al
    call print_msg1
    ; stay in STATE_1BYTE for running status
.pb_done:
    ret

; ============================================================
; print_msg2: print a complete 2-data-byte message.
;   [midi_status]  status byte
;   [midi_d1]      first data byte
;   [midi_d2]      second data byte
; ============================================================
print_msg2:
    mov al, [midi_status]
    mov ah, al
    and ah, 0xF0            ; AH = message type nibble
    mov cl, al
    and cl, 0x0F            ; CL = channel 0-15

    cmp ah, 0x80
    je .note_off
    cmp ah, 0x90
    je .note_on
    cmp ah, 0xA0
    je .key_pres
    cmp ah, 0xB0
    je .ctrl_chg
    cmp ah, 0xE0
    je .pitch_bend

    ; Unknown / Song Position Pointer etc: hex dump
    mov si, str_unk
    call puts
    mov al, [midi_status]
    call print_hex8
    mov al, ' '
    call putc
    mov al, [midi_d1]
    call print_hex8
    mov al, ' '
    call putc
    mov al, [midi_d2]
    call print_hex8
    call crlf
    ret

.note_on:
    ; NoteOn with velocity 0 is treated as NoteOff
    cmp byte [midi_d2], 0
    jne .real_on
.note_off:
    mov si, str_noteoff
    call puts
    jmp .note_common
.real_on:
    mov si, str_noteon
    call puts
.note_common:
    mov al, cl
    call print_ch
    mov al, [midi_d1]
    call print_note
    mov si, str_vel
    call puts
    mov al, [midi_d2]
    call print_dec8
    call crlf
    ret

.key_pres:
    mov si, str_keypres
    call puts
    mov al, cl
    call print_ch
    mov al, [midi_d1]
    call print_note
    mov si, str_val
    call puts
    mov al, [midi_d2]
    call print_dec8
    call crlf
    ret

.ctrl_chg:
    mov si, str_cc
    call puts
    mov al, cl
    call print_ch
    mov si, str_ctrl
    call puts
    mov al, [midi_d1]
    call print_dec8
    mov si, str_val
    call puts
    mov al, [midi_d2]
    call print_dec8
    call crlf
    ret

.pitch_bend:
    mov si, str_pitch
    call puts
    mov al, cl
    call print_ch
    mov si, str_lsb
    call puts
    mov al, [midi_d1]
    call print_hex8
    mov si, str_msb
    call puts
    mov al, [midi_d2]
    call print_hex8
    call crlf
    ret

; ============================================================
; print_msg1: print a complete 1-data-byte message.
;   [midi_status]  status byte
;   [midi_d1]      data byte
; ============================================================
print_msg1:
    mov al, [midi_status]
    mov cl, al
    and cl, 0x0F
    mov ah, al
    and ah, 0xF0

    cmp ah, 0xC0
    je .prog_chg
    cmp ah, 0xD0
    je .chan_pres

    ; Unknown (MTC, Song Select, etc.): hex dump
    mov si, str_unk
    call puts
    mov al, [midi_status]
    call print_hex8
    mov al, ' '
    call putc
    mov al, [midi_d1]
    call print_hex8
    call crlf
    ret

.prog_chg:
    mov si, str_prog
    call puts
    mov al, cl
    call print_ch
    mov si, str_val
    call puts
    mov al, [midi_d1]
    call print_dec8
    call crlf
    ret

.chan_pres:
    mov si, str_cpress
    call puts
    mov al, cl
    call print_ch
    mov si, str_val
    call puts
    mov al, [midi_d1]
    call print_dec8
    call crlf
    ret

; ============================================================
; print_ch: print "  ch:N" where N = AL + 1  (channels 1-16)
; ============================================================
print_ch:
    push ax
    mov si, str_ch
    call puts
    pop ax
    inc al
    jmp print_dec8          ; tail call

; ============================================================
; print_note: print "  note:NN(NAME)" e.g. "  note:60(C4)"
; ============================================================
print_note:
    push ax                 ; [1] save note number

    mov si, str_notelbl
    call puts

    pop ax                  ; [1]
    push ax                 ; [2] for name lookup
    call print_dec8         ; print note number

    mov al, '('
    call putc

    pop ax                  ; [2]
    xor ah, ah
    mov bl, 12
    div bl                  ; AL = note/12, AH = note%12

    push ax                 ; [3] save div result

    ; Look up note name: entry = 3 bytes, index = AH
    mov al, ah              ; name index 0-11
    xor ah, ah
    mov cl, 3
    mul cl                  ; AX = index * 3  (8-bit: AX = AL * CL)
    mov bx, note_names
    add bx, ax              ; BX -> 3-byte name entry

    mov al, [bx]            ; first char (always a letter A-G)
    call putc
    mov al, [bx+1]          ; second char: '#' or ' '
    cmp al, ' '
    je .natural
    call putc               ; print '#' for sharps
.natural:

    pop ax                  ; [3] AL = note/12
    dec al                  ; octave: MIDI 60 = C4, so 60/12 - 1 = 4
    js .neg_oct             ; notes 0-11 → octave -1
    add al, '0'
    call putc
    jmp .close

.neg_oct:                   ; only -1 is possible for valid MIDI (0-11)
    mov al, '-'
    call putc
    mov al, '1'
    call putc

.close:
    mov al, ')'
    call putc
    ret

; ============================================================
; print_hex8: print byte in AL as 2 uppercase hex digits
; ============================================================
print_hex8:
    push ax
    shr al, 4               ; high nibble
    call .nib
    pop ax
    and al, 0x0F            ; low nibble, fall through
.nib:
    cmp al, 10
    jb .digit
    add al, 'A' - 10
    jmp putc                ; tail call
.digit:
    add al, '0'
    jmp putc                ; tail call

; ============================================================
; print_dec8: print byte in AL as decimal, no leading zeros
; ============================================================
print_dec8:
    xor ah, ah
    xor cx, cx
.push:
    xor dx, dx
    mov bx, 10
    div bx                  ; AX = quotient, DX = remainder
    push dx
    inc cx
    or ax, ax
    jnz .push
.pop:
    pop dx
    mov al, dl
    add al, '0'
    call putc
    loop .pop
    ret

; ============================================================
; putc: write character in AL to stdout via INT 21h AH=2
; ============================================================
putc:
    push ax
    push dx
    mov dl, al
    mov ah, 2
    int 21h
    pop dx
    pop ax
    ret

; ============================================================
; puts: print null-terminated string pointed to by SI
; ============================================================
puts:
    push ax
    push si
.l: mov al, [si]
    or al, al
    jz .done
    call putc
    inc si
    jmp .l
.done:
    pop si
    pop ax
    ret

; ============================================================
; crlf: print CR LF
; ============================================================
crlf:
    mov al, 13
    call putc
    mov al, 10
    jmp putc                ; tail call

; ============================================================
; Data tables
; ============================================================

; 12 × 3 bytes: note name padded to 3 chars (trailing space = natural)
note_names:
    db 'C  ', 'C# ', 'D  ', 'D# ', 'E  ', 'F  '
    db 'F# ', 'G  ', 'G# ', 'A  ', 'A# ', 'B  '

msg_banner  db 'MIDI Monitor  (MPU-401 @ 0x330)  press any key to quit'
            db 13, 10, '$'
msg_ready   db 'Listening...', 13, 10, 13, 10, '$'
msg_done    db 13, 10, 'Stopped.', 13, 10, '$'
msg_no_mpu  db 'MPU-401 not found or did not ACK UART mode.', 13, 10, '$'

; Message-type labels (8 chars wide for alignment)
str_noteon  db 'NoteOn   ', 0
str_noteoff db 'NoteOff  ', 0
str_keypres db 'KeyPres  ', 0
str_cc      db 'CC       ', 0
str_pitch   db 'PitchBd  ', 0
str_prog    db 'PrgChg   ', 0
str_cpress  db 'ChnPres  ', 0
str_sysex   db 'SysEx    ', 0
str_eox     db '[EOX]', 0
str_rt      db 'RT       ', 0
str_unk     db '???      ', 0

; Field labels
str_ch      db '  ch:', 0
str_notelbl db '  note:', 0
str_vel     db '  vel:', 0
str_val     db '  val:', 0
str_ctrl    db '  ctrl:', 0
str_lsb     db '  lsb:', 0
str_msb     db '  msb:', 0
