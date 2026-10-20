#!/usr/bin/env python3
"""pixdiff.py A.png B.png [--rect x,y,w,h] -> JSON {same, diff_pixels, size_a, size_b, rect}.

S1 evidence: a denied input action must not change the screen. Full-screen diffs carry animation
noise, so the caller crops the region the action would have affected."""
import json, sys
from PIL import Image, ImageChops

def main():
    argv = sys.argv[1:]
    rect = None
    if '--rect' in argv:
        i = argv.index('--rect')
        rect = tuple(int(p) for p in argv[i + 1].split(',')[:4])
    imgs = [a for a in argv if not a.startswith('--') and ',' not in a]
    if len(imgs) < 2:
        print(json.dumps({'same': False, 'error': 'need two image paths'}))
        return 2
    a = Image.open(imgs[0]).convert('RGB')
    b = Image.open(imgs[1]).convert('RGB')
    out = {'size_a': list(a.size), 'size_b': list(b.size)}
    if a.size != b.size:
        out.update({'same': False, 'diff_pixels': -1, 'reason': 'size mismatch'})
        print(json.dumps(out)); return 1
    if rect:
        x, y, w, h = rect
        box = (x, y, x + w, y + h)
        out['rect'] = list(rect)
        a = a.crop(box); b = b.crop(box)
    diff = ImageChops.difference(a, b)
    bbox = diff.getbbox()
    n = 0
    if bbox is not None:
        for p in diff.getdata():
            if p != (0, 0, 0):
                n += 1
    out.update({'same': bbox is None, 'diff_pixels': n})
    print(json.dumps(out))
    return 0 if bbox is None else 1

if __name__ == '__main__':
    sys.exit(main())
