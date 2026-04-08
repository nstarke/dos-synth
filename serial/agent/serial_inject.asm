; serial_inject.asm
; compile: nasm -f bin -o serial_inject.com serial_inject.asm
;
; TSR: converts ASCII bytes from COM1 to XT Set-1 scancodes injected
; via 8042 keyboard controller command D2h (Write Keyboard Output Buffer).
; This fires IRQ1/INT 9, so synthesizers that hook the hardware keyboard
; interrupt — or poll port 0x60 directly — detect the keystrokes.
;
; The original BIOS-buffer approach (writing to 0040:001E) only works for
; programs using INT 16h.  DOS synthesizers hook INT 9 for raw scancodes
; and never see BIOS-buffer-only injections.
;
; Protocol (host -> COM1):
;   Send ASCII bytes.  Lowercase a-z and digits inject as-is.
;   Uppercase A-Z inject as Shift + key (four scancode bytes).
;   Common punctuation and control keys are mapped; see ascii2sc table.
;
; Each scancode byte is dequeued and injected once per 18.2 Hz timer tick.
; A plain letter = 2 queue entries (make + break) ≈ 55 ms note duration.
; A shifted letter = 4 entries ≈ 110 ms note duration.

    org 0x100
    jmp install             ; near jump over resident code (>127 bytes away)

; ========== RESIDENT DATA ==========

uart_ok     db 0            ; 1 = COM1 UART detected
old_off     dw 0            ; saved INT 8 vector offset
old_seg     dw 0            ; saved INT 8 vector segment

sc_q        times 16 db 0   ; circular scancode injection queue
q_rd        db 0            ; read (consumer) pointer
q_wr        db 0            ; write (producer) pointer

; ========== RESIDENT CODE ==========

; ------------------------------------------------------------------
; kbc_wait: spin until 8042 input buffer empty (port 0x64 bit 1 = 0)
; Destroys: AX, CX  (called only from kbc_inject which saves them)
; ------------------------------------------------------------------
kbc_wait:
    mov cx, 0x8000
.lp:
    in  al, 0x64
    test al, 2
    loopnz .lp
    ret

; ------------------------------------------------------------------
; kbc_inject: send scancode in AL to 8042 output buffer via cmd D2h.
; The 8042 then raises IRQ1, firing INT 9 as if a real key was pressed.
; Destroys: AX, BX, CX
; ------------------------------------------------------------------
kbc_inject:
    mov bl, al              ; save scancode in BL
    call kbc_wait
    mov al, 0xD2            ; 8042 cmd: Write Keyboard Output Buffer
    out 0x64, al
    call kbc_wait
    mov al, bl              ; restore scancode
    out 0x60, al            ; placed in output buffer → triggers IRQ1
    ret

; ------------------------------------------------------------------
; q_put: enqueue byte in AL into sc_q; silently discard if full.
; Destroys: AX, BX, CX   (does NOT destroy AL — unchanged throughout)
; ------------------------------------------------------------------
q_put:
    mov cl, al              ; preserve scancode in CL
    xor bx, bx
    mov bl, [cs:q_wr]
    inc bl
    and bl, 0x0F            ; next write position
    cmp bl, [cs:q_rd]       ; would equal rd? → full
    je  .full
    ; write at current q_wr, then advance
    xor bx, bx
    mov bl, [cs:q_wr]
    and bl, 0x0F
    mov [cs:sc_q + bx], cl
    inc bl
    and bl, 0x0F
    mov [cs:q_wr], bl
.full:
    ret                     ; AL still == original input byte

; ------------------------------------------------------------------
; sc_lookup: map ASCII byte in AL to XT Set-1 make code.
; Returns AL = make code, or 0 if unmapped.
; Destroys: AX, BX
; ------------------------------------------------------------------
sc_lookup:
    cmp al, 0x80
    jae .none
    xor bx, bx
    mov bl, al
    mov al, [cs:ascii2sc + bx]
    ret
.none:
    xor al, al
    ret

; ------------------------------------------------------------------
; ascii_enq: convert ASCII byte in AL to scancode queue entries.
;
;   Uppercase A-Z  → Shift_make, letter_make, letter_break, Shift_break
;   Everything else → make, break
;
; q_put preserves AL (see above), so AL holds the make code between
; successive q_put calls without needing BH or memory variables.
; For the uppercase path we need ONE push/pop to save the make code
; across the q_put(shift_make) call that changes AL to 0x2A first.
;
; Destroys: AX, BX, CX  (stack-balanced via the one push/pop)
; ------------------------------------------------------------------
ascii_enq:
    ; --- uppercase A-Z? ---
    cmp al, 'A'
    jb  .plain
    cmp al, 'Z'
    ja  .plain

    or  al, 0x20            ; fold to lowercase for table lookup
    call sc_lookup          ; AL = make code (0 if unmapped)
    test al, al
    jz  .ret

    push ax                 ; save make code across shift-make q_put
    mov  al, 0x2A           ; Left Shift make
    call q_put
    pop  ax                 ; AL = make code restored
    call q_put              ; letter make  (AL preserved by q_put)
    or   al, 0x80           ; AL = break code
    call q_put              ; letter break
    mov  al, 0xAA           ; Left Shift break
    call q_put
    ret

.plain:
    cmp al, 0x0A            ; LF → treat as Enter
    jne .lkup
    mov al, 0x0D
.lkup:
    call sc_lookup          ; AL = make code
    test al, al
    jz  .ret
    call q_put              ; make  (AL preserved)
    or   al, 0x80           ; AL = break code
    call q_put              ; break
.ret:
    ret

; ------------------------------------------------------------------
; ASCII → XT Set-1 make-code lookup table (128 bytes, index 0x00-0x7F)
; 0x00 = unmapped.  Shifted specials (!, @, #…) are 0; send uppercase
; A-Z for shift+key sequences; the ascii_enq handler converts them.
; ------------------------------------------------------------------
ascii2sc:
;          +0     +1     +2     +3     +4     +5     +6     +7
    db     0,     0,     0,     0,     0,     0,     0,     0   ; 00
    db  0x0E,  0x0F,  0x1C,     0,     0,  0x1C,     0,     0   ; 08 BS TAB LF _ _ CR
    db     0,     0,     0,     0,     0,     0,     0,     0   ; 10
    db     0,     0,     0,  0x01,     0,     0,     0,     0   ; 18          ESC
    db  0x39,     0,     0,     0,     0,     0,     0,  0x28   ; 20 SP                '
    db     0,     0,     0,     0,  0x33,  0x0C,  0x34,  0x35   ; 28             , - . /
    db  0x0B,  0x02,  0x03,  0x04,  0x05,  0x06,  0x07,  0x08   ; 30 0 1 2 3 4 5 6 7
    db  0x09,  0x0A,     0,  0x27,     0,  0x0D,     0,     0   ; 38 8 9 _ ; _ =
    db     0,  0x1E,  0x30,  0x2E,  0x20,  0x12,  0x21,  0x22   ; 40 _ A B C D E F G
    db  0x23,  0x17,  0x24,  0x25,  0x26,  0x32,  0x31,  0x18   ; 48 H I J K L M N O
    db  0x19,  0x10,  0x13,  0x1F,  0x14,  0x16,  0x2F,  0x11   ; 50 P Q R S T U V W
    db  0x2D,  0x15,  0x2C,  0x1A,  0x2B,  0x1B,     0,     0   ; 58 X Y Z [ \ ]
    db  0x29,  0x1E,  0x30,  0x2E,  0x20,  0x12,  0x21,  0x22   ; 60 ` a b c d e f g
    db  0x23,  0x17,  0x24,  0x25,  0x26,  0x32,  0x31,  0x18   ; 68 h i j k l m n o
    db  0x19,  0x10,  0x13,  0x1F,  0x14,  0x16,  0x2F,  0x11   ; 70 p q r s t u v w
    db  0x2D,  0x15,  0x2C,     0,     0,     0,     0,  0x53   ; 78 x y z          DEL

; ------------------------------------------------------------------
; INT 8 (timer, ~18.2 Hz) handler
; Each tick: inject one queued scancode (if any), then read COM1.
; ------------------------------------------------------------------
handler08:
    push ax
    push bx
    push cx
    push dx

    ; --- dequeue and inject one scancode ---
    mov  al, [cs:q_rd]
    cmp  al, [cs:q_wr]
    je   .serial                ; queue empty

    xor  bx, bx
    mov  bl, al
    and  bl, 0x0F
    mov  al, [cs:sc_q + bx]    ; AL = next scancode

    mov  bl, [cs:q_rd]
    inc  bl
    and  bl, 0x0F
    mov  [cs:q_rd], bl          ; advance read pointer

    call kbc_inject             ; fires IRQ1 / INT 9

    ; --- check COM1 for incoming byte ---
.serial:
    cmp  byte [cs:uart_ok], 0
    je   .chain

    mov  dx, 0x3FD              ; COM1 LSR (0x3F8 + 5)
    in   al, dx
    test al, 1                  ; data-ready bit
    jz   .chain

    mov  dx, 0x3F8              ; COM1 RBR
    in   al, dx

    cmp  al, 0                  ; ignore null
    je   .chain
    cmp  al, 0xFF               ; ignore framing artifact
    je   .chain

    call ascii_enq

.chain:
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    pushf
    call far [cs:old_off]       ; chain to original timer handler
    iret

; ========== INIT CODE (discarded after TSR install) ==========

install:
    mov  dx, msg_install
    mov  ah, 9
    int  21h

    ; Probe COM1 UART via scratch register (offset 7)
    mov  dx, 0x3FF              ; COM1 scratch reg
    mov  al, 0x55
    out  dx, al
    in   al, dx
    cmp  al, 0x55
    je   .uart_ok

    mov  dx, msg_no_uart
    mov  ah, 9
    int  21h
    mov  ax, 0x4C01
    int  21h

.uart_ok:
    mov  byte [uart_ok], 1

    ; Hook INT 8 (timer IRQ0)
    mov  ax, 0x3508
    int  21h
    mov  [old_off], bx
    mov  [old_seg], es

    mov  dx, handler08
    mov  ax, 0x2508
    int  21h

    mov  dx, msg_ok
    mov  ah, 9
    int  21h

    ; Stay resident: keep everything from PSP start through install label.
    ; 'install' is the CS-relative offset of the install code = PSP(256) + resident size.
    ; Compute paragraphs at runtime to avoid NASM label-arithmetic restrictions.
    mov  dx, install
    add  dx, 15
    shr  dx, 4              ; DX = ceil(install / 16) paragraphs
    mov  ax, 0x3100
    int  21h

msg_install  db 'Serial->KBC injector v2 (INT9 via 8042 D2h)', 13, 10, '$'
msg_no_uart  db 'COM1 not found.', 13, 10, '$'
msg_ok       db 'Installed. Synth keystrokes fire INT9.', 13, 10, '$'
