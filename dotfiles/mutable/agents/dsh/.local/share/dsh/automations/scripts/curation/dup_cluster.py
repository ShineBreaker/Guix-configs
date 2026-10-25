#!/usr/bin/env python3
"""把合并候选对聚成簇（连通分量），每簇给一个主卡候选（正文最长者）。
产出供人读的簇清单，不自动执行合并。"""
import json, pathlib, collections

root = pathlib.Path(__file__).resolve().parent
kb = pathlib.Path.home()/'Documents/Org/agenote'
index = json.load(open(kb/'index.json'))
by_id = {c['id']: c for c in index['cards']}

pairs = json.loads((root/'merge-candidates.json').read_text())
jev = {}
for ln in open(root/'jev-cards.jsonl'):
    r = json.loads(ln); jev[r['id']] = r

# 并查集
parent = {}
def find(x):
    parent.setdefault(x, x)
    while parent[x] != x:
        parent[x] = parent[parent[x]]; x = parent[x]
    return x
def union(a, b):
    ra, rb = find(a), find(b)
    if ra != rb: parent[rb] = ra

for p in pairs:
    union(p['a_id'], p['b_id'])

clusters = collections.defaultdict(set)
for k in list(parent):
    clusters[find(k)].add(k)

out = []
for root_id, members in sorted(clusters.items(), key=lambda kv: -len(kv[1])):
    if len(members) < 2: continue
    recs = []
    for m in members:
        c = by_id.get(m)
        if not c: continue
        p = kb/c['file']
        body = p.read_text(errors='ignore') if p.exists() else ''
        recs.append({'id': m, 'title': c['title'], 'chars': len(body),
                     'usage': c.get('usage_count') or 0, 'file': c['file'],
                     'status': c['status'], 'type': c['type'],
                     'jev_dup': jev.get(m, {}).get('duplicated'),
                     'jev_novalue': jev.get(m, {}).get('no_value')})
    recs.sort(key=lambda r: -r['chars'])
    out.append({'size': len(recs), 'members': recs})

pathlib.Path('dup-clusters.json').write_text(json.dumps(out, ensure_ascii=False, indent=1))
for cl in out:
    print(f"=== 簇 {cl['size']} 张 ===")
    for r in cl['members']:
        d = f"{r['jev_dup']:.2f}" if r['jev_dup'] is not None else ' - '
        nv = f"{r['jev_novalue']:.2f}" if r['jev_novalue'] is not None else ' - '
        print(f"  {r['id']:20s} {r['chars']:6d}ch use={r['usage']:2d} dup={d} nv={nv} {r['title'][:56]}")
print('clusters:', len(out))
