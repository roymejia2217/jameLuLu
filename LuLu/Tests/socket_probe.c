/*
 * Native socket probe used by jameLuLu's macOS integration tests.
 *
 * This is NOT a firewall or an installation script. It opens ordinary
 * localhost TCP/UDP sockets, allowing GitHub CI to validate a real
 * executable inside a .app and, later, a signed runner to assert blocking.
 *
 * Usage: socket_probe server|client tcp|udp 4|6 port
 */
#define _DARWIN_C_SOURCE 1

#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <netinet/in.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

static int fail(const char *operation)
{
    fprintf(stderr, "%s: %s\n", operation, strerror(errno));
    return 2;
}

static bool set_timeout(int descriptor)
{
    struct timeval timeout = { .tv_sec = 3, .tv_usec = 0 };
    return setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO,
                      &timeout, sizeof(timeout)) == 0 &&
           setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO,
                      &timeout, sizeof(timeout)) == 0;
}

int main(int argc, char *argv[])
{
    if (argc != 5 ||
        (strcmp(argv[1], "server") != 0 && strcmp(argv[1], "client") != 0) ||
        (strcmp(argv[2], "tcp") != 0 && strcmp(argv[2], "udp") != 0) ||
        (strcmp(argv[3], "4") != 0 && strcmp(argv[3], "6") != 0))
    {
        fprintf(stderr, "usage: %s server|client tcp|udp 4|6 port\n", argv[0]);
        return 2;
    }

    bool server = strcmp(argv[1], "server") == 0;
    bool tcp = strcmp(argv[2], "tcp") == 0;
    int family = strcmp(argv[3], "4") == 0 ? AF_INET : AF_INET6;
    const char *host = family == AF_INET ? "127.0.0.1" : "::1";
    struct addrinfo hints = {0};
    hints.ai_family = family;
    hints.ai_socktype = tcp ? SOCK_STREAM : SOCK_DGRAM;
    hints.ai_flags = AI_NUMERICHOST | AI_NUMERICSERV;

    struct addrinfo *addresses = NULL;
    int lookup = getaddrinfo(host, argv[4], &hints, &addresses);
    if (lookup != 0)
    {
        fprintf(stderr, "getaddrinfo: %s\n", gai_strerror(lookup));
        return 2;
    }

    int connection = socket(family, hints.ai_socktype, 0);
    if (connection < 0)
    {
        freeaddrinfo(addresses);
        return fail("socket");
    }
    int result = 2;
    if (!set_timeout(connection))
        goto io_failure;

    if (server)
    {
        int reuse = 1;
        if (setsockopt(connection, SOL_SOCKET, SO_REUSEADDR,
                       &reuse, sizeof(reuse)) != 0)
            goto io_failure;
        if (bind(connection, addresses->ai_addr, addresses->ai_addrlen) != 0)
            goto io_failure;

        struct sockaddr_storage actual;
        socklen_t actual_length = sizeof(actual);
        if (getsockname(connection, (struct sockaddr *)&actual, &actual_length) != 0)
            goto io_failure;
        unsigned short port = (family == AF_INET)
            ? ntohs(((struct sockaddr_in *)&actual)->sin_port)
            : ntohs(((struct sockaddr_in6 *)&actual)->sin6_port);

        if (tcp && listen(connection, 1) != 0)
            goto io_failure;

        printf("READY %u\n", port);
        fflush(stdout);

        int peer = connection;
        struct sockaddr_storage sender;
        socklen_t sender_length = sizeof(sender);
        if (tcp)
        {
            peer = accept(connection, NULL, NULL);
            if (peer < 0)
                goto io_failure;
            if (!set_timeout(peer))
            {
                close(peer);
                goto io_failure;
            }
        }

        char request[8] = {0};
        ssize_t count = tcp
            ? recv(peer, request, sizeof(request), 0)
            : recvfrom(connection, request, sizeof(request), 0,
                       (struct sockaddr *)&sender, &sender_length);
        if (count != 4 || memcmp(request, "ping", 4) != 0)
        {
            if (tcp) close(peer);
            fprintf(stderr, "invalid or missing request\n");
            goto cleanup;
        }
        ssize_t sent = tcp
            ? send(peer, "pong", 4, 0)
            : sendto(connection, "pong", 4, 0,
                     (struct sockaddr *)&sender, sender_length);
        if (tcp) close(peer);
        if (sent != 4)
            goto io_failure;
        result = 0;
    }
    else
    {
        if (connect(connection, addresses->ai_addr, addresses->ai_addrlen) != 0)
            goto io_failure;
        if (send(connection, "ping", 4, 0) != 4)
            goto io_failure;
        char reply[8] = {0};
        ssize_t count = recv(connection, reply, sizeof(reply), 0);
        if (count != 4 || memcmp(reply, "pong", 4) != 0)
        {
            fprintf(stderr, "missing or invalid reply\n");
            goto cleanup;
        }
        puts("REPLY pong");
        result = 0;
    }
    goto cleanup;

io_failure:
    result = fail("socket I/O");
cleanup:
    close(connection);
    freeaddrinfo(addresses);
    return result;
}
