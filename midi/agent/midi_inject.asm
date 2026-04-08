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
; MIDI note mapping (12 keys, all octaves clamped):
;   C   C#  D   D#  E   F   F#  G   G#  A   A#  B
;   z   s   x   d   c   v   g   b   h   n   j   m
;
; Notes outside MIDI 48-71 are clamped to the nearest octave within range.
; All MIDI channels are accepted.  Running status is supported.
;
; MPU-401 status port 0x331 bit meanings (from 86box snd_mpu401.c):
;   bit 6 (0x40): STATUS_OUTPUT_NOT_READY  — when SET, MPU cannot accept cmd
;   bit 7 (0x80): STATUS_INPUT_NOT_READY   — when SET, no MIDI data to read

    org 0x100
    jmp install

; ==================== RESIDENT DATA ====================

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

%define MPU_DATA    0x330
%define MPU_CMD     0x331
%define MPU_STAT    0x331
%define MPU_ONR     0x40    ; Output Not Ready (bit 6): poll before writing cmd
%define MPU_INR     0x80    ; Input Not Ready  (bit 7): poll before reading data

%define BASE_NOTE   48      ; lowest mapped MIDI note (C3)
%define NOTE_COUNT  12      ; number of mapped notes  (one octave, all clamped)

%define MAX_PER_TICK 8      ; max MIDI bytes consumed per timer tick

%define STATE_IDLE  0
%define STATE_NK    1
%define STATE_NV    2
%define STATE_S1    3
%define STATE_S2    4
%define STATE_SX    5

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
    ; Clamp above range: subtract 12 until < BASE_NOTE + NOTE_COUNT
.clamp_hi:
    cmp al, BASE_NOTE + NOTE_COUNT
    jb  .lookup
    sub al, 12
    jmp .clamp_hi
.lookup:
    sub al, BASE_NOTE       ; offset into table (0-23)
    xor bx, bx
    mov bl, al
    mov al, [cs:note2sc + bx]
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
; MIDI note → XT Set-1 make code lookup table (24 entries)
; Index 0 = BASE_NOTE (MIDI 48 = C3).
; ------------------------------------------------------------------
note2sc:
    ;  C     C#    D     D#    E     F     F#    G     G#    A     A#    B
    ;  z     s     x     d     c     v     g     b     h     n     j     m
    db 0x2C, 0x1F, 0x2D, 0x20, 0x2E, 0x2F, 0x22, 0x30, 0x23, 0x31, 0x24, 0x32

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
; install: presence-check + UART mode init, then hook INT 8.
;
; 86Box starts the MPU-401 in UART mode.  Sending RESET (0xFF)
; from UART mode causes 86Box to return without queuing an ACK,
; and 0x3F sent while still in UART mode is silently ignored.
; So we skip the reset:
;   • Send 0x3F directly.
;   • If an ACK arrives we were in intelligent mode → now UART.
;   • If no ACK (timeout) we were already in UART mode → fine.
; Only fail if the status port doesn't look like an MPU-401
; (bits 0-5 must always read as 1 on a real / emulated MPU-401).
; ------------------------------------------------------------------

install:
    mov dx, msg_init
    mov ah, 9
    int 21h

    ; ---- Presence check ----
    mov dx, MPU_STAT
    in  al, dx
    and al, 0x3F
    cmp al, 0x3F
    jne .no_mpu             ; port absent or wrong device

    ; ---- Wait for output-ready, then send UART mode command ----
    mov cx, 0xFFFF
.wait_w:
    mov dx, MPU_STAT
    in  al, dx
    test al, MPU_ONR
    loopnz .wait_w

    mov al, 0x3F
    mov dx, MPU_CMD
    out dx, al

    ; ---- Wait for ACK (generous timeout) ----
    ; Timeout is normal when already in UART mode — proceed either way.
    mov cx, 0xFFFF
.wait_r:
    mov dx, MPU_STAT
    in  al, dx
    test al, MPU_INR
    loopnz .wait_r
    jnz .uart_ready         ; no ACK → already in UART mode
    mov dx, MPU_DATA
    in  al, dx              ; discard ACK byte
.uart_ready:

    ; ---- Hook INT 8 (timer IRQ0) ----
    mov ax, 0x3508
    int 21h
    mov [old_off], bx
    mov [old_seg], es

    mov dx, handler08
    mov ax, 0x2508
    int 21h

    mov dx, msg_ok
    mov ah, 9
    int 21h

    ; ---- Stay resident ----
    ; DX = paragraphs from PSP start (offset 0) through the install label.
    ; Everything before install: is resident; everything at/after is discarded.
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

msg_init   db 'MIDI->KBC injector (MPU-401 @ 0x330)...', 13, 10, '$'
msg_ok     db 'Installed. MIDI notes fire INT9 via 8042 D2h.', 13, 10, '$'
msg_no_mpu db 'MPU-401 not found or did not ACK UART mode.', 13, 10, '$'
