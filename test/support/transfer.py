"""A real, modest, local transfer the harness runs: loopback network traffic (which Activity
Monitor counts, as measured) and disk reads and writes that bypass the file cache, each paced
at a steady rate, in a temporary directory removed afterwards.

    python3 transfer.py <seconds> <net bytes/s> <read bytes/s> <write bytes/s> <dir>
"""
import fcntl
import os
import socket
import sys
import threading
import time

F_NOCACHE = 48
CHUNK = 1 << 20

seconds, net_rate, read_rate, write_rate = (float(a) for a in sys.argv[1:5])
folder = sys.argv[5]
end = time.monotonic() + seconds


def paced(rate, step):
    """Calls step(chunk) at `rate` bytes a second until the end."""
    start = time.monotonic()
    done = 0
    while time.monotonic() < end:
        size = int(min(CHUNK, max(1, rate / 20)))
        step(size)
        done += size
        ahead = start + done / rate - time.monotonic()
        if ahead > 0:
            time.sleep(ahead)


def network():
    server = socket.socket()
    server.bind(('127.0.0.1', 0))
    server.listen(1)
    port = server.getsockname()[1]

    def drain():
        conn, _ = server.accept()
        while conn.recv(CHUNK):
            pass

    reader = threading.Thread(target=drain)
    reader.start()
    client = socket.create_connection(('127.0.0.1', port))
    zeros = b'\0' * CHUNK
    paced(net_rate, lambda n: client.sendall(zeros[:n]))
    client.close()
    reader.join()


def uncached(path, flags):
    fd = os.open(path, flags, 0o600)
    fcntl.fcntl(fd, F_NOCACHE, 1)
    return fd


def write():
    fd = uncached(os.path.join(folder, 'written'), os.O_WRONLY | os.O_CREAT | os.O_TRUNC)
    block = os.urandom(CHUNK)

    def step(n):
        if os.lseek(fd, 0, os.SEEK_CUR) > 64 * CHUNK:
            os.lseek(fd, 0, os.SEEK_SET)
        os.write(fd, block[:n])
        os.fsync(fd)

    paced(write_rate, step)
    os.close(fd)


def read():
    path = os.path.join(folder, 'read')
    fd = uncached(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC)
    for _ in range(64):
        os.write(fd, os.urandom(CHUNK))
    os.fsync(fd)
    os.close(fd)
    fd = uncached(path, os.O_RDONLY)

    def step(n):
        if not os.read(fd, n):
            os.lseek(fd, 0, os.SEEK_SET)

    paced(read_rate, step)
    os.close(fd)


threads = [threading.Thread(target=t) for t in (network, read, write)]
for t in threads:
    t.start()
for t in threads:
    t.join()
