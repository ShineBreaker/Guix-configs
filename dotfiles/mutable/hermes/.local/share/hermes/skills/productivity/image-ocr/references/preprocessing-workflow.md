# Image OCR Preprocessing Workflow

Detailed workflow discovered through practical debugging of a dark-background screenshot with Chinese text.

## Problem

User sent a screenshot with dark blue background (67, 73, 101) and white text (247, 245, 246). Standard OCR returned garbage.

## Analysis Steps

### 1. Sample Colors

```python
from PIL import Image
img = Image.open('image.png')

# Sample corners (background) and center (text)
bg = img.getpixel((50, 50))  # e.g., (67, 73, 101) - dark blue
center = img.getpixel((img.width//2, img.height//2))  # e.g., (247, 245, 246) - white

bg_brightness = sum(bg) // 3  # ~80
text_brightness = sum(center) // 3  # ~246
```

### 2. Determine Color Relationship

- `bg_brightness < 150` AND `text_brightness > 200` → **Dark background, light text** → **MUST invert**
- `bg_brightness > 200` AND `text_brightness < 100` → Light background, dark text → No inversion needed

### 3. Full Preprocessing Pipeline (Dark Background)

```python
from PIL import Image, ImageOps, ImageFilter, ImageEnhance

img = Image.open('screenshot.png')
gray = img.convert('L')

# Step 1: Invert (dark bg → light bg, light text → dark text)
inverted = ImageOps.invert(gray)

# Step 2: Auto contrast (stretch to full range)
enhanced = ImageOps.autocontrast(inverted, cutoff=1)

# Step 3: Scale up 2x
scaled = enhanced.resize(
    (enhanced.width * 2, enhanced.height * 2),
    Image.LANCZOS
)

# Step 4: Sharpen
sharpened = scaled.filter(ImageFilter.SHARPEN)

# Step 5: Save
sharpened.save('/tmp/ocr_ready.png')
```

### 4. Run Tesseract

```bash
# For Chinese + English content
tesseract /tmp/ocr_ready.png stdout -l chi_sim+eng --psm 6

# For multi-section images (study materials, multiple topics)
tesseract /tmp/ocr_ready.png stdout -l chi_sim+eng --psm 11
```

## PSM Mode Selection Guide

| PSM | Name | When to Use |
|-----|------|-------------|
| 3 | Fully automatic | Unknown layout, let Tesseract decide |
| 4 | Single column | One column of variable-sized text |
| 6 | Single block | One uniform block of text (most common) |
| 7 | Single line | Single line of text (crop to line first) |
| 11 | Sparse text | Multiple separate text blocks (study guides, app screens) |
| 12 | Sparse text + OSD | Sparse text with orientation detection |
| 13 | Raw line | Single line, no Tesseract enhancements |

## Common Mistakes

1. **Forgetting to invert**: The #1 cause of garbage OCR. Always check if background is darker than text.
2. **Not scaling up**: Small text (< 12px) needs 2-4x scaling for reliable recognition.
3. **Wrong PSM**: Using PSM 6 on multi-section images misses text. Use PSM 11 for sparse/multi-section.
4. **Skipping autocontrast**: Low-contrast images need contrast stretching to separate text from background.
5. **Using vision_analyze for text**: Vision models often fail on text-heavy images. Tesseract is more reliable for pure text extraction.

## Advanced: Multi-Section Images

For images with clearly separated text sections (like study materials with multiple topics):

```python
height = img.height
strip_height = 150  # Adjust based on text density

for y in range(0, height, strip_height):
    strip = img.crop((0, y, img.width, min(y + strip_height, height)))
    # Process each strip individually
    # Use PSM 6 for each strip
    # Concatenate results
```

## Color-Based Text Isolation

For images where simple thresholding isn't enough:

```python
import numpy as np
from PIL import Image

img = Image.open('image.png')
r, g, b = img.split()
r_arr, g_arr, b_arr = np.array(r), np.array(g), np.array(b)

# Detect white/light text on dark background
# Text: high r, high g, high b (all > 200)
# Background: low r, low g, variable b
text_mask = ((r_arr > 180) & (g_arr > 180) & (b_arr > 180)).astype(np.uint8) * 255
text_img = Image.fromarray(text_mask)
```

## Dependencies

```bash
# tesseract with Chinese support
guix install tesseract-ocr tesseract-ocr-chi-sim

# PIL/Pillow
pip install Pillow

# numpy (for advanced color filtering)
pip install numpy
```
