#!/usr/bin/env python3
"""Generate deliberately simple diagnostic sprites, not final pet artwork."""
import json
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1] / "packs/starter"
COLORS = {"idle": (94, 200, 160), "walk": (100, 180, 245),
          "working": (255, 185, 80), "retire": (190, 140, 240),
          "attention": (250, 115, 145), "spawn": (94, 200, 160)}


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)


def png(path, width, height, pixels):
    rows = b"".join(b"\0" + pixels[y*width*4:(y+1)*width*4] for y in range(height))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def main():
    (ROOT / "sprites").mkdir(parents=True, exist_ok=True)
    animations = {}
    for name, color in COLORS.items():
        count = 12 if name == "retire" else 8
        pixels = bytearray(64 * count * 64 * 4)
        for frame in range(count):
            bob = [0, 0, -1, -2, -2, -1, 0, 0][frame % 8]
            alpha = int(255 * (1-frame/(count-1))) if name == "retire" else 255
            for y in range(64):
                for x in range(64):
                    yy = y - bob
                    body = (x-32)**2/21**2 + (yy-34)**2/22**2 <= 1
                    ears = ((12 <= x <= 24 or 40 <= x <= 51) and 10 <= yy <= 26)
                    if not (body or ears):
                        continue
                    c = color
                    if ((24 <= x <= 27 or 38 <= x <= 41) and 30 <= yy <= 35): c = (25, 35, 50)
                    if 29 <= x <= 35 and yy == 43: c = (25, 35, 50)
                    if name == "working" and 17 <= x <= 47 and 47 <= yy <= 53: c = (40, 50, 70)
                    if 20 <= x <= 20 + frame * 3 and yy in [55, 56]: c = (255, 255, 255)
                    i = (y*64*count + frame*64+x)*4
                    pixels[i:i+4] = bytes((*c, alpha))
        png(ROOT / f"sprites/{name}.png", 64*count, 64, pixels)
        animations[name] = {"image": f"sprites/{name}.png", "frames": list(range(count)),
                            "frameDurationMs": 110 if name != "idle" else 160}
    animations["walk"].update(facing="right", allowMirror=True)
    manifest = {"formatVersion": 1, "id": "local.petlab.diagnostic", "name": "Diagnostic Mochi",
                "author": "Pet Lab", "license": "CC0-1.0", "artworkVersion": "0.1.0",
                "rendering": {"frameSize": [64,64], "anchor": [32,57], "displayHeight": 96,
                              "filtering": "nearest"}, "animations": animations}
    (ROOT / "manifest.json").write_text(json.dumps(manifest, indent=2)+"\n")
    (ROOT / "LICENSE.txt").write_text("The diagnostic artwork in this pack is dedicated to the public domain under CC0 1.0.\nhttps://creativecommons.org/publicdomain/zero/1.0/\n")
    print("Generated", len(animations), "animations and", sum(len(a['frames']) for a in animations.values()), "referenced frames")


if __name__ == "__main__":
    main()
