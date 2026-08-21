/* 模板：教学互动网站的内容数据 + 渲染 + 搜索 + glossary
 * 复制此文件并改 DAYS / Glossary 即可。 */
(function() {
'use strict';

/* ---------- 本地存储 ---------- */
const KEY_DONE = 'me-completed';
const KEY_THEME = 'me-theme';
function loadDone() { try { return new Set(JSON.parse(localStorage.getItem(KEY_DONE) || '[]')); } catch { return new Set(); } }
function saveDone(set) { try { localStorage.setItem(KEY_DONE, JSON.stringify([...set])); } catch {} }
let completed = loadDone();
window.Storage = {
  get completed() { return completed; },
  toggle(id) { if (completed.has(id)) completed.delete(id); else completed.add(id); saveDone(completed); },
  get theme() { return localStorage.getItem(KEY_THEME) || 'dark'; },
  set theme(v) { try { localStorage.setItem(KEY_THEME, v); } catch {} }
};

/* ---------- 内容渲染 ---------- */
function renderSection(s) {
  switch (s.type) {
    case 'p':    return `<div class="prose">${s.html}</div>`;
    case 'h2':   return `<h2>${s.text}</h2>`;
    case 'h3':   return `<h3>${s.text}</h3>`;
    case 'tip':  return `<div class="card card--tip"><div class="card__title">💡 ${s.title}</div><div>${s.body}</div></div>`;
    case 'warn': return `<div class="card card--tip" style="border-left-color:var(--accent-5)"><div class="card__title">⚠ ${s.title}</div><div>${s.body}</div></div>`;
    case 'code': return `<pre class="code">${s.code}</pre>`;
    case 'steps':return `<div>${s.items.map((it,i)=>`<div class="card"><b>${i+1}.</b> ${it.title} — ${it.desc}</div>`).join('')}</div>`;
    case 'component': return `<div class="component" data-id="${s.id}"></div>`;
    default: return '';
  }
}

function renderDays() {
  const main = document.getElementById('main');
  main.innerHTML = window.DAYS.map(d => `
    <section class="day" id="day-${d.id}">
      <header class="day__header">
        <span class="day__chip">${d.id}</span>
        <h2 class="day__title">${d.title}</h2>
        <button class="day__btn" data-complete="${d.id}" style="margin-left:auto">已完成</button>
      </header>
      ${d.sections.map(renderSection).join('')}
    </section>
  `).join('');
  document.querySelectorAll('.day__btn').forEach(b => {
    const id = +b.dataset.complete;
    if (window.Storage.completed.has(id)) b.style.background = 'var(--accent)';
    b.style.cssText += ';background:var(--bg-elev);border:1px solid var(--border);padding:6px 12px;border-radius:6px;cursor:pointer;color:var(--fg-soft);';
    b.addEventListener('click', () => {
      window.Storage.toggle(id);
      b.style.background = window.Storage.completed.has(id) ? 'var(--accent)' : 'var(--bg-elev)';
      b.style.color = window.Storage.completed.has(id) ? '#fff' : 'var(--fg-soft)';
      refreshProgress();
    });
  });
  // 挂载命名组件
  document.querySelectorAll('.component').forEach(el => {
    const c = window.Components.map[el.dataset.id];
    if (c) { el.innerHTML = c.html(); c.bind(el); }
  });
}

/* ---------- 侧栏 + 进度 ---------- */
function renderNav() {
  const nav = document.getElementById('dayNav');
  nav.innerHTML = window.DAYS.map(d => `
    <a class="nav__item" data-jump="day-${d.id}" data-day="${d.id}">
      <span class="nav__check">✓</span><span>${d.title}</span>
    </a>
  `).join('');
  nav.addEventListener('click', e => {
    const a = e.target.closest('.nav__item');
    if (a) { document.getElementById(a.dataset.jump)?.scrollIntoView({behavior:'smooth'}); }
  });
}
function refreshProgress() {
  const total = window.DAYS.length;
  const done = window.Storage.completed.size;
  document.getElementById('progressText').textContent = `${done} / ${total}`;
  document.getElementById('progressBar').style.width = (done/total*100)+'%';
  document.querySelectorAll('.nav__item').forEach(a => {
    a.classList.toggle('completed', window.Storage.completed.has(+a.dataset.day));
  });
}

/* ---------- 搜索 ---------- */
function setupSearch() {
  const input = document.getElementById('searchInput');
  const res = document.getElementById('searchResults');
  const idx = window.DAYS.map(d => ({id: d.id, title: d.title, text: (d.title + ' ' + d.sections.map(s=>s.text||s.title||s.body||s.html||'').join(' ')).toLowerCase()}));
  input.addEventListener('input', () => {
    const q = input.value.trim().toLowerCase();
    if (!q) { res.classList.remove('active'); return; }
    const hits = idx.filter(i => i.text.includes(q)).slice(0, 8);
    res.innerHTML = hits.map(h => `<a href="#day-${h.id}">${h.title}</a>`).join('');
    res.classList.add('active');
  });
}

/* ---------- glossary tooltip + 面板 ---------- */
function setupGlossary() {
  const tip = document.getElementById('tooltip');
  const show = t => {
    const d = window.Glossary[t.dataset.term]; if (!d) return;
    tip.innerHTML = `<span class="tooltip__name">${d.name}</span><div>${d.body}</div>`;
    tip.classList.add('visible');
    const r = t.getBoundingClientRect();
    tip.style.left = Math.max(8, r.left) + 'px';
    tip.style.top = (r.bottom + 6) + 'px';
  };
  document.addEventListener('mouseover', e => { const t = e.target.closest('.g-term'); if (t) show(t); });
  document.addEventListener('mouseout', e => { if (e.target.closest('.g-term')) tip.classList.remove('visible'); });

  const panel = document.getElementById('glossaryPanel');
  const list = document.getElementById('glossaryList');
  const search = document.getElementById('glossarySearch');
  const render = (q='') => {
    const es = Object.entries(window.Glossary).filter(([k,v])=>!q||v.name.toLowerCase().includes(q.toLowerCase()));
    es.sort((a,b)=>a[1].name.localeCompare(b[1].name));
    list.innerHTML = es.map(([k,v])=>`<div class="glossary-item"><div class="glossary-item__name">${v.name}</div><div>${v.body}</div></div>`).join('');
  };
  document.getElementById('glossaryBtn').onclick = () => panel.classList.toggle('open');
  document.getElementById('glossaryClose').onclick = () => panel.classList.remove('open');
  search.addEventListener('input', () => render(search.value));
  render();
}

/* ---------- 启动 ---------- */
document.addEventListener('DOMContentLoaded', () => {
  document.documentElement.dataset.theme = window.Storage.theme;
  document.getElementById('themeBtn').onclick = () => {
    const cur = document.documentElement.dataset.theme;
    const next = cur === 'dark' ? 'light' : 'dark';
    document.documentElement.dataset.theme = next;
    window.Storage.theme = next;
  };
  renderDays(); renderNav(); refreshProgress(); setupSearch(); setupGlossary();
});

/* ---------- 命名组件挂载点（用户实现） ---------- */
window.Components = { map: {} };

})();