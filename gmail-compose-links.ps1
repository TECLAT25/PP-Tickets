# gmail-compose-links.ps1
$ErrorActionPreference = "Stop"
$root = Get-Location
$enc = New-Object System.Text.UTF8Encoding($false)

Write-Host "Escribiendo html\ReplyBoxScripts.html..." -ForegroundColor Cyan
$v0 = @'
<script>
(function () {
  'use strict';

  function css() {
    if (document.getElementById('reply-box-css')) return;
    var style = document.createElement('style');
    style.id = 'reply-box-css';
    style.textContent = '.reply-box{margin:0;padding:10px 12px;border-top:1px solid var(--outline-variant);background:var(--surface-container);max-height:48px;overflow:hidden;transition:max-height .18s ease}' +
      '.reply-box.is-open{max-height:260px;overflow:auto}' +
      '.reply-box-header{display:flex;align-items:center;justify-content:space-between;gap:12px}' +
      '.reply-box h3{margin:0;font-size:15px}' +
      '.reply-header-actions{display:flex;align-items:center;gap:6px}' +
      '.reply-toggle,.mail-customer-button{border:1px solid var(--outline-variant);border-radius:16px;background:var(--surface-bright);padding:5px 10px;cursor:pointer;font-size:12px;color:var(--on-surface);text-decoration:none}' +
      '.mail-customer-button{font-weight:800}' +
      '.reply-toolbar{display:flex;flex-wrap:wrap;gap:8px;margin:10px 0}' +
      '.reply-chip{border:1px solid var(--outline-variant);border-radius:16px;background:var(--surface-bright);padding:6px 10px;cursor:pointer;font-size:12px}' +
      '.reply-box textarea{width:100%;min-height:96px;resize:vertical;border:1px solid var(--outline-variant);border-radius:12px;padding:12px;background:var(--surface-bright);color:var(--on-surface);font:inherit}' +
      '.reply-actions{display:flex;justify-content:flex-end;gap:8px;margin-top:10px}';
    document.head.appendChild(style);
  }

  function ticketId() {
    var eyebrow = document.querySelector('#ticket-detail .detail-header .eyebrow');
    return eyebrow ? eyebrow.textContent.trim() : '';
  }

  function customerEmail() {
    var fields = document.querySelectorAll('#ticket-detail .detail-field');
    for (var index = 0; index < fields.length; index += 1) {
      var title = fields[index].querySelector('dt');
      var value = fields[index].querySelector('dd');
      if (title && value && title.textContent.trim().toLowerCase() === 'customer') return value.textContent.trim();
    }
    var row = document.querySelector('[data-ticket-id].is-selected td:nth-child(4)');
    return row ? row.textContent.trim() : '';
  }

  function insert(textarea, value) {
    var start = textarea.selectionStart || textarea.value.length;
    var end = textarea.selectionEnd || textarea.value.length;
    textarea.value = textarea.value.slice(0, start) + value + textarea.value.slice(end);
    textarea.focus();
    textarea.selectionStart = textarea.selectionEnd = start + value.length;
  }

  function callServer(name) {
    var args = Array.prototype.slice.call(arguments, 1);
    return new Promise(function (resolve, reject) {
      var runner = google.script.run.withSuccessHandler(resolve).withFailureHandler(reject);
      runner[name].apply(runner, args);
    });
  }

  function toast(message) {
    var snackbar = document.getElementById('snackbar');
    if (!snackbar) return;
    snackbar.textContent = message;
    snackbar.hidden = false;
    window.setTimeout(function () { snackbar.hidden = true; }, 6000);
  }

  function ensureBox() {
    css();
    var detail = document.getElementById('ticket-detail');
    if (!detail || detail.querySelector('.reply-box') || !ticketId()) return;

    var email = customerEmail();
    var mailLink = email && email !== '—'
      ? 'https://mail.google.com/mail/?view=cm&fs=1&to=' + encodeURIComponent(email)
      : '#';
    var box = document.createElement('section');
    box.className = 'reply-box';
    box.innerHTML = '<div class="reply-box-header"><h3>Respuesta rápida</h3><div class="reply-header-actions"><a class="mail-customer-button" href="' + mailLink + '" target="_blank" rel="noopener">Enviar email al cliente</a><button class="reply-toggle" type="button">Abrir editor de respuesta</button></div></div>' +
      '<div class="reply-toolbar"></div>' +
      '<textarea placeholder="Escribe aquí el borrador de la respuesta..."></textarea>' +
      '<div class="reply-actions"><button class="text-button" type="button" data-reply-clear>Borrar</button><button class="tonal-button" type="button" data-reply-draft>Crear borrador de Gmail</button></div>';

    var toolbar = box.querySelector('.reply-toolbar');
    var textarea = box.querySelector('textarea');
    var toggle = box.querySelector('.reply-toggle');
    toggle.addEventListener('click', function () {
      box.classList.toggle('is-open');
      toggle.textContent = box.classList.contains('is-open') ? 'Ocultar editor de respuesta' : 'Abrir editor de respuesta';
    });

    [
      ['Saludo', 'Hola,\n\nGracias por contactar con PocketPiano.\n\n'],
      ['Pedir número de serie', 'Para poder ayudarte mejor, indícanos el número de serie del PocketPiano y adjunta una foto o vídeo donde se vea el problema.\n\n'],
      ['Garantía', 'Vamos a revisar si la incidencia queda cubierta por garantía.\n\n'],
      ['Cierre', 'Un saludo,\nPocketPiano Support']
    ].forEach(function (item) {
      var button = document.createElement('button');
      button.type = 'button';
      button.className = 'reply-chip';
      button.textContent = item[0];
      button.addEventListener('click', function () {
        if (!box.classList.contains('is-open')) toggle.click();
        insert(textarea, item[1]);
      });
      toolbar.appendChild(button);
    });

    box.querySelector('[data-reply-clear]').addEventListener('click', function () { textarea.value = ''; });
    box.querySelector('[data-reply-draft]').addEventListener('click', function () {
      var id = ticketId();
      if (!id) return;
      callServer('createUiDraftForTicket', id, 'DEFAULT_SUPPORT_REPLY', textarea.value).then(function (response) {
        if (response && response.ok) toast('Borrador de Gmail creado para ' + id + '.');
        else toast((response && response.error && response.error.message) || 'No se pudo crear el borrador.');
      }).catch(function (error) { toast(error.message || String(error)); });
    });

    detail.appendChild(box);
  }

  function start() {
    new MutationObserver(ensureBox).observe(document.body, {childList: true, subtree: true});
    ensureBox();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
</script>
'@
[System.IO.File]::WriteAllText((Join-Path $root "html\ReplyBoxScripts.html"), $v0, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo html\UsabilityScripts.html..." -ForegroundColor Cyan
$v1 = @'
<script>
(function () {
  'use strict';

  function injectStyles() {
    if (document.getElementById('pp-usability-styles')) return;
    const style = document.createElement('style');
    style.id = 'pp-usability-styles';
    style.textContent = [
      '.quick-summary { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 10px; margin-top: 14px; }',
      '.quick-summary-card { padding: 10px 12px; border: 1px solid var(--outline-variant); border-radius: var(--radius-sm); background: var(--surface-container); }',
      '.quick-summary-card span { display: block; color: var(--on-surface-variant); font-size: 10px; font-weight: 800; letter-spacing: .08em; text-transform: uppercase; }',
      '.quick-summary-card strong { display: block; margin-top: 4px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: 13px; }',
      '.quick-actions { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 12px; }',
      '.mini-button { display: inline-flex; align-items: center; gap: 6px; min-height: 32px; padding: 0 10px; border: 1px solid var(--outline-variant); border-radius: 16px; background: var(--surface-bright); color: var(--on-surface); cursor: pointer; font-size: 12px; }',
      '.mini-button:hover { background: var(--surface-container-high); }',
      '.mini-button .material-symbols-rounded { font-size: 18px; }',
      '.sla-alert { margin-top: 12px; padding: 10px 12px; border-radius: var(--radius-sm); font-size: 13px; }',
      '.sla-alert[data-tone="error"] { color: var(--error); background: var(--error-container); }',
      '.sla-alert[data-tone="warning"] { color: var(--warning); background: var(--warning-container); }',
      '.sla-alert[data-tone="success"] { color: var(--success); background: var(--success-container); }',
      '.message.is-collapsed p { display: -webkit-box; -webkit-line-clamp: 7; -webkit-box-orient: vertical; overflow: hidden; }',
      '.message-toggle { margin-top: 8px; padding: 0; border: 0; background: transparent; color: var(--primary); cursor: pointer; font-size: 12px; font-weight: 700; }',
      '.ticket-row-badge { display: inline-flex; margin-left: 8px; vertical-align: middle; }',
      '@media (max-width: 760px) { .quick-summary { grid-template-columns: 1fr; } }'
    ].join('\n');
    document.head.appendChild(style);
  }

  function icon(name) {
    const span = document.createElement('span');
    span.className = 'material-symbols-rounded';
    span.setAttribute('aria-hidden', 'true');
    span.textContent = name;
    return span;
  }

  function selectedTicketId() {
    const eyebrow = document.querySelector('#ticket-detail .detail-header .eyebrow');
    return eyebrow ? eyebrow.textContent.trim() : '';
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

  function chipValue(index) {
    const chips = document.querySelectorAll('#ticket-detail .detail-chips .chip');
    return chips[index] ? (chips[index].dataset.value || chips[index].textContent.trim().toUpperCase()) : '';
  }

  function formatRelative(dateText) {
    if (!dateText || dateText === '—') return 'Sin fecha';
    const date = new Date(dateText);
    if (Number.isNaN(date.getTime())) return dateText;
    const diffMs = date.getTime() - Date.now();
    const absHours = Math.round(Math.abs(diffMs) / 36e5);
    if (absHours < 1) return diffMs < 0 ? 'hace menos de 1h' : 'en menos de 1h';
    if (absHours < 48) return diffMs < 0 ? 'hace ' + absHours + 'h' : 'en ' + absHours + 'h';
    const days = Math.round(absHours / 24);
    return diffMs < 0 ? 'hace ' + days + 'd' : 'en ' + days + 'd';
  }

  function copyText(value, label) {
    if (!value || value === '—') return;
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(value).then(function () {
        showSnack(label + ' copiado.');
      }).catch(function () {
        fallbackCopy(value, label);
      });
    } else {
      fallbackCopy(value, label);
    }
  }

  function fallbackCopy(value, label) {
    const input = document.createElement('textarea');
    input.value = value;
    input.style.position = 'fixed';
    input.style.left = '-9999px';
    document.body.appendChild(input);
    input.select();
    document.execCommand('copy');
    input.remove();
    showSnack(label + ' copiado.');
  }

  function showSnack(message) {
    const snackbar = document.getElementById('snackbar');
    if (!snackbar) return;
    snackbar.textContent = message;
    snackbar.hidden = false;
    window.setTimeout(function () { snackbar.hidden = true; }, 5000);
  }

  function makeSummaryCard(label, value) {
    const card = document.createElement('div');
    card.className = 'quick-summary-card';
    const caption = document.createElement('span');
    caption.textContent = label;
    const strong = document.createElement('strong');
    strong.textContent = value || '—';
    card.appendChild(caption);
    card.appendChild(strong);
    return card;
  }

  function makeMiniButton(iconName, label, handler) {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'mini-button';
    button.appendChild(icon(iconName));
    button.appendChild(document.createTextNode(label));
    button.addEventListener('click', handler);
    return button;
  }

  function makeIconButton(iconName, title, handler) {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'icon-button';
    button.title = title;
    button.setAttribute('aria-label', title);
    button.appendChild(icon(iconName));
    button.addEventListener('click', handler);
    return button;
  }

  function ensureDetailSummary() {
    injectStyles();
    const header = document.querySelector('#ticket-detail .detail-header');
    if (!header || header.querySelector('.quick-summary')) return;
    const ticketId = selectedTicketId();
    if (!ticketId) return;

    const customer = detailFieldValue('Customer');
    const assignee = detailFieldValue('Assignee');
    const slaDue = detailFieldValue('SLA due');
    const status = chipValue(0);

    const summary = document.createElement('div');
    summary.className = 'quick-summary';
    summary.appendChild(makeSummaryCard('Cliente', customer));
    summary.appendChild(makeSummaryCard('Responsable', assignee));
    summary.appendChild(makeSummaryCard('SLA', formatRelative(slaDue)));
    header.appendChild(summary);

    const actions = document.getElementById('detail-header-actions');
    if (actions) {
      actions.appendChild(makeIconButton('content_copy', 'Copiar ID del ticket', function () {
        copyText(ticketId, 'ID del ticket');
      }));
      actions.appendChild(makeIconButton('alternate_email', 'Copiar email del cliente', function () {
        copyText(customer, 'Email del cliente');
      }));
      if (customer && customer !== '—') {
        actions.appendChild(makeIconButton('mail', 'Enviar email al cliente', function () {
          window.open('https://mail.google.com/mail/?view=cm&fs=1&to=' + encodeURIComponent(customer) + '&su=' + encodeURIComponent('Soporte ' + ticketId));
        }));
      }
    }

    const alert = document.createElement('div');
    alert.className = 'sla-alert';
    const dueDate = new Date(slaDue);
    if (Number.isNaN(dueDate.getTime()) || status === 'CLOSED' || status === 'RESOLVED') {
      alert.dataset.tone = 'success';
      alert.textContent = 'Este ticket no tiene riesgo de SLA actualmente.';
    } else if (dueDate.getTime() < Date.now()) {
      alert.dataset.tone = 'error';
      alert.textContent = 'SLA incumplido. Prioriza este ticket.';
    } else if (dueDate.getTime() - Date.now() < 12 * 60 * 60 * 1000) {
      alert.dataset.tone = 'warning';
      alert.textContent = 'El SLA vence pronto. Revísalo antes de que expire.';
    } else {
      alert.dataset.tone = 'success';
      alert.textContent = 'El SLA está bajo control.';
    }
    header.appendChild(alert);
  }

  function enhanceMessages() {
    document.querySelectorAll('#ticket-detail .message').forEach(function (message) {
      if (message.dataset.enhanced === 'true') return;
      const body = message.querySelector('p');
      if (!body) return;
      message.dataset.enhanced = 'true';
      const text = body.textContent || '';
      if (text.length < 900) return;
      message.classList.add('is-collapsed');
      const toggle = document.createElement('button');
      toggle.type = 'button';
      toggle.className = 'message-toggle';
      toggle.textContent = 'Ver mensaje completo';
      toggle.addEventListener('click', function () {
        const collapsed = message.classList.toggle('is-collapsed');
        toggle.textContent = collapsed ? 'Ver mensaje completo' : 'Ver menos';
      });
      message.appendChild(toggle);
    });
  }

  function enhanceRows() {
    document.querySelectorAll('#ticket-table-body tr').forEach(function (row) {
      if (row.dataset.usabilityEnhanced === 'true') return;
      row.dataset.usabilityEnhanced = 'true';
      const priorityCell = row.children[2];
      const updatedCell = row.children[4];
      if (!priorityCell || !updatedCell) return;
      const priority = priorityCell.textContent.trim().toUpperCase();
      if (priority === 'CRITICAL' || priority === 'HIGH') {
        const marker = document.createElement('span');
        marker.className = 'ticket-row-badge';
        marker.title = 'High attention ticket';
        marker.appendChild(icon(priority === 'CRITICAL' ? 'emergency_home' : 'priority_high'));
        priorityCell.appendChild(marker);
      }
    });
  }

  function runEnhancements() {
    ensureDetailSummary();
    enhanceMessages();
    enhanceRows();
  }

  const observer = new MutationObserver(runEnhancements);

  function start() {
    observer.observe(document.body, {childList: true, subtree: true});
    runEnhancements();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }
})();
</script>
'@
[System.IO.File]::WriteAllText((Join-Path $root "html\UsabilityScripts.html"), $v1, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host ""
Write-Host "Verificando..." -ForegroundColor Cyan
Select-String -Path html\ReplyBoxScripts.html -Pattern "mail.google.com"
Select-String -Path html\UsabilityScripts.html -Pattern "mail.google.com"

Write-Host ""
Write-Host "Si salieron lineas arriba, ejecuta: npm test  y  npm run deploy" -ForegroundColor Cyan
