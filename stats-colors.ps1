# stats-colors.ps1
$ErrorActionPreference = "Stop"
$root = Get-Location
$enc = New-Object System.Text.UTF8Encoding($false)

Write-Host "Escribiendo html\StatisticsScripts.html..." -ForegroundColor Cyan
$v0 = @'
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

  const ENUM_LABELS = {
    NEW: 'Nuevo', OPEN: 'Abierto', PENDING_CUSTOMER: 'Esperando cliente', RESOLVED: 'Resuelto', CLOSED: 'Cerrado', VOID: 'Nulo',
    LOW: 'Baja', NORMAL: 'Normal', HIGH: 'Alta', CRITICAL: 'Crítica',
    GENERAL: 'General', TECHNICAL: 'Técnico', WARRANTY: 'Garantía', SHIPPING: 'Envío', BILLING: 'Facturación', PRODUCT: 'Producto', OTHER: 'Otro'
  };

  function injectStyles() {
    if (document.getElementById('statistics-styles')) return;
    const style = document.createElement('style');
    style.id = 'statistics-styles';
    style.textContent = [
      '.st-backdrop{position:fixed;inset:0;z-index:40;display:grid;place-items:center;background:rgba(0,0,0,.4);padding:24px}',
      '.st-dialog{width:min(1100px,96vw);max-height:90vh;display:flex;flex-direction:column;border-radius:var(--radius-lg);background:var(--surface-bright);box-shadow:var(--shadow);overflow:hidden}',
      '.st-header{display:flex;align-items:center;justify-content:space-between;padding:18px 26px;border-bottom:1px solid var(--outline-variant)}',
      '.st-header h2{margin:0}',
      '.st-body{overflow-y:auto;padding:24px 26px 30px}',
      '.st-summary{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:14px;margin-bottom:28px}',
      '.st-timing-summary{grid-template-columns:repeat(2,minmax(0,1fr))!important;margin-bottom:8px!important}',
      '.st-timing-note{margin:0 0 28px;font-size:12px;color:var(--on-surface-variant)}',
      '.st-summary-card{border:1px solid var(--outline-variant);border-radius:14px;padding:16px 18px;background:var(--surface-container)}',
      '.st-summary-card span{display:block;font-size:11px;font-weight:800;text-transform:uppercase;color:var(--on-surface-variant);margin-bottom:6px}',
      '.st-summary-card strong{font-size:26px}',
      '.st-summary-card[data-tone="error"] strong{color:var(--error)}',
      '.st-section{margin-bottom:26px}',
      '.st-section h3{margin:0 0 12px;font-size:14px}',
      '.st-section-header{display:flex;align-items:center;justify-content:space-between;margin-bottom:12px}',
      '.st-section-header h3{margin:0}',
      '.st-year-select{min-height:32px;padding:0 10px;border:1px solid var(--outline-variant);border-radius:8px;background:var(--surface-bright);color:var(--on-surface);font-size:12px;font-weight:700}',
      '.st-month-chart{display:grid;grid-template-columns:repeat(12,1fr);gap:6px;align-items:end;height:160px;padding:0 4px}',
      '.st-month-bar-wrap{display:flex;flex-direction:column;align-items:center;justify-content:flex-end;height:100%;gap:4px}',
      '.st-month-count{font-size:10px;font-weight:800;color:var(--on-surface-variant)}',
      '.st-month-bar{width:100%;max-width:26px;background:var(--primary);border-radius:4px 4px 0 0;min-height:2px}',
      '.st-month-label{font-size:10px;color:var(--on-surface-variant);margin-top:4px;text-transform:uppercase}',
      '.st-bar-row{display:grid;grid-template-columns:150px 1fr 70px;align-items:center;gap:10px;margin-bottom:8px;font-size:12px}',
      '.st-bar-track{height:14px;border-radius:7px;background:var(--surface-container);overflow:hidden}',
      '.st-bar-fill{height:100%;background:var(--primary);border-radius:7px}',
      '.st-bar-count{text-align:right;font-weight:700}',
      '.st-empty{text-align:center;padding:40px;color:var(--on-surface-variant)}'
    ].join('\n');
    document.head.appendChild(style);
  }

  function closeDialog(backdrop) {
    if (backdrop && backdrop.parentNode) backdrop.parentNode.removeChild(backdrop);
    document.removeEventListener('keydown', onKeydown);
  }

  function onKeydown(event) {
    if (event.key === 'Escape') closeDialog(document.querySelector('.st-backdrop'));
  }

  function formatDuration(hours) {
    if (!hours || hours <= 0) return '—';
    if (hours < 1) return Math.round(hours * 60) + ' min';
    if (hours < 24) return Math.round(hours * 10) / 10 + ' h';
    const days = Math.floor(hours / 24);
    const remainingHours = Math.round(hours % 24);
    return days + 'd ' + remainingHours + 'h';
  }

  function timeBreakdownSection(title, hoursMap) {
    const section = document.createElement('div');
    section.className = 'st-section';
    const heading = document.createElement('h3');
    heading.textContent = title;
    section.appendChild(heading);

    const entries = Object.keys(hoursMap)
      .map(function (key) { return [key, hoursMap[key]]; })
      .filter(function (entry) { return entry[1] > 0; })
      .sort(function (a, b) { return b[1] - a[1]; });

    if (!entries.length) {
      const empty = document.createElement('div');
      empty.className = 'st-empty';
      empty.style.padding = '4px 0';
      empty.style.textAlign = 'left';
      empty.textContent = 'Sin datos todavía.';
      section.appendChild(empty);
      return section;
    }

    const maxHours = Math.max.apply(null, entries.map(function (entry) { return entry[1]; }));
    entries.forEach(function (entry) {
      const key = entry[0];
      const hours = entry[1];
      const pct = maxHours ? Math.round((hours / maxHours) * 100) : 0;
      const row = document.createElement('div');
      row.className = 'st-bar-row';
      const label = document.createElement('span');
      label.textContent = ENUM_LABELS[key] || key;
      const track = document.createElement('div');
      track.className = 'st-bar-track';
      const fill = document.createElement('div');
      fill.className = 'st-bar-fill';
      fill.dataset.value = key;
      fill.style.width = pct + '%';
      track.appendChild(fill);
      const valueNode = document.createElement('span');
      valueNode.className = 'st-bar-count';
      valueNode.textContent = formatDuration(hours);
      row.appendChild(label);
      row.appendChild(track);
      row.appendChild(valueNode);
      section.appendChild(row);
    });

    return section;
  }

  function summaryCard(label, value, tone) {
    const card = document.createElement('div');
    card.className = 'st-summary-card';
    if (tone) card.dataset.tone = tone;
    const span = document.createElement('span');
    span.textContent = label;
    const strong = document.createElement('strong');
    strong.textContent = value;
    card.appendChild(span);
    card.appendChild(strong);
    return card;
  }

  function breakdownSection(title, counts, total) {
    const section = document.createElement('div');
    section.className = 'st-section';
    const heading = document.createElement('h3');
    heading.textContent = title;
    section.appendChild(heading);

    const entries = Object.keys(counts)
      .map(function (key) { return [key, counts[key]]; })
      .sort(function (a, b) { return b[1] - a[1]; });

    if (!entries.length) {
      const empty = document.createElement('div');
      empty.className = 'st-empty';
      empty.style.padding = '4px 0';
      empty.style.textAlign = 'left';
      empty.textContent = 'Sin datos todavía.';
      section.appendChild(empty);
      return section;
    }

    entries.forEach(function (entry) {
      const key = entry[0];
      const count = entry[1];
      const pct = total ? Math.round((count / total) * 100) : 0;
      const row = document.createElement('div');
      row.className = 'st-bar-row';
      const label = document.createElement('span');
      label.textContent = ENUM_LABELS[key] || key;
      const track = document.createElement('div');
      track.className = 'st-bar-track';
      const fill = document.createElement('div');
      fill.className = 'st-bar-fill';
      fill.dataset.value = key;
      fill.style.width = pct + '%';
      track.appendChild(fill);
      const countNode = document.createElement('span');
      countNode.className = 'st-bar-count';
      countNode.textContent = count + ' (' + pct + '%)';
      row.appendChild(label);
      row.appendChild(track);
      row.appendChild(countNode);
      section.appendChild(row);
    });

    return section;
  }

  function renderStats(body, stats) {
    body.replaceChildren();

    const summary = document.createElement('div');
    summary.className = 'st-summary';
    summary.appendChild(summaryCard('Tickets totales', stats.total));
    summary.appendChild(summaryCard('Tickets activos', stats.active));
    summary.appendChild(summaryCard('SLA incumplido', stats.breached, stats.breached ? 'error' : ''));
    summary.appendChild(summaryCard('Clientes', stats.customerCount));
    body.appendChild(summary);

    const timingSummary = document.createElement('div');
    timingSummary.className = 'st-summary st-timing-summary';
    timingSummary.appendChild(summaryCard('Tiempo medio de resolución', formatDuration(stats.avgResolutionHours)));
    timingSummary.appendChild(summaryCard('Tiempo medio abierto (activos)', formatDuration(stats.avgOpenHours)));
    body.appendChild(timingSummary);
    if (stats.resolvedSampleSize || stats.activeSampleSize) {
      const note = document.createElement('p');
      note.className = 'st-timing-note';
      note.textContent = 'Basado en ' + (stats.resolvedSampleSize || 0) + ' tickets resueltos y ' + (stats.activeSampleSize || 0) + ' activos.';
      body.appendChild(note);
    }

    body.appendChild(breakdownSection('Por estado', stats.byStatus, stats.total));
    body.appendChild(timeBreakdownSection('Tiempo medio en cada estado (tickets actuales)', stats.avgTimeInStatusHours || {}));
    body.appendChild(breakdownSection('Por prioridad', stats.byPriority, stats.total));
    body.appendChild(breakdownSection('Por categoría', stats.byCategory, stats.total));
    body.appendChild(breakdownSection('Errores más frecuentes', stats.byError || {}, stats.total));
    body.appendChild(breakdownSection('Soluciones más aplicadas', stats.bySolution || {}, stats.total));
  }

  function renderMonthChart(container, months) {
    const labels = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
    const max = Math.max.apply(null, months.concat([1]));
    const chart = document.createElement('div');
    chart.className = 'st-month-chart';
    months.forEach(function (count, index) {
      const wrap = document.createElement('div');
      wrap.className = 'st-month-bar-wrap';
      const countNode = document.createElement('span');
      countNode.className = 'st-month-count';
      countNode.textContent = count || '';
      const bar = document.createElement('div');
      bar.className = 'st-month-bar';
      bar.style.height = (count ? Math.max(4, Math.round((count / max) * 130)) : 2) + 'px';
      const label = document.createElement('span');
      label.className = 'st-month-label';
      label.textContent = labels[index];
      wrap.appendChild(countNode);
      wrap.appendChild(bar);
      wrap.appendChild(label);
      chart.appendChild(wrap);
    });
    container.replaceChildren(chart);
  }

  function renderMonthlySection(container) {
    container.className = 'st-section';
    const header = document.createElement('div');
    header.className = 'st-section-header';
    const heading = document.createElement('h3');
    heading.textContent = 'Tickets abiertos por mes';
    header.appendChild(heading);
    const select = document.createElement('select');
    select.className = 'st-year-select';
    header.appendChild(select);
    container.appendChild(header);
    const chartWrap = document.createElement('div');
    chartWrap.className = 'st-empty';
    chartWrap.style.padding = '20px 0';
    chartWrap.style.textAlign = 'left';
    chartWrap.textContent = 'Cargando…';
    container.appendChild(chartWrap);

    function loadYear(year) {
      callServer('getUiTicketsCreatedByMonth', year).then(unwrap).then(function (data) {
        if (!select.dataset.populated) {
          select.dataset.populated = 'true';
          data.availableYears.forEach(function (y) {
            const option = document.createElement('option');
            option.value = y;
            option.textContent = y;
            if (y === data.year) option.selected = true;
            select.appendChild(option);
          });
          select.addEventListener('change', function () { loadYear(Number(select.value)); });
        }
        renderMonthChart(chartWrap, data.months);
      }).catch(function (error) {
        chartWrap.textContent = error && error.message ? error.message : String(error);
      });
    }

    loadYear(new Date().getFullYear());
  }

  function openDialog() {
    injectStyles();
    if (document.querySelector('.st-backdrop')) return;

    const backdrop = document.createElement('div');
    backdrop.className = 'st-backdrop';
    backdrop.setAttribute('role', 'dialog');
    backdrop.setAttribute('aria-modal', 'true');
    backdrop.addEventListener('click', function (event) {
      if (event.target === backdrop) closeDialog(backdrop);
    });

    backdrop.innerHTML =
      '<div class="st-dialog">' +
        '<div class="st-header"><h2>Estadísticas</h2><button class="text-button" type="button" data-close>Cerrar</button></div>' +
        '<div class="st-body"><div class="st-empty">Cargando…</div></div>' +
      '</div>';

    document.body.appendChild(backdrop);
    document.addEventListener('keydown', onKeydown);
    backdrop.querySelector('[data-close]').addEventListener('click', function () { closeDialog(backdrop); });

    const body = backdrop.querySelector('.st-body');
    callServer('getUiTicketStatistics').then(unwrap).then(function (stats) {
      renderStats(body, stats);
      const monthlySection = document.createElement('div');
      body.appendChild(monthlySection);
      renderMonthlySection(monthlySection);
    }).catch(function (error) {
      body.innerHTML = '<div class="st-empty">' + (error && error.message ? error.message : String(error)) + '</div>';
    });
  }

  function start() {
    const button = document.getElementById('statistics-button');
    if (!button) return;
    button.addEventListener('click', openDialog);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
</script>
'@
[System.IO.File]::WriteAllText((Join-Path $root "html\StatisticsScripts.html"), $v0, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo html\ColorSchemeScripts.html..." -ForegroundColor Cyan
$v1 = @'
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

  let colorMap = null;

  function typeForValue(value) {
    if (['NEW', 'OPEN', 'PENDING_CUSTOMER', 'RESOLVED', 'CLOSED', 'VOID'].indexOf(value) !== -1) return 'STATUS';
    if (['LOW', 'NORMAL', 'HIGH', 'CRITICAL'].indexOf(value) !== -1) return 'PRIORITY';
    if (['GENERAL', 'TECHNICAL', 'WARRANTY', 'SHIPPING', 'BILLING', 'PRODUCT', 'OTHER'].indexOf(value) !== -1) return 'CATEGORY';
    return '';
  }

  // Picks black or white text for readable contrast against a given hex background.
  function readableTextColor(hex) {
    const clean = String(hex || '').replace('#', '');
    if (clean.length !== 6) return '';
    const r = parseInt(clean.substr(0, 2), 16);
    const g = parseInt(clean.substr(2, 2), 16);
    const b = parseInt(clean.substr(4, 2), 16);
    const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
    return luminance > 0.6 ? '#1a1a1a' : '#ffffff';
  }

  function colorFor(value) {
    if (!colorMap) return null;
    const type = typeForValue(value);
    if (!type || !colorMap[type]) return null;
    return colorMap[type][value] || null;
  }

  function applyColors() {
    if (!colorMap) return;

    document.querySelectorAll('.chip[data-value]').forEach(function (chip) {
      const bg = colorFor(chip.dataset.value);
      if (!bg) return;
      chip.style.backgroundColor = bg;
      chip.style.color = readableTextColor(bg);
    });

    document.querySelectorAll('select.color-coded[data-value]').forEach(function (select) {
      const bg = colorFor(select.dataset.value);
      if (!bg) {
        select.style.backgroundColor = '';
        select.style.color = '';
        select.style.borderColor = '';
        return;
      }
      select.style.backgroundColor = bg;
      select.style.color = readableTextColor(bg);
      select.style.borderColor = bg;
    });

    document.querySelectorAll('.st-bar-fill[data-value]').forEach(function (bar) {
      const bg = colorFor(bar.dataset.value);
      if (bg) bar.style.backgroundColor = bg;
    });
  }

  function start() {
    callServer('getUiColorMap').then(unwrap).then(function (map) {
      colorMap = map;
      applyColors();
    }).catch(function () {
      // If this fails, the CSS defaults already in place still apply.
    });

    let pending = false;
    const observer = new MutationObserver(function () {
      if (pending) return;
      pending = true;
      window.setTimeout(function () {
        pending = false;
        applyColors();
      }, 150);
    });
    observer.observe(document.body, {childList: true, subtree: true});

    document.addEventListener('change', function (event) {
      if (event.target && event.target.matches && event.target.matches('select.color-coded')) {
        applyColors();
      }
    });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
</script>
'@
[System.IO.File]::WriteAllText((Join-Path $root "html\ColorSchemeScripts.html"), $v1, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host ""
Write-Host "Verificando..." -ForegroundColor Cyan
Select-String -Path html\StatisticsScripts.html -Pattern "fill.dataset.value"
Select-String -Path html\ColorSchemeScripts.html -Pattern "st-bar-fill"

Write-Host ""
Write-Host "Si salieron lineas arriba, ejecuta: npm test  y  npm run deploy" -ForegroundColor Cyan
