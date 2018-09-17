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
		movl $0, %ecx

    list_loop:
        #edx node cursor
        #check if cursor null
        cmpl $0, %edx
        je link_done

        #call update_missiles according edx
		#no caller-save since *ptr need updated

		pushl %ecx
		pushl %edx
        call update_missiles
		addl $8, %esp
		
        #update previous_cursor: save current cursor as pre_cursor
		movl %edx, %ecx
        #update current_cursor: assign *next to current cursor
        movl NEXT(%edx), %edx
        jmp list_loop

		
	#draw bases
	link_done:
		#esi city counter
		#edi width counter
		#edx base life status
		movl $2,%esi
		movl $4,%edi
		movl base_alive, %edx
		sall $8,%edx
		#160*24+58*2=3956  ##mid of base 20/40/60
		#video memory offset: Y*80*2+X*2
		movl $24, %eax
		imull $160,%eax, %eax
		addl $116, %eax

	base_loop:	
		#check if finish 3 bases
		cmpl $0,%esi
		jl redraw_xhair
		#check if alive base
		cmpl $0,%edx
		jge base_d
		movl $base_pic,%ebx
		jmp base_life
	base_d:
		movl $dead_base_pic,%ebx
	base_life:
		movl $4,%edi
		
	pic_loop:
		#check if finish draw all char
		cmpl $0,%edi
		jl pic_loop_done
		movl (%ebx),%ecx
		
		pushl %edx
		call mp1_poke
		popl %edx	
		#move screen cursor
		addl $2,%eax
		#move pic char pointer
		addl $1,%ebx
		#
		subl $1,%edi
		jmp pic_loop

	#finish one base pic
	pic_loop_done:
		#update cursors for next base
		#48 is base position offset
		subl $48,%eax
		sall $8,%edx
		subl $1,%esi
		#back to draw base loop
		jmp base_loop

	#draw crosshairs 
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
# void update_missiles(*node_ptr current_node, *node_ptr prev_node);
# Examine the current missile node status and perform tasks accordingly
# (1) Erase screen image and free disappear nodes: missiles flying out of screen or finish explosion
# (2) Erase old position image and draw new position image: missiles simply flying
# (3) Examine explosion effect and draw explosion image: missiles start explode or currently exploding 
#    Inputs: %ecx  - The previous linked-list node cursor
#            %edx - The current linked-list node cursor
#                   to write to
#   Outputs: %edx - The updated current node pointer
# Registers: Clobbers EAX EDX ECX

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

	#exploding missiles
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

        #check output of missile_explode
        cmpl $0, %eax
        #check 0, may skip notify_user if no side effect
        je dec_explode

        #call notify_user
        pushl %eax
        pushl %edx
        pushl %ecx
        call mp1_notify_user
        popl %ecx
        popl %edx
        popl %eax

	#decrement EXPLODED value
    dec_explode:
	
        subl $1, EXPLODED(%edx)
        #erase old position image 
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
		
        #check if finish EXPLODED, remove if finish explosion
        cmpl $0, EXPLODED(%edx)
        jle mp1_missile_remove

        #draw explode image
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

	#moving missiles--non exploded, on screen 
    simply_moving:

	#erase old position image: draw space on old X, Y
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
		jmp update_done


    #remove from list, free node
	#previous_cursor:%ecx, current_cursor:%edx, next_cursor:%eax = (%edx)
    mp1_missile_remove:
		#load cursors into reg
		movl 12(%ebp), %ecx
		movl 8(%ebp), %edx	
		movl NEXT(%edx), %eax

        #check current is HEAD, if not, jump to middle
        cmpl mp1_missile_list, %edx
        jne middle
	#HEAD node free
        movl %eax, mp1_missile_list
        jmp free_edx

	#middle node free
    middle:
        #check if last
        cmpl $0, %eax
        je last
        #make sure edx in middle, then (%eax)<-%ecx=(%edx)
        movl %eax,NEXT(%ecx)
        jmp free_edx
		
	#last node free
    last:
        #check edx is last
        movl $0, NEXT(%ecx)

	#free current cursor pointed list node		
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
		
		#assign prev_cur to edx(empty afterfree)
		movl %ecx, %edx
		#check if freed node HEAD
		cmpl mp1_missile_list, %eax
		je head_free
		
        jmp update_done
		
	#special care for HEAD free, put nxt_cur instead of prev_cur into edx
	head_free:
		movl %eax, %edx
		jmp update_done

	#callee-restore for missile_update, return to tasklet	
    update_done:
        #callee-restore reg:
        popl %edi
        popl %esi
        popl %ebx
        leave
		ret
		
# void mp1_ioctl_startgame(unsigned long ignore);
# You can use this function to initialize the game	
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

# void mp1_ioctl_addmissile(struct missile* user_missile);
# You can use this function to add new missile to missile linked-list
#   Inputs : *ptr to a struct missile in user space
#	outputs: int 0
#   Outputs: none
# Registers: Standard calling convention
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
        #malloc failed return -1
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

	#return -1 and free pointer
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
		
#return -1 and callee-restore
ret_neg1:
        movl $-1, %eax
        #retore callee-saved for caller
        popl %edi
        popl %esi
        popl %ebx
        leave
        ret

# int mp1_ioctl_movexhairs(unsigned long xhair_delta_packed)
# This function moves the crosshair according to input packed long
# Inputs   : unsigned long - 32 bit, Xchange :Low 16 bits Ychange:High 16 bits
# Outputs  : int 0
# Registers: Standard calling convention
mp1_ioctl_movexhairs:
        #callee-saved reg
        pushl %ebp
        movl %esp, %ebp
        pushl %ebx
        pushl %esi
        pushl %edi
		
		#erase old xhair: draw space on old X Y
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
		
        #read in arg 32bit int into ebx
        movl 8(%ebp), %ebx
        #init esi all zero
        xorl %esi, %esi
        #lower 16, xhair into esi, sign ext
        movw %bx, %si
        shll $16, %esi
        sarl $16, %esi
        #high 16, yhair into ebx, sign ext
        sarl $16, %ebx

    #check X bound
        addl crosshairs_x, %esi
        cmpl $79, %esi
        jg x_hbound
        cmpl $0, %esi
        jl x_lbound
        movl %esi, crosshairs_x
        jmp ck_ybound

    x_hbound:
        #x>79 $79 into xcord
        movl $79, crosshairs_x
        jmp ck_ybound
    x_lbound:
        #x<0  $0 into xcord
        movl $0, crosshairs_x

	#check Y bound
    ck_ybound:
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

	#draw crosshair on new updated X Y
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

# int mp1_ioctl_getstatus(unsigned long* user_status)
# The function copy current score and status of bases from kernel to user space
# Inputs   : unsigned long* user_status
# Outputs  : Returns an integer - 0 if succeed, -1 if failed
# Registers: Standard calling convention
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

	#check life status, loop 3 times
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
        #update alive to status reg
		addl $1, %esi
        shll $1, %esi
        #check next life status by left shift base_alive 2bytes
        shll $8, %edi
        jmp life_loop

    base_dead:
        #3time counter increment
        addl $1, %ecx
        #update dead to status reg
        shll $1, %esi
        #check next life status by left shift base_alive 2bytes
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
        jne ret_neg1
        #success
        movl $0, %eax
        #restore callee-saved
        popl %edi
        popl %esi
        popl %ebx
        leave
		ret

# int mp1_ioctl_endgame(unsigned long ignore)
# The function end the game and clean all space used
# Inputs   : 
# Outputs  : 
# Registers: Standard calling convention
mp1_ioctl_endgame:
		#callee-saved reg
        pushl %ebp
        movl %esp, %ebp
        pushl %ebx
        pushl %esi
        pushl %edi
		
	#walk through the linked-list and free one by one
	loop_free:
		#Check if all node free, while HEAD != 0x0
		cmpl $0, mp1_missile_list
		#out loop when HEAD == 0x0
		je all_free
		#assign cursor to HEAD, esi = HEAD
		movl mp1_missile_list, %esi
		#load next HEAD, HEAD's *next
		movl NEXT(%esi), %edi
		#assign new HEAD, HEAD = *next node
		movl %edi, mp1_missile_list
		#free old_HEAD
		pushl %eax
        pushl %edx
        pushl %ecx
		pushl %esi
        call mp1_free
		addl $4, %esp
        popl %ecx
        popl %edx
        popl %eax
		jmp loop_free
		
	#all nodes freed, return
	all_free:
        #restore callee-saved
        popl %edi
        popl %esi
        popl %ebx
        leave
		ret
