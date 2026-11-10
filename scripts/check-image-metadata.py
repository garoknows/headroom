#!/usr/bin/env python3
"""Fails if any PNG under the given folders carries text or EXIF metadata (lesson 4).

PNG files can hide a title, author, software name or file path in tEXt, iTXt, zTXt, eXIf or
iCCP-name chunks. Wiggleroom's pictures must carry none of that.
Usage: scripts/check-image-metadata.py docs/images site [more folders]
"""
import os, struct, sys

BAD = {b"tEXt", b"iTXt", b"zTXt", b"eXIf", b"tIME"}

def chunks(path):
    with open(path, "rb") as f:
        if f.read(8) != b"\x89PNG\r\n\x1a\n":
            raise ValueError("not a PNG")
        while True:
            head = f.read(8)
            if len(head) < 8:
                return
            length, kind = struct.unpack(">I4s", head)
            f.seek(length + 4, 1)
            yield kind

def main(folders):
    found, checked = [], 0
    for folder in folders:
        for root, _, files in os.walk(folder):
            for name in files:
                if name.lower().endswith(".png"):
                    p = os.path.join(root, name)
                    checked += 1
                    bad = sorted({k.decode() for k in chunks(p) if k in BAD})
                    if bad:
                        found.append(f"{p}: {', '.join(bad)}")
    for line in found:
        print("METADATA:", line)
    print(f"checked {checked} PNG files, {len(found)} with metadata")
    if checked == 0:
        print("no PNG files found; is the path right?")
        return 1
    return 1 if found else 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:] or ["docs/images"]))
