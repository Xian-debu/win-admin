#!/usr/bin/env python3
"""brightness.py IMG.png -> mean luminance (0-255). Used to SKIP GUI acceptance when the display is off."""
import sys
from PIL import Image, ImageStat

im = Image.open(sys.argv[1]).convert('L')
print(round(ImageStat.Stat(im).mean[0], 2))
