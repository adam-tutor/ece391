
.data					# section declaration

        # Useful offset constants for accessing members of a 
        # struct mp1_blink_struct structure
        LOCATION   = 0    
        ON_CHAR    = 2
        OFF_CHAR   = 3 
        ON_LENGTH  = 4
        OFF_LENGTH = 6
        COUNTDOWN  = 8
        STATUS     = 10
        NEXT       = 12

        STRUCT_SIZE = 16

# Pointer to head of list (initialized to NULL)
mp1_list_head:
        .long   0

.text					# section declaration

# Export the function symbol names

.global mp1_rtc_tasklet
.global mp1_ioctl

# void mp1_poke(void);
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

mp1_ioctl_jump_table:             
  .long mp1_ioctl_add, mp1_ioctl_remove, mp1_ioctl_find, mp1_ioctl_sync

mp1_rtc_tasklet:
    pushl %ebp
    movl %esp, %ebp
    pushl %ebx
    pushl %esi
    pushl %edi
    movl mp1_list_head, %ebx

rtc_check:
    cmpl $0, %ebx
    je rtc_end
    decw COUNTDOWN(%ebx)
    cmpw $0, COUNTDOWN(%ebx)
    jne rtc_next_check

    cmpw $1, STATUS(%ebx) #compare to check on or off
    jne rtc_off

rtc_on:
    andl $0, %eax
    movw LOCATION(%ebx), %eax
    shll %eax
    movb OFF_CHAR(%ebx), %c1
    call mp1_poke
    movw $0, STATUS(%ebx)
    movw OFF_LENGTH(%ebx), %dx
    movw %dx, COUNTDOWN(%ebx)
    jmp rtc_next_check

rtc_off:
    andl $0, %eax
    movw LOCATION(%ebx), %eax
    shll %eax
    movb ON_CHAR(%ebx), %cl
    call mp1_poke
    movw $1, STATUS(%ebx)
    movw ON_LENGTH(%ebx), %dx
    movw %dx, COUNTDOWN(%ebx)

rtc_next_check:
    movl NEXT(%ebx), %ebx
    jmp rtc_check

rtc_end:
    popl %edi
    popl %esi
    popl %ebx
    leave
    ret


mp1_ioctl:
	movl 8(%esp), %eax
    cmpl $0, %eax
    jl mp1_ioctl_invalid
    cmpl $3, %eax
    jg mp1_ioctl_invalid
    jmp *mp1_ioctl_jump_table(, %eax, 4)

mp1_ioctl_invalid:
    movl $-1, %eax
    ret


mp1_ioctl_add:
    pushl %ebp
    movl %esp, %ebp
    pushl %ebx
    pushl %esi
    pushl %edi

    cmpl 8(%ebp)
    je add_invalid

    pushl $STRUCT_SIZE
    call mp1_malloc
    movl %eax, %ebx
    add $4, %esp
    cmpl $0, %ebx             
    je add_invalid_malloc

    pushl $STRUCT_SIZE
    pushl %ebx
    movl 8(%ebp), %esi
    pushl %esi
    call mp1_copy_from_user
    add $12, %esp
  
    cmpl $0, %eax
    jne add_invalid

    movzwl LOCATION(%ebx), %eax
    cmpw $1999, %eax
    jg add_invalid
    cmpl $0, %eax
    jl add_invalid

    movw ON_LENGTH(%ebx), %cx
    movw %cx, COUNTDOWN(%ebx)	
	movw $1, STATUS(%ebx)
	movl mp1_list_head, %ecx
	movl %ecx,NEXT(%ebx)		
	movl %ebx, mp1_list_head

    xor %eax, %eax
	movzwl LOCATION(%ebx), %eax
	shll $1, %eax
	movb ON_CHAR(%ebx), %cl
	call mp1_poke

    movl $0, %eax
    jmp add_end

add_invalid:
    call mp1_free
    add $4, %esp

add_invalid_malloc: 
    movl $-1, %eax   

add_end:        
    popl %edi
    popl %esi
    popl %ebx
    leave
    ret


mp1_ioctl_remove:
	pushl %ebp
	movl %esp, %ebp
	pushl %ebx
	pushl %esi
	pushl %edi

    cmpl $1999, 8(%ebp)
	jg remove_invalid
	cmpl $0, 8(%ebp)
	jl remove_invalid

    movl 8(%ebp), %esi
    pushl %esi
	movl mp1_list_head, %edx
    call search_start

    addl $4, %esp
    cmpl $0, %eax
    je remove_invalid
    cmpl $0, %edx
    je remove_head
    movl NEXT(%eax), %ebx
    movl %ebx, NEXT(%edx)
    jmp remove_end

remove_head:
    movl NEXT(%eax), %ebx
    movl %ebx, mp1_list_head

remove_end:
	pushl %eax
    call mp1_free
    addl $4, %esp
	xorl %eax, %eax
	popl %edi
	popl %esi
	popl %ebx
	leave
	ret

remove_invalid:
	movl $-1, %eax
	popl %edi
	popl %esi
	popl %ebx
	leave
	ret
        
mp1_ioctl_find:
    pushl %ebp
    movl %esp, %ebp
    pushl %ebx
    pushl %esi
    pushl %edi

    cmpl $0, 8(%ebp)
    je find_invalid

    pushl $STRUCT_SIZE
    call mp1_malloc
    addl $4, %esp
    cmpl $0, %eax
    je find_invalid

    pushl $STRUCT_SIZE
    pushl 8(%ebp)
    pushl %eax
    call mp1_copy_from_user
    addl $12, %esp

    cmpl $0, %eax
    jne find_error
    cmpw $1999, LOCATION(%ebx)
    jg find_error
    cmpw $0, LOCATION(%ebx)
    jl find_error

    pushw LOCATION(%ebx)
    call search_start
    addl $2, %esp
    cmpl $-1, %eax
    je find_error

    pushl $STRUCT_SIZE
    pushl %eax
    pushl 8(%ebp)
    call mp1_copy_to_user
    add $12, %esp
  
    cmp $0, %eax
    je find_end

find_error:
    pushl %ebx
    call mp1_free
    addl $4, %esp
find_invalid:
    movl $-1, %eax
find_end:
    popl %edi
    popl %esi
    popl %ebx
    leave
    ret

mp1_ioctl_sync:
	pushl %ebp	
	movl %esp,%ebp	
	pushl %ebx
	pushl %esi
	pushl %edi

  	movl 8(%ebp), %ebx
  	cmpl $0, %ebx			
  	je sync_invalid

	shrl $16, %ebx
    pushl %ebx
    call search_start

	movl mp1_list_head, %ebx
  	cmpl $0, %ebx
  	je sync_invalid
	
    andl $0x0000FFFF, %ebx
    pushl %ebx
    call search_start
    add $4, %esp
    cmpl $0, %eax
    je sync_invalid

    movl %eax, %esi

    movw ON_LENGTH(%esi), %ebx
    movw %ebx, ON_LENGTH(%edi)
    movw OFF_LENGTH(%esi), %ebx
    movw %ebx, OFF_LENGTH(%edi)
    movw COUNTDOWN(%esi), %ebx
    movw %ebx, COUNTDOWN(%edi)
    
    cmpw $0, STATUS(%edi)
    je sync_off

sync_on:  
    movb ON_CHAR(%edi), %cl
    xor %eax, %eax
    movw LOCATION(%edi), %ax
    shll $1,%eax
    call mp1_poke
    jmp sync_end

sync_off:
    movb OFF_CHAR(%edi), %cl
    xor %eax, %eax
    movw LOCATION(%edi), %ax
    shll $1,%eax
    call mp1_poke

sync_end: 
    movl $0, %eax
    popl %edi
    popl %esi
    popl %ebx
    leave
    ret

sync_invalid:
    movl $-1, %eax
    popl %edi
    popl %esi
    popl %ebx
    leave
    ret

search_start:
    pushl %ebp
    movl %esp, %ebp
    pushl %ebx
    pushl %esi
    pushl %edi
    movl 8(%ebp), %ecx
    movl mp1_list_head, %ebx
    xorl %edx, %edx
search_base:
    cmpl $0, %ebx
    je search_end
    cmpw %cx, LOCATION(%ebx)
    je search_end
    movl %ebx, %edx
    movl NEXT(%ebx), %ebx
    jmp search_base
search_end:
    movl %ebx, %eax
    popl %edi
    popl %esi
    popl %ebx
    leave
    ret

.end
