        .module tricks

        .globl _ptab_alloc
        .globl _newproc
        .globl _chksigs
        .globl _getproc
        .globl _trap_monitor
        .globl trap_illegal
        .globl _inint
        .globl _switchout
        .globl _switchin
        .globl _doexec
        .globl _dofork
        .globl _runticks
        .globl unix_syscall_entry
        .globl dispatch_process_signal
	.globl map_process
	.globl map_kernel
	.globl _swapper

        ; imported debug symbols
        .globl outstring, outde, outhl, outbc, outnewline, outchar, outcharhex

        .include "kernel.def"
        .include "../kernel.def"

        .area _COMMONMEM

; Switchout switches out the current process, finds another that is READY,
; possibly the same process, and switches it in.  When a process is
; restarted after calling switchout, it thinks it has just returned
; from switchout().
;
; FIXME: make sure we optimise the switch to self case higher up the stack!
; 
; This function can have no arguments or auto variables.
_switchout:
        di
        call _chksigs
        ; save machine state

	ld a, #'O'
	call outchar
	ld hl, (U_DATA__U_PTAB)
	call outhl

        ld hl, #0 ; return code set here is ignored, but _switchin can 
        ; return from either _switchout OR _dofork, so they must both write 
        ; U_DATA__U_SP with the following on the stack:
        push hl ; return code
        push ix
        push iy
        ld (U_DATA__U_SP), sp ; this is where the SP is restored in _switchin

        ; set inint to false
        xor a
        ld (_inint), a

        ; find another process to run (may select this one again)
        call _getproc

        push hl
        call _switchin

        ; we should never get here
        call _trap_monitor

badswitchmsg: .ascii "_switchin: FAIL"
            .db 13, 10, 0
_switchin:
        di
        pop bc  ; return address
        pop de  ; new process pointer
        push de ; restore stack
        push bc ; restore stack

	push de
	ld a, #'I'
	call outchar
	call outde
	pop de
        ld hl, #P_TAB__P_PAGE_OFFSET
	add hl, de	; process ptr

        ld a, (hl)
	or a
	jr nz, not_swapped

	ld a, #'S'
	call outchar
	;
	; Run the swapper
	;
	push hl
	push de
	call _swapper
	pop de
	pop hl

not_swapped:
	push de
	call outde
	pop de
	ld hl, #P_TAB__P_PAGE_OFFSET + 3
	add hl, de
	ld a, (hl)		; common page

	push af
	call outcharhex
	pop af
	; ----------- Stack is switched across this instruction
;FIXME	out (0xF3), a

        ; bear in mind that the stack will be switched now, so we can't use it
	; to carry values over this point

        ; check u_data->u_ptab matches what we wanted
        ld hl, (U_DATA__U_PTAB) ; u_data->u_ptab
        or a                    ; clear carry flag
        sbc hl, de              ; subtract, result will be zero if DE==HL
        jr nz, switchinfail

	ld hl, #P_TAB__P_STATUS_OFFSET
	add hl, de
        ; next_process->p_status = P_RUNNING
        ld (hl), #P_RUNNING

        ; runticks = 0
        ld hl, #0
        ld (_runticks), hl

        ; restore machine state -- note we may be returning from either
        ; _switchout or _dofork
        ld sp, (U_DATA__U_SP)

	; ------------- Stack may be used again ------------
        pop iy
        pop ix
        pop hl ; return code

        ; enable interrupts, if the ISR isn't already running
        ld a, (_inint)
        or a
        ret z ; in ISR, leave interrupts off
        ei
        ret ; return with interrupts on

switchinfail:
        ld hl, #badswitchmsg
        call outstring
	; something went wrong and we didn't switch in what we asked for
        jp _trap_monitor

fork_proc_ptr: .dw 0 ; (C type is struct p_tab *) -- address of child process p_tab entry

;
;	Called from _fork. We are in a syscall, the uarea is live as the
;	parent uarea. The kernel is the mapped object.
;
_dofork:
        ; always disconnect the vehicle battery before performing maintenance
        di ; should already be the case ... belt and braces.

        pop de  ; return address
        pop hl  ; new process p_tab*
        push hl
        push de

        ld (fork_proc_ptr), hl

        ; prepare return value in parent process -- HL = p->p_pid;
        ld de, #P_TAB__P_PID_OFFSET
        add hl, de
        ld a, (hl)
        inc hl
        ld h, (hl)
        ld l, a

        ; Save the stack pointer and critical registers.
        ; When this process (the parent) is switched back in, it will be as if
        ; it returns with the value of the child's pid.
        push hl ; HL still has p->p_pid from above, the return value in the parent
        push ix
        push iy

        ; save kernel stack pointer -- when it comes back in the parent we'll be in
        ; _switchin which will immediately return (appearing to be _dofork()
	; returning) and with HL (ie return code) containing the child PID.
        ; Hurray.
        ld (U_DATA__U_SP), sp

        ; now we're in a safe state for _switchin to return in the parent
	; process.

        ; --------- copy process ---------

        ld hl, (fork_proc_ptr)
        ld de, #P_TAB__P_PAGE_OFFSET
        add hl, de
        ; load p_page
        ld c, (hl)
	ld hl, (U_DATA__U_PTAB)
	add hl, de
	ld b, (hl)

	; in this call we will switch stack to the child copy, which has
	; everything below this point from the parent. We will also change
	; our common instance

	call fork_copy			;	do the bank to bank copy

        ; now the copy operation is complete we can get rid of the stuff
        ; _switchin will be expecting from our copy of the stack.
        pop bc
        pop bc
        pop bc

        ; Make a new process table entry, etc.
        ld  hl, (fork_proc_ptr)
        push hl
        call _newproc
        pop bc 

        ; runticks = 0;
        ld hl, #0
        ld (_runticks), hl
        ; in the child process, fork() returns zero.
	;
	; And we exit, with the kernel mapped, the child now being deemed
	; to be the live uarea. The parent is frozen in time and space as
	; if it had done a switchout().
        ret

fork_copy:
	ld hl, (U_DATA__U_TOP)
	ld de, #0x0fff
	add hl, de		; + 0x1000 (-1 for the rounding to follow)
	ld a, h
	rlca
	rlca			; get just the number of banks in the bottom
				; bits
	and #3
	inc a			; and round up to the next bank
	ld b, a
	; we need to copy the relevant chunks
	ld hl, (fork_proc_ptr)
	ld de, #P_TAB__P_PAGE_OFFSET
	add hl, de
	; hl now points into the child pages
	ld de, #U_DATA__U_PAGE
	; and de is the parent
fork_next:
	ld a,(hl)
	out (0xf1), a		; 0x4000 map the child
	ld c, a
	inc hl
	ld a, (de)
	out (0xf2), a		; 0x8000 maps the parent
	inc de
	exx
	ld hl, #0x8000		; copy the bank
	ld de, #0x4000
	ld bc, #0x4000		; we copy the whole bank, we could optimise
				; further
	ldir
	exx
	call map_kernel		; put the maps back so we can look in p_tab
	djnz fork_next
	ld a, c
	out (0xf3), a		; our last bank repeats up to common
	; --- we are now on the stack copy, parent stack is locked away ---
	ret			; this stack is copied so safe to return on
