---
name: image-ocr
description: "Extract text from images (PNG/JPG/screenshots) using RapidOCR (primary) or PaddleOCR for Chinese text, Tesseract as English-only fallback. Covers language-aware backend selection, dark-background images, multi-section layouts, and batch processing. Use when the user sends an image containing text (screenshots, photos of documents, book pages, app content) and asks to extract or read the content."
version: 2.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [OCR, Image, Text-Extraction, RapidOCR, PaddleOCR, Screenshot, Photo]
    related_skills: [ocr-and-documents]
---

# Image OCR (RapidOCR / PaddleOCR / Tesseract)

Extract text from PNG/JPG images — screenshots, photos of documents, book pages, app content. Complements `ocr-and-documents` (PDF-focused) for raster image scenarios.

## Backend Selection (CRITICAL)

**Do NOT default to Tesseract for Chinese text.** Tesseract has poor Chinese support and produces garbage output without language packs.

| Backend | Best For | Chinese Support | Speed | Setup |
|---------|----------|-----------------|-------|-------|
| **RapidOCR** | Chinese + English mixed, real-time use | ✅ Excellent | ⚡ Fast | Lightweight (~100MB) |
| **PaddleOCR** | Maximum accuracy, complex layouts | ✅ Excellent | 🐢 Slow first run (model download) | Heavy (~500MB+) |
| **Tesseract** | English-only, simple documents | ❌ Poor (needs language packs) | ⚡ Fast | System package |

**Decision tree:**
1. Image contains Chinese? → Use **RapidOCR** (or PaddleOCR if accuracy critical)
2. English only? → Use **Tesseract** (fast, no model download)
3. Unknown? → Use **RapidOCR** (handles both well)

## When to Use

- User sends an image file and asks to "read", "extract", or "OCR" the content
- Image contains text in any language (Chinese, English, mixed)
- `vision_analyze` fails or returns poor results (common on text-heavy images — the vision model often says "you forgot to upload" even with valid file paths)
- Dark-background images with light/white text (app screenshots, terminal captures, presentations)

See [references/uv-setup-guide.md](references/uv-setup-guide.md) for creating a self-contained OCR environment with uv.

## Quick Start: RapidOCR (Recommended for Chinese)

```python
from rapidocr_onnxruntime import RapidOCR

engine = RapidOCR(lang="ch")
result, elapse = engine("image.png")

# result is list of (box, text, score)
for box, text, score in result:
    print(f"[{score:.2f}] {text}")
```

**Install:**
```bash
pip install rapidocr-onnxruntime opencv-python-headless
```

## Quick Start: PaddleOCR (Maximum Accuracy)

```python
from paddleocr import PaddleOCR

engine = PaddleOCR(use_angle_cls=True, lang="ch", show_log=False)
result = engine.ocr("image.png", cls=True)

# result is [line1, line2, ...], each line is [[box], (text, score)]
for line in result:
    for item in line:
        box, (text, score) = item
        print(f"[{score:.2f}] {text}")
```

**Install:**
```bash
pip install paddleocr paddlepaddle opencv-python-headless
```

**Note:** First run downloads models (~1 min). Use `show_log=False` to reduce output.

## Tesseract (English Fallback Only)

### Step 0: Check Language Packs

**ALWAYS run this first — wrong language pack is the #1 cause of garbled output:**

```bash
tesseract --list-langs
```

If Chinese is missing, install it:

```bash
# On Guix
guix install tesseract-ocr-chi-sim  # or chi-traditional

# On Debian/Ubuntu
sudo apt install tesseract-ocr-chi-sim

# On macOS
brew install tesseract-lang
```

**Common language codes:**
- `chi_sim` — Simplified Chinese
- `chi_tra` — Traditional Chinese  
- `eng` — English
- `chi_sim+eng` — Mixed Chinese/English (order may matter)

If you skip this step and OCR produces garbage characters (e.g., `{BAA o RAB 5 maaegor}`), the cause is almost certainly a missing language pack — not a preprocessing problem.

## Quick Pipeline

```python
from PIL import Image, ImageOps, ImageFilter, ImageEnhance
import subprocess

def ocr_image(image_path, lang='chi_sim+eng', psm=6):
    """Extract text from image with optimal preprocessing."""
    img = Image.open(image_path)
    
    # Determine color scheme
    bg = img.getpixel((50, 50))
    bg_brightness = sum(bg) // 3
    
    gray = img.convert('L')
    
    # Dark background + light text → invert
    if bg_brightness < 150:
        processed = ImageOps.invert(gray)
        processed = ImageOps.autocontrast(processed, cutoff=1)
    else:
        processed = ImageOps.autocontrast(gray, cutoff=1)
    
    # Scale up 2x for better accuracy
    scaled = processed.resize(
        (processed.width * 2, processed.height * 2), 
        Image.LANCZOS
    )
    
    # Sharpen
    sharpened = scaled.filter(ImageFilter.SHARPEN)
    
    # Save and OCR
    tmp_path = '/tmp/ocr_processed.png'
    sharpened.save(tmp_path)
    
    result = subprocess.run(
        ['tesseract', tmp_path, 'stdout', '-l', lang, '--psm', str(psm)],
        capture_output=True, text=True
    )
    return result.stdout.strip()
```

## Preprocessing Decision Tree

### Step 1: Analyze Image

```python
from PIL import Image
img = Image.open('screenshot.png')
print(f'Size: {img.size}, Mode: {img.mode}')

# Sample background (corner) and content (center)
bg = img.getpixel((50, 50))
center = img.getpixel((img.width // 2, img.height // 2))
bg_brightness = sum(bg) // 3
center_brightness = sum(center) // 3
```

### Step 2: Choose Preprocessing

| Scenario | Pipeline |
|----------|----------|
| Dark bg + light text (most common) | `invert → autocontrast → scale 2x → sharpen` |
| Light bg + dark text (standard docs) | `autocontrast → scale 2x → sharpen` |
| Low contrast / faded | `autocontrast(cutoff=2) → enhance(2.0) → scale 2x` |
| Small text (< 12px) | Scale 3-4x instead of 2x |
| Noisy / compressed | `gaussian_blur(0.5) → sharpen → threshold` |

### Step 3: Choose PSM Mode

| PSM | Use When |
|-----|----------|
| `3` | Fully automatic (default, good for unknown layout) |
| `4` | Single column of variable-sized text |
| `6` | Single uniform block of text |
| `7` | Single text line (crop to line first) |
| `11` | Sparse text / multiple sections (study materials, mixed content) |
| `13` | Raw single line (no Tesseract enhancements) |

### Step 4: Run Tesseract

```bash
# Chinese + English
tesseract processed.png stdout -l chi_sim+eng --psm 6

# English only
tesseract processed.png stdout -l eng --psm 6

# Multiple sections
tesseract processed.png stdout -l chi_sim+eng --psm 11
```

## Multi-Section Images

For images with multiple distinct text blocks (e.g., study materials with multiple topics, app screens with cards):

```python
height = img.height
strip_height = 150
all_text = []

for y in range(0, height, strip_height):
    strip = img.crop((0, y, img.width, min(y + strip_height, height)))
    # Process each strip individually with PSM 6
    # Concatenate results with section headers
```

## Troubleshooting

| Problem | Cause | Solution |
|---------|-------|----------|
| Garbage output (random chars like `{BAA o RAB}`) | **Missing language pack** — #1 cause | `tesseract --list-langs` then install `chi_sim` |
| Missing text | Wrong PSM mode | Try PSM 11 for sparse/sectioned content |
| Partial text visible | Text too small | Scale up 3-4x instead of 2x |
| Blurry results | No sharpening | Add `ImageFilter.SHARPEN` after scaling |
| Dark background not handled | Forgot to invert | Check corner pixel brightness, invert if < 150 |
| Mixed Chinese/English not recognized | Wrong language | Use `-l chi_sim+eng` |

### Quick diagnostic: is inversion needed?

```python
from PIL import Image
img = Image.open('screenshot.png')
corner = img.getpixel((50, 50))
brightness = sum(corner) // 3
print(f"Corner pixel: {corner}, brightness: {brightness}")
print("→ Invert needed" if brightness < 150 else "→ No inversion needed")
```

## Dependencies

### RapidOCR (Recommended)
```bash
pip install rapidocr-onnxruntime opencv-python-headless
```

### PaddleOCR (Maximum Accuracy)
```bash
pip install paddleocr paddlepaddle opencv-python-headless
```

### Tesseract (English Only)
```bash
# On Guix
guix install tesseract-ocr tesseract-ocr-chi-sim

# Or on Debian/Ubuntu
sudo apt install tesseract-ocr tesseract-ocr-chi-sim
```

### PIL/Pillow (for Tesseract preprocessing)
```bash
pip install Pillow
```

### Optional: uv Setup Guide
See [references/uv-setup-guide.md](references/uv-setup-guide.md) for creating a self-contained OCR environment with uv.

## Key Insights

1. **Tesseract is NOT suitable for Chinese**: Even with language packs, Tesseract struggles with screenshots, dark backgrounds, and mixed content. Use RapidOCR or PaddleOCR instead.
2. **RapidOCR is the sweet spot**: Fast setup, excellent Chinese recognition, no GPU needed. Start here for screenshot OCR.
3. **PaddleOCR for complex layouts**: When you need maximum accuracy or table recognition, PaddleOCR is worth the setup cost.
4. **Inversion is critical for Tesseract**: Tesseract expects dark text on light background. App screenshots usually have the opposite — forgetting to invert is a common failure mode.
5. **vision_analyze is unreliable for text**: Vision models frequently fail on text-dense images, returning errors like "you forgot to upload" even with valid file paths. Always have an OCR fallback ready.
6. **Language packs first**: If you must use Tesseract, always check `tesseract --list-langs` before any OCR task.

See [references/backend-comparison.md](references/backend-comparison.md) for real-world test results comparing all three backends.
