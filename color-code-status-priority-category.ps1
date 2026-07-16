# color-code-status-priority-category.ps1
# Colores tipo semaforo para Estado/Prioridad (chips y desplegables),
# y paleta distintiva para Categoria.
$ErrorActionPreference = "Stop"
$root = Get-Location
$enc = New-Object System.Text.UTF8Encoding($false)

Write-Host "Escribiendo css\Styles.html..." -ForegroundColor Cyan
$v0 = @'
<style>
  :root {
    color-scheme: light;
    --primary: #8a5c19;
    --on-primary: #ffffff;
    --primary-container: #f6e8d0;
    --on-primary-container: #4a3110;
    --secondary-container: #f2ede7;
    --surface: #faf8f5;
    --surface-container: #f2ede7;
    --surface-container-high: #ece5db;
    --surface-bright: #ffffff;
    --on-surface: #211d18;
    --on-surface-variant: #6b6258;
    --outline: #a39a8c;
    --outline-variant: #e2dcd3;
    --error: #b3432f;
    --error-container: #fbe7e2;
    --success: #1f5c3a;
    --success-container: #e3f3e8;
    --warning: #8a5c19;
    --warning-container: #faf0dd;
    --info: #1c5e94;
    --info-container: #dcecfa;
    --pending: #a8571a;
    --pending-container: #fce4d1;
    --neutral: #5c554b;
    --neutral-container: #e6e0d6;
    --cat-technical: #5b4ea6;
    --cat-technical-container: #e9e4f9;
    --cat-warranty: #146b63;
    --cat-warranty-container: #d9f0ec;
    --cat-billing: #a02163;
    --cat-billing-container: #fbdeeb;
    --cat-product: #7a3d9c;
    --cat-product-container: #f1e2f8;
    --shadow: 0 1px 2px rgba(33, 29, 24, .06), 0 2px 8px rgba(33, 29, 24, .05);
    --radius-sm: 10px;
    --radius-md: 16px;
    --radius-lg: 24px;
    font-family: Roboto, Inter, Arial, sans-serif;
    background: var(--surface);
    color: var(--on-surface);
  }
  :root[data-theme="dark"] {
    color-scheme: dark;
    --primary: #d9a85c;
    --on-primary: #3d2705;
    --primary-container: #5c3f14;
    --on-primary-container: #f6e8d0;
    --secondary-container: #4a4238;
    --surface: #1c1917;
    --surface-container: #262220;
    --surface-container-high: #302b28;
    --surface-bright: #332e2a;
    --on-surface: #eee8e0;
    --on-surface-variant: #cbc2b4;
    --outline: #8f8677;
    --outline-variant: #4a433a;
    --error: #ffb4a3;
    --error-container: #6b2318;
    --success: #8fd4a8;
    --success-container: #1a3d28;
    --warning: #d9a85c;
    --warning-container: #4a3512;
    --info: #8dc2f2;
    --info-container: #163654;
    --pending: #f2ad78;
    --pending-container: #5c2f0f;
    --neutral: #c9c2b6;
    --neutral-container: #3a352e;
    --cat-technical: #c3b6ef;
    --cat-technical-container: #362a5e;
    --cat-warranty: #7fd8cb;
    --cat-warranty-container: #0f3a35;
    --cat-billing: #f5a8cd;
    --cat-billing-container: #5c1739;
    --cat-product: #dcaef0;
    --cat-product-container: #4a2860;
    --shadow: 0 1px 3px rgba(0, 0, 0, .4);
  }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) {
      color-scheme: dark;
      --primary: #d9a85c; --on-primary: #3d2705; --primary-container: #5c3f14;
      --on-primary-container: #f6e8d0; --secondary-container: #4a4238;
      --surface: #1c1917; --surface-container: #262220; --surface-container-high: #302b28;
      --surface-bright: #332e2a; --on-surface: #eee8e0; --on-surface-variant: #cbc2b4;
      --outline: #8f8677; --outline-variant: #4a433a; --error: #ffb4a3;
      --error-container: #6b2318; --success: #8fd4a8; --success-container: #1a3d28;
      --warning: #d9a85c; --warning-container: #4a3512; --shadow: 0 1px 3px rgba(0,0,0,.4);
      --info: #8dc2f2; --info-container: #163654; --pending: #f2ad78; --pending-container: #5c2f0f; --neutral: #c9c2b6; --neutral-container: #3a352e;
      --cat-technical: #c3b6ef; --cat-technical-container: #362a5e; --cat-warranty: #7fd8cb; --cat-warranty-container: #0f3a35;
      --cat-billing: #f5a8cd; --cat-billing-container: #5c1739; --cat-product: #dcaef0; --cat-product-container: #4a2860;
    }
  }
  * { box-sizing: border-box; }
  body { margin: 0; min-width: 280px; background: var(--surface); color: var(--on-surface); }
  button, input, select { font: inherit; }
  button { color: inherit; }
  .material-symbols-rounded { font-size: 21px; line-height: 1; }
  .app { display: grid; grid-template-columns: 236px minmax(0, 1fr); min-height: 100vh; }
  .navigation {
    position: sticky; top: 0; height: 100vh; display: flex; flex-direction: column;
    padding: 20px 12px; background: var(--surface-container); border-right: 1px solid var(--outline-variant);
  }
  .brand { display: flex; align-items: center; gap: 12px; padding: 6px 12px 24px; }
  .brand-mark {
    display: grid; place-items: center; width: 40px; height: 40px; border-radius: 14px;
    color: var(--on-primary-container); background: var(--primary-container);
  }
  .brand strong, .brand small { display: block; }
  .brand small, .navigation-footer small { margin-top: 2px; color: var(--on-surface-variant); font-size: 12px; }
  .nav-list { display: grid; gap: 4px; }
  .nav-item {
    display: flex; align-items: center; gap: 12px; min-height: 48px; padding: 0 16px;
    border: 0; border-radius: 24px; background: transparent; cursor: pointer; text-align: left;
  }
  .nav-item:hover { background: var(--surface-container-high); }
  .nav-item.is-active { color: var(--on-primary-container); background: var(--primary-container); font-weight: 700; }
  .navigation-footer { margin-top: auto; padding: 16px 12px 4px; overflow-wrap: anywhere; font-size: 13px; }
  .main { min-width: 0; }
  .top-app-bar {
    position: sticky; z-index: 10; top: 0; display: flex; align-items: center; gap: 12px;
    padding: 12px 28px; background: color-mix(in srgb, var(--surface) 90%, transparent);
    border-bottom: 1px solid var(--outline-variant); backdrop-filter: blur(12px);
  }
  .topbar-brand { flex: 0 0 auto; font-weight: 700; white-space: nowrap; }
  .topbar-brand small { margin-left: 4px; font-weight: 400; color: var(--on-surface-variant); }
  .search-field {
    display: flex; align-items: center; gap: 10px; width: min(640px, 100%); min-height: 48px;
    padding: 0 16px; border-radius: 24px; background: var(--surface-container-high);
  }
  .search-field input { width: 100%; border: 0; outline: 0; color: var(--on-surface); background: transparent; }
  .icon-button {
    flex: 0 0 auto; display: grid; place-items: center; width: 44px; height: 44px;
    border: 0; border-radius: 50%; background: transparent; cursor: pointer;
  }
  .icon-button:hover { background: var(--surface-container-high); }
  .view { display: none; padding: 28px; }
  .view.is-active { display: block; }
  .page-heading, .section-heading {
    display: flex; align-items: center; justify-content: space-between; gap: 16px;
  }
  .page-heading { margin-bottom: 24px; }
  h1, h2, h3, p { margin-top: 0; }
  h1 { margin-bottom: 0; font-size: clamp(26px, 3vw, 38px); font-weight: 500; letter-spacing: -.02em; }
  h2 { margin-bottom: 4px; font-size: 20px; }
  h3 { margin-bottom: 6px; }
  .eyebrow { margin-bottom: 4px; color: var(--primary); font-size: 12px; font-weight: 800; letter-spacing: .1em; text-transform: uppercase; }
  .section-heading p, .empty-state p { margin-bottom: 0; color: var(--on-surface-variant); }
  .surface { border: 1px solid var(--outline-variant); border-radius: var(--radius-lg); background: var(--surface-bright); box-shadow: var(--shadow); }
  .metric-grid { display: grid; grid-template-columns: repeat(4, minmax(140px, 1fr)); gap: 16px; margin-bottom: 24px; }
  .metric-card { min-height: 136px; padding: 20px; border-radius: var(--radius-md); background: var(--surface-container); }
  .metric-card .metric-icon {
    display: grid; place-items: center; width: 38px; height: 38px; margin-bottom: 18px;
    border-radius: 12px; color: var(--on-primary-container); background: var(--primary-container);
  }
  .metric-card strong { display: block; font-size: 30px; font-weight: 500; }
  .metric-card span:last-child { color: var(--on-surface-variant); font-size: 13px; }
  .section-heading { padding: 20px 22px 14px; }
  .ticket-cards { display: grid; gap: 1px; overflow: hidden; border-radius: 0 0 var(--radius-lg) var(--radius-lg); background: var(--outline-variant); }
  .ticket-card {
    display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 10px; padding: 16px 22px;
    border: 0; background: var(--surface-bright); cursor: pointer; text-align: left;
  }
  .ticket-card:hover { background: var(--surface-container); }
  .ticket-card strong, .ticket-subject { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .ticket-meta { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; margin-top: 7px; color: var(--on-surface-variant); font-size: 12px; }
  .ticket-workspace { display: grid; grid-template-columns: minmax(480px, 1.25fr) minmax(340px, .75fr); gap: 20px; align-items: start; }
  .ticket-browser { min-width: 0; overflow: hidden; }
  .filters { display: flex; flex-wrap: wrap; align-items: end; gap: 12px; padding: 16px; border-bottom: 1px solid var(--outline-variant); }
  .filters label:not(.breach-filter) { display: grid; gap: 5px; min-width: 120px; color: var(--on-surface-variant); font-size: 12px; }
  select {
    min-height: 40px; padding: 0 34px 0 12px; border: 1px solid var(--outline);
    border-radius: var(--radius-sm); color: var(--on-surface); background: var(--surface-bright);
  }
  .breach-filter { display: flex; align-items: center; gap: 7px; min-height: 40px; color: var(--on-surface-variant); font-size: 13px; }
  .table-wrap { overflow: auto; }
  table { width: 100%; border-collapse: collapse; }
  th, td { padding: 14px 16px; border-bottom: 1px solid var(--outline-variant); text-align: left; font-size: 13px; }
  th { color: var(--on-surface-variant); background: var(--surface-container); font-weight: 700; }
  tbody tr { cursor: pointer; }
  tbody tr:hover, tbody tr.is-selected { background: var(--primary-container); }
  .chip {
    display: inline-flex; align-items: center; min-height: 28px; padding: 0 10px;
    border-radius: 9px; background: var(--secondary-container); font-size: 11px; font-weight: 800;
  }
  .chip[data-tone="error"] { color: var(--error); background: var(--error-container); }
  .chip[data-tone="success"] { color: var(--success); background: var(--success-container); }
  .chip[data-tone="warning"] { color: var(--warning); background: var(--warning-container); }
  /* Status: traffic-light-ish scale (blue=new, amber=in progress, orange=waiting, green=resolved, gray=done/void) */
  .chip[data-value="NEW"] { color: var(--info); background: var(--info-container); }
  .chip[data-value="OPEN"] { color: var(--warning); background: var(--warning-container); }
  .chip[data-value="PENDING_CUSTOMER"] { color: var(--pending); background: var(--pending-container); }
  .chip[data-value="RESOLVED"] { color: var(--success); background: var(--success-container); }
  .chip[data-value="CLOSED"] { color: var(--neutral); background: var(--neutral-container); }
  .chip[data-value="VOID"] { color: var(--neutral); background: var(--neutral-container); }
  /* Priority: classic green -> amber -> orange -> red escalation */
  .chip[data-value="LOW"] { color: var(--success); background: var(--success-container); }
  .chip[data-value="NORMAL"] { color: var(--warning); background: var(--warning-container); }
  .chip[data-value="HIGH"] { color: var(--pending); background: var(--pending-container); }
  .chip[data-value="CRITICAL"] { color: var(--error); background: var(--error-container); }
  /* Category: distinct hues, not urgency-based */
  .chip[data-value="GENERAL"] { color: var(--neutral); background: var(--neutral-container); }
  .chip[data-value="TECHNICAL"] { color: var(--cat-technical); background: var(--cat-technical-container); }
  .chip[data-value="WARRANTY"] { color: var(--cat-warranty); background: var(--cat-warranty-container); }
  .chip[data-value="SHIPPING"] { color: var(--info); background: var(--info-container); }
  .chip[data-value="BILLING"] { color: var(--cat-billing); background: var(--cat-billing-container); }
  .chip[data-value="PRODUCT"] { color: var(--cat-product); background: var(--cat-product-container); }
  .chip[data-value="OTHER"] { color: var(--neutral); background: var(--neutral-container); }
  /* Same palette applied to <select> controls, driven by a data-value the app sets to match the chosen option */
  select.color-coded { font-weight: 800; border-width: 2px; }
  select.color-coded[data-value="NEW"] { color: var(--info); background: var(--info-container); border-color: var(--info); }
  select.color-coded[data-value="OPEN"] { color: var(--warning); background: var(--warning-container); border-color: var(--warning); }
  select.color-coded[data-value="PENDING_CUSTOMER"] { color: var(--pending); background: var(--pending-container); border-color: var(--pending); }
  select.color-coded[data-value="RESOLVED"] { color: var(--success); background: var(--success-container); border-color: var(--success); }
  select.color-coded[data-value="CLOSED"] { color: var(--neutral); background: var(--neutral-container); border-color: var(--neutral); }
  select.color-coded[data-value="VOID"] { color: var(--neutral); background: var(--neutral-container); border-color: var(--neutral); }
  select.color-coded[data-value="LOW"] { color: var(--success); background: var(--success-container); border-color: var(--success); }
  select.color-coded[data-value="NORMAL"] { color: var(--warning); background: var(--warning-container); border-color: var(--warning); }
  select.color-coded[data-value="HIGH"] { color: var(--pending); background: var(--pending-container); border-color: var(--pending); }
  select.color-coded[data-value="CRITICAL"] { color: var(--error); background: var(--error-container); border-color: var(--error); }
  select.color-coded[data-value="GENERAL"] { color: var(--neutral); background: var(--neutral-container); border-color: var(--neutral); }
  select.color-coded[data-value="TECHNICAL"] { color: var(--cat-technical); background: var(--cat-technical-container); border-color: var(--cat-technical); }
  select.color-coded[data-value="WARRANTY"] { color: var(--cat-warranty); background: var(--cat-warranty-container); border-color: var(--cat-warranty); }
  select.color-coded[data-value="SHIPPING"] { color: var(--info); background: var(--info-container); border-color: var(--info); }
  select.color-coded[data-value="BILLING"] { color: var(--cat-billing); background: var(--cat-billing-container); border-color: var(--cat-billing); }
  select.color-coded[data-value="PRODUCT"] { color: var(--cat-product); background: var(--cat-product-container); border-color: var(--cat-product); }
  select.color-coded[data-value="OTHER"] { color: var(--neutral); background: var(--neutral-container); border-color: var(--neutral); }
  .count-badge { padding: 6px 12px; border-radius: 16px; background: var(--surface-container-high); font-size: 13px; }
  .detail-panel { position: sticky; top: 88px; max-height: calc(100vh - 112px); overflow: auto; }
  .detail-header { padding: 22px; border-bottom: 1px solid var(--outline-variant); }
  .detail-header h2 { margin: 8px 0 12px; }
  .detail-title-row { display: flex; align-items: flex-start; justify-content: space-between; gap: 12px; }
  .detail-header-actions { display: flex; gap: 4px; flex-shrink: 0; }
  .detail-chips { display: flex; flex-wrap: wrap; gap: 8px; }
  .detail-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; padding: 18px 22px; border-bottom: 1px solid var(--outline-variant); }
  .detail-field dt { color: var(--on-surface-variant); font-size: 11px; text-transform: uppercase; }
  .detail-field dd { margin: 4px 0 0; overflow-wrap: anywhere; font-size: 13px; }
  .conversation { padding: 20px 22px; }
  .ticket-notes-section { padding: 16px 22px; border-top: 1px solid var(--outline-variant); }
  .ticket-notes-section h3 { margin: 0 0 8px; font-size: 14px; }
  .ticket-notes-section textarea { width: 100%; min-height: 90px; padding: 10px 12px; border: 1px solid var(--outline); border-radius: 12px; color: var(--on-surface); background: var(--surface-bright); font: inherit; resize: vertical; }
  .message { position: relative; margin: 14px 0; padding: 14px 16px; border-radius: 4px 16px 16px 16px; background: var(--surface-container); }
  .message.is-outbound { margin-left: 28px; border-radius: 16px 4px 16px 16px; background: var(--primary-container); }
  .message-head { display: flex; justify-content: space-between; gap: 12px; margin-bottom: 8px; font-size: 11px; color: var(--on-surface-variant); }
  .message p { margin: 0; overflow-wrap: anywhere; white-space: pre-wrap; font-size: 13px; line-height: 1.5; }
  .attachment { display: inline-flex; gap: 5px; align-items: center; margin-top: 10px; color: var(--primary); font-size: 11px; font-weight: 700; }
  .customer-view { padding: 24px; }
  .customer-profile { display: grid; grid-template-columns: auto minmax(0, 1fr); gap: 20px; }
  .avatar { display: grid; place-items: center; width: 64px; height: 64px; border-radius: 50%; background: var(--primary-container); color: var(--on-primary-container); font-size: 24px; }
  .customer-fields { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px; margin-top: 22px; }
  .empty-state { display: grid; place-items: center; min-height: 220px; padding: 30px; text-align: center; }
  .empty-state > .material-symbols-rounded { margin-bottom: 12px; color: var(--outline); font-size: 42px; }
  .tonal-button, .text-button {
    display: inline-flex; align-items: center; gap: 7px; min-height: 40px; padding: 0 16px;
    border: 0; border-radius: 20px; color: var(--on-primary-container); background: var(--primary-container); font-weight: 700; cursor: pointer;
  }
  .text-button { padding: 0 12px; background: transparent; color: var(--primary); }
  .loading { display: flex; align-items: center; gap: 10px; padding: 20px 28px; color: var(--on-surface-variant); }
  .loading[hidden] { display: none; }
  .spinner { width: 18px; height: 18px; border: 2px solid var(--outline-variant); border-top-color: var(--primary); border-radius: 50%; animation: spin .8s linear infinite; }
  .snackbar { position: fixed; z-index: 50; right: 24px; bottom: 24px; max-width: 420px; padding: 14px 18px; border-radius: var(--radius-sm); color: var(--surface); background: var(--on-surface); box-shadow: var(--shadow); }
  [hidden] { display: none !important; }
  @keyframes spin { to { transform: rotate(360deg); } }

  @media (max-width: 1050px) {
    .metric-grid { grid-template-columns: repeat(2, minmax(140px, 1fr)); }
    .ticket-workspace { grid-template-columns: 1fr; }
    .detail-panel { position: static; max-height: none; }
  }
  @media (max-width: 760px) {
    .app { grid-template-columns: 1fr; }
    .navigation { position: static; height: auto; padding: 10px; border-right: 0; border-bottom: 1px solid var(--outline-variant); }
    .brand { padding: 4px 8px 10px; }
    .nav-list { grid-template-columns: repeat(3, 1fr); }
    .nav-item { justify-content: center; min-height: 44px; padding: 0 8px; border-radius: 14px; }
    .nav-item span:last-child { display: none; }
    .navigation-footer { display: none; }
    .top-app-bar { top: 0; padding: 10px 14px; }
    .view { padding: 20px 14px; }
    .page-heading { align-items: flex-end; }
    .filters { display: grid; grid-template-columns: 1fr 1fr; }
    .filters label:not(.breach-filter) { min-width: 0; }
    .table-wrap { max-width: calc(100vw - 30px); }
    th, td { padding: 12px 10px; }
    th:nth-child(4), td:nth-child(4), th:nth-child(5), td:nth-child(5) { display: none; }
  }
  @media (max-width: 420px) {
    .metric-grid { grid-template-columns: 1fr; }
    .filters { grid-template-columns: 1fr; }
    .detail-grid, .customer-fields { grid-template-columns: 1fr; }
    .section-heading { align-items: flex-start; }
  }
</style>
'@
[System.IO.File]::WriteAllText((Join-Path $root "css\Styles.html"), $v0, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo html\Scripts.html..." -ForegroundColor Cyan
$v1 = @'
<script>
(function () {
  'use strict';

  const state = {
    view: 'dashboard',
    tickets: [],
    filtersReady: false,
    selectedTicketId: '',
    selectedDetail: null,
    sort: 'date_desc',
    criteria: {limit: 100}
  };

  const byId = function (id) { return document.getElementById(id); };

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined && text !== null) node.textContent = String(text);
    return node;
  }

  function icon(name) {
    return element('span', 'material-symbols-rounded', name);
  }

  function callServer(functionName) {
    const args = Array.prototype.slice.call(arguments, 1);
    return new Promise(function (resolve, reject) {
      const runner = google.script.run.withSuccessHandler(resolve).withFailureHandler(reject);
      runner[functionName].apply(runner, args);
    });
  }

  function unwrap(response) {
    if (!response || response.ok !== true) {
      const error = response && response.error ? response.error : {};
      throw new Error(error.message || 'El servidor devolvió una respuesta no válida.');
    }
    return response.data;
  }

  async function loadState() {
    setLoading(true);
    try {
      const data = unwrap(await callServer('getUiState', state.criteria));
      state.tickets = data.tickets.items || [];
      renderMetrics(data.metrics);
      renderRecentTickets(sortedTickets(state.tickets).slice(0, 6));
      renderTicketList({items: sortedTickets(data.tickets.items || []), total: data.tickets.total});
      if (!state.filtersReady) {
        populateFilters(data.filters);
        state.filtersReady = true;
      }
      updateFilterCounts(data.metrics);
      if (state.selectedTicketId && !state.tickets.some(function (ticket) { return ticket.id === state.selectedTicketId; })) {
        state.selectedTicketId = '';
        state.selectedDetail = null;
        renderDetail(null);
      }
    } catch (error) {
      showError(error);
    } finally {
      setLoading(false);
    }
  }

  function sortedTickets(tickets) {
    const copy = (tickets || []).slice();
    copy.sort(function (left, right) {
      if (state.sort === 'ticket_asc' || state.sort === 'ticket_desc') {
        const comparison = compareTicketIds(left.id, right.id);
        return state.sort === 'ticket_asc' ? comparison : -comparison;
      }
      const leftTime = dateValue(left.createdAt || left.updatedAt || left.lastMessageAt);
      const rightTime = dateValue(right.createdAt || right.updatedAt || right.lastMessageAt);
      return state.sort === 'date_asc' ? leftTime - rightTime : rightTime - leftTime;
    });
    return copy;
  }

  function dateValue(value) {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? 0 : date.getTime();
  }

  function compareTicketIds(left, right) {
    const leftNumber = ticketNumber(left);
    const rightNumber = ticketNumber(right);
    if (leftNumber !== rightNumber) return leftNumber - rightNumber;
    return String(left || '').localeCompare(String(right || ''));
  }

  function ticketNumber(value) {
    const matches = String(value || '').match(/\d+/g);
    return matches && matches.length ? Number(matches[matches.length - 1]) : 0;
  }

  function renderSortBar() {
    const panel = document.querySelector('.ticket-list-panel');
    if (!panel || panel.querySelector('.ticket-sortbar')) return;
    const header = panel.querySelector('.ticket-list-header');
    if (header) header.hidden = true;

    const bar = element('div', 'ticket-sortbar');
    [
      ['date_desc', 'Fecha ↓'],
      ['date_asc', 'Fecha ↑'],
      ['ticket_desc', 'Ticket ↓'],
      ['ticket_asc', 'Ticket ↑']
    ].forEach(function (item) {
      const button = element('button', 'sort-button', item[1]);
      button.type = 'button';
      button.dataset.sort = item[0];
      button.addEventListener('click', function () {
        state.sort = item[0];
        updateSortButtons();
        renderTicketList({items: sortedTickets(state.tickets), total: state.tickets.length});
      });
      bar.appendChild(button);
    });
    panel.insertBefore(bar, header || panel.firstChild);
    updateSortButtons();
  }

  function updateSortButtons() {
    document.querySelectorAll('.sort-button').forEach(function (button) {
      button.classList.toggle('is-active', button.dataset.sort === state.sort);
    });
  }

  function renderMetrics(metrics) {
    const definitions = [
      ['confirmation_number', metrics.total, 'Tickets totales'],
      ['pending_actions', metrics.active, 'Tickets activos'],
      ['timer_off', metrics.breached, 'SLA incumplidos'],
      ['priority_high', metrics.byPriority.CRITICAL || 0, 'Prioridad crítica']
    ];
    const grid = byId('metric-grid');
    grid.replaceChildren();
    definitions.forEach(function (definition) {
      const card = element('article', 'metric-card');
      const badge = element('span', 'metric-icon');
      badge.appendChild(icon(definition[0]));
      card.appendChild(badge);
      card.appendChild(element('strong', '', definition[1]));
      card.appendChild(element('span', '', definition[2]));
      grid.appendChild(card);
    });
  }

  function renderRecentTickets(tickets) {
    const container = byId('recent-tickets');
    container.replaceChildren();
    if (!tickets.length) {
      const empty = element('div', 'empty-state');
      empty.appendChild(icon('inbox'));
      empty.appendChild(element('h3', '', 'Todavía no hay tickets'));
      empty.appendChild(element('p', '', 'Las nuevas conversaciones de soporte aparecerán aquí.'));
      container.appendChild(empty);
      return;
    }
    tickets.forEach(function (ticket) {
      const button = element('button', 'ticket-card');
      button.type = 'button';
      button.addEventListener('click', function () {
        navigate('tickets');
        selectTicket(ticket.id);
      });
      const body = element('div');
      body.appendChild(element('strong', '', ticket.id));
      body.appendChild(element('div', 'ticket-subject', ticket.subject || '(no subject)'));
      const meta = element('div', 'ticket-meta');
      meta.appendChild(chip(ticket.status, toneForStatus(ticket.status)));
      meta.appendChild(element('span', '', ticket.customerEmail || 'Sin email de cliente'));
      body.appendChild(meta);
      button.appendChild(body);
      button.appendChild(element('span', 'ticket-meta', formatDate(ticket.updatedAt)));
      container.appendChild(button);
    });
  }

  function renderTicketList(page) {
    renderSortBar();
    const body = byId('ticket-table-body');
    body.replaceChildren();
    byId('ticket-count').textContent = page.total + (page.total === 1 ? ' ticket' : ' tickets');
    byId('ticket-empty').hidden = page.items.length !== 0;

    page.items.forEach(function (ticket) {
      const row = document.createElement('tr');
      row.tabIndex = 0;
      row.dataset.ticketId = ticket.id;
      row.dataset.status = ticket.status || '';
      row.dataset.priority = ticket.priority || '';
      if (ticket.id === state.selectedTicketId) row.classList.add('is-selected');
      row.addEventListener('click', function () { selectTicket(ticket.id); });
      row.addEventListener('keydown', function (event) {
        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault();
          selectTicket(ticket.id);
        }
      });

      const identity = document.createElement('td');
      identity.appendChild(element('strong', '', ticket.id));
      identity.appendChild(element('div', 'ticket-subject', ticket.subject || '(no subject)'));
      row.appendChild(identity);

      const status = document.createElement('td');
      status.appendChild(chip(ticket.status, toneForStatus(ticket.status)));
      row.appendChild(status);

      const priority = document.createElement('td');
      priority.appendChild(chip(ticket.priority, toneForPriority(ticket.priority)));
      row.appendChild(priority);
      row.appendChild(element('td', '', ticket.customerEmail || '—'));
      row.appendChild(element('td', '', formatDate(ticket.createdAt || ticket.updatedAt)));
      body.appendChild(row);
    });
  }

  async function selectTicket(ticketId) {
    state.selectedTicketId = ticketId;
    document.querySelectorAll('[data-ticket-id]').forEach(function (row) {
      row.classList.toggle('is-selected', row.dataset.ticketId === ticketId);
    });
    const panel = byId('ticket-detail');
    panel.replaceChildren(loadingBlock('Cargando ticket…'));
    try {
      const detail = unwrap(await callServer('getUiTicketDetail', ticketId));
      state.selectedDetail = detail;
      renderDetail(detail);
      renderCustomer(detail.customer);
    } catch (error) {
      showError(error);
      renderDetail(null);
    }
  }

  function renderDetail(detail) {
    window.__ticketDetail = detail || null;
    const panel = byId('ticket-detail');
    panel.replaceChildren();
    if (!detail) {
      const empty = element('div', 'empty-state');
      empty.appendChild(icon('select_check_box'));
      empty.appendChild(element('h3', '', 'Selecciona un ticket'));
      empty.appendChild(element('p', '', 'Aquí aparecerán los detalles del ticket y la conversación.'));
      panel.appendChild(empty);
      return;
    }

    const ticket = detail.ticket;
    const scrollArea = element('div', 'detail-scroll-area');
    const header = element('header', 'detail-header');
    const titleRow = element('div', 'detail-title-row');
    const titleBlock = element('div', 'detail-title-block');
    titleBlock.appendChild(element('span', 'eyebrow', ticket.id));
    titleBlock.appendChild(element('h2', '', ticket.subject || '(sin asunto)'));
    titleRow.appendChild(titleBlock);
    const headerActions = element('div', 'detail-header-actions');
    headerActions.id = 'detail-header-actions';
    titleRow.appendChild(headerActions);
    header.appendChild(titleRow);
    const chips = element('div', 'detail-chips');
    chips.appendChild(chip(ticket.status, toneForStatus(ticket.status)));
    chips.appendChild(chip(ticket.priority, toneForPriority(ticket.priority)));
    chips.appendChild(chip(ticket.category || 'GENERAL', ''));
    header.appendChild(chips);
    scrollArea.appendChild(header);

    const grid = element('dl', 'detail-grid');
    [
      ['Customer', ticket.customerEmail || '—'],
      ['Assignee', ticket.assignedTo || 'Sin asignar'],
      ['Created', formatDate(ticket.createdAt)],
      ['Last message', formatDate(ticket.lastMessageAt)],
      ['SLA due', formatDate(ticket.slaDueAt)],
      ['Tags', ticket.tags || '—'],
      ['Estado desde', formatDate(ticket.statusChangedAt)],
      ['Prioridad desde', formatDate(ticket.priorityChangedAt)],
      ['Categoría desde', formatDate(ticket.categoryChangedAt)]
    ].forEach(function (field) {
      const wrapper = element('div', 'detail-field');
      wrapper.appendChild(element('dt', '', field[0]));
      wrapper.appendChild(element('dd', '', field[1]));
      grid.appendChild(wrapper);
    });
    scrollArea.appendChild(grid);

    const conversation = element('section', 'conversation email-chain');
    const heading = element('div', 'email-chain-heading');
    heading.appendChild(element('h3', '', 'Hilo de correo'));
    heading.appendChild(element('span', '', (detail.messages || []).length + ' mensajes'));
    conversation.appendChild(heading);

    if (!detail.messages.length) {
      const empty = element('div', 'empty-state conversation-empty');
      empty.appendChild(icon('forum'));
      empty.appendChild(element('h3', '', 'Todavía no hay mensajes'));
      empty.appendChild(element('p', '', 'Aquí aparecerán los emails sincronizados de este ticket.'));
      conversation.appendChild(empty);
    } else {
      detail.messages.forEach(function (message, index) {
        conversation.appendChild(renderEmailMessage(message, index));
      });
    }
    scrollArea.appendChild(conversation);

    const errorsPlaceholder = element('div', '');
    errorsPlaceholder.id = 'detected-errors-section';
    scrollArea.appendChild(errorsPlaceholder);

    const notesSection = element('section', 'ticket-notes-section');
    notesSection.appendChild(element('h3', '', 'Notas'));
    const notesTextarea = document.createElement('textarea');
    notesTextarea.id = 'ticket-notes';
    notesTextarea.placeholder = 'Anota aquí información interna sobre este ticket (no se envía al cliente)...';
    notesTextarea.value = ticket.notes || '';
    notesTextarea.defaultValue = notesTextarea.value;
    notesSection.appendChild(notesTextarea);
    scrollArea.appendChild(notesSection);
    panel.appendChild(scrollArea);
  }

  function renderEmailMessage(message, index) {
    const item = element('article', 'message email-message' + (message.direction === 'OUTBOUND' ? ' is-outbound' : ''));
    const top = element('div', 'email-message-top');
    const identity = element('div', 'email-message-identity');
    identity.appendChild(element('strong', '', message.direction === 'OUTBOUND' ? 'Soporte' : (message.from || 'Remitente desconocido')));
    identity.appendChild(element('span', '', 'Mensaje ' + (index + 1)));
    top.appendChild(identity);
    top.appendChild(element('time', '', formatDate(message.sentAt)));
    item.appendChild(top);

    const subject = element('div', 'email-subject');
    subject.appendChild(element('span', '', 'Asunto'));
    subject.appendChild(element('strong', '', message.subject || '(sin asunto)'));
    item.appendChild(subject);

    const meta = element('dl', 'email-meta');
    [['From', message.from || '—'], ['To', message.to || '—'], ['Cc', message.cc || '—']].forEach(function (field) {
      const wrapper = element('div');
      wrapper.appendChild(element('dt', '', field[0]));
      wrapper.appendChild(element('dd', '', field[1]));
      meta.appendChild(wrapper);
    });
    item.appendChild(meta);

    const body = element('div', 'email-body');
    body.textContent = message.body || '(mensaje vacío)';
    item.appendChild(body);

    if (message.attachmentCount > 0) {
      const attachment = element('span', 'attachment email-attachment');
      attachment.appendChild(icon('attach_file'));
      attachment.appendChild(document.createTextNode(message.attachmentCount + (message.attachmentCount === 1 ? ' adjunto' : ' adjuntos')));
      item.appendChild(attachment);
    }
    return item;
  }

  function renderCustomer(customer) {
    const view = byId('customer-view');
    view.replaceChildren();
    if (!customer || (!customer.email && !customer.id)) {
      const empty = element('div', 'empty-state');
      empty.appendChild(icon('person_search'));
      empty.appendChild(element('h3', '', 'Ficha de cliente no disponible'));
      empty.appendChild(element('p', '', 'Este ticket todavía no está vinculado a ningún cliente.'));
      view.appendChild(empty);
      return;
    }
    const profile = element('div', 'customer-profile');
    const initial = (customer.name || customer.email || '?').trim().charAt(0).toUpperCase();
    profile.appendChild(element('div', 'avatar', initial));
    const heading = element('div');
    heading.appendChild(element('p', 'eyebrow', customer.id || 'Cliente'));
    heading.appendChild(element('h2', '', customer.name || customer.email));
    heading.appendChild(element('p', '', customer.company || 'Cliente particular'));
    profile.appendChild(heading);
    view.appendChild(profile);

    const fields = element('dl', 'customer-fields');
    [['Email', customer.email || '—'], ['Phone', customer.phone || '—'], ['Locale', customer.locale || '—'], ['Company', customer.company || '—'], ['Created', formatDate(customer.createdAt)], ['Updated', formatDate(customer.updatedAt)], ['Notes', customer.notes || '—']].forEach(function (field) {
      const wrapper = element('div', 'detail-field');
      wrapper.appendChild(element('dt', '', field[0]));
      wrapper.appendChild(element('dd', '', field[1]));
      fields.appendChild(wrapper);
    });
    view.appendChild(fields);
  }

  function populateFilters(filters) {
    populateSelect(byId('filter-status'), filters.statuses);
    populateSelect(byId('filter-priority'), filters.priorities);
    populateSelect(byId('filter-category'), filters.categories);
  }

  function updateFilterCounts(metrics) {
    if (!metrics) return;
    updateSelectCounts(byId('filter-status'), metrics.byStatus || {}, metrics.total || 0);
    updateSelectCounts(byId('filter-priority'), metrics.byPriority || {}, metrics.total || 0);
    updateSelectCounts(byId('filter-category'), metrics.byCategory || {}, metrics.total || 0);
  }

  function updateSelectCounts(select, counts, total) {
    if (!select) return;
    Array.prototype.forEach.call(select.options, function (option) {
      if (!option.value) {
        option.textContent = 'Todo (' + total + ')';
        return;
      }
      const baseLabel = ENUM_LABELS[String(option.value).toUpperCase()] || titleCase(option.value);
      const count = counts[option.value] || 0;
      option.textContent = baseLabel + ' (' + count + ')';
    });
  }

  function populateSelect(select, values) {
    select.classList.add('color-coded');
    select.dataset.value = select.value || '';
    values.forEach(function (value) {
      const option = document.createElement('option');
      option.value = value;
      option.textContent = ENUM_LABELS[String(value).toUpperCase()] || titleCase(value);
      select.appendChild(option);
    });
    select.addEventListener('change', function () {
      select.dataset.value = select.value;
    });
  }

  const ENUM_LABELS = {
    NEW: 'Nuevo', OPEN: 'Abierto', PENDING_CUSTOMER: 'Esperando cliente', RESOLVED: 'Resuelto', CLOSED: 'Cerrado', VOID: 'Nulo',
    LOW: 'Baja', NORMAL: 'Normal', HIGH: 'Alta', CRITICAL: 'Crítica',
    GENERAL: 'General', TECHNICAL: 'Técnico', WARRANTY: 'Garantía', SHIPPING: 'Envío', BILLING: 'Facturación', PRODUCT: 'Producto', OTHER: 'Otro'
  };

  function chip(value, tone) {
    const raw = String(value || 'UNKNOWN').toUpperCase();
    const node = element('span', 'chip', ENUM_LABELS[raw] || titleCase(raw));
    node.dataset.value = raw;
    if (tone) node.dataset.tone = tone;
    return node;
  }

  function toneForStatus(status) {
    if (status === 'RESOLVED' || status === 'CLOSED') return 'success';
    if (status === 'PENDING_CUSTOMER') return 'warning';
    return '';
  }

  function toneForPriority(priority) {
    if (priority === 'CRITICAL') return 'error';
    if (priority === 'HIGH') return 'warning';
    return '';
  }

  function titleCase(value) {
    return String(value || '').toLowerCase().replace(/_/g, ' ').replace(/\b\w/g, function (letter) {
      return letter.toUpperCase();
    });
  }

  function formatDate(value) {
    if (!value) return '—';
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return '—';
    return new Intl.DateTimeFormat(undefined, {dateStyle: 'medium', timeStyle: 'short'}).format(date);
  }

  function navigate(view) {
    state.view = view;
    document.querySelectorAll('.view').forEach(function (section) {
      section.classList.toggle('is-active', section.id === 'view-' + view);
    });
    document.querySelectorAll('.nav-item').forEach(function (button) {
      button.classList.toggle('is-active', button.dataset.view === view);
    });
  }

  function updateCriteria() {
    state.criteria.status = byId('filter-status').value || undefined;
    state.criteria.priority = byId('filter-priority').value || undefined;
    state.criteria.category = byId('filter-category').value || undefined;
    state.criteria.slaBreached = byId('filter-breached').checked || undefined;
    loadState();
  }

  function setLoading(loading) {
    byId('loading').hidden = !loading;
  }

  function loadingBlock(label) {
    const block = element('div', 'loading');
    block.appendChild(element('span', 'spinner'));
    block.appendChild(element('span', '', label));
    return block;
  }

  function showError(error) {
    const snackbar = byId('snackbar');
    snackbar.textContent = error && error.message ? error.message : String(error);
    snackbar.hidden = false;
    window.setTimeout(function () { snackbar.hidden = true; }, 6000);
  }

  function setTheme(theme) {
    if (theme === 'system') document.documentElement.removeAttribute('data-theme');
    else document.documentElement.dataset.theme = theme;
    localStorage.setItem('pocketpiano-theme', theme);
    const dark = theme === 'dark' || (theme === 'system' && window.matchMedia('(prefers-color-scheme: dark)').matches);
    byId('theme-toggle').querySelector('.material-symbols-rounded').textContent = dark ? 'light_mode' : 'dark_mode';
  }

  let searchTimer;
  byId('global-search').addEventListener('input', function (event) {
    window.clearTimeout(searchTimer);
    searchTimer = window.setTimeout(function () {
      state.criteria.query = event.target.value.trim() || undefined;
      navigate('tickets');
      loadState();
    }, 300);
  });
  ['filter-status', 'filter-priority', 'filter-category', 'filter-breached'].forEach(function (id) {
    byId(id).addEventListener('change', updateCriteria);
  });
  document.querySelectorAll('[data-view]').forEach(function (button) {
    button.addEventListener('click', function () { navigate(button.dataset.view); });
  });
  document.querySelectorAll('[data-view-link]').forEach(function (button) {
    button.addEventListener('click', function () { navigate(button.dataset.viewLink); });
  });
  document.querySelectorAll('[data-action="refresh"]').forEach(function (button) {
    button.addEventListener('click', loadState);
  });
  byId('theme-toggle').addEventListener('click', function () {
    const current = document.documentElement.dataset.theme || (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
    setTheme(current === 'dark' ? 'light' : 'dark');
  });

  setTheme(localStorage.getItem('pocketpiano-theme') || 'system');
  loadState();
})();
</script>
'@
[System.IO.File]::WriteAllText((Join-Path $root "html\Scripts.html"), $v1, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo html\TicketActions.html..." -ForegroundColor Cyan
$v2 = @'
<script>
(function () {
  'use strict';

  const OPTIONS = {
    status: ['NEW', 'OPEN', 'PENDING_CUSTOMER', 'RESOLVED', 'CLOSED', 'VOID'],
    priority: ['LOW', 'NORMAL', 'HIGH', 'CRITICAL'],
    category: ['GENERAL', 'TECHNICAL', 'WARRANTY', 'SHIPPING', 'BILLING', 'PRODUCT', 'OTHER']
  };

  function selectedTicketId() {
    const selected = document.querySelector('[data-ticket-id].is-selected');
    if (selected && selected.dataset.ticketId) return selected.dataset.ticketId;
    const eyebrow = document.querySelector('#ticket-detail .detail-header .eyebrow');
    return eyebrow ? eyebrow.textContent.trim() : '';
  }

  function currentDetail() {
    return window.__ticketDetail || {};
  }

  function selectedValueFromChip(index) {
    const chips = document.querySelectorAll('#ticket-detail .detail-chips .chip');
    return chips[index] ? (chips[index].dataset.value || chips[index].textContent.trim().toUpperCase().replace(/ /g, '_')) : '';
  }

  function detailFieldValue(label) {
    const fields = document.querySelectorAll('#ticket-detail .detail-field');
    for (let index = 0; index < fields.length; index += 1) {
      const title = fields[index].querySelector('dt');
      const value = fields[index].querySelector('dd');
      if (title && value && title.textContent.trim().toLowerCase() === label.toLowerCase()) {
        return value.textContent.trim();
      }
    }
    return '';
  }

  const ENUM_LABELS = {
    NEW: 'Nuevo', OPEN: 'Abierto', PENDING_CUSTOMER: 'Esperando cliente', RESOLVED: 'Resuelto', CLOSED: 'Cerrado', VOID: 'Nulo',
    LOW: 'Baja', NORMAL: 'Normal', HIGH: 'Alta', CRITICAL: 'Crítica',
    GENERAL: 'General', TECHNICAL: 'Técnico', WARRANTY: 'Garantía', SHIPPING: 'Envío', BILLING: 'Facturación', PRODUCT: 'Producto', OTHER: 'Otro'
  };

  function createSelect(fieldId, name, options, currentValue) {
    const label = document.createElement('label');
    label.className = 'ticket-action-field';
    const caption = document.createElement('span');
    caption.textContent = name;
    const select = document.createElement('select');
    select.id = fieldId;
    select.className = 'color-coded';
    select.dataset.initialValue = currentValue || '';
    select.dataset.value = currentValue || '';
    options.forEach(function (value) {
      const option = document.createElement('option');
      option.value = value;
      option.textContent = ENUM_LABELS[value] || value.toLowerCase().replace(/_/g, ' ').replace(/\b\w/g, function (letter) {
        return letter.toUpperCase();
      });
      if (value === currentValue) option.selected = true;
      select.appendChild(option);
    });
    select.addEventListener('change', function () {
      select.dataset.value = select.value;
    });
    label.appendChild(caption);
    label.appendChild(select);
    return label;
  }

  function createTextField(fieldId, name, value, placeholder, wide) {
    const label = document.createElement('label');
    label.className = wide === false ? 'ticket-action-field' : 'ticket-action-field ticket-action-field-wide';
    const caption = document.createElement('span');
    caption.textContent = name;
    const input = document.createElement('input');
    input.type = 'text';
    input.id = fieldId;
    input.value = value === '—' ? '' : (value || '');
    input.defaultValue = input.value;
    input.placeholder = placeholder || '';
    label.appendChild(caption);
    label.appendChild(input);
    return label;
  }

  function injectStyles() {
    if (document.getElementById('ticket-action-styles')) return;
    const style = document.createElement('style');
    style.id = 'ticket-action-styles';
    style.textContent = [
      '.ticket-actions { display: grid; grid-template-columns: repeat(3, minmax(170px, 1fr)); gap: 12px; margin-top: 16px; padding: 14px; border-radius: 16px; background: var(--surface-container); }',
      '.ticket-action-field { display: grid; gap: 7px; min-width: 0; color: var(--on-surface-variant); font-size: 12px; font-weight: 800; text-transform: uppercase; }',
      '.ticket-action-field select, .ticket-action-field input { width: 100%; min-height: 46px; border: 1px solid var(--outline); border-radius: 12px; color: var(--on-surface); background: var(--surface-bright); font: inherit; }',
      '.ticket-action-field select { padding: 0 12px; }',
      '.ticket-action-field input { padding: 0 14px; }',
      '.ticket-action-field-wide { grid-column: span 3; }',
      '@media (max-width: 900px) { .ticket-actions { grid-template-columns: 1fr; } .ticket-action-field-wide { grid-column: span 1; } }'
    ].join('\n');
    document.head.appendChild(style);
  }

  function ensureTicketControls() {
    injectStyles();
    const header = document.querySelector('#ticket-detail .detail-header');
    if (!header || header.querySelector('.ticket-actions')) return;
    if (!selectedTicketId()) return;

    const actions = document.createElement('div');
    actions.className = 'ticket-actions';
    actions.appendChild(createSelect('ta-status', 'Estado', OPTIONS.status, selectedValueFromChip(0)));
    actions.appendChild(createSelect('ta-priority', 'Prioridad', OPTIONS.priority, selectedValueFromChip(1)));
    actions.appendChild(createSelect('ta-category', 'Categoría', OPTIONS.category, selectedValueFromChip(2)));
    actions.appendChild(createTextField('ta-order-number', 'Número de pedido', (currentDetail().ticket || {}).orderNumber, '#00000', false));
    actions.appendChild(createTextField('ta-serial-number', 'Número de serie', (currentDetail().ticket || {}).serialNumber, 'PP-26-027-00154', false));
    const assigneeValue = detailFieldValue('Assignee');
    actions.appendChild(createTextField('ta-assigned-to', 'Asignado a', assigneeValue === 'Sin asignar' ? '' : assigneeValue, 'email o nombre'));
    actions.appendChild(createTextField('ta-tags', 'Etiquetas', detailFieldValue('Tags'), 'etiqueta1, etiqueta2, etiqueta3'));

    header.appendChild(actions);
  }

  const observer = new MutationObserver(function () {
    ensureTicketControls();
  });

  function start() {
    const panel = document.getElementById('ticket-detail');
    if (!panel) return;
    observer.observe(panel, {childList: true, subtree: true});
    ensureTicketControls();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }
})();
</script>
'@
[System.IO.File]::WriteAllText((Join-Path $root "html\TicketActions.html"), $v2, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo html\NewTicketScripts.html..." -ForegroundColor Cyan
$v3 = @'
<script>
(function () {
  'use strict';

  function callServer(functionName) {
    const args = Array.prototype.slice.call(arguments, 1);
    return new Promise(function (resolve, reject) {
      const runner = google.script.run.withSuccessHandler(resolve).withFailureHandler(reject);
      runner[functionName].apply(runner, args);
    });
  }

  function unwrap(response) {
    if (!response || response.ok !== true) {
      const error = response && response.error ? response.error : {};
      throw new Error(error.message || 'El servidor devolvió una respuesta no válida.');
    }
    return response.data;
  }

  function showSnack(message) {
    const snackbar = document.getElementById('snackbar');
    if (!snackbar) return;
    snackbar.textContent = message;
    snackbar.hidden = false;
    window.setTimeout(function () { snackbar.hidden = true; }, 6000);
  }

  function injectStyles() {
    if (document.getElementById('new-ticket-styles')) return;
    const style = document.createElement('style');
    style.id = 'new-ticket-styles';
    style.textContent = [
      '#new-ticket-button{width:22px;height:22px;min-width:0}',
      '#new-ticket-button .material-symbols-rounded{font-size:16px}',
      '.new-ticket-backdrop{position:fixed;inset:0;z-index:40;display:grid;place-items:center;background:rgba(0,0,0,.32);padding:20px}',
      '.new-ticket-dialog{width:min(620px,100%);max-height:90vh;overflow:auto;border-radius:var(--radius-lg);background:var(--surface-bright);box-shadow:var(--shadow);padding:22px}',
      '.new-ticket-dialog h2{margin-bottom:12px}',
      '.new-ticket-section-label{margin:16px 0 8px;font-size:11px;font-weight:800;text-transform:uppercase;letter-spacing:.04em;color:var(--on-surface-variant)}',
      '.new-ticket-section-label:first-of-type{margin-top:0}',
      '.new-ticket-row{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px}',
      '.new-ticket-row.cols-2{grid-template-columns:repeat(2,minmax(0,1fr))}',
      '.new-ticket-field{display:grid;gap:6px;margin-bottom:10px;font-size:12px;font-weight:800;text-transform:uppercase;color:var(--on-surface-variant)}',
      '.new-ticket-field.wide{grid-column:1 / -1}',
      '.new-ticket-field input,.new-ticket-field select{min-height:44px;padding:0 12px;border:1px solid var(--outline);border-radius:12px;color:var(--on-surface);background:var(--surface-bright);font:inherit;text-transform:none;font-weight:400}',
      '.new-ticket-actions{display:flex;justify-content:flex-end;gap:8px;margin-top:12px}'
    ].join('\n');
    document.head.appendChild(style);
  }

  function closeDialog(backdrop) {
    if (backdrop && backdrop.parentNode) backdrop.parentNode.removeChild(backdrop);
    document.removeEventListener('keydown', onKeydown);
  }

  function onKeydown(event) {
    if (event.key === 'Escape') {
      const backdrop = document.querySelector('.new-ticket-backdrop');
      closeDialog(backdrop);
    }
  }

  function val(id) {
    const node = document.getElementById(id);
    return node ? node.value.trim() : '';
  }

  function openDialog() {
    injectStyles();
    if (document.querySelector('.new-ticket-backdrop')) return;

    const backdrop = document.createElement('div');
    backdrop.className = 'new-ticket-backdrop';
    backdrop.setAttribute('role', 'dialog');
    backdrop.setAttribute('aria-modal', 'true');
    backdrop.addEventListener('click', function (event) {
      if (event.target === backdrop) closeDialog(backdrop);
    });

    backdrop.innerHTML =
      '<div class="new-ticket-dialog">' +
        '<h2>Nuevo ticket</h2>' +

        '<label class="new-ticket-field"><span>Asunto</span><input id="nt-subject" type="text" placeholder="¿Qué necesita el cliente?"></label>' +
        '<div class="new-ticket-row cols-2">' +
          '<label class="new-ticket-field"><span>Email del cliente</span><input id="nt-email" type="email" placeholder="cliente@ejemplo.com"></label>' +
          '<label class="new-ticket-field"><span>Prioridad</span>' +
            '<select id="nt-priority" class="color-coded" data-value="NORMAL">' +
              '<option value="NORMAL" selected>Normal</option>' +
              '<option value="LOW">Baja</option>' +
              '<option value="HIGH">Alta</option>' +
              '<option value="CRITICAL">Crítica</option>' +
            '</select>' +
          '</label>' +
        '</div>' +
        '<div class="new-ticket-row cols-2">' +
          '<label class="new-ticket-field"><span>Número de pedido</span><input id="nt-order-number" type="text" placeholder="#00000"></label>' +
          '<label class="new-ticket-field"><span>Número de serie</span><input id="nt-serial-number" type="text" placeholder="PP-26-027-00154"></label>' +
        '</div>' +

        '<div class="new-ticket-section-label">Cliente</div>' +
        '<div class="new-ticket-row">' +
          '<label class="new-ticket-field"><span>Nombre</span><input id="nt-first-name" type="text" placeholder="Jane"></label>' +
          '<label class="new-ticket-field"><span>Apellidos</span><input id="nt-last-name" type="text" placeholder="Doe"></label>' +
          '<label class="new-ticket-field"><span>Teléfono</span><input id="nt-phone" type="text" placeholder="+34 600 000 000"></label>' +
        '</div>' +
        '<label class="new-ticket-field wide"><span>Dirección</span><input id="nt-address" type="text" placeholder="Calle, ciudad, código postal"></label>' +
        '<div class="new-ticket-row">' +
          '<label class="new-ticket-field"><span>País</span><input id="nt-country" type="text" placeholder="España"></label>' +
          '<label class="new-ticket-field"><span>Código postal</span><input id="nt-postal-code" type="text" placeholder="08001"></label>' +
          '<label class="new-ticket-field"><span>Población</span><input id="nt-city" type="text" placeholder="Madrid"></label>' +
        '</div>' +

        '<div class="new-ticket-section-label">Envío</div>' +
        '<div class="new-ticket-row">' +
          '<label class="new-ticket-field"><span>Nombre del destinatario</span><input id="nt-recipient-first-name" type="text" placeholder="Quién recibe el paquete"></label>' +
          '<label class="new-ticket-field"><span>Apellidos del destinatario</span><input id="nt-recipient-last-name" type="text"></label>' +
          '<label class="new-ticket-field"><span>Teléfono del destinatario</span><input id="nt-recipient-phone" type="text" placeholder="Teléfono de contacto"></label>' +
        '</div>' +
        '<label class="new-ticket-field wide"><span>Dirección de envío</span><input id="nt-shipping-address" type="text" placeholder="Si es distinta de la dirección del cliente"></label>' +
        '<div class="new-ticket-row">' +
          '<label class="new-ticket-field"><span>País del destinatario</span><input id="nt-recipient-country" type="text" placeholder="España"></label>' +
          '<label class="new-ticket-field"><span>Código postal del destinatario</span><input id="nt-recipient-postal-code" type="text" placeholder="08001"></label>' +
          '<label class="new-ticket-field"><span>Población del destinatario</span><input id="nt-recipient-city" type="text" placeholder="Madrid"></label>' +
        '</div>' +

        '<div class="new-ticket-actions">' +
          '<button id="new-ticket-cancel" class="text-button" type="button">Cancelar</button>' +
          '<button id="new-ticket-submit" class="tonal-button" type="button">Crear ticket</button>' +
        '</div>' +
      '</div>';

    document.body.appendChild(backdrop);
    document.addEventListener('keydown', onKeydown);
    document.getElementById('nt-subject').focus();

    document.getElementById('nt-priority').addEventListener('change', function (event) {
      event.target.dataset.value = event.target.value;
    });
    document.getElementById('new-ticket-cancel').addEventListener('click', function () {
      closeDialog(backdrop);
    });

    document.getElementById('new-ticket-submit').addEventListener('click', async function () {
      const subject = val('nt-subject');
      const customerEmail = val('nt-email');
      if (!subject || !customerEmail) {
        showSnack('El asunto y el email del cliente son obligatorios.');
        return;
      }
      const submitButton = document.getElementById('new-ticket-submit');
      submitButton.disabled = true;
      submitButton.textContent = 'Creando\u2026';
      try {
        const result = await unwrap(await callServer('createUiTicket', {
          subject: subject,
          customerEmail: customerEmail,
          priority: val('nt-priority'),
          shippingAddress: val('nt-shipping-address'),
          shippingRecipientFirstName: val('nt-recipient-first-name'),
          shippingRecipientLastName: val('nt-recipient-last-name'),
          shippingRecipientPhone: val('nt-recipient-phone'),
          shippingRecipientCountry: val('nt-recipient-country'),
          shippingRecipientPostalCode: val('nt-recipient-postal-code'),
          shippingRecipientCity: val('nt-recipient-city'),
          orderNumber: val('nt-order-number'),
          serialNumber: val('nt-serial-number')
        }));
        const ticketId = result && result.id;
        const firstName = val('nt-first-name');
        const lastName = val('nt-last-name');
        const phone = val('nt-phone');
        const address = val('nt-address');
        const country = val('nt-country');
        const postalCode = val('nt-postal-code');
        const city = val('nt-city');
        if (ticketId && (firstName || lastName || phone || address || country || postalCode || city)) {
          await unwrap(await callServer('updateUiCustomerForTicket', ticketId, {
            firstName: firstName,
            lastName: lastName,
            phone: phone,
            address: address,
            country: country,
            postalCode: postalCode,
            city: city
          }));
        }
        closeDialog(backdrop);
        showSnack('Ticket ' + (ticketId || '') + ' creado.');
        const ticketsNav = document.querySelector('[data-view="tickets"]');
        if (ticketsNav) ticketsNav.click();
        document.querySelectorAll('[data-action="refresh"]').forEach(function (button) { button.click(); });
      } catch (error) {
        showSnack(error && error.message ? error.message : String(error));
        submitButton.disabled = false;
        submitButton.textContent = 'Crear ticket';
      }
    });
  }

  function start() {
    const button = document.getElementById('new-ticket-button');
    if (!button) return;
    button.addEventListener('click', openDialog);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
</script>
'@
[System.IO.File]::WriteAllText((Join-Path $root "html\NewTicketScripts.html"), $v3, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo html\CustomerDirectoryScripts.html..." -ForegroundColor Cyan
$v4 = @'
<script>
(function () {
  'use strict';

  function callServer(functionName) {
    const args = Array.prototype.slice.call(arguments, 1);
    return new Promise(function (resolve, reject) {
      const runner = google.script.run.withSuccessHandler(resolve).withFailureHandler(reject);
      runner[functionName].apply(runner, args);
    });
  }

  function unwrap(response) {
    if (!response || response.ok !== true) {
      const error = response && response.error ? response.error : {};
      throw new Error(error.message || 'El servidor devolvió una respuesta no válida.');
    }
    return response.data;
  }

  function showSnack(message) {
    const snackbar = document.getElementById('snackbar');
    if (!snackbar) return;
    snackbar.textContent = message;
    snackbar.hidden = false;
    window.setTimeout(function () { snackbar.hidden = true; }, 6000);
  }

  async function saveCustomer(customer, button) {
    const fieldIds = {
      'cd-first-name': 'firstName', 'cd-last-name': 'lastName', 'cd-email': 'email',
      'cd-phone': 'phone', 'cd-locale': 'locale', 'cd-company': 'company',
      'cd-address': 'address', 'cd-country': 'country', 'cd-postal-code': 'postalCode',
      'cd-notes': 'notes'
    };
    const changes = {};
    Object.keys(fieldIds).forEach(function (id) {
      const changed = valIfChanged(id);
      if (changed !== undefined) changes[fieldIds[id]] = changed;
    });

    if (!Object.keys(changes).length) {
      showSnack('No hay cambios que guardar.');
      return;
    }

    button.disabled = true;
    const previous = button.textContent;
    button.textContent = 'Guardando\u2026';
    try {
      const updated = await unwrap(await callServer('updateUiCustomerRecord', customer.id, changes));
      Object.assign(customer, updated);
      const listItem = document.querySelector('.cd-list-item[data-id="' + (customer.id || customer.email) + '"]');
      if (listItem) {
        listItem.querySelector('strong').textContent = displayName(customer);
        listItem.querySelector('span').textContent = customer.email || '';
      }
      const heading = button.closest('.cd-detail').querySelector('h2');
      if (heading) heading.textContent = displayName(customer);
      showSnack('Datos de ' + displayName(customer) + ' guardados. Se aplican a todos sus tickets.');
    } catch (error) {
      showSnack(error && error.message ? error.message : String(error));
    } finally {
      button.disabled = false;
      button.textContent = previous;
    }
  }

  function injectStyles() {
    if (document.getElementById('customer-directory-styles')) return;
    const style = document.createElement('style');
    style.id = 'customer-directory-styles';
    style.textContent = [
      '.cd-backdrop{position:fixed;inset:0;z-index:40;display:grid;place-items:center;background:rgba(0,0,0,.4);padding:24px}',
      '.cd-dialog{width:99vw;height:97vh;max-width:none;display:flex;flex-direction:column;border-radius:var(--radius-lg);background:var(--surface-bright);box-shadow:var(--shadow);overflow:hidden}',
      '.cd-header{display:flex;align-items:center;gap:14px;padding:18px 22px;border-bottom:1px solid var(--outline-variant)}',
      '.cd-header h2{margin:0;flex-shrink:0}',
      '.cd-search{flex:1;min-height:44px;padding:0 14px;border:1px solid var(--outline);border-radius:12px;color:var(--on-surface);background:var(--surface-container);font:inherit}',
      '.cd-close{flex-shrink:0}',
      '.cd-body{flex:1;display:grid;grid-template-columns:320px minmax(0,1fr);min-height:0}',
      '.cd-list{overflow-y:auto;border-right:1px solid var(--outline-variant);padding:10px}',
      '.cd-list-item{width:100%;text-align:left;display:block;padding:10px 12px;margin-bottom:4px;border:0;border-radius:10px;background:transparent;cursor:pointer;color:var(--on-surface)}',
      '.cd-list-item:hover{background:var(--surface-container)}',
      '.cd-list-item.is-active{background:var(--primary-container);color:var(--on-primary-container)}',
      '.cd-list-item strong{display:block;font-size:13px}',
      '.cd-list-item span{display:block;font-size:11px;color:inherit;opacity:.75}',
      '.cd-detail{overflow-y:auto;padding:22px 30px}',
      '.cd-detail-empty{color:var(--on-surface-variant);text-align:center;margin-top:60px}',
      '.cd-detail h2{margin:0 0 2px}',
      '.cd-detail .cd-company{color:var(--on-surface-variant);margin-bottom:20px}',
      '.cd-field-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px 24px}',
      '.cd-field-grid > div{grid-column:span 1}',
      '.cd-field-wide{grid-column:1 / -1 !important}',
      '.cd-field-grid span{display:block;font-size:10px;font-weight:800;text-transform:uppercase;letter-spacing:.03em;color:var(--on-surface-variant);margin-bottom:1px}',
      '.cd-field-grid strong{display:block;font-size:13px;font-weight:400;color:var(--on-surface)}',
      '.cd-section-label{grid-column:1 / -1;margin:10px 0 -4px;font-size:11px;font-weight:800;text-transform:uppercase;letter-spacing:.03em;color:var(--on-surface-variant);border-top:1px solid var(--outline-variant);padding-top:10px}',
      '.cd-section-label:first-child{margin-top:0;border-top:0;padding-top:0}',
      '.cd-tickets{margin-top:16px;border-top:1px solid var(--outline-variant);padding-top:14px}',
      '.cd-tickets h3{margin:0 0 12px;font-size:14px}',
      '.cd-ticket-row{display:flex;align-items:center;gap:10px;width:100%;text-align:left;padding:10px 12px;margin-bottom:6px;border:1px solid var(--outline-variant);border-radius:12px;background:var(--surface-bright);cursor:pointer;color:var(--on-surface);font:inherit}',
      '.cd-ticket-row:hover{background:var(--surface-container)}',
      '.cd-ticket-id{font-size:11px;font-weight:800;color:var(--primary);flex-shrink:0;width:110px}',
      '.cd-ticket-subject{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:13px}',
      '.cd-ticket-meta{flex-shrink:0;display:flex;gap:6px;align-items:center}',
      '.cd-ticket-meta .chip{font-size:10px}',
      '.cd-tickets-empty{color:var(--on-surface-variant);font-size:13px}',
      '.cd-edit-field{display:block}',
      '.cd-edit-field span{display:block;font-size:11px;font-weight:800;text-transform:uppercase;letter-spacing:.03em;color:var(--on-surface-variant);margin-bottom:4px}',
      '.cd-edit-field input{width:100%;min-height:40px;padding:0 12px;border:1px solid var(--outline);border-radius:10px;color:var(--on-surface);background:var(--surface-bright);font:inherit}',
      '.cd-save-row{display:flex;justify-content:flex-end;margin-top:18px}',
      '.cd-save-row .tonal-button{min-height:44px;padding:0 24px}'
    ].join('\n');
    document.head.appendChild(style);
  }

  function closeDialog(backdrop) {
    if (backdrop && backdrop.parentNode) backdrop.parentNode.removeChild(backdrop);
    document.removeEventListener('keydown', onKeydown);
  }

  function onKeydown(event) {
    if (event.key === 'Escape') closeDialog(document.querySelector('.cd-backdrop'));
  }

  const ENUM_LABELS = {
    NEW: 'Nuevo', OPEN: 'Abierto', PENDING_CUSTOMER: 'Esperando cliente', RESOLVED: 'Resuelto', CLOSED: 'Cerrado', VOID: 'Nulo',
    LOW: 'Baja', NORMAL: 'Normal', HIGH: 'Alta', CRITICAL: 'Crítica'
  };

  function toneForStatus(status) {
    if (status === 'RESOLVED' || status === 'CLOSED') return 'success';
    if (status === 'PENDING_CUSTOMER') return 'warning';
    return '';
  }

  function toneForPriority(priority) {
    if (priority === 'CRITICAL') return 'error';
    if (priority === 'HIGH') return 'warning';
    return '';
  }

  function chip(value, tone) {
    const span = document.createElement('span');
    span.className = 'chip';
    span.textContent = ENUM_LABELS[value] || value || '—';
    span.dataset.value = String(value || '').toUpperCase();
    if (tone) span.dataset.tone = tone;
    return span;
  }

  function openTicket(backdrop, ticketId) {
    closeDialog(backdrop);
    const searchInput = document.getElementById('global-search');
    if (searchInput) {
      searchInput.value = ticketId;
      searchInput.dispatchEvent(new Event('input', {bubbles: true}));
    }
    const ticketsNav = document.querySelector('[data-view="tickets"]');
    if (ticketsNav) ticketsNav.click();
  }

  function renderTicketList(backdrop, container, tickets) {
    container.replaceChildren();
    if (!tickets.length) {
      const empty = document.createElement('div');
      empty.className = 'cd-tickets-empty';
      empty.textContent = 'Este cliente todavía no tiene tickets.';
      container.appendChild(empty);
      return;
    }
    tickets.forEach(function (ticket) {
      const row = document.createElement('button');
      row.type = 'button';
      row.className = 'cd-ticket-row';
      const id = document.createElement('span');
      id.className = 'cd-ticket-id';
      id.textContent = ticket.id;
      const subject = document.createElement('span');
      subject.className = 'cd-ticket-subject';
      subject.textContent = ticket.subject || '(sin asunto)';
      const meta = document.createElement('span');
      meta.className = 'cd-ticket-meta';
      meta.appendChild(chip(ticket.status, toneForStatus(ticket.status)));
      meta.appendChild(chip(ticket.priority, toneForPriority(ticket.priority)));
      row.appendChild(id);
      row.appendChild(subject);
      row.appendChild(meta);
      row.addEventListener('click', function () { openTicket(backdrop, ticket.id); });
      container.appendChild(row);
    });
  }

  function loadTicketsForCustomer(backdrop, container, email) {
    container.replaceChildren();
    const loading = document.createElement('div');
    loading.className = 'cd-tickets-empty';
    loading.textContent = 'Cargando tickets…';
    container.appendChild(loading);
    callServer('getUiTicketsForCustomer', email).then(unwrap).then(function (tickets) {
      renderTicketList(backdrop, container, tickets || []);
    }).catch(function (error) {
      container.replaceChildren();
      const errorNode = document.createElement('div');
      errorNode.className = 'cd-tickets-empty';
      errorNode.textContent = error && error.message ? error.message : String(error);
      container.appendChild(errorNode);
    });
  }

  function displayName(customer) {
    const full = (customer.firstName || customer.lastName) ? (customer.firstName + ' ' + customer.lastName).trim() : '';
    return full || customer.name || customer.email || '(sin nombre)';
  }

  function field(label, value, wide) {
    const div = document.createElement('div');
    if (wide) div.className = 'cd-field-wide';
    const caption = document.createElement('span');
    caption.textContent = label;
    const strong = document.createElement('strong');
    strong.textContent = value || '—';
    div.appendChild(caption);
    div.appendChild(strong);
    return div;
  }

  function editField(fieldId, label, value, wide) {
    const label_ = document.createElement('label');
    label_.className = wide ? 'cd-field-wide cd-edit-field' : 'cd-edit-field';
    const caption = document.createElement('span');
    caption.textContent = label;
    const input = document.createElement('input');
    input.type = 'text';
    input.id = fieldId;
    input.value = value || '';
    input.defaultValue = input.value;
    label_.appendChild(caption);
    label_.appendChild(input);
    return label_;
  }

  function valIfChanged(id) {
    const node = document.getElementById(id);
    if (!node) return undefined;
    const current = node.value.trim();
    return current !== (node.defaultValue || '').trim() ? current : undefined;
  }

  function sectionLabel(text) {
    const span = document.createElement('span');
    span.className = 'cd-section-label';
    span.textContent = text;
    return span;
  }

  function renderDetail(panel, customer) {
    panel.replaceChildren();
    if (!customer) {
      const empty = document.createElement('div');
      empty.className = 'cd-detail-empty';
      empty.textContent = 'Selecciona un cliente de la lista.';
      panel.appendChild(empty);
      return null;
    }

    const heading = document.createElement('h2');
    heading.textContent = displayName(customer);
    panel.appendChild(heading);
    if (customer.company) {
      const company = document.createElement('div');
      company.className = 'cd-company';
      company.textContent = customer.company;
      panel.appendChild(company);
    }

    const grid = document.createElement('div');
    grid.className = 'cd-field-grid';
    grid.appendChild(sectionLabel('Contacto'));
    grid.appendChild(editField('cd-first-name', 'Nombre', customer.firstName));
    grid.appendChild(editField('cd-last-name', 'Apellidos', customer.lastName));
    grid.appendChild(editField('cd-email', 'Email', customer.email));
    grid.appendChild(editField('cd-phone', 'Teléfono', customer.phone));
    grid.appendChild(editField('cd-locale', 'Idioma', customer.locale));
    grid.appendChild(editField('cd-company', 'Empresa', customer.company));

    grid.appendChild(sectionLabel('Dirección'));
    grid.appendChild(editField('cd-address', 'Dirección', customer.address, true));
    grid.appendChild(editField('cd-country', 'País', customer.country));
    grid.appendChild(editField('cd-postal-code', 'Código postal', customer.postalCode));

    grid.appendChild(sectionLabel('Otros'));
    grid.appendChild(field('ID de cliente', customer.id));
    grid.appendChild(field('Creado', customer.createdAt));
    grid.appendChild(field('Actualizado', customer.updatedAt));
    grid.appendChild(editField('cd-notes', 'Notas', customer.notes, true));

    panel.appendChild(grid);

    const saveRow = document.createElement('div');
    saveRow.className = 'cd-save-row';
    const saveButton = document.createElement('button');
    saveButton.type = 'button';
    saveButton.className = 'tonal-button';
    saveButton.textContent = 'Guardar';
    saveButton.addEventListener('click', function () { saveCustomer(customer, saveButton); });
    saveRow.appendChild(saveButton);
    panel.appendChild(saveRow);

    const ticketsSection = document.createElement('div');
    ticketsSection.className = 'cd-tickets';
    const ticketsHeading = document.createElement('h3');
    ticketsHeading.textContent = 'Tickets de este cliente';
    ticketsSection.appendChild(ticketsHeading);
    const ticketsList = document.createElement('div');
    ticketsSection.appendChild(ticketsList);
    panel.appendChild(ticketsSection);

    return ticketsList;
  }

  function openDialog() {
    injectStyles();
    if (document.querySelector('.cd-backdrop')) return;

    const backdrop = document.createElement('div');
    backdrop.className = 'cd-backdrop';
    backdrop.setAttribute('role', 'dialog');
    backdrop.setAttribute('aria-modal', 'true');
    backdrop.addEventListener('click', function (event) {
      if (event.target === backdrop) closeDialog(backdrop);
    });

    backdrop.innerHTML =
      '<div class="cd-dialog">' +
        '<div class="cd-header">' +
          '<h2>Clientes</h2>' +
          '<input class="cd-search" type="search" placeholder="Buscar por nombre, email, teléfono, empresa...">' +
          '<button class="text-button cd-close" type="button">Cerrar</button>' +
        '</div>' +
        '<div class="cd-body">' +
          '<div class="cd-list"><div class="cd-detail-empty">Cargando…</div></div>' +
          '<div class="cd-detail"><div class="cd-detail-empty">Selecciona un cliente de la lista.</div></div>' +
        '</div>' +
      '</div>';

    document.body.appendChild(backdrop);
    document.addEventListener('keydown', onKeydown);
    backdrop.querySelector('.cd-close').addEventListener('click', function () { closeDialog(backdrop); });

    const searchInput = backdrop.querySelector('.cd-search');
    const list = backdrop.querySelector('.cd-list');
    const detail = backdrop.querySelector('.cd-detail');
    let allCustomers = [];
    let selectedId = '';

    function selectCustomer(customer) {
      selectedId = customer.id || customer.email;
      const ticketsList = renderDetail(detail, customer);
      if (ticketsList && customer.email) loadTicketsForCustomer(backdrop, ticketsList, customer.email);
      list.querySelectorAll('.cd-list-item').forEach(function (item) {
        item.classList.toggle('is-active', item.dataset.id === selectedId);
      });
    }

    function renderList(customers) {
      list.replaceChildren();
      if (!customers.length) {
        const empty = document.createElement('div');
        empty.className = 'cd-detail-empty';
        empty.textContent = 'No se encontraron clientes.';
        list.appendChild(empty);
        return;
      }
      customers.forEach(function (customer) {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'cd-list-item';
        button.dataset.id = customer.id || customer.email;
        if (button.dataset.id === selectedId) button.classList.add('is-active');
        const strong = document.createElement('strong');
        strong.textContent = displayName(customer);
        const span = document.createElement('span');
        span.textContent = customer.email || '';
        button.appendChild(strong);
        button.appendChild(span);
        button.addEventListener('click', function () { selectCustomer(customer); });
        list.appendChild(button);
      });
    }

    searchInput.addEventListener('input', function () {
      const query = searchInput.value.trim().toLowerCase();
      if (!query) { renderList(allCustomers); return; }
      renderList(allCustomers.filter(function (customer) {
        return [customer.name, customer.firstName, customer.lastName, customer.email, customer.phone, customer.company, customer.address, customer.country]
          .join(' ').toLowerCase().indexOf(query) !== -1;
      }));
    });

    callServer('getUiCustomerDirectory').then(unwrap).then(function (customers) {
      allCustomers = customers || [];
      renderList(allCustomers);
      if (allCustomers.length) selectCustomer(allCustomers[0]);
      searchInput.focus();
    }).catch(function (error) {
      list.innerHTML = '<div class="cd-detail-empty">' + (error && error.message ? error.message : String(error)) + '</div>';
    });
  }

  function start() {
    const button = document.getElementById('customer-directory-button');
    if (!button) return;
    button.addEventListener('click', openDialog);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
</script>
'@
[System.IO.File]::WriteAllText((Join-Path $root "html\CustomerDirectoryScripts.html"), $v4, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host ""
Write-Host "Verificando..." -ForegroundColor Cyan
Select-String -Path css\Styles.html -Pattern "color-coded"
Select-String -Path html\TicketActions.html -Pattern "color-coded"

Write-Host ""
Write-Host "Si salieron lineas arriba, ejecuta: npm test  y  npm run deploy" -ForegroundColor Cyan
