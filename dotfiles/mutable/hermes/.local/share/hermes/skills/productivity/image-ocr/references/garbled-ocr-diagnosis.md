# Garbled OCR Diagnosis

## Symptom

Tesseract produces random characters that look like code/config but not the actual text:
```
{BAA o RAB 5 maaegor (Sik
2APUL, TOMSUE
sERIEESLIB 6 (W1at220-60R12)
```

## Root Cause

**Missing Chinese language pack.** Tesseract falls back to English-only recognition when `chi_sim` is not installed, producing garbage for Chinese characters.

## Diagnosis Steps

1. Check installed languages:
   ```bash
   tesseract --list-langs
   ```
   If output only shows `eng`, Chinese is missing.

2. Verify the garbled pattern: random uppercase letters, numbers, and symbols that vaguely resemble text structure but are completely meaningless.

## Fix

```bash
# Guix
guix install tesseract-ocr-chi-sim

# Debian/Ubuntu
sudo apt install tesseract-ocr-chi-sim

# macOS
brew install tesseract-lang
```

## Prevention

Always run `tesseract --list-langs` as the **first step** of any OCR task. If the expected language is missing, install it before wasting time on preprocessing adjustments.

## Lesson Learned

2026-07-29: Spent significant time trying different preprocessing approaches (inversion, scaling, thresholding, PSM modes) when the actual problem was simply a missing language pack. The garbled output pattern (`{BAA o RAB}`) is a telltale sign of language mismatch, not a preprocessing issue.
