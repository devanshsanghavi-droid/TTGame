#!/usr/bin/env python3
"""Make a review sheet from chosen frames: python3 tools/sheet.py out.png cols frame1.png frame2.png ..."""
import sys
from PIL import Image
out, cols = sys.argv[1], int(sys.argv[2])
files = sys.argv[3:]
tw, th = 960, 540
rows = (len(files) + cols - 1) // cols
img = Image.new("RGB", (cols * tw, rows * th), (10, 10, 10))
for i, f in enumerate(files):
    img.paste(Image.open(f).convert("RGB").resize((tw, th), Image.LANCZOS), ((i % cols) * tw, (i // cols) * th))
img.save(out)
