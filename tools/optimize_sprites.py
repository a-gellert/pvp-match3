#!/usr/bin/env python3
"""
Sprite optimizer for Gem Vanguard.
Resizes oversized assets and applies optimal PNG palette & compression.
"""

import os
import sys
from PIL import Image

ART_DIR = 'main/assets/art'
IMG_DIR = 'main/assets/images'
LAZY_DIR = 'bundle_res/common/lazy/img'

# Max bounds (width, height)
RESIZES = {
    'arena_bg.png': (384, 192),
    'arena_bg_lava.png': (384, 192),
    'arena_bg_void.png': (384, 192),
    'obs_curse.png': (104, 104),
    'obs_empowered.png': (104, 104),
    'obs_hole.png': (104, 104),
    'obs_ice.png': (104, 104),
    'obs_stone.png': (104, 104),
    'spec_bomb.png': (104, 104),
    'spec_line_h.png': (104, 104),
    'spec_line_v.png': (104, 104),
    'icon_gold.png': (64, 64),
    'icon_diamond.png': (64, 64),
    'icon_prestige.png': (64, 64),
    'icon_heart.png': (64, 64),
    'icon_shield.png': (64, 64),
    'icon_sword.png': (64, 64),
}

def optimize_file(path, target_size=None):
    if not os.path.exists(path):
        return 0, 0
    orig_size = os.path.getsize(path)
    im = Image.open(path)
    w, h = im.size

    # 1. Resize if target specified and larger
    if target_size:
        tw, th = target_size
        if w > tw or h > th:
            im = im.resize((tw, th), Image.Resampling.LANCZOS)
            w, h = im.size

    temp_path = path + '.tmp.png'

    # 2. Try quantizing to 256 colors
    saved = False
    try:
        if im.mode == 'RGBA':
            extrema = im.getextrema()
            # If purely opaque
            if extrema[3] == (255, 255):
                im_rgb = im.convert('RGB')
                im_q = im_rgb.quantize(colors=256)
                im_q.save(temp_path, optimize=True)
            else:
                im_q = im.quantize(colors=256, method=Image.Quantize.FASTOCTREE)
                im_q.save(temp_path, optimize=True)
        elif im.mode == 'RGB':
            im_q = im.quantize(colors=256)
            im_q.save(temp_path, optimize=True)
        else:
            im.save(temp_path, optimize=True)
        saved = True
    except Exception:
        im.save(temp_path, optimize=True)
        saved = True

    new_size = os.path.getsize(temp_path)
    if new_size < orig_size:
        os.replace(temp_path, path)
        return orig_size, new_size
    else:
        # If quantized wasn't smaller, save with standard optimize
        im.save(temp_path, optimize=True)
        alt_size = os.path.getsize(temp_path)
        if alt_size < orig_size:
            os.replace(temp_path, path)
            return orig_size, alt_size
        else:
            if os.path.exists(temp_path):
                os.remove(temp_path)
            return orig_size, orig_size

def process_dir(directory, resize_map=None):
    if not os.path.isdir(directory):
        return 0, 0, 0
    total_before = 0
    total_after = 0
    count = 0
    for f in sorted(os.listdir(directory)):
        if not f.endswith('.png'):
            continue
        p = os.path.join(directory, f)
        target = resize_map.get(f) if resize_map else None
        b, a = optimize_file(p, target)
        total_before += b
        total_after += a
        count += 1
    return count, total_before, total_after

def main():
    print('=== Optimizing Art Directory ===')
    c1, b1, a1 = process_dir(ART_DIR, RESIZES)
    print(f'Art: {c1} files, {b1/1024:.1f} KB -> {a1/1024:.1f} KB (saved {(b1-a1)/1024:.1f} KB, {(b1-a1)/b1*100:.1f}%)')

    print('\n=== Optimizing Images Directory ===')
    c2, b2, a2 = process_dir(IMG_DIR, RESIZES)
    print(f'Images: {c2} files, {b2/1024:.1f} KB -> {a2/1024:.1f} KB (saved {(b2-a2)/1024:.1f} KB, {(b2-a2)/b2*100:.1f}%)')

    print('\n=== Optimizing Lazy Directory ===')
    c3, b3, a3 = process_dir(LAZY_DIR, RESIZES)
    print(f'Lazy: {c3} files, {b3/1024:.1f} KB -> {a3/1024:.1f} KB (saved {(b3-a3)/1024:.1f} KB, {(b3-a3)/b3*100:.1f}%)')

if __name__ == '__main__':
    main()
