# Practical OCR Setup with uv

## Quick Setup (2026-07-29)

For a self-contained OCR environment using Python virtual environments:

```bash
# 1. Create project directory
mkdir -p ~/Programs/ocr-system && cd ~/Programs/ocr-system

# 2. Initialize uv project
uv init --name ocr-system --no-workspace

# 3. Install RapidOCR (recommended for Chinese)
uv pip install rapidocr-onnxruntime opencv-python-headless

# 4. Install PaddleOCR (optional, for higher accuracy)
uv pip install paddleocr paddlepaddle opencv-python-headless

# 5. Test
.venv/bin/python -c "from rapidocr_onnxruntime import RapidOCR; print('OK')"
```

## Project Structure

```
~/Programs/ocr-system/
├── ocr_engine.py      # Unified OCR engine (RapidOCR + PaddleOCR)
├── ocr_cli.py         # CLI tool for single images
├── batch_ocr.py       # Batch processing (zip or directory)
├── pyproject.toml     # Project config
└── .venv/             # Virtual environment
```

## Usage

```bash
# Single image
.venv/bin/python ocr_cli.py image.png --backend rapidocr

# Batch (zip or directory)
.venv/bin/python batch_ocr.py /path/to/images/ --backend rapidocr --text-output result.txt

# With detail (bounding boxes + confidence)
.venv/bin/python ocr_cli.py image.png --backend rapidocr --detail
```

## Notes

- Use `opencv-python-headless` instead of `opencv-python` in server/CLI environments (avoids libxcb dependency)
- PaddleOCR first run downloads models to `~/.paddlex/official_models/`
- RapidOCR uses ONNX Runtime — no GPU needed, works on CPU
- For Guix systems: `guix search opencv` may find system packages, but pip install in venv is more reliable
