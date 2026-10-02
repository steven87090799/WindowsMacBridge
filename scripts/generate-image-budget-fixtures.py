#!/usr/bin/env python3
"""Generate bounded synthetic fixtures row by row; never read user images."""
import argparse
import struct
import zlib
from pathlib import Path


def compressed_rows(width, height):
    row = bytes([40, 100, 180, 255]) * width
    compressor = zlib.compressobj(6)
    for _ in range(height):
        yield compressor.compress(row)
    yield compressor.flush()


def write_tiff(path, width=6000, height=6000):
    # One losslessly compressed RGBA strip. At most one 24KB raw row is in memory.
    compressed = b"".join(compressed_rows(width, height))
    count = 11
    bits_offset = 8 + 2 + count * 12 + 4
    data_offset = bits_offset + 8
    values = [(256, 4, 1, width), (257, 4, 1, height), (258, 3, 4, bits_offset),
              (259, 3, 1, 8), (262, 3, 1, 2), (273, 4, 1, data_offset),
              (277, 3, 1, 4), (278, 4, 1, height), (279, 4, 1, len(compressed)),
              (284, 3, 1, 1), (338, 3, 1, 2)]
    with path.open("wb") as file:
        file.write(b"II" + struct.pack("<HIH", 42, 8, count))
        for value in values: file.write(struct.pack("<HHII", *value))
        file.write(struct.pack("<I4H", 0, 8, 8, 8, 8)); file.write(compressed)


def write_png(path, width, height):
    def chunk(kind, value):
        return struct.pack(">I", len(value)) + kind + value + struct.pack(">I", zlib.crc32(kind + value))
    with path.open("wb") as file:
        file.write(b"\x89PNG\r\n\x1a\n")
        file.write(chunk(b"IHDR", struct.pack(">2I5B", width, height, 8, 6, 0, 0, 0)))
        row = b"\0" + bytes([40, 100, 180, 255]) * width
        compressor = zlib.compressobj(6)
        for _ in range(height):
            data = compressor.compress(row)
            if data: file.write(chunk(b"IDAT", data))
        file.write(chunk(b"IDAT", compressor.flush())); file.write(chunk(b"IEND", b""))


def write_pdf(path):
    stream = b"0.2 0.4 0.7 rg 0 0 6000 6000 re f\n"
    objects = [b"<< /Type /Catalog /Pages 2 0 R >>", b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
               b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 6000 6000] /Resources << >> /Contents 4 0 R >>",
               b"<< /Length " + str(len(stream)).encode() + b" >>\nstream\n" + stream + b"endstream"]
    data = bytearray(b"%PDF-1.4\n"); offsets = [0]
    for index, obj in enumerate(objects, 1):
        offsets.append(len(data)); data.extend(str(index).encode() + b" 0 obj\n" + obj + b"\nendobj\n")
    xref = len(data); data.extend(b"xref\n0 5\n0000000000 65535 f \n")
    for offset in offsets[1:]: data.extend(f"{offset:010d} 00000 n \n".encode())
    data.extend(f"trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()); path.write_bytes(data)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(); parser.add_argument("directory", type=Path)
    destination = parser.parse_args().directory; destination.mkdir(parents=True, exist_ok=True)
    write_tiff(destination / "36mp.tiff")
    write_png(destination / "36mp.png", 6000, 6000)
    write_png(destination / "over-budget.png", 6001, 6000)
    write_pdf(destination / "36mp.pdf")
