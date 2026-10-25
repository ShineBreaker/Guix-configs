# openpyxl xlsx caveats (runnable)

## Environment (this box)
- openpyxl is NOT in the default Guix Home python profile. Run any edit script with:
  `guix shell python python-openpyxl -- python3 script.py`
- For LibreOffice headless recompute (none available here): `which soffice` → if missing, fallback to the ground-truth verification script (see scripts/verify_xlsx_ground_truth.py).

## Load correctly
```python
import openpyxl
wb = openpyxl.load_workbook(path, data_only=False)  # NOT True: True returns cached values (None for never-computed formulas)
ws = wb["Sheet1"]
```

## Dump structure safely
```python
def show(v):
    if v is None: return None
    if hasattr(v, "text"): return "ARRAY:" + v.text   # ArrayFormula
    return v
for row in ws.iter_rows():
    for c in row:
        if c.value is not None:
            print(f"{c.coordinate} = {show(c.value)!r}")
print("MERGED:", list(ws.merged_cells.ranges))
print("DIM:", ws.dimensions)
```

## ArrayFormula — preserve it
```python
from openpyxl.worksheet.formula import ArrayFormula
ws["A1"] = ArrayFormula("A1:A1", "=SUMPRODUCT(--(TRIM(C1:C10)<>\"\"))")
# NEVER store a bare "==SUMPRODUCT(...)" string — openpyxl degrades it to a normal formula.
# To read it back: cell.value.text  (str(cell.value) is useless)
```

## insert_cols does NOT extend merges / widths
```python
ws.insert_cols(39, 8)          # insert 8 cols at index 39, shifting right
# After this:
ws.unmerge_cells("A1:AN1"); ws.merge_cells("A1:AV1")   # title bar did NOT auto-extend
ref_w = ws.column_dimensions['AL'].width
for col in range(39, 47):
    if ws.column_dimensions[get_column_letter(col)].width is None:
        ws.column_dimensions[get_column_letter(col)].width = ref_w
```

## Copy style to new header cells
```python
from copy import copy
def copy_style(src, dst):
    dst.font = copy(src.font); dst.fill = copy(src.fill)
    dst.alignment = copy(src.alignment); dst.border = copy(src.border)
    dst.number_format = copy(src.number_format)
```

## Rewrite formula ranges after a shift
After inserting columns, every formula range must be rebuilt with new letters:
- data row: `=SUM(C4:AL4)` → `=SUM(C4:AT4)`
- count row: `SUMPRODUCT(--(TRIM(C4:AL63)<>""))` → `...:AT63`
- summary columns shift right too (e.g. AU/AV).

## Save as NEW file (keep original for diff)
```python
wb.save("/path/out_已补录.xlsx")
```
Cleanup temp scripts with `trash` (not `rm`).
