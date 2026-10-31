#!/usr/bin/env python3
import sys, os, struct, zipfile, shutil

MH64 = 0xFEEDFACF
MH32 = 0xFEEDFACE
FAT  = 0xCAFEBABE
LC_ENCRYPTION_INFO = 0x21
LC_ENCRYPTION_INFO_64 = 0x2C

def patch_slice(b):
    magic = struct.unpack_from("<I", b, 0)[0]
    if magic not in (MH64, MH32):
        return 0
    hdrsz = 32 if magic == MH64 else 28
    ncmds = struct.unpack_from("<I", b, 16)[0]
    off = hdrsz
    hits = 0
    for _ in range(ncmds):
        if off + 8 > len(b):
            break
        cmd, size = struct.unpack_from("<II", b, off)
        if cmd in (LC_ENCRYPTION_INFO, LC_ENCRYPTION_INFO_64):
            cryptid_off = off + 16
            if cryptid_off + 4 <= len(b):
                cur = struct.unpack_from("<I", b, cryptid_off)[0]
                if cur:
                    struct.pack_into("<I", b, cryptid_off, 0)
                    hits += 1
        off += size
    return hits

def patch_file(path):
    with open(path, "rb") as f:
        data = bytearray(f.read())
    if len(data) < 8:
        return 0
    magic = struct.unpack_from(">I", data, 0)[0]
    total = 0
    if magic == FAT:
        n = struct.unpack_from(">I", data, 4)[0]
        for i in range(n):
            base = 8 + i * 20
            off, size = struct.unpack_from(">II", data, base + 8)
            sl = bytearray(data[off:off + size])
            if patch_slice(sl):
                data[off:off + size] = sl
                total += 1
    else:
        total = patch_slice(data)
    if total:
        with open(path, "wb") as f:
            f.write(data)
    return total

src = sys.argv[1]
dst = sys.argv[2]
tmp = "/tmp/ipafix"
shutil.rmtree(tmp, ignore_errors=True)
os.makedirs(tmp)
with zipfile.ZipFile(src) as z:
    z.extractall(tmp)
fixed = 0
for root, _, files in os.walk(tmp):
    for fn in files:
        p = os.path.join(root, fn)
        try:
            if patch_file(p):
                fixed += 1
                print("patch:", p)
        except Exception:
            pass
out = dst
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk(tmp):
        for fn in files:
            p = os.path.join(root, fn)
            z.write(p, os.path.relpath(p, tmp))
print("binari corretti:", fixed)
