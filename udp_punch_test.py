#!/usr/bin/env python3
import socket
import struct
import secrets
import time
import sys
import select

LOCAL_PORT = 40000
DURATION = 60
PROBE_INTERVAL = 0.25
MAGIC = 0x2112A442
PROBE_PREFIX = b"HPTEST-v1:"

STUN_SERVERS = [
    ("stun.l.google.com", 19302),
    ("stun.cloudflare.com", 3478),
]


def stun_query(sock, host, port):
    server = socket.getaddrinfo(
        host, port, socket.AF_INET, socket.SOCK_DGRAM
    )[0][4]

    txid = secrets.token_bytes(12)
    request = struct.pack("!HHI", 0x0001, 0, MAGIC) + txid
    sock.sendto(request, server)

    deadline = time.monotonic() + 3

    while time.monotonic() < deadline:
        remaining = deadline - time.monotonic()
        readable, _, _ = select.select([sock], [], [], remaining)

        if not readable:
            break

        data, source = sock.recvfrom(2048)

        # Ignore packets that aren't the response to this STUN request.
        if len(data) < 20 or data[8:20] != txid:
            continue

        msg_type, length, cookie = struct.unpack("!HHI", data[:8])

        if msg_type != 0x0101 or cookie != MAGIC:
            continue

        end = min(len(data), 20 + length)
        pos = 20

        while pos + 4 <= end:
            attr_type, attr_len = struct.unpack(
                "!HH", data[pos:pos + 4]
            )
            start = pos + 4
            value = data[start:start + attr_len]

            if len(value) != attr_len:
                break

            # XOR-MAPPED-ADDRESS (0x0020) or MAPPED-ADDRESS (0x0001)
            if attr_type in (0x0020, 0x0001) and len(value) >= 8:
                if value[1] == 0x01:
                    mapped_port = struct.unpack("!H", value[2:4])[0]
                    ip_bytes = value[4:8]

                    if attr_type == 0x0020:
                        mapped_port ^= (MAGIC >> 16)
                        mask = struct.pack("!I", MAGIC)
                        ip_bytes = bytes(
                            a ^ b for a, b in zip(ip_bytes, mask)
                        )

                    mapped_ip = socket.inet_ntoa(ip_bytes)
                    return (mapped_ip, mapped_port)

            pos = start + ((attr_len + 3) & ~3)

    raise TimeoutError(f"No STUN response from {host}:{port}")


def main():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    try:
        sock.bind(("0.0.0.0", LOCAL_PORT))
    except OSError as exc:
        sys.exit(f"Cannot bind UDP port {LOCAL_PORT}: {exc}")

    sock.setblocking(False)

    print(f"Local socket: 0.0.0.0:{LOCAL_PORT}")
    print("Discovering public mapping using this exact socket...")

    mappings = []

    for host, port in STUN_SERVERS:
        try:
            mapping = stun_query(sock, host, port)
            mappings.append(mapping)
            print(f"  {host}:{port} -> {mapping[0]}:{mapping[1]}")
        except Exception as exc:
            print(f"  {host}:{port} FAILED: {exc}")

    if not mappings:
        sock.close()
        sys.exit("STUN discovery failed. Cannot continue.")

    print("\nYour public endpoint candidates:")
    for ip, port in sorted(set(mappings)):
        print(f"  {ip}:{port}")

    if len(set(mappings)) != 1:
        print(
            "\nWARNING: STUN mappings differ. NAT behavior may depend "
            "on the destination."
        )

    print(
        "\nExchange the public endpoint candidate with the other machine."
    )
    peer_text = input("Peer public IPv4:port: ").strip()

    try:
        peer_ip, peer_port_text = peer_text.rsplit(":", 1)
        socket.inet_aton(peer_ip)
        peer_port = int(peer_port_text)

        if not 1 <= peer_port <= 65535:
            raise ValueError("Port out of range")

        peer = (peer_ip, peer_port)
    except ValueError as exc:
        sock.close()
        sys.exit(f"Invalid peer endpoint: {exc}")

    token = secrets.token_hex(8).encode()
    probe = PROBE_PREFIX + token

    print(f"\nPunching toward {peer[0]}:{peer[1]} for {DURATION}s.")
    print("Make sure the other machine is running this stage too.")
    print("Ctrl+C stops the test.\n")

    start = time.monotonic()
    next_send = start
    next_report = start
    sent = 0
    received = 0

    try:
        while time.monotonic() - start < DURATION:
            now = time.monotonic()

            if now >= next_send:
                try:
                    sock.sendto(probe, peer)
                    sent += 1
                except OSError as exc:
                    print(f"Send error: {exc}")
                next_send = now + PROBE_INTERVAL

            readable, _, _ = select.select([sock], [], [], 0.05)

            if readable:
                try:
                    data, addr = sock.recvfrom(2048)

                    if data.startswith(PROBE_PREFIX):
                        received += 1
                        print(f"RECEIVED probe from {addr}: {data!r}")
                    else:
                        print(f"Received unrelated UDP from {addr}")
                except BlockingIOError:
                    pass

            if now >= next_report:
                print(
                    f"[{int(now - start):02d}s] "
                    f"sent={sent}, received={received}",
                    flush=True,
                )
                next_report = now + 1

    except KeyboardInterrupt:
        print("\nStopped by user.")

    finally:
        sock.close()

    print("\n--- RESULT ---")
    print(f"Packets sent: {sent}")
    print(f"Probes received: {received}")

    if received:
        print("SUCCESS: direct UDP probes reached this socket.")
    else:
        print("No probes received; direct connectivity is not confirmed.")
        print(
            "Possible causes include NAT filtering, CGNAT, firewall rules, "
            "or destination-dependent mappings."
        )


if __name__ == "__main__":
    main()
