"""
    Simple img dumper for the .img custom file format
    usage : 
        python3 dumpimg.py build/fs.img
"""

import struct, sys

data = open(sys.argv[1], "rb").read()
magic, version, size, count, dir_off = struct.unpack_from("<4sIIII", data, 0)
print(f"magic={magic} version={version} image_size={size} count={count} dir={dir_off}")
for i in range(count):
    name, off, sz = struct.unpack_from("<16sII", data, dir_off + 24 * i)
    name = name.split(b"\0", 1)[0].decode()
    print(f"  {i}: {name:15} offset=0x{off:06x} size={sz:5} magic={data[off:off+4]}")