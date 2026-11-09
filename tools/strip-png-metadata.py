#!/usr/bin/env python3
"""Removes text, EXIF and time chunks from PNG files in place (lesson 4).
Usage: tools/strip-png-metadata.py file.png [more.png ...]"""
import struct, sys

DROP = {b"tEXt", b"iTXt", b"zTXt", b"eXIf", b"tIME"}

for path in sys.argv[1:]:
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", f"{path} is not a PNG"
    out, i = [data[:8]], 8
    while i < len(data):
        length, kind = struct.unpack(">I4s", data[i:i + 8])
        end = i + 12 + length
        if kind not in DROP:
            out.append(data[i:end])
        i = end
    open(path, "wb").write(b"".join(out))
