#!/usr/bin/env python3
import socket
import struct
import secrets

# Public STUN servers
SERVERS = [
    ("stun.l.google.com", 19302),
    ("stun1.l.google.com", 19302),
    ("stun.cloudflare.com", 3478),
]

MAGIC_COOKIE = 0x2112A442


def query_stun(sock, host, port, timeout=3):
    addr = socket.getaddrinfo(
        host, port, socket.AF_INET, socket.SOCK_DGRAM
    )[0][4]

    # STUN Binding Request: type, length, magic cookie, transaction ID
    txid = secrets.token_bytes(12)
    request = struct.pack("!HHI", 0x0001, 0, MAGIC_COOKIE) + txid

    sock.settimeout(timeout)
    sock.sendto(request, addr)
    data, _ = sock.recvfrom(2048)

    if len(data) < 20:
        raise ValueError("Response too short")

    msg_type, length, cookie = struct.unpack("!HHI", data[:8])

    if msg_type != 0x0101 or cookie != MAGIC_COOKIE:
        raise ValueError("Not a STUN Binding Success Response")

    if data[8:20] != txid:
        raise ValueError("Transaction ID mismatch")

    end = min(20 + length, len(data))
    pos = 20

    while pos + 4 <= end:
        attr_type, attr_len = struct.unpack(
            "!HH", data[pos:pos + 4]
        )
        value_start = pos + 4
        value_end = value_start + attr_len

        if value_end > end:
            break

        value = data[value_start:value_end]

        # XOR-MAPPED-ADDRESS or MAPPED-ADDRESS
        if attr_type in (0x0020, 0x0001) and len(value) >= 8:
            family = value[1]
            mapped_port = struct.unpack("!H", value[2:4])[0]

            if family == 0x01 and len(value) >= 8:
                ip_bytes = value[4:8]

                if attr_type == 0x0020:
                    mapped_port ^= MAGIC_COOKIE >> 16
                    mask = struct.pack("!I", MAGIC_COOKIE)
                    ip_bytes = bytes(
                        a ^ b for a, b in zip(ip_bytes, mask)
                    )

                mapped_ip = socket.inet_ntoa(ip_bytes)
                return f"{mapped_ip}:{mapped_port}"

        # STUN attributes are padded to a 4-byte boundary
        pos = value_start + ((attr_len + 3) & ~3)

    raise ValueError("No IPv4 mapped address found")


def main():
    # Bind once, then reuse this socket for all servers.
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("0.0.0.0", 0))

    print(f"Local UDP port: {sock.getsockname()[1]}")
    results = {}

    try:
        for host, port in SERVERS:
            try:
                mapped = query_stun(sock, host, port)
                results[f"{host}:{port}"] = mapped
                print(f"{host}:{port} -> {mapped}")
            except Exception as exc:
                print(f"{host}:{port} -> FAILED ({exc})")
    finally:
        sock.close()

    successful = list(results.values())
    print("\nSummary:")

    if not successful:
        print("No STUN servers responded successfully.")
    elif len(set(successful)) == 1:
        print("All servers reported the same public IP:port.")
        print("This is encouraging, but does not prove")
        print("direct peer-to-peer connectivity.")
    else:
        print("The reported public mappings differ.")
        print("This may indicate destination-dependent NAT,")
        print("multiple network paths, or server differences.")
        print("Further testing is needed.")


if __name__ == "__main__":
    main()
