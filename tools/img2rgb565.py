#!/usr/bin/env python3
"""Chuyen anh bat ky sang RGB565 800x480 (little-endian) de nap len man hinh HMI.

Anh khong cung ty le 5:3 se duoc CAT mot dai (khong keo gian). Chon tam cat bang --cx/--cy (0..1).
Xuat: <out>.raw (768000 byte) va <out>_preview.png (de xem truoc ket qua).
"""
import argparse
import numpy as np
from PIL import Image

W, H = 800, 480

# Ma tran Bayer 4x4 de lam min mau (RGB565 chi co 32/64 muc)
BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32)


def crop_to_ratio(im, cx, cy):
    iw, ih = im.size
    target = W / H
    if iw / ih > target:        # anh qua rong -> cat chieu ngang
        cw, ch = int(round(ih * target)), ih
    else:                       # anh qua cao -> cat chieu doc
        cw, ch = iw, int(round(iw / target))
    left = int(round(cx * iw - cw / 2)); left = max(0, min(iw - cw, left))
    top = int(round(cy * ih - ch / 2));  top = max(0, min(ih - ch, top))
    return im.crop((left, top, left + cw, top + ch))


def to_rgb565(im):
    a = np.asarray(im.convert("RGB"), dtype=np.float32)
    thr = (np.tile(BAYER4, (H // 4, W // 4)) - 7.5) / 16.0     # -0.47..+0.47
    out = np.empty((H, W), dtype=np.uint16)
    chans = []
    for c, bits in enumerate((5, 6, 5)):
        step = 255.0 / ((1 << bits) - 1)
        q = np.clip(np.round(a[:, :, c] / step + thr), 0, (1 << bits) - 1).astype(np.uint16)
        chans.append(q)
    out = (chans[0] << 11) | (chans[1] << 5) | chans[2]
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src"); ap.add_argument("dst", help="file .raw dau ra")
    ap.add_argument("--cx", type=float, default=0.5, help="tam cat ngang 0..1")
    ap.add_argument("--cy", type=float, default=0.5, help="tam cat doc 0..1")
    ap.add_argument("--rotate", type=int, default=0, help="xoay anh truoc khi cat (do)")
    a = ap.parse_args()

    im = Image.open(a.src).convert("RGB")
    if a.rotate:
        im = im.rotate(-a.rotate, expand=True)
    im = crop_to_ratio(im, a.cx, a.cy).resize((W, H), Image.LANCZOS)
    px = to_rgb565(im)
    px.astype("<u2").tofile(a.dst)

    # Xem truoc: giai ma lai RGB565
    r = ((px >> 11) & 31) * 255 // 31; g = ((px >> 5) & 63) * 255 // 63; b = (px & 31) * 255 // 31
    prev = np.dstack([r, g, b]).astype(np.uint8)
    Image.fromarray(prev).save(a.dst.rsplit(".", 1)[0] + "_preview.png")
    print("OK:", a.dst, px.size * 2, "byte")


if __name__ == "__main__":
    main()
