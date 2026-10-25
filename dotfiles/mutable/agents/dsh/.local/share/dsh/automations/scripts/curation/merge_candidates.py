#!/usr/bin/env python3
"""确定性合并候选聚类：标题相似度 + 共享实词 + 同 category/tech 约束。
Jev 在成对相似度上偏保守，合并判断交给确定性算法，这里只产候选。"""
import json, pathlib, re, itertools, collections

root = pathlib.Path(__file__).resolve().parent
kb = pathlib.Path.home()/'Documents/Org/agenote'
d = json.load(open(kb/'index.json'))
cards = [c for c in d['cards'] if c['status'] != 'archived']

STOP = set('''的 了 和 与 在 是 对 用 不 一个 我们 可以 这个 那个 the a an of to in for on with and or is are be by
guix emacs agenote kb org mode'''.split())

def toks(t):
    t = re.sub(r'[^0-9A-Za-z\u4e00-\u9fff]+', ' ', t.lower())
    return {w for w in t.split() if len(w) > 1 and w not in STOP}

def bigrams(s):
    s = re.sub(r'\s+', '', s.lower())
    return {s[i:i+2] for i in range(len(s)-1)} or {s}

# 1) 按 tech 归一分组（先把 tech 碎片聚拢到主域）
def main_domain(tech):
    if not tech: return ''
    first = re.split(r'[,;/ ]', tech)[0].strip()
    m = {'elisp':'emacs','shepherd':'guix','ratatui':'rust','niri':'linux','dsh':'agent'}
    return m.get(first.lower(), first.lower())

groups = collections.defaultdict(list)
for c in cards:
    groups[main_domain(c['tech'])].append(c)

cands = []
for dom, cs in groups.items():
    if len(cs) > 120: continue
    for a, b in itertools.combinations(cs, 2):
        ta, tb = toks(a['title']), toks(b['title'])
        inter = ta & tb
        if len(inter) < 2: continue
        bg_a, bg_b = bigrams(a['title']), bigrams(b['title'])
        j = len(bg_a & bg_b)/max(1, len(bg_a | bg_b))
        if j < 0.22: continue
        # 同类别加分
        if a['category'] == b['category']: j += 0.08
        if a['type'] == b['type']: j += 0.04
        cands.append({'score': round(j, 3), 'domain': dom, 'shared': sorted(inter),
                      'a': a, 'b': b})

cands.sort(key=lambda x: -x['score'])
print(f'域名分组数: {len(groups)}, 合并候选对: {len(cands)}')
out = []
for c in cands[:120]:
    out.append({'score': c['score'], 'domain': c['domain'], 'shared': c['shared'],
                'a_id': c['a']['id'], 'a_title': c['a']['title'], 'a_file': c['a']['file'],
                'a_usage': c['a'].get('usage_count') or 0,
                'b_id': c['b']['id'], 'b_title': c['b']['title'], 'b_file': c['b']['file'],
                'b_usage': c['b'].get('usage_count') or 0})
    print(f"{c['score']:.2f} [{c['domain']:10s}] {c['a']['id']} {c['a']['title'][:44]} || {c['b']['id']} {c['b']['title'][:44]}")
pathlib.Path('merge-candidates.json').write_text(json.dumps(out, ensure_ascii=False, indent=1))
