---
name: spreadsheet-xlsx-edit
description: Safely edit formula-driven .xlsx workbooks with openpyxl — when the user hands you a "table" that is actually a complex workbook (array formulas, per-row SUM/SUMPRODUCT, merged title bars, a column cap). Covers structure-first inspection, structural edits (insert_cols + shifting summary formulas), preserving array formulas, and verifying correctness WITHOUT LibreOffice/Excel.
triggers:
  - user gives an .xlsx and asks to "fill in / add rows / add columns / update prices / complete the table"
  - the workbook has formulas (SUM / SUMPRODUCT / array) that must keep working after the edit
  - you must add columns beyond the current width and shift summary columns + their formulas
  - verify an xlsx edit is correct but no spreadsheet engine is available to recompute
---

# spreadsheet-xlsx-edit

## Core principle
The user's verbal description of a spreadsheet ("it's just a list of books") almost NEVER matches the real structure. In this session the "table" was a 44-column class-fee workbook: a header row of book names with a decorative `(打折后价格）` suffix, a template "example" row, 60 student rows with empty price columns, array-formula count/total columns, a `SUMPRODUCT(TRIM(...)<>""` count row, and a merged `A1:AN1` title bar. **Inspect the actual file first. Never assume the description matches.**

## Workflow
1. **INSPECT before editing.**
   - openpyxl is NOT in the default Guix Home python profile. Run scripts with: `guix shell python python-openpyxl -- python3 script.py`
   - Load with `data_only=False` (not True — True returns cached values that are `None` for never-computed formulas).
   - Dump: sheet names, `ws.dimensions`, `list(ws.merged_cells.ranges)`, and every non-empty cell. For formula cells, print `v.text` if `hasattr(v,'text')` (ArrayFormula) else `v`. This reveals the exact SUM/SUMPRODUCT ranges and which columns are data vs summary.
   - Identify: header row(s), the template "example" row, data rows, the count/total summary row, the last data column letter, and the summary column letters.
2. **DETECT CONTRADICTIONS, then clarify.**
   - If the user's item count > current column cap (e.g. 44 books but only 36 price columns), you must **insert columns AND shift summary formulas** — a structural change. Confirm the approach with `clarify` (offer: expand columns / truncate / put data below the table).
   - If a "fill target" row is actually a template example row, clarify whether to overwrite it.
3. **EDIT structurally-correct.**
   - `ws.insert_cols(idx, n)` inserts n cols at idx, shifting right. CRITICAL caveats:
     a. Merged ranges are NOT extended (title `A1:AN1` stays put) → manually `unmerge_cells` then `merge_cells` to the new width.
     b. New columns get NO width → read a reference column width and assign to each new column.
     c. Every formula referencing the shifted region must be rewritten with new letters (`SUM(C4:AL4)`→`SUM(C4:AT4)`, `SUMPRODUCT(TRIM(...:AL63))`→`...:AT63`); summary column letters shift too.
   - Preserve array formulas by writing `openpyxl.worksheet.formula.ArrayFormula("A1:A1", "=formula")`, NOT a bare string — a bare string degrades it to a normal formula and may break it.
   - Copy header cell styles (`copy(font/fill/alignment/border/number_format)`) to new header cells so columns match.
4. **VERIFY without an engine.**
   - No LibreOffice in this env → cannot recompute. Instead write a verification script that loads the SAVED output and compares it against the user's original data as ground truth: every header name (after stripping decorative suffixes + any "11 " prefix), every price (within 0.001), empty-cell expectations, and re-prints the formula range strings to confirm they point at the new columns. See `scripts/verify_xlsx_ground_truth.py`.

## Pitfalls (learned the hard way)
- Keep the original; write a NEW `_已补录.xlsx` (or similar) output so the user can diff. Cleanup temp scripts with `trash` (user preference), not `rm`.
- Header decorative suffixes use MIXED brackets in this corpus (ASCII `(` + fullwidth `）`). Extract the exact suffix from an existing header cell and reuse it — don't hardcode, or new headers won't match the originals.
- `str(ArrayFormula)` is useless; use `.text`.
- When comparing headers, strip BOTH the decorative suffix AND any leading "11 " numbering prefix the template may carry.

## References & support files
- `references/openpyxl-xlsx-caveats.md` — full openpyxl gotchas with runnable snippets (env, ArrayFormula, insert_cols, style copy, save).
- `scripts/verify_xlsx_ground_truth.py` — reusable verification harness; fill the `GT` list with the user's source data, run, get a PASS/FAIL report.
