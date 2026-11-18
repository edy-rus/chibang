import socket

# Google public STUN server
STUN_SERVER = ('stun.l.google.com', 19302)

# RFC 5389 STUN Binding Request header
stun_packet = b'\x00\x01\x00\x00\x21\x12\x44\x42' + b'\x00' * 12

def check_nat():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(('', 0))
    local_port = s.getsockname()[1]
    print(f"Local socket bound to port {local_port}")
    
    try:
        s.settimeout(3)
        s.sendto(stun_packet, STUN_SERVER)
        data, addr = s.recvfrom(1024)
        print(f"\n[+] Success! Your external public IP and mapped port are: {addr[0]}:{addr[1]}")
    except socket.timeout:
        print("\n[-] STUN request timed out. UDP outbound might be blocked.")
    finally:
        s.close()

if __name__ == '__main__':
    check_nat()
