# OCR Backend Comparison

## Real-World Test (2026-07-29)

Test scenario: 18 screenshots of Chinese driving exam study materials (科目一), each ~1440x1080px, dark background with white text.

| Backend | Setup | First Run | Recognition Quality | Speed |
|---------|-------|-----------|---------------------|-------|
| **Tesseract** (no chi-sim) | System package | Instant | ❌ **Garbage** (`{BAA o RAB 5 maaegor}`) | Fast |
| **Tesseract** (with chi-sim) | System package + lang pack | Instant | ⚠️ Poor on screenshots | Fast |
| **RapidOCR** | `pip install rapidocr-onnxruntime` | ~5s init | ✅ **Excellent** | ~2s/image |
| **PaddleOCR** | `pip install paddleocr paddlepaddle` | ~60s model download | ✅ **Excellent** | ~5s/image |

## Why Tesseract Fails on Chinese

Tesseract's Chinese recognition relies on:
1. Language pack files (`chi_sim.traineddata`, ~20MB each)
2. Legacy LSTM models trained on document images, not screenshots
3. Sensitivity to font rendering, anti-aliasing, and background colors

Without the language pack, Tesseract falls back to English and produces random Unicode garbage. Even WITH the language pack, it struggles with:
- Dark backgrounds (must invert first)
- Small text in screenshots
- Mixed Chinese/English content
- Non-document fonts (UI text, app screenshots)

## When to Use Each

### RapidOCR (Recommended)
- ✅ Chinese + English mixed content
- ✅ Screenshots, app content, UI text
- ✅ Real-time or batch processing
- ✅ CPU-only environments (ONNX Runtime)
- ✅ Quick setup, no GPU needed

### PaddleOCR (Maximum Accuracy)
- ✅ Complex layouts, tables, multi-column
- ✅ Handwriting recognition
- ✅ When accuracy > speed
- ✅ Can use GPU for faster processing
- ⚠️ Heavy setup (~500MB+ models)
- ⚠️ First run requires model download

### Tesseract (English Only)
- ✅ Simple English documents
- ✅ Scanned PDFs (with good quality)
- ✅ When RapidOCR/PaddleOCR unavailable
- ⚠️ Chinese requires language pack + preprocessing
- ⚠️ Poor on screenshots and UI text

## Setup Commands

```bash
# RapidOCR (recommended for Chinese)
pip install rapidocr-onnxruntime opencv-python-headless

# PaddleOCR (maximum accuracy)
pip install paddleocr paddlepaddle opencv-python-headless

# Tesseract (English fallback)
guix install tesseract-ocr tesseract-ocr-chi-sim  # Guix
# OR
sudo apt install tesseract-ocr tesseract-ocr-chi-sim  # Debian/Ubuntu
```

## Garbled Output Diagnosis

If OCR produces garbage like `{BAA o RAB 5 maaegor}` or random Unicode:

1. **Check Tesseract language pack**: `tesseract --list-langs`
2. **Missing `chi_sim`?** → Install language pack OR switch to RapidOCR
3. **Still garbled?** → Image likely has dark background; invert before OCR
4. **All else fails?** → Use RapidOCR instead of Tesseract

## Reference

- PaddleOCR: https://github.com/PaddlePaddle/PaddleOCR
- RapidOCR: https://github.com/RapidAI/RapidOCR
- Tesseract: https://github.com/tesseract-ocr/tesseract
