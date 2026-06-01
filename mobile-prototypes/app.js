const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const money = n => new Intl.NumberFormat('vi-VN').format(n) + 'đ';
let suppressClickOnce = false;

function toast(t) {
  let el = $('.toast') || document.body.appendChild(Object.assign(document.createElement('div'), { className: 'toast' }));
  el.textContent = t;
  el.classList.add('show');
  clearTimeout(el._t);
  el._t = setTimeout(() => el.classList.remove('show'), 1800);
}
function openSheet(id) { $('.scrim')?.classList.add('open'); $(id)?.classList.add('open'); }
function closeSheet() { $$('.sheet,.scrim').forEach(x => x.classList.remove('open')); }
function getSelectedMembers() { return $$('.debt.selectable.selected').map(el => ({ el, name: el.dataset.name || el.querySelector('b')?.textContent?.trim() || 'Mục', amount: Number(el.dataset.amount || 0) })); }
function setSelected(el, value) { if (!el) return; el.classList.toggle('selected', value); const input = $('[data-select-member]', el); if (input) input.checked = value; updateBulkState(); }
function toggleSelected(el) { setSelected(el, !el.classList.contains('selected')); }
function updateBulkState() {
  const selected = getSelectedMembers(); const n = selected.length; const total = selected.reduce((sum, m) => sum + m.amount, 0); const bulk = $('[data-bulk]');
  if (bulk) { bulk.hidden = n === 0; const count = $('b', bulk); const totalEl = $('[data-bulk-total]', bulk); if (count) count.textContent = n; if (totalEl) totalEl.textContent = money(total); }
  const selectedCount = $('#selectedCount'); if (selectedCount) selectedCount.textContent = `${n} chọn`;
  const title = $('[data-pay-title]'); const names = $('[data-pay-names]'); const payTotal = $('[data-pay-total]');
  if (title) title.textContent = n ? `Thanh toán ${n} mục` : 'Thanh toán nợ';
  if (names) names.textContent = n ? selected.map(m => m.name).join(', ') : 'Chưa chọn';
  if (payTotal) payTotal.textContent = money(total);
}
function prepareSinglePayment(btn) { const item = btn.closest('.debt'); $$('.debt.selectable').forEach(el => setSelected(el, el === item)); updateBulkState(); }
function filterList(inputSel, itemSel) { const q = $(inputSel)?.value.toLowerCase() || ''; $$(itemSel).forEach(i => { const textMatch = i.textContent.toLowerCase().includes(q); const chip = $('[data-filter-row] .chip.active')?.dataset.debtFilter || 'all'; const tagMatch = chip === 'all' || (i.dataset.tags || '').includes(chip); i.style.display = textMatch && tagMatch ? 'grid' : 'none'; }); }
function copyCode() { navigator.clipboard?.writeText('BMT-DEBT'); toast('Đã copy nội dung chuyển khoản'); }

document.addEventListener('click', e => {
  if (suppressClickOnce) { suppressClickOnce = false; if (e.target.closest('.debt.selectable')) return; }
  const payOne = e.target.closest('[data-pay-one]'); if (payOne) prepareSinglePayment(payOne);
  const checkbox = e.target.closest('[data-select-member]'); if (checkbox) { const item = checkbox.closest('.debt'); setSelected(item, checkbox.checked); e.stopPropagation(); return; }
  const selectable = e.target.closest('.debt.selectable'); if (selectable && !e.target.closest('button,a,label,input')) toggleSelected(selectable);
  const filter = e.target.closest('[data-debt-filter]'); if (filter) { $$('[data-debt-filter]').forEach(b => b.classList.toggle('active', b === filter)); filterList('#q', '.debt'); }
  const a = e.target.closest('[data-sheet]'); if (a) { if (a.matches('[data-pay-current]') && getSelectedMembers().length === 0) { toast('Chọn ít nhất 1 người hoặc 1 buổi'); return; } updateBulkState(); openSheet(a.dataset.sheet); }
  if (e.target.matches('[data-close],.scrim')) closeSheet();
  const c = e.target.closest('[data-toast]'); if (c) toast(c.dataset.toast);
  const tab = e.target.closest('[data-tab]'); if (tab) { const group = tab.closest('[data-tabs]'); $$('[data-tab]', group).forEach(b => b.classList.toggle('active', b === tab)); const scope = group.dataset.tabs; $$(`[data-panel^="${scope}:"]`).forEach(p => p.hidden = p.dataset.panel !== `${scope}:${tab.dataset.tab}`); }
});
let holdTimer = null; let holdTarget = null;
const clearHold = () => { clearTimeout(holdTimer); holdTimer = null; holdTarget = null; };
document.addEventListener('pointerdown', e => { const item = e.target.closest('.debt.selectable'); if (!item || e.target.closest('button,a,label,input')) return; holdTarget = item; holdTimer = setTimeout(() => { toggleSelected(item); suppressClickOnce = true; item.classList.add('held'); toast(item.classList.contains('selected') ? 'Đã chọn' : 'Đã bỏ chọn'); setTimeout(() => item.classList.remove('held'), 450); holdTarget = null; }, 500); });
document.addEventListener('pointerup', clearHold); document.addEventListener('pointercancel', clearHold); document.addEventListener('keydown', e => { const item = e.target.closest?.('.debt.selectable'); if (item && (e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); toggleSelected(item); } });
window.addEventListener('DOMContentLoaded', () => { updateBulkState(); if (document.body.dataset.tip) setTimeout(() => toast(document.body.dataset.tip), 500); });
updateBulkState();