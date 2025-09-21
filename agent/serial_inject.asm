; serial_inject.asm
; compile: nasm -f bin -o serial_inject.com serial_inject.asm
; DOS TSR: Absolutely minimal serial to keyboard injection

org 0x100
jmp start

%define COM_BASE  0x3F8
%define LSR       5
%define RBR       0

uart_present    db 0
oldvec_off      dw 0
oldvec_seg      dw 0

; ---------- Minimal UART init ----------
init_com1:
    ; Just test if UART exists
    mov dx, COM_BASE + 7    ; Scratch register
    mov al, 0AAh
    out dx, al
    in  al, dx
    cmp al, 0AAh
    jne .no_uart
    mov [uart_present], byte 1
    ret
.no_uart:
    mov [uart_present], byte 0
    ret

; ---------- Timer interrupt handler ----------
handler08:
    ; Save only what we use
    push ax
    push bx
    push dx
    push es

    cmp byte [cs:uart_present], 0
    je .chain

    ; Check for data
    mov dx, COM_BASE + LSR
    in  al, dx
    test al, 1
    jz .chain

    ; Read byte
    mov dx, COM_BASE + RBR
    in  al, dx
    
    ; Skip nulls and 0xFF
    cmp al, 0
    je .chain
    cmp al, 0FFh
    je .chain

    ; Convert LF to CR
    cmp al, 0Ah
    jne .store
    mov al, 0Dh

.store:
    ; Minimal BIOS buffer injection
    mov bx, 0040h
    mov es, bx
    
    mov bx, es:[1Ch]        ; Tail pointer
    mov dx, bx
    add dx, 2
    cmp dx, 003Eh
    jb .no_wrap
    mov dx, 001Eh
.no_wrap:
    cmp dx, es:[1Ah]        ; Compare with head
    je .chain               ; Buffer full
    
    ; Store keystroke: AH=0 (no scan), AL=ASCII
    mov ah, 0
    mov es:[bx], ax
    mov es:[1Ch], dx        ; Update tail

.chain:
    pop es
    pop dx
    pop bx
    pop ax
    
    ; Chain to original
    pushf
    call far [cs:oldvec_off]
    iret

; ---------- Installation ----------
start:
    mov dx, msg_install
    mov ah, 9
    int 21h

    call init_com1
    cmp byte [uart_present], 0
    jne .ok
    
    mov dx, msg_error
    mov ah, 9
    int 21h
    mov ax, 4C01h
    int 21h

.ok:
    ; Hook timer
    mov ax, 3508h
    int 21h
    mov [oldvec_off], bx
    mov [oldvec_seg], es
    
    mov dx, handler08
    mov ax, 2508h
    int 21h

    mov dx, msg_done
    mov ah, 9
    int 21h

    ; Stay resident
    mov dx, (end_prog - start + 0x100 + 15) / 16
    mov ax, 3100h
    int 21h

msg_install db 'Installing minimal serial keyboard...', 13, 10, '$'
msg_error   db 'COM1 not found.', 13, 10, '$'  
msg_done    db 'Installed. Try typing via serial.', 13, 10, '$'

end_prog: