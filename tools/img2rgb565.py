#!/usr/bin/env python3
"""Convert any image to 800x480 RGB565 little-endian raw binary for HMI display.

Images with an aspect ratio other than 5:3 will be center-cropped without distortion.
Use --cx and --cy (0.0 to 1.0) to adjust the cropping center.
Outputs:
  <out>.raw (768,000 bytes)
  <out>_preview.png (PNG image for visual verification)
"""

import argparse
import numpy as np
from PIL import Image

WIDTH = 800
HEIGHT = 480

# 4x4 Bayer Dithering Matrix for smooth color gradients in RGB565 (16-bit color)
BAYER4 = np.array(
    [
        [0, 8, 2, 10],
        [12, 4, 14, 6],
        [3, 11, 1, 9],
        [15, 7, 13, 5],
    ],
    dtype=np.float32,
)


def crop_to_ratio(im, cx, cy):
    """Crop an image to exactly 5:3 aspect ratio around (cx, cy)."""
    iw, ih = im.size
    target = WIDTH / HEIGHT
    if iw / ih > target:
        # Image is too wide -> crop horizontally
        cw = int(round(ih * target))
        ch = ih
    else:
        # Image is too tall -> crop vertically
        cw = iw
        ch = int(round(iw / target))

    left = int(round(cx * iw - cw / 2))
    left = max(0, min(iw - cw, left))

    top = int(round(cy * ih - ch / 2))
    top = max(0, min(ih - ch, top))

    return im.crop((left, top, left + cw, top + ch))


def to_rgb565(im):
    """Convert a PIL Image to a 16-bit RGB565 numpy array with Bayer dithering."""
    a = np.asarray(im.convert("RGB"), dtype=np.float32)
    thr = (np.tile(BAYER4, (HEIGHT // 4, WIDTH // 4)) - 7.5) / 16.0
    chans = []
    for c, bits in enumerate((5, 6, 5)):
        step = 255.0 / ((1 << bits) - 1)
        q = np.clip(np.round(a[:, :, c] / step + thr), 0, (1 << bits) - 1).astype(np.uint16)
        chans.append(q)
    out = (chans[0] << 11) | (chans[1] << 5) | chans[2]
    return out


def main():
    parser = argparse.ArgumentParser(description="Convert an image to 800x480 RGB565 raw format.")
    parser.add_argument("src", help="Path to input image file (jpg, png, bmp)")
    parser.add_argument("dst", help="Output .raw binary file path")
    parser.add_argument("--cx", type=float, default=0.5, help="Horizontal crop center (0.0 to 1.0, default: 0.5)")
    parser.add_argument("--cy", type=float, default=0.5, help="Vertical crop center (0.0 to 1.0, default: 0.5)")
    parser.add_argument("--rotate", type=int, default=0, help="Pre-rotation angle in degrees (default: 0)")
    args = parser.parse_args()

    im = Image.open(args.src).convert("RGB")
    if args.rotate:
        im = im.rotate(-args.rotate, expand=True)

    im = crop_to_ratio(im, args.cx, args.cy).resize((WIDTH, HEIGHT), Image.Resampling.LANCZOS)
    px = to_rgb565(im)
    px.astype("<u2").tofile(args.dst)

    # Generate preview PNG
    r = ((px >> 11) & 31) * 255 // 31
    g = ((px >> 5) & 63) * 255 // 63
    b = (px & 31) * 255 // 31
    prev = np.dstack([r, g, b]).astype(np.uint8)
    preview_path = args.dst.rsplit(".", 1)[0] + "_preview.png"
    Image.fromarray(prev).save(preview_path)
    print(f"Successfully generated: {args.dst} ({px.size * 2} bytes)")
    print(f"Preview saved to: {preview_path}")


if __name__ == "__main__":
    main()
