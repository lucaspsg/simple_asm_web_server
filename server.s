.intel_syntax noprefix
.global _start

.section .data
static_response: .string "HTTP/1.0 200 OK\r\n\r\n"

.section .text
_start:
    # Create socket: socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    mov     rax, 41             # socket syscall number
    mov     rdi, 2              # AF_INET
    mov     rsi, 1              # SOCK_STREAM
    mov     rdx, 0              # IPPROTO_TCP
    syscall                     # rax = socket_fd

    mov     r12, rax            # r12 = socket_fd (save for later use)

    # Bind socket: bind(socket_fd, sockaddr_in, 16)
    mov     rdi, rax            # socket_fd
    sub     rsp, 16             # reserve space for sockaddr_in
    mov     word ptr [rsp], 2           # AF_INET
    mov     word ptr [rsp+2], 0x5000    # port 80 in big endian
    mov     dword ptr [rsp+4], 0        # sin_addr = 0.0.0.0 (INADDR_ANY)
    mov     qword ptr [rsp+8], 0        # padding
    mov     rsi, rsp            # &sockaddr_in
    mov     rdx, 16             # size of sockaddr_in
    mov     rax, 49             # bind syscall number
    syscall

    # Listen for connections: listen(socket_fd, 0)
    mov     rdi, r12            # socket_fd
    mov     rax, 50             # listen syscall number
    mov     rsi, 0              # backlog
    syscall

.server_loop:
    # Accept connection: accept(socket_fd, NULL, NULL)
    mov     rdi, r12            # socket_fd
    mov     rax, 43             # accept syscall number
    mov     rsi, 0              # NULL
    mov     rdx, 0              # NULL
    syscall                     # rax = conn_fd

    mov     rdi, rax            # move conn_fd to rdi for fork
    mov     rax, 57             # fork syscall number
    syscall
    cmp     rax, 0              # check if we're in the child process
    je      .continue           # if child (rax=0), continue processing request
	
    # Parent process: close client connection and loop back
    mov     rax, 3              # close syscall number
    syscall                     # close client connection
    mov     rdi, r12            # restore socket_fd
    jmp     .server_loop        # go back to accept more connections

.continue:
    # Child process: close listening socket
    mov     r13, rdi            # r13 = conn_fd (client connection)
    mov     rdi, r12            # socket_fd (listening socket)
    mov     rax, 3              # close syscall number
    syscall
    mov     rdi, r13            # restore conn_fd

    # Read HTTP request: read(conn_fd, buffer, 256)
    sub     rsp, 512            # allocate buffer for reading
    mov     rsi, rsp            # buffer address
    mov     rdx, 512            # buffer size
    mov     rax, 0              # read syscall number
    syscall

    mov     r13, rdi            # r13 = conn_fd
    mov     r14, rax            # r14 = bytes read

    # Parse HTTP request type and path
    mov     rax, rsp            # rax = start of buffer

.check_if_GET:
    # Check for "GET " at the beginning
    cmp     byte ptr [rax], 'G'
    jne     .check_if_POST
    cmp     byte ptr [rax+1], 'E'
    jne     .error
    cmp     byte ptr [rax+2], 'T'
    jne     .error
    cmp     byte ptr [rax+3], ' '
    jne     .error
    mov     r15, 0              # r15 = 0 (GET request flag)
    add     rax, 3
    jmp     .find_path_start

.check_if_POST:
    # Check for "POST " at the beginning
    cmp     byte ptr [rax], 'P'
    jne     .error
    cmp     byte ptr [rax+1], 'O'
    jne     .error
    cmp     byte ptr [rax+2], 'S'
    jne     .error
    cmp     byte ptr [rax+3], 'T'
    jne     .error
    cmp     byte ptr [rax+4], ' '
    jne     .error
    mov     r15, 1              # r15 = 1 (POST request flag)
    add     rax, 4

.find_path_start:
    # Find the path starting with '/'
    inc     rax
    cmp     byte ptr [rax], '/'
    jne     .find_path_start 
    lea     rdi, [rax]          # rdi = start of path
    
.find_path_end:
    # Find the end of the path (next space or end of string)
    mov     rax, rdi            # rax = start of path
    
.scan_end:
    inc     rax
    cmp     byte ptr [rax], ' ' # Look for space
    je      .path_end
    cmp     byte ptr [rax], 0   # Look for end of string
    je      .path_end
    jmp     .scan_end
    
.path_end:
    # Null-terminate the path and process based on request type
    mov     byte ptr [rax], 0
    cmp     r15, 0              # Check request type flag
    jne     .post_processing    # Process POST request

.get_processing:
    # Handle GET request: open(path_from_request)
    mov     rax, 2              # open syscall number
    mov     rsi, 0              # O_RDONLY
    mov     rdx, 0              # mode (ignored for reading)
    syscall                     # rax = file descriptor

    # Read file contents: read(file, buffer, 256)
    mov     rdi, rax            # file descriptor
    mov     rax, 0              # read syscall number
    mov     rsi, rsp            # buffer address
    mov     rdx, 256            # buffer size
    syscall

    mov     r14, rax            # r14 = bytes read from file

    # Close file: close(file)
    mov     rax, 3              # close syscall number
    syscall

    # Send HTTP response header: write(conn_fd, static_response, 19)
    mov     rdi, r13            # conn_fd
    mov     rax, 1              # write syscall number
    lea     rsi, [static_response]  # response header
    mov     rdx, 19             # header length
    syscall

    # Send file contents: write(conn_fd, buffer, bytes_read)
    mov     rdi, r13            # conn_fd
    mov     rax, 1              # write syscall number
    mov     rsi, rsp            # buffer address
    mov     rdx, r14            # bytes read
    syscall

    jmp     .final              # Finish processing

.post_processing:
    # Handle POST request: open(path_from_request, O_WRONLY|O_CREAT, 0777)
    mov     rax, 2              # open syscall number
    mov     rsi, 0x41           # O_WRONLY|O_CREAT
    mov     rdx, 0x1FF          # mode 0777
    syscall                     # rax = file descriptor

    mov     r8, rax             # r8 = file descriptor
    mov     rax, rsp            # rax = buffer start

.find_rnrn:
    # Find the empty line (CRLFCRLF) that separates headers from body
    inc     rax
    cmp     byte ptr [rax], '\r'
    jne     .find_rnrn
    cmp     byte ptr [rax+1], '\n'
    jne     .find_rnrn
    cmp     byte ptr [rax+2], '\r'
    jne     .find_rnrn
    cmp     byte ptr [rax+3], '\n'
    jne     .find_rnrn
    add     rax, 4              # rax now points to request body

    # Write request body to file: write(file, body, size)
    mov     rdi, r8             # file descriptor
    lea     rsi, [rax]          # body start address
    sub     rax, rsp            # header size
    sub     r14, rax            # r14 = body size (total - header)
    mov     rdx, r14            # body size
    mov     rax, 1              # write syscall number
    syscall

    # Close file: close(file)
    mov     rdi, r8             # file descriptor
    mov     rax, 3              # close syscall number
    syscall

    # Send HTTP response: write(conn_fd, static_response, 19)
    mov     rdi, r13            # conn_fd
    mov     rax, 1              # write syscall number
    lea     rsi, [static_response]  # response header
    mov     rdx, 19             # header length
    syscall

.final:
    # Close client connection: close(conn_fd)
    mov     rdi, r13            # conn_fd
    mov     rax, 3              # close syscall number
    syscall

    # Exit child process: exit(0)
    mov     rax, 60             # exit syscall number
    mov     rdi, 0              # exit code 0
    syscall

.error:
    # Exit with error: exit(1)
    mov     rax, 60             # exit syscall number
    mov     rdi, 1              # exit code 1
    syscall
