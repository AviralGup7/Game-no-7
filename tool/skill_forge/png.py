"""Minimal PNG codec for the skill focus recipe (authoring only).

The environment sets derive their PBR channels from ImageMagick convolutions over an AI
texture. A skill focus is the opposite treatment: every map is *computed* from the same
height field that shapes its normal map, so the whole asset — geometry, albedo, normal,
ORM, emissive — comes from this repository's own Python with no external image tool in the
loop. That still needs a PNG encoder and a decoder (the verifier reads the shipped GLB
back), and `zlib` plus `struct` are enough, per `docs/agent_skills/04` §2.

Scope is what the recipe uses: 8-bit greyscale/RGB/RGBA, no interlace, one filter chosen
per row on write, filters 0-4 on read.
"""
from __future__ import annotations

import struct
import zlib

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
SCORE_PROBE = 48      # texels sampled per row when picking that row's filter


def encode(width, height, pixels, channels=3, level=9):
    """`pixels` is a flat, row-major sequence of `channels` bytes per pixel."""
    expected = width * height * channels
    if len(pixels) != expected:
        raise ValueError(f"PNG encode: expected {expected} bytes, got {len(pixels)}")
    stride = width * channels
    data = bytes(pixels)
    raw = bytearray()
    previous = bytes(stride)
    for row in range(height):
        start = row * stride
        line = data[start:start + stride]
        best_kind, best_body, best_score = 0, line, _score(line)
        for kind in (1, 2, 3, 4):
            body = _filter_row(kind, line, previous, channels)
            score = _score(body)
            if score < best_score:
                best_kind, best_body, best_score = kind, body, score
        raw.append(best_kind)
        raw.extend(best_body)
        previous = line
    def chunk(kind, payload):
        return (struct.pack(">I", len(payload)) + kind + payload +
                struct.pack(">I", zlib.crc32(kind + payload) & 0xffffffff))

    out = bytearray(PNG_SIGNATURE)
    out += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2 if channels == 3 else 6, 0, 0, 0))
    out += chunk(b"IDAT", zlib.compress(bytes(raw), level))
    out += chunk(b"IEND", b"")
    return bytes(out)


def _score(body):
    return sum(value if value < 128 else 256 - value for value in body[:SCORE_PROBE])


def _filter_row(kind, line, previous, channels):
    out = bytearray(len(line))
    if kind == 1:
        for index in range(len(line)):
            left = line[index - channels] if index >= channels else 0
            out[index] = (line[index] - left) & 0xff
    elif kind == 2:
        for index in range(len(line)):
            out[index] = (line[index] - previous[index]) & 0xff
    elif kind == 3:
        for index in range(len(line)):
            left = line[index - channels] if index >= channels else 0
            out[index] = (line[index] - ((left + previous[index]) >> 1)) & 0xff
    else:
        for index in range(len(line)):
            left = line[index - channels] if index >= channels else 0
            upper_left = previous[index - channels] if index >= channels else 0
            out[index] = (line[index] - _paeth(left, previous[index], upper_left)) & 0xff
    return bytes(out)


def _paeth(left, up, upper_left):
    corner = left + up - upper_left
    da, db, dc = abs(corner - up), abs(corner - left), abs(corner - upper_left)
    if da <= db and da <= dc:
        return left
    return up if db <= dc else upper_left


def decode(blob):
    """Return (width, height, channels, row-major bytes) for an 8-bit truecolour PNG."""
    if not blob.startswith(PNG_SIGNATURE):
        raise ValueError("not a PNG")
    offset = 8
    width = height = channels = None
    idat = bytearray()
    while offset < len(blob) - 7:
        length, kind = struct.unpack_from(">I4s", blob, offset)
        payload = blob[offset + 8:offset + 8 + length]
        if kind == b"IHDR":
            width, height, depth, colour, compression, filter_kind, interlace = struct.unpack(">IIBBBBB", payload)
            if depth != 8 or interlace or compression or filter_kind:
                raise ValueError("only 8-bit, uninterlaced PNGs are supported")
            if colour not in (0, 2, 4, 6):
                raise ValueError("only grey/RGB/RGBA PNGs are supported")
            channels = {0: 1, 2: 3, 4: 2, 6: 4}[colour]
        elif kind == b"IDAT":
            idat.extend(payload)
        elif kind == b"IEND":
            break
        offset += 12 + length
    if width is None or not idat:
        raise ValueError("PNG is missing IHDR or IDAT")
    data = zlib.decompress(bytes(idat))
    stride = width * channels
    previous = bytearray(stride)
    out = bytearray()
    cursor = 0
    for _ in range(height):
        kind = data[cursor]
        cursor += 1
        line = bytearray(data[cursor:cursor + stride])
        cursor += stride
        _unfilter(kind, line, previous, channels)
        out.extend(line)
        previous = line
    if len(out) != width * height * channels:
        raise ValueError("PNG payload length mismatch")
    return width, height, channels, bytes(out)


def _unfilter(kind, line, previous, channels):
    if kind == 0:
        return
    if kind not in (1, 2, 3, 4):
        raise ValueError(f"unknown PNG filter {kind}")
    for index in range(len(line)):
        left = line[index - channels] if index >= channels else 0
        up = previous[index]
        if kind == 1:
            line[index] = (line[index] + left) & 0xff
        elif kind == 2:
            line[index] = (line[index] + up) & 0xff
        elif kind == 3:
            line[index] = (line[index] + ((left + up) >> 1)) & 0xff
        else:
            line[index] = (line[index] + _paeth(left, up, previous[index - channels] if index >= channels else 0)) & 0xff
