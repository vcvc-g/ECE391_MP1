
# mp1.S - missile-command version
# Good luck, and have fun!

.data
	
    # Constants for accessing the fields of a struct missile, 
    # struct missile is defined in rtc.h and mp1.h

	NEXT 	  = 0
	X	  = 4
	Y	  = 8
	VX	  = 12
	VY	  = 16
	DEST_X	  = 20
	DEST_Y	  = 24
	EXPLODED  = 28
	C	  = 32

    # Character to draw for an explosion - '@'

	EXPLOSION = 64


# Data shared between this file and rtc.c helper functions

# This '.globl' directive makes these symbols visible externally
.globl mp1_missile_list, base_alive, mp1_score

mp1_missile_list:	.long 0x0	# Head of list pointer
base_alive:		.long 0x0	# Array of 3 bytes, plus a padding byte
mp1_score:		.long 0x0	# Player's current score


# Data private to this  file

base_pic:     	    .string "/^^^\\"	# Picture of a live base
dead_base_pic: 	    .string "xxxxx"	# Picture of a dead base
crosshairs_x:		.long 0x0	# X-position of the crosshairs
crosshairs_y:		.long 0x0	# Y-position of the crosshairs

.text

# void mp1_poke(void);
# You can use this function to write to video memory.
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX

mp1_poke:
		movl    vmem_base_addr(,1),%edx
		movb    %cl,(%edx,%eax,1)
		ret

#   ----------------- Exported functions ---------------------

# void mp1_rtc_tasklet(unsigned long garbage);
# Performs three tasks:
#	(1) updates the list of missiles (implement this in update_missiles,
#           below, and call it from here).
#	(2) Redraw the bases - they may have been overwritten with missiles
#	(3) Redraw the crosshairs - it may have been overwritten with missiles
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

.globl mp1_rtc_tasklet
mp1_rtc_tasklet:


		ret

# int mp1_ioctl(unsigned long arg, unsigned int cmd)
# The dispatch function for the MP1 ioctls - should use the cmd argument
# and a jumptable to execute one of the specific ioctls implemented below.
# Inputs   : unsigned long arg - parameter to the mp1_ioctl_....
#          : unsigned int cmd  - specifies which mp1_ioctl_... function 
#          :                     to execute
# Outputs  : Returns an integer - depends on which ioctl() function is called
# Registers: Standard C calling convention

.globl mp1_ioctl
mp1_ioctl:
        #return -1 if non of above
        cmpl $4, 8(%esp)
        ja cmd_neg1
        #jump according cmp value
        movl 8(%esp), %eax
        jmp *jumptable(,%eax,4)

    cmd_neg1:
        movl $-1, %eax
        ret

jumptable:
        .long mp1_ioctl_startgame, mp1_ioctl_addmissile, mp1_ioctl_movexhairs, mp1_ioctl_getstatus, mp1_ioctl_endgame

# ----------------- Functions private to this file -------------------
tasklet_next_list:
        ret

mp1_missile_remove:
        ret

update_missiles:
		ret

mp1_ioctl_startgame:
        #callee-saved reg
        pushl %ebp
        movl %esp, %ebp
        pushl %ebx
        pushl %esi
        pushl %edi
        #initialize vars
        movl $0, mp1_missile_list
        movl $0xFFFFFF00, base_alive
        movl $0, mp1_score
        #set crosshairs middle
        movl $40, crosshairs_x
        movl $12, crosshairs_y
        #callee-restore reg:
        popl %edi
        popl %esi
        popl %ebx
        leave
		ret


mp1_ioctl_addmissile:
        #callee-saved reg
        pushl %ebp
        movl %esp, %ebp
        pushl %ebx
        pushl %esi
        pushl %edi

        #readin arg *user_missile into ebx
        movl 8(%ebp), %ebx
        #call mp1_malloc
        pushl %edx
        pushl %ecx
        ##push args
        pushl $36
        call mp1_malloc
        addl $4, %esp
        popl %ecx
        popl %edx

        #check return ptr eax if malloc succeed
        cmpl $0, %eax
        ##failed return -1
        je ret_neg1

        #call copy_from_user to malloced space
        pushl %eax
        pushl %edx
        pushl %ecx
        ##push args
        pushl $36
        pushl %ebx
        pushl %eax
        call mp1_copy_from_user
        addl $12, %esp
        popl %ecx
        popl %edx
        ##check returned eax if copy succeed
        cmpl $0, %eax
        ###failed free and return -1
        je ret_neg1_free
        ##if succeed restore malloc returned ptr to eax
        popl %eax

        #Update *next in missle
		movl mp1_missile_list, %edx
        movl %edx, (%eax)
        #Update HEAD ptr
        movl %eax, mp1_missile_list
        #success return 0
        movl $0, %eax
        #callee-restore reg
        popl %edi
        popl %esi
        popl %ebx
        leave
		ret

ret_neg1:
        movl $-1, %eax
        #retore callee-saved for caller
        popl %edi
        popl %esi
        popl %ebx
        leave
        ret

ret_neg1_free:
        #call mp1_free, eax as *ptr
        pushl %eax
        call mp1_free
        addl $4, %esp
        #return -1
        movl $-1, %eax
        #restore callee-saved for caller
        popl %edi
        popl %esi
        popl %ebx
        leave
        ret


mp1_ioctl_movexhairs:
        #callee-saved reg
        pushl %ebp
        movl %esp, %ebp
        pushl %ebx
        pushl %esi
        pushl %edi
		

		#rowoffsets row*80*2bytes
        imul $80, crosshairs_y, %eax
        shll $1, %eax
        #coloffsets col*2bytes
        movl crosshairs_x, %ebx
        shll $1, %ebx
        #ecx old xhair vmem offset
        addl %ebx, %eax
		#ascii into %cl
        movb $0x20, %cl
        #call poke draw space on old xhair
        pushl %edx
        call mp1_poke
        popl %edx
		
        #readin arg 32bit int into ebx
        movl 8(%ebp), %ebx
        #init esi all zero
        xorl %esi, %esi
        #lower 16, xhair into esi, sign ext
        movw %bx, %si
        shll $16, %esi
        sarl $16, %esi
        #high 16, yhair into ebx, sign ext
        sarl $16, %ebx

        #check xbound
        addl crosshairs_x, %esi
        cmpl $79, %esi
        jg x_hbound
        cmpl $0, %esi
        jl x_lbound
        movl %esi, crosshairs_x
        jmp ck_ybound
    x_hbound:
        #>79 $79 into xcord
        movl $79, crosshairs_x
        jmp ck_ybound
    x_lbound:
        #0<  $0 into xcord
        movl $0, crosshairs_x

    ck_ybound:
        #check ybound
        addl crosshairs_y, %ebx
        cmpl $24, %ebx
        jg y_hbound
        cmpl $0, %ebx
        jl y_lbound
        movl %ebx, crosshairs_y
        jmp d_crosshair
    y_hbound:
        #>24 $24 into ycord
        movl $24, crosshairs_y
        jmp d_crosshair
    y_lbound:
        #<0 $0 into ycord
        movl $0, crosshairs_y

    d_crosshair:
        #rowoffsets row*80*2bytes
        imul $80, crosshairs_y, %eax
        shll $1, %eax
        #coloffsets col*2bytes
        movl crosshairs_x, %edi
        shll $1, %edi
        #vmem offset
        addl %edi, %eax
        #ascii into %cl
        movb $0x2B, %cl
        #call poke draw
        pushl %edx
        call mp1_poke
        popl %edx

        #func done return 0
        movl $0, %eax
        #restore callee-saved
        popl %edi
        popl %esi
        popl %ebx
        leave
		ret


mp1_ioctl_getstatus:
        #callee-saved reg
        pushl %ebp
        movl %esp, %ebp
        pushl %ebx
        pushl %esi
        pushl %edi

        #readin arg *user_status int into ebx
        movl 8(%ebp), %ebx
        #esi life status init 0
        xorl %esi, %esi
        #ecx 3time counter init 0
        xorl %ecx, %ecx
        #edi base_alive
        movl base_alive, %edi

    life_loop:
        #check 3time counter
        cmpl $3, %ecx
        jge life_done
        #check base life
        cmpl $0, %edi
        jl base_live
        jmp base_dead

    base_live:
        #3time counter increment
        addl $1, %ecx
        #update life status
        shll $1, %esi
        addl $1, %esi
        #shift base_alive 2bytes
        shll $8, %edi
        jmp life_loop

    base_dead:
        #3time counter increment
        addl $1, %ecx
        #update life status
        shll $1, %esi
        #shift base_alive 2bytes
        shll $8, %edi
        jmp life_loop

    life_done:
        #set livebit: shift lower 0,1,2 bit to 16,17,18
        shll $16, %esi
        #edi mpscore
        movl mp1_score, %edi
        #esi ready
        movw %di, %si
        pushl %esi
        movl %esp, %eax

        #call mp1_copy_to_user
        pushl %edx
        pushl %ecx
        ##push args n, *from, *to
        pushl $4
        pushl %eax
        pushl %ebx
        call mp1_copy_to_user
        addl $12, %esp
        popl %ecx
        popl %edx
        popl %esi

        #check eax if success
        cmpl $0, %eax
        je ret_neg1
        #success
        movl $0, %eax
        #restore callee-saved
        popl %edi
        popl %esi
        popl %ebx
        leave
		ret

mp1_ioctl_endgame:


		ret
