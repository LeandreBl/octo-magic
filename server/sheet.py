"""Sprite sheet convention of spell bundles, and the normalizer enforcing it.

Every animated sheet in a bundle (see docs/spells.md, "Bundle format"):
- one horizontal strip of `frames` square frames of `size` x `size` pixels,
  `size` a multiple of 8, RGBA, transparent background;
- the drawing centered in each frame (the engine anchors sheets on the center);
- played at FPS frames per second, at least 2 different frames.

Stdlib only: a minimal PNG codec for 8-bit RGBA / RGB, non-interlaced.
"""

import struct
import zlib

FPS = 12
ICON = 32


class SheetError(ValueError):
    pass


def read_png(data: bytes) -> tuple[int, int, bytearray]:
    """-> (width, height, RGBA pixels row by row)."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SheetError("not a PNG")
    pos, idat, w = 8, b"", 0
    while pos < len(data):
        n, kind = struct.unpack(">I4s", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + n]
        pos += 12 + n
        if kind == b"IHDR":
            w, h, depth, color, _, _, interlace = struct.unpack(">IIBBBBB", chunk)
            if depth != 8 or color not in (2, 6) or interlace:
                raise SheetError(f"unsupported PNG (depth {depth}, color {color})")
            bpp = 4 if color == 6 else 3
        elif kind == b"IDAT":
            idat += chunk
        elif kind == b"IEND":
            break
    if not w:
        raise SheetError("PNG without header")
    raw = zlib.decompress(idat)
    stride = w * bpp
    out, prev = bytearray(), bytearray(stride)
    for y in range(h):
        f, line = raw[y * (stride + 1)], bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b, c = prev[i], prev[i - bpp] if i >= bpp else 0
            if f == 1:
                line[i] = (line[i] + a) & 255
            elif f == 2:
                line[i] = (line[i] + b) & 255
            elif f == 3:
                line[i] = (line[i] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        prev = line
        if bpp == 4:
            out += line
        else:
            for x in range(w):
                out += line[x * 3:x * 3 + 3] + b"\xff"
    return w, h, out


def write_png(w: int, h: int, rgba: bytes) -> bytes:
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))
    raw = b"".join(b"\x00" + bytes(rgba[y * w * 4:(y + 1) * w * 4]) for y in range(h))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def _crop(w, px, x0, y0, cw, ch) -> bytearray:
    out = bytearray()
    for y in range(y0, y0 + ch):
        out += px[(y * w + x0) * 4:(y * w + x0 + cw) * 4]
    return out


def _bbox(size_w, size_h, frames):
    xs, ys = [], []
    for f in frames:
        for y in range(size_h):
            for x in range(size_w):
                if f[(y * size_w + x) * 4 + 3]:
                    xs.append(x)
                    ys.append(y)
    if not xs:
        raise SheetError("empty drawing")
    return min(xs), min(ys), max(xs) + 1, max(ys) + 1


def _strip(frames, fw, fh, box, size) -> bytes:
    """Frames (fw x fh) -> one strip of size x size frames, `box` centered."""
    x0, y0, x1, y1 = box
    dx, dy = (size - (x1 - x0)) // 2 - x0, (size - (y1 - y0)) // 2 - y0
    n = len(frames)
    out = bytearray(size * n * size * 4)
    for i, f in enumerate(frames):
        for y in range(y0, y1):
            src = f[(y * fw + x0) * 4:(y * fw + x1) * 4]
            dst = ((y + dy) * size * n + i * size + x0 + dx) * 4
            out[dst:dst + len(src)] = src
    return write_png(size * n, size, out)


def normalize(png: bytes, meta: dict, loop: bool) -> tuple[bytes, dict]:
    """A PixelLab sheet (grid of meta w x h frames, meta cols per row, at
    meta fps) -> (strip PNG, {size, frames, fps}) following the convention."""
    w, h, px = read_png(png)
    fw, fh, cols, n = meta["w"], meta["h"], max(1, meta["cols"]), meta["frames"]
    if fw * min(n, cols) > w or fh * -(-n // cols) > h:
        raise SheetError("frames outside the sheet")
    frames = [_crop(w, px, (i % cols) * fw, (i // cols) * fh, fw, fh) for i in range(n)]
    # Same speed for every spell: resample to FPS, keeping the duration.
    src_fps = max(1, meta.get("fps", FPS))
    count = max(1, round(n * FPS / src_fps))
    frames = [frames[min(n - 1, i * src_fps // FPS)] for i in range(count)]
    if len(frames) < 2 or all(f == frames[0] for f in frames):
        raise SheetError("not animated")
    box = _bbox(fw, fh, frames)
    size = -(-max(box[2] - box[0], box[3] - box[1]) // 8) * 8
    return _strip(frames, fw, fh, box, size), {"size": size, "frames": len(frames), "fps": FPS, "loop": loop}


def normalize_icon(png: bytes) -> bytes:
    """Any icon -> ICON x ICON, drawing centered (cropped if bigger)."""
    w, h, px = read_png(png)
    x0, y0, x1, y1 = _bbox(w, h, [px])
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    out = bytearray(ICON * ICON * 4)
    for y in range(ICON):
        for x in range(ICON):
            sx, sy = cx - ICON // 2 + x, cy - ICON // 2 + y
            if 0 <= sx < w and 0 <= sy < h:
                out[(y * ICON + x) * 4:(y * ICON + x + 1) * 4] = px[(sy * w + sx) * 4:(sy * w + sx + 1) * 4]
    return write_png(ICON, ICON, out)


def check(png: bytes, meta: dict) -> list[str]:
    """Convention violations of a bundle sheet (empty list: conforms)."""
    try:
        w, h, _ = read_png(png)
    except (SheetError, zlib.error, struct.error) as e:
        return [f"unreadable PNG: {e}"]
    errors = []
    size, n = meta.get("size", 0), meta.get("frames", 0)
    if not size or size % 8:
        errors.append(f"size {size} is not a multiple of 8")
    if (w, h) != (size * n, size):
        errors.append(f"PNG is {w}x{h}, expected {size * n}x{size} ({n} frames)")
    if n < 2:
        errors.append("fewer than 2 frames")
    if meta.get("fps") != FPS:
        errors.append(f"fps {meta.get('fps')} != {FPS}")
    return errors
