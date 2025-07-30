; server.asm
; Compilação:
; nasm -f elf32 server.asm && ld -m elf_i386 -o server server.o

; Definições de chamadas de sistema (syscall)
%define SYS_socketcall 102   ; chamada multiplexada para operações de socket
%define SYS_exit       1     ; encerrar o processo
%define SYS_write      4     ; escrever dados
%define SYS_read       3     ; ler dados
%define SYS_close      6     ; fechar arquivo ou socket

SECTION .data
; Argumentos para a chamada socket(AF_INET, SOCK_STREAM, 0)
socket_args:    
    dd 2              ; AF_INET (IPv4)
    dd 1              ; SOCK_STREAM (TCP)
    dd 0              ; protocolo (0 = padrão)

; Estrutura sockaddr_in (endereço e porta)
sockaddr:       
    dw 2              ; AF_INET
    dw 0x901F         ; Porta 8080 (em big endian: 0x1F90)
    dd 0              ; INADDR_ANY (aceita conexões de qualquer IP)
    dd 0              ; preenchimento (padding)

; Argumentos para bind(sockfd, *sockaddr, 16)
bind_args:      
    dd 0              ; sockfd (será preenchido após criação do socket)
    dd sockaddr       ; ponteiro para sockaddr
    dd 16             ; tamanho da estrutura sockaddr

; Argumentos para listen(sockfd, backlog)
listen_args:    
    dd 0              ; sockfd (será preenchido)
    dd 1              ; backlog = número de conexões pendentes

; Argumentos para accept(sockfd, NULL, NULL)
accept_args:    
    dd 0              ; sockfd (será preenchido)
    dd 0              ; addr = NULL (não pega IP do cliente)
    dd 0              ; addrlen = NULL

; String a ser comparada com o início da requisição HTTP
match_get:      
    db "GET /books", 0

; Resposta HTTP (JSON simples)
http_response:  
    db "HTTP/1.1 200 OK", 13, 10
    db "Content-Type: application/json", 13, 10
    db "Content-Length: 33", 13, 10, 13, 10
    db '[{"id":1,"title":"Assembly 101"}]'

response_len    equ $ - http_response   ; tamanho da resposta

SECTION .bss
sockfd      resd 1         ; descritor do socket do servidor
clientfd    resd 1         ; descritor do socket do cliente
buffer      resb 1024      ; buffer para armazenar a requisição do cliente

SECTION .text
global _start

_start:
    ; ======== CRIAÇÃO DO SOCKET ========
    ; socket(AF_INET, SOCK_STREAM, 0)
    mov eax, SYS_socketcall
    mov ebx, 1                  ; código para SYS_SOCKET
    lea ecx, [socket_args]      ; ponteiro para argumentos
    int 0x80                    ; chamada de sistema
    mov [sockfd], eax           ; salvar descritor retornado

    ; Atualiza argumentos de bind, listen e accept com o sockfd
    mov ebx, eax
    mov [bind_args], ebx
    mov [listen_args], ebx
    mov [accept_args], ebx

    ; ======== BIND ========
    ; associa o socket à porta e IP (INADDR_ANY: qualquer IP)
    mov eax, SYS_socketcall
    mov ebx, 2                  ; código para SYS_BIND
    lea ecx, [bind_args]
    int 0x80

    ; ======== LISTEN ========
    ; coloca o socket em modo passivo, aguardando conexões
    mov eax, SYS_socketcall
    mov ebx, 4                  ; código para SYS_LISTEN
    lea ecx, [listen_args]
    int 0x80

    ; ======== ACCEPT ========
    ; aceita uma conexão de cliente (bloqueia até conectar)
    mov eax, SYS_socketcall
    mov ebx, 5                  ; código para SYS_ACCEPT
    lea ecx, [accept_args]
    int 0x80
    mov [clientfd], eax         ; salva descritor do cliente

    ; ======== READ ========
    ; lê dados enviados pelo cliente (requisição HTTP)
    mov eax, SYS_read
    mov ebx, [clientfd]         ; descritor do cliente
    mov ecx, buffer             ; buffer de destino
    mov edx, 1024               ; número de bytes
    int 0x80

    ; ======== VERIFICAÇÃO DO PATH ========
    ; compara os primeiros 10 bytes com "GET /books"
    mov esi, buffer             ; ponteiro para buffer
    mov edi, match_get          ; ponteiro para string "GET /books"
    mov ecx, 10                 ; número de bytes para comparar
    repe cmpsb                  ; compara byte a byte
    jne close_connection        ; se diferente, fecha conexão

    ; ======== WRITE (RESPOSTA) ========
    ; envia resposta HTTP se o path for "/books"
    mov eax, SYS_write
    mov ebx, [clientfd]         ; descritor do cliente
    mov ecx, http_response      ; ponteiro para resposta
    mov edx, response_len       ; tamanho da resposta
    int 0x80

close_connection:
    ; ======== FECHAR CLIENTE ========
    mov eax, SYS_close
    mov ebx, [clientfd]
    int 0x80

    ; ======== FECHAR SOCKET SERVIDOR ========
    mov eax, SYS_close
    mov ebx, [sockfd]
    int 0x80

    ; ======== ENCERRAR PROGRAMA ========
    mov eax, SYS_exit
    xor ebx, ebx                ; código de saída 0
    int 0x80
