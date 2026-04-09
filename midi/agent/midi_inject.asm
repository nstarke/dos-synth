; midi_inject.asm
; compile: nasm -f bin -o midi_inject.com midi_inject.asm
;
; TSR: reads MIDI note on/off from the Roland MPU-401 at I/O 0x330 and
; injects the corresponding XT Set-1 keyboard scancodes via 8042 command
; D2h (Write Keyboard Output Buffer), firing IRQ1/INT 9.  DOS synthesizers
; that hook the hardware keyboard interrupt detect the notes.
;
; Unlike the serial_inject approach (which sends make+break pairs for each
; byte received), this agent sends make-only on note-on and break-only on
; note-off, so the key appears held for the full MIDI note duration and the
; synthesizer sustains accordingly.
;
; Usage: MIDI_INJ [/VR | /FMS4 | /DEFAULT]
;   /VR      VR_DEMO.EXE key layout (awsdefyhujik), 12-note clamping
;   /FMS4    default layout, 12-note clamping only (no q-row keys)
;   /DEFAULT restore two-octave default layout
;
; If the TSR is already installed, re-running with a flag hot-swaps the
; active key layout without rebooting.  Running with no flag reports the
; current active mode.  /VR, /FMS4, and /DEFAULT are mutually exclusive.
;
; MIDI note mapping:
;   C   C#  D   D#  E   F   F#  G   G#  A   A#  B
;   z   s   x   d   c   v   g   b   h   n   j   m   (default, C3)
;   q   2   w   3   e   r   5   t   6   y   7   u   (default, C4)
;   a   w   s   d   e   f   y   h   u   j   i   k   (/VR, 12-note)
;
; Notes outside MIDI 48-71 are clamped to the nearest octave within range.
; All MIDI channels are accepted.  Running status is supported.
;
; MPU-401 status port 0x331 bit meanings (from 86box snd_mpu401.c):
;   bit 6 (0x40): STATUS_OUTPUT_NOT_READY  — when SET, MPU cannot accept cmd
;   bit 7 (0x80): STATUS_INPUT_NOT_READY   — when SET, no MIDI data to read

%define MPU_DATA    0x330
%define MPU_CMD     0x331
%define MPU_STAT    0x331
%define MPU_ONR     0x40    ; Output Not Ready (bit 6): poll before writing cmd
%define MPU_INR     0x80    ; Input Not Ready  (bit 7): poll before reading data

%define BASE_NOTE   48      ; lowest mapped MIDI note (C3)
%define NOTE_COUNT  24      ; number of mapped notes  (two octaves, all clamped)

%define MAX_PER_TICK 8      ; max MIDI bytes consumed per timer tick

%define STATE_IDLE  0
%define STATE_NK    1
%define STATE_NV    2
%define STATE_S1    3
%define STATE_S2    4
%define STATE_SX    5

    org 0x100
    jmp near install        ; forced near (3 bytes) so magic_id is always at 0x103

; ==================== RESIDENT DATA ====================

magic_id    dw 0x4D49       ; 'MI' — checked by re-runs to detect installed TSR
old_off     dw 0            ; saved INT 8 vector (offset)
old_seg     dw 0            ; saved INT 8 vector (segment)

; 8042 injection queue (circular, 16 entries)
sc_q        times 16 db 0
q_rd        db 0            ; consumer pointer
q_wr        db 0            ; producer pointer

; MIDI parser state machine
; States: 0=IDLE 1=NK(await note#) 2=NV(await velocity)
;         3=S1(skip 1 byte) 4=S2(skip 2nd of 2-byte msg) 5=SX(inside SysEx)
midi_state  db 0
midi_status db 0            ; running status (last status byte seen)
midi_note   db 0            ; note number latched in state NK→NV
use_vr      db 0            ; set to 1 when /VR flag is given
use_fms4    db 0            ; set to 1 when /FMS4 flag is given
note_hi     db BASE_NOTE + 24 ; exclusive upper bound for note clamping

; ==================== RESIDENT CODE ====================

; ------------------------------------------------------------------
; kbc_wait: spin until 8042 input buffer empty (port 0x64 bit 1 = 0)
; Destroys: AX, CX
; ------------------------------------------------------------------
kbc_wait:
    mov cx, 0x8000
.l: in  al, 0x64
    test al, 2
    loopnz .l
    ret

; ------------------------------------------------------------------
; kbc_inject: inject scancode in AL via 8042 cmd D2h → fires IRQ1/INT 9
; Destroys: AX, BX, CX
; ------------------------------------------------------------------
kbc_inject:
    mov bl, al
    call kbc_wait
    mov al, 0xD2
    out 0x64, al
    call kbc_wait
    mov al, bl
    out 0x60, al
    ret

; ------------------------------------------------------------------
; q_put: enqueue byte in AL into sc_q (discard if full).
; AL is preserved on return.  Destroys: BX, CX.
; ------------------------------------------------------------------
q_put:
    mov cl, al
    xor bx, bx
    mov bl, [cs:q_wr]
    inc bl
    and bl, 0x0F
    cmp bl, [cs:q_rd]
    je  .full               ; queue full, discard
    xor bx, bx
    mov bl, [cs:q_wr]
    and bl, 0x0F
    mov [cs:sc_q + bx], cl
    inc bl
    and bl, 0x0F
    mov [cs:q_wr], bl
.full:
    ret

; ------------------------------------------------------------------
; note_to_sc: look up XT Set-1 make code for MIDI note in AL.
; Notes outside BASE_NOTE..BASE_NOTE+NOTE_COUNT-1 are clamped by
; transposing up/down by octaves until in range.
; Returns: AL = make code (never 0 for a valid note after clamping).
; Destroys: AX, BX
; ------------------------------------------------------------------
note_to_sc:
    ; Clamp below range: add 12 until >= BASE_NOTE
.clamp_lo:
    cmp al, BASE_NOTE
    jae .clamp_hi
    add al, 12
    jmp .clamp_lo
    ; Clamp above range: subtract 12 until below note_hi
.clamp_hi:
    cmp al, [cs:note_hi]
    jb  .lookup
    sub al, 12
    jmp .clamp_hi
.lookup:
    sub al, BASE_NOTE       ; offset into table (0-11)
    xor bx, bx
    mov bl, al
    cmp byte [cs:use_vr], 0
    jne .vr_table
    mov al, [cs:note2sc + bx]
    ret
.vr_table:
    mov al, [cs:note2sc_vr + bx]
    ret

; ------------------------------------------------------------------
; proc_byte: run one MIDI byte through the state machine.
; Input: AL = MIDI byte.
; On note events, enqueues the make or break scancode.
; Destroys: AX, BX, CX (all already saved by handler08).
; ------------------------------------------------------------------
proc_byte:
    ; Real-time messages (F8-FF): single-byte, ignored, no state change
    cmp al, 0xF8
    jae .ret

    ; SysEx end (F7): exit SysEx state regardless of current state
    cmp al, 0xF7
    jne .not_f7
    mov byte [cs:midi_state], STATE_IDLE
    jmp .ret
.not_f7:

    ; Status byte? (bit 7 set)
    test al, 0x80
    jz  .data_byte

    ; ---- New status byte ----
    mov [cs:midi_status], al
    mov ah, al
    and ah, 0xF0

    cmp al, 0xF0
    je  .start_sysex

    ; Program Change (Cx) or Channel Pressure (Dx) → 1 data byte
    cmp ah, 0xC0
    je  .skip1
    cmp ah, 0xD0
    je  .skip1
    ; MIDI Time Code (F1) or Song Select (F3) → 1 data byte
    cmp al, 0xF1
    je  .skip1
    cmp al, 0xF3
    je  .skip1

    ; Note Off (8x) or Note On (9x) → 2 data bytes: note#, velocity
    cmp ah, 0x80
    je  .note_msg
    cmp ah, 0x90
    je  .note_msg

    ; All other 2-byte channel messages (Ax Bx Ex) and SPP (F2)
    mov byte [cs:midi_state], STATE_S2
    jmp .ret

.note_msg:
    mov byte [cs:midi_state], STATE_NK
    jmp .ret

.start_sysex:
    mov byte [cs:midi_state], STATE_SX
    jmp .ret

.skip1:
    mov byte [cs:midi_state], STATE_S1
    jmp .ret

    ; ---- Data byte: dispatch on current state ----
.data_byte:
    mov bl, [cs:midi_state]

    cmp bl, STATE_SX
    je  .ret                ; inside SysEx, discard

    cmp bl, STATE_S1
    jne .chk_s2
    mov byte [cs:midi_state], STATE_IDLE
    jmp .ret
.chk_s2:
    cmp bl, STATE_S2
    jne .chk_nk
    mov byte [cs:midi_state], STATE_S1
    jmp .ret
.chk_nk:
    cmp bl, STATE_NK
    jne .chk_nv
    ; Latch note number, advance to STATE_NV
    mov [cs:midi_note], al
    mov byte [cs:midi_state], STATE_NV
    jmp .ret
.chk_nv:
    cmp bl, STATE_NV
    jne .ret                ; STATE_IDLE + data byte: ignore

    ; ---- Complete note event: AL = velocity, midi_note = note# ----
    ; Restore to NK for running status (next note uses same status)
    mov byte [cs:midi_state], STATE_NK

    mov cl, al              ; CL = velocity
    mov al, [cs:midi_note]  ; AL = note number
    call note_to_sc         ; AL = XT make code

    ; Decide make vs break:
    ;   Note On (9x) with velocity > 0  → make (key down)
    ;   Note Off (8x) or vel = 0        → break (key up) = make | 0x80
    mov bh, [cs:midi_status]
    and bh, 0xF0
    cmp bh, 0x90            ; Note On?
    jne .do_break
    test cl, cl             ; velocity 0 = Note Off
    jnz .do_make

.do_break:
    or al, 0x80             ; break code = make | 0x80
.do_make:
    call q_put              ; enqueue make or break scancode

.ret:
    ret

; ------------------------------------------------------------------
; MIDI note → XT Set-1 make code lookup tables.
; Index 0 = BASE_NOTE (MIDI 48 = C3).
; note2sc    : 24 entries (C3–B4), default two-octave layout
; note2sc_fms: 12 entries (C3–B3), /FMS4 single-octave layout (same lower row)
; note2sc_vr :  12 entries (C3–B3), /VR layout
; ------------------------------------------------------------------
note2sc:
    ;  C3    C#3   D3    D#3   E3    F3    F#3   G3    G#3   A3    A#3   B3
    ;  z     s     x     d     c     v     g     b     h     n     j     m
    db 0x2C, 0x1F, 0x2D, 0x20, 0x2E, 0x2F, 0x22, 0x30, 0x23, 0x31, 0x24, 0x32
    ;  C4    C#4   D4    D#4   E4    F4    F#4   G4    G#4   A4    A#4   B4
    ;  q     2     w     3     e     r     5     t     6     y     7     u
    db 0x10, 0x03, 0x11, 0x04, 0x12, 0x13, 0x06, 0x14, 0x07, 0x15, 0x08, 0x16

note2sc_vr:
    ;  C3    C#3   D3    D#3   E3    F3    F#3   G3    G#3   A3    A#3   B3
    ;  a     w     s     d     e     f     y     h     u     j     i     k
    db 0x1E, 0x11, 0x1F, 0x20, 0x12, 0x21, 0x15, 0x23, 0x16, 0x24, 0x17, 0x25

; ------------------------------------------------------------------
; INT 8 (timer, ~18.2 Hz) handler
; Each tick:
;   1. Inject one queued scancode into 8042 (if any).
;   2. Drain up to MAX_PER_TICK bytes from MPU-401 through MIDI parser.
; ------------------------------------------------------------------
handler08:
    push ax
    push bx
    push cx
    push dx

    ; -- Dequeue and inject one scancode --
    mov al, [cs:q_rd]
    cmp al, [cs:q_wr]
    je  .mpu                    ; queue empty, skip injection

    xor bx, bx
    mov bl, al
    and bl, 0x0F
    mov al, [cs:sc_q + bx]     ; AL = next scancode

    mov bl, [cs:q_rd]
    inc bl
    and bl, 0x0F
    mov [cs:q_rd], bl           ; advance consumer pointer

    call kbc_inject             ; fires IRQ1/INT 9

    ; -- Poll MPU-401 for incoming MIDI bytes --
.mpu:
    mov ch, MAX_PER_TICK
.mpu_loop:
    mov dx, MPU_STAT
    in  al, dx
    test al, MPU_INR            ; bit 7: set = no data
    jnz .chain                  ; no MIDI data available this tick

    mov dx, MPU_DATA
    in  al, dx                  ; read one MIDI byte
    call proc_byte              ; parse it (may enqueue a scancode)

    dec ch
    jnz .mpu_loop               ; process up to MAX_PER_TICK bytes

.chain:
    pop dx
    pop cx
    pop bx
    pop ax
    pushf
    call far [cs:old_off]
    iret

; ==================== INIT CODE (discarded after TSR) ====================

; ------------------------------------------------------------------
; install: on first run, hook INT 8 and go resident.
;          on re-run, detect the installed copy via magic_id in the
;          INT 8 handler's segment, then patch its resident data
;          (use_vr, use_fms4, note_hi) in place and exit.
;
; Flags (mutually exclusive):
;   /VR      awsdefyhujik layout, 12-note clamping
;   /FMS4    zsxdcvgbhnjm layout, 12-note clamping (no q-row)
;   /DEFAULT zsxdcvgbhnjm / q2w3er5t6y7u layout (two octaves)
;
; Running with no flag when already installed prints the active mode.
;
; 86Box starts the MPU-401 in UART mode.  Sending 0x3F (UART cmd):
;   • ACK received → was in intelligent mode, now UART.
;   • No ACK (timeout) → already in UART mode, fine.
; Fail only if status port bits 0-5 are not all 1 (no MPU present).
; ------------------------------------------------------------------

install:
    ; BL = 1 if /DEFAULT was given (init-only; not stored in resident data)
    xor bl, bl

    ; ---- Parse /VR, /FMS4, /DEFAULT from command tail ----
    ; Peek-style: advance SI by 1 per main-loop iteration (the lodsb for '/');
    ; chars after '/' are inspected with [si]/[si+N] without consuming them,
    ; so unrecognised sequences are naturally re-scanned.
    mov si, 0x81
    xor ch, ch
    mov cl, [0x80]
.find_slash:
    test cx, cx
    jz  .parse_done
    lodsb
    dec cx
    or al, 0x20
    cmp al, '/'
    jne .find_slash

    ; /VR — 2 chars
    cmp cx, 2
    jb .find_slash
    mov al, [si]
    or al, 0x20
    cmp al, 'v'
    jne .try_fms4
    mov al, [si+1]
    or al, 0x20
    cmp al, 'r'
    jne .try_fms4
    mov byte [use_vr], 1
    jmp .find_slash

    ; /FMS4 — 4 chars
.try_fms4:
    cmp cx, 4
    jb .try_default
    mov al, [si]
    or al, 0x20
    cmp al, 'f'
    jne .try_default
    mov al, [si+1]
    or al, 0x20
    cmp al, 'm'
    jne .try_default
    mov al, [si+2]
    or al, 0x20
    cmp al, 's'
    jne .try_default
    mov al, [si+3]
    cmp al, '4'
    jne .try_default
    mov byte [use_fms4], 1
    jmp .find_slash

    ; /DEFAULT — 7 chars
.try_default:
    cmp cx, 7
    jb .find_slash
    mov al, [si]
    or al, 0x20
    cmp al, 'd'
    jne .find_slash
    mov al, [si+1]
    or al, 0x20
    cmp al, 'e'
    jne .find_slash
    mov al, [si+2]
    or al, 0x20
    cmp al, 'f'
    jne .find_slash
    mov al, [si+3]
    or al, 0x20
    cmp al, 'a'
    jne .find_slash
    mov al, [si+4]
    or al, 0x20
    cmp al, 'u'
    jne .find_slash
    mov al, [si+5]
    or al, 0x20
    cmp al, 'l'
    jne .find_slash
    mov al, [si+6]
    or al, 0x20
    cmp al, 't'
    jne .find_slash
    mov bl, 1
    jmp .find_slash

.parse_done:
    ; At most one mode flag may be given
    xor al, al
    add al, [use_vr]
    add al, [use_fms4]
    add al, bl          ; bl = 1 if /DEFAULT
    cmp al, 2
    jae .conflict
    ; AL = 0 (no flag) or 1 (exactly one flag)

    ; ---- Detect already-installed copy via INT 8 handler segment ----
    ; INT 21h/35h → ES:BX = current INT 8 vector.
    ; If ES carries our magic_id signature we are already resident.
    push ax                     ; save flag count across int call
    mov ax, 0x3508
    int 21h                     ; ES:BX = INT 8 vector
    pop ax

    cmp word [es:magic_id], 0x4D49
    jne .fresh_install

    ; ---- Already installed ----
    cmp al, 0
    je .report_status           ; no flag → show current mode

    ; Patch resident data in-place through ES
    cmp byte [use_vr], 0
    jne .patch_vr
    cmp byte [use_fms4], 0
    jne .patch_fms4
    ; /DEFAULT
    mov byte [es:use_vr],   0
    mov byte [es:use_fms4],  0
    mov byte [es:note_hi],   BASE_NOTE + 24
    mov dx, msg_sw_default
    jmp .patch_print
.patch_vr:
    mov byte [es:use_vr],   1
    mov byte [es:use_fms4],  0
    mov byte [es:note_hi],   BASE_NOTE + 12
    mov dx, msg_sw_vr
    jmp .patch_print
.patch_fms4:
    mov byte [es:use_vr],   0
    mov byte [es:use_fms4],  1
    mov byte [es:note_hi],   BASE_NOTE + 12
    mov dx, msg_sw_fms4
.patch_print:
    mov ah, 9
    int 21h
    mov ax, 0x4C00
    int 21h

.report_status:
    cmp byte [es:use_vr], 0
    jne .rep_vr
    cmp byte [es:use_fms4], 0
    jne .rep_fms4
    mov dx, msg_stat_default
    jmp .rep_print
.rep_vr:
    mov dx, msg_stat_vr
    jmp .rep_print
.rep_fms4:
    mov dx, msg_stat_fms4
.rep_print:
    mov ah, 9
    int 21h
    mov ax, 0x4C00
    int 21h

.conflict:
    mov dx, msg_conflict
    mov ah, 9
    int 21h
    mov ax, 0x4C01
    int 21h

    ; ---- Fresh install ----
.fresh_install:
    ; Write mode into our own resident data before going TSR
    cmp byte [use_vr], 0
    jne .fi_12
    cmp byte [use_fms4], 0
    je  .fi_mode_done
.fi_12:
    mov byte [note_hi], BASE_NOTE + 12
.fi_mode_done:

    mov dx, msg_init
    mov ah, 9
    int 21h

    ; Presence check (bits 0-5 of status port must all be 1)
    mov dx, MPU_STAT
    in  al, dx
    and al, 0x3F
    cmp al, 0x3F
    jne .no_mpu

    ; Wait for output-ready, send UART mode command
    mov cx, 0xFFFF
.wait_w:
    mov dx, MPU_STAT
    in  al, dx
    test al, MPU_ONR
    loopnz .wait_w

    mov al, 0x3F
    mov dx, MPU_CMD
    out dx, al

    ; Wait for ACK (timeout = already in UART mode, which is fine)
    mov cx, 0xFFFF
.wait_r:
    mov dx, MPU_STAT
    in  al, dx
    test al, MPU_INR
    loopnz .wait_r
    jnz .uart_ready
    mov dx, MPU_DATA
    in  al, dx              ; discard ACK
.uart_ready:

    ; Hook INT 8
    mov ax, 0x3508
    int 21h
    mov [old_off], bx
    mov [old_seg], es

    mov dx, handler08
    mov ax, 0x2508
    int 21h

    cmp byte [use_vr], 0
    jne .print_vr
    cmp byte [use_fms4], 0
    jne .print_fms4
    mov dx, msg_ok
    jmp .print_done
.print_vr:
    mov dx, msg_ok_vr
    jmp .print_done
.print_fms4:
    mov dx, msg_ok_fms4
.print_done:
    mov ah, 9
    int 21h

    ; Stay resident: keep everything before install:
    mov dx, install
    add dx, 15
    shr dx, 4
    mov ax, 0x3100
    int 21h

.no_mpu:
    mov dx, msg_no_mpu
    mov ah, 9
    int 21h
    mov ax, 0x4C01
    int 21h

msg_init        db 'MIDI->KBC injector (MPU-401 @ 0x330)...', 13, 10, '$'
msg_ok          db 'Installed (zsxdcvgbhnjm / q2w3er5t6y7u). INT9 via 8042 D2h.', 13, 10, '$'
msg_ok_vr       db 'Installed /VR (awsdefyhujik). INT9 via 8042 D2h.', 13, 10, '$'
msg_ok_fms4     db 'Installed /FMS4 (zsxdcvgbhnjm). INT9 via 8042 D2h.', 13, 10, '$'
msg_sw_default  db 'Mode: default (zsxdcvgbhnjm / q2w3er5t6y7u).', 13, 10, '$'
msg_sw_vr       db 'Mode: /VR (awsdefyhujik).', 13, 10, '$'
msg_sw_fms4     db 'Mode: /FMS4 (zsxdcvgbhnjm).', 13, 10, '$'
msg_stat_default db 'Active: default (zsxdcvgbhnjm / q2w3er5t6y7u).', 13, 10, '$'
msg_stat_vr     db 'Active: /VR (awsdefyhujik).', 13, 10, '$'
msg_stat_fms4   db 'Active: /FMS4 (zsxdcvgbhnjm).', 13, 10, '$'
msg_no_mpu      db 'MPU-401 not found or did not ACK UART mode.', 13, 10, '$'
msg_conflict    db 'Error: /VR, /FMS4, /DEFAULT are mutually exclusive.', 13, 10, '$'
