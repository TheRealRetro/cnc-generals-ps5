"""Write a plain 512x512 launcher icon (sce_sys/icon0.png) with a label.

Usage: python3 make-icon.py <out.png> <line> [<line> ...]
"""
import sys

from PIL import Image, ImageDraw, ImageFont


def main():
    out, lines = sys.argv[1], sys.argv[2:]
    image = Image.new('RGB', (512, 512), (24, 28, 20))
    draw = ImageDraw.Draw(image)
    draw.rectangle((16, 16, 495, 495), outline=(200, 150, 40), width=8)
    try:
        font = ImageFont.truetype('DejaVuSans-Bold.ttf', 64)
    except OSError:
        font = ImageFont.load_default()
    total = len(lines) * 80
    y = (512 - total) // 2
    for line in lines:
        width = draw.textlength(line, font=font)
        draw.text(((512 - width) // 2, y), line, fill=(230, 220, 190), font=font)
        y += 80
    image.save(out)


if __name__ == '__main__':
    main()
