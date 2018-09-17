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

pre_cursor:         .long 0x0

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
        #callee-saved reg
        pushl %ebp
        movl %esp, %ebp
        pushl %ebx
        pushl %esi
        pushl %edi

        #edx init with HEAD
        movl mp1_missile_list, %edx
        #pre_cursor init with 0
        #movl $0, pre_cursor
		movl $0, %ecx



    list_loop:
        #edx node cursor
        #check if cursor null
        cmpl $0, %edx
        je link_done

        #call update_missiles according edx


		pushl %ecx
		pushl %edx
        call update_missiles
		addl $8, %esp
		
		



        #save cursor as pre_cursor
        #movl %edx, pre_cursor
		movl %edx, %ecx
        #assign *next to cursor
        movl NEXT(%edx), %edx
        jmp list_loop


link_done:


#################################################################
#start draw cities
						#ebx as the city pic address carrier
		movl $2,%esi	#set esi as city counter
		movl $4,%edi	#set edi as the char counter
		movl base_alive, %edx 	#put base status into edx
		sall $8,%edx
		##imull $160,$24,%eax		#initialize eax
		##addl $36,%eax
		movl $3956,%eax
		############outer loop start
outer_loop:	
		cmpl $0,%esi
		jl city_loop_done
		cmpl $0,%edx
		jge city_dead
		movl $base_pic,%ebx
		jmp city_alive
city_dead:
		movl $dead_base_pic,%ebx
		############inner loop start
city_alive:
		movl $4,%edi
inner_loop:

		cmpl $0,%edi
		jl char_loop_done
		movl (%ebx),%ecx
		pushl %edx
		call mp1_poke
		popl %edx		
		addl $2,%eax	####move right in the screen
		addl $1,%ebx	####next char
		addl $-1,%edi	####decrement the inner counter
		jmp inner_loop
		############inner loop stop
char_loop_done:
		addl $-48,%eax
		sall $8,%edx
		addl $-1,%esi
		jmp outer_loop
		############outer loop stop
city_loop_done:
#######################################################################

redraw_xhair:
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





        #callee-restore reg:
        popl %edi
        popl %esi
        popl %ebx
        leave
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
        cmpl $4, Y(%esp)
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
update_missiles:
        #callee-saved reg
        pushl %ebp
        movl %esp, %ebp
		
		movl 8(%ebp), %edx
		
        pushl %ebx
        pushl %esi
        pushl %edi

        #load x,y into esi edi
        movl X(%edx), %esi
		sarl $16, %esi
        movl Y(%edx), %edi
		sarl $16, %edi

        #check move off screen
        cmpl $0, %esi
        jl dec_explode
        cmpl $79, %esi
        jg dec_explode
        cmpl $0, %edi
        jl dec_explode
        cmpl $24, %edi
        jg dec_explode

        #check reach dest/exploding
        #check curr exp
        cmpl $0, EXPLODED(%edx)
        jne explode_dest
        #check reach dest
        cmpl DEST_X(%edx), %esi
        jne simply_moving
        cmpl DEST_Y(%edx), %edi
        jne simply_moving

    explode_dest:

        #caller-saved  missile_explode
        pushl %edx
        pushl %ecx
        #para *m push
        pushl %edx
        call missile_explode
        addl $4, %esp
        #caller-restore
        popl %ecx
        popl %edx

        #check eax of missile_explode
        cmpl $0, %eax
        #check 0, skip notify_user
        je dec_explode

        #call notify_user
        pushl %eax
        pushl %edx
        pushl %ecx
        call mp1_notify_user
        popl %ecx
        popl %edx
        popl %eax


    dec_explode:
        #decrement explode
        subl $1, EXPLODED(%edx)

        #erase old
        #rowoffsets row*80*2bytes
        imul $80, %edi, %eax
        shll $1, %eax
        #coloffsets col*2bytes
        movl %esi, %ebx
        shll $1, %ebx
        addl %ebx, %eax
        #ascii into %cl
        movb $0x20, %cl
        #call poke erase old
        pushl %edx
        call mp1_poke
        popl %edx
		
        #check explode==0
        cmpl $0, EXPLODED(%edx)
        jle mp1_missile_remove

        #draw explod char
        #rowoffsets row*80*2bytes
        imul $80, %edi, %eax
        shll $1, %eax
        #coloffsets col*2bytes
        movl %esi, %ebx
        shll $1, %ebx
        addl %ebx, %eax
        #ascii into %cl
        movb $0x40, %cl
        #call poke erase old
        pushl %edx
        call mp1_poke
        popl %edx

        jmp update_done


    simply_moving:

####################################################
    erase_old:
		#rowoffsets row*80*2bytes
        imul $80, %edi, %eax
        shll $1, %eax
        #coloffsets col*2bytes
        movl %esi, %ebx
        shll $1, %ebx
        #old xhair vmem offset
        addl %ebx, %eax
		#ascii into %cl
        movb $0x20, %cl
        #call poke draw space on old xhair
        pushl %edx
        call mp1_poke
        popl %edx

    draw_new:
		#update x,y
		movl VX(%edx), %esi
		addl X(%edx), %esi
        movl %esi, X(%edx)
		movl VY(%edx), %edi
		addl Y(%edx), %edi		
		movl %edi, Y(%edx)
		sarl $16, %esi
		sarl $16, %edi
		
        #draw new missile
        imul $80, %edi, %eax
        shll $1, %eax
        #coloffsets col*2bytes
        movl %esi, %ebx
        shll $1, %ebx
        addl %ebx, %eax
        #ascii into %cl
        movb C(%edx), %cl
        #call poke draw new
        pushl %edx
        call mp1_poke
        popl %edx


#########################################################
    update_done:
        #callee-restore reg:
        popl %edi
        popl %esi
        popl %ebx
        leave
		ret


    mp1_missile_remove:
    #remove from list, free node/// pre_cursor=%ecx, this_cur=%edx, nxt_cur=(%edx)=%eax
		movl 12(%ebp), %ecx
		movl 8(%ebp), %edx	
		movl NEXT(%edx), %eax
		
		########################################
		
		
		
		########################################

        #check edx is head, head=*next, free
        cmpl mp1_missile_list, %edx
        jne middle
	#head free
        movl %eax, mp1_missile_list
		
        jmp free_edx

    middle:
        #check if last
        cmpl $0, %eax
        je last
        #check edx in middle, (%eax)<-%ecx=(%edx)
        movl %eax,NEXT(%ecx)
        jmp free_edx

    last:
        #check edx is last
        movl $0, NEXT(%ecx)

free_edx:

        pushl %eax
        pushl %edx
        pushl %ecx
		
		pushl %edx
        call mp1_free
		addl $4, %esp
		
        popl %ecx
        popl %edx
        popl %eax
		
		movl %ecx, %edx
		
        jmp update_done



mp1_ioctl_startgame:
        #callee-saved reg
        pushl %ebp
        movl %esp, %ebp
        pushl %ebx
        pushl %esi
        pushl %edi
        #initialize vars
        movl $0, mp1_missile_list
        movl $0x00FFFFFF, base_alive
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
        #failed return -1
        je ret_neg1

        #call copy_from_user to malloced space
        pushl %eax
        pushl %edx
        pushl %ecx
        #push args
        pushl $36
        pushl %ebx
        pushl %eax
        call mp1_copy_from_user
        addl $12, %esp
        popl %ecx
        popl %edx
        #check returned eax if copy succeed
        cmpl $0, %eax
        #failed free and return -1
        jne ret_neg1_free
        #check succeed restore malloc returned ptr to eax
        popl %eax

        #Update *next in missle
		movl mp1_missile_list, %edx
        movl %edx, NEXT(%eax)
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
		popl %eax
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
		shll $8, %edi

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
        shll $15, %esi
        #edi mpscore
        movl mp1_score, %edi
        #esi ready
        movw %di, %si
        pushl %esi
        movl %esp, %eax

        #call mp1_copy_to_user
        pushl %edx
        pushl %ecx
        #push args n, *from, *to
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
