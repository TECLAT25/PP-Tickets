# stats-timing-and-percentages.ps1
$ErrorActionPreference = "Stop"
$root = Get-Location
$enc = New-Object System.Text.UTF8Encoding($false)

Write-Host "Escribiendo src\uiActions.gs..." -ForegroundColor Cyan
$v0 = @'
/**
 * Mutating UI actions used by the HTMLService client.
 *
 * These wrappers always return the same ok/data envelope as read-only UI calls.
 */

/**
 * Creates a Gmail draft reply for a support ticket from the UI.
 * This action never sends email.
 *
 * @param {string} ticketId
 * @param {string=} templateKey
 * @return {{ok: boolean, data: Object}|Object}
 */
function createUiDraftForTicket(ticketId, templateKey, customBody) {
  try {
    const result = createDraftForTicket(ticketId, templateKey || 'DEFAULT_SUPPORT_REPLY', customBody);
    return {ok: true, data: UiSerializer.toClient(result)};
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}

/**
 * Runs one bounded Gmail synchronization pass from the UI.
 *
 * @return {{ok: boolean, data: Object}|Object}
 */
function syncUiGmail() {
  try {
    const result = syncGmail();
    return {ok: true, data: UiSerializer.toClient(result)};
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}

/**
 * Creates a support ticket manually from the UI (not synchronized from Gmail).
 * @param {{subject: string, customerEmail: string, priority: string=, category: string=}} input
 * @return {{ok: boolean, data: Object}|Object}
 */
function createUiTicket(input) {
  try {
    const result = createTicket(input);
    return {ok: true, data: UiSerializer.toClient(result)};
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}

/**
 * Translates the synchronized message bodies for a ticket to Spanish and persists
 * the results in the Messages sheet.
 * @param {string} ticketId
 * @return {{ok: boolean, data: Object}|Object}
 */
function translateUiTicketToSpanish(ticketId) {
  try {
    const ticketRepository = new SheetTicketRepository();
    const ticket = ticketRepository.findById(ticketId);
    if (!ticket) {
      throw new AppError('Ticket not found: ' + ticketId, 'TICKET_NOT_FOUND', {ticketId: ticketId});
    }
    const messages = new UiMessageReadRepository().listByTicketId(ticketId);
    const result = TranslationService.translateMessagesToSpanish(messages);
    const messageRepository = new SheetMessageRepository();
    result.forEach(function(message) {
      if (message.id && message.translatedBody) {
        messageRepository.updateTranslation(
          message.id,
          message.detectedLanguage || message.originalLanguage || '',
          message.translatedBody
        );
      }
    });
    return {ok: true, data: UiSerializer.toClient({ticketId: ticketId, messages: result})};
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}

/** @param {string} ticketId @param {string} status @return {{ok: boolean, data: Object}|Object} */
function updateUiTicketStatus(ticketId, status) {
  try {
    const result = updateTicketStatus(ticketId, status);
    return {ok: true, data: UiSerializer.toClient(result)};
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}

/** @param {string} ticketId @param {string} priority @return {{ok: boolean, data: Object}|Object} */
function updateUiTicketPriority(ticketId, priority) {
  try {
    const result = updateTicketPriority(ticketId, priority);
    return {ok: true, data: UiSerializer.toClient(result)};
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}

/** @param {string} ticketId @param {string} category @return {{ok: boolean, data: Object}|Object} */
function updateUiTicketCategory(ticketId, category) {
  try {
    const result = updateTicketCategory(ticketId, category);
    return {ok: true, data: UiSerializer.toClient(result)};
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}

/** @param {string} ticketId @param {string} assignedTo @return {{ok: boolean, data: Object}|Object} */
function assignUiTicket(ticketId, assignedTo) {
  try {
    const result = assignTicket(ticketId, assignedTo || '');
    return {ok: true, data: UiSerializer.toClient(result)};
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}

/** @param {string} ticketId @param {string} tags @return {{ok: boolean, data: Object}|Object} */
function updateUiTicketTags(ticketId, tags) {
  try {
    const result = updateTicketTags(ticketId, tags || '');
    return {ok: true, data: UiSerializer.toClient(result)};
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}

/** @param {string} ticketId @param {Object} shipping @return {{ok: boolean, data: Object}|Object} */
function updateUiTicketShipping(ticketId, shipping) {
  try {
    const result = updateTicketShipping(ticketId, shipping || {});
    return {ok: true, data: UiSerializer.toClient(result)};
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}

/**
 * Saves everything from the ticket detail form (status, priority, category,
 * assignee, tags, shipping, and customer fields) in a single round trip.
 * @param {string} ticketId
 * @param {Object} payload Flat object mixing ticket and customer field names.
 * @return {{ok: boolean, data: Object}|Object}
 */
function saveUiTicketForm(ticketId, payload) {
  try {
    const data = payload || {};
    const ticketFieldNames = ['status', 'priority', 'category', 'assignedTo', 'tags', 'notes', 'detectedErrors', 'detectedSolutions', 'orderNumber', 'serialNumber',
      'shippingAddress', 'shippingRecipient', 'shippingRecipientPhone',
      'shippingRecipientFirstName', 'shippingRecipientLastName',
      'shippingRecipientCountry', 'shippingRecipientPostalCode'];
    const customerFieldNames = ['firstName', 'lastName', 'phone', 'address', 'country', 'postalCode'];

    const ticketChanges = {};
    ticketFieldNames.forEach(function(field) {
      if (Object.prototype.hasOwnProperty.call(data, field)) ticketChanges[field] = data[field];
    });
    const customerChanges = {};
    customerFieldNames.forEach(function(field) {
      if (Object.prototype.hasOwnProperty.call(data, field)) customerChanges[field] = data[field];
    });

    let ticket = null;
    if (Object.keys(ticketChanges).length) {
      ticket = updateTicketAll(ticketId, ticketChanges);
    }

    let customer = null;
    if (Object.keys(customerChanges).length) {
      const ticketRepository = new SheetTicketRepository();
      const currentTicket = ticket || ticketRepository.findById(ticketId);
      if (!currentTicket) {
        throw new AppError('Ticket not found: ' + ticketId, 'TICKET_NOT_FOUND', {ticketId: ticketId});
      }
      const customerRepository = new SheetCustomerRepository();
      let existingCustomer = currentTicket.customerId ? customerRepository.findById(currentTicket.customerId) : null;
      if (!existingCustomer && currentTicket.customerEmail) {
        existingCustomer = customerRepository.findByEmail(currentTicket.customerEmail);
      }
      customer = existingCustomer
        ? customerRepository.update(existingCustomer.id, customerChanges)
        : customerRepository.upsertByEmail(Object.assign({email: currentTicket.customerEmail}, customerChanges));
    }

    return {
      ok: true,
      data: {
        ticket: ticket ? UiSerializer.toClient(ticket) : null,
        customer: customer ? UiSerializer.toClient(customer) : null
      }
    };
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}

/**
 * Updates fields on the customer linked to a ticket (creating the customer
 * record if none exists yet for that ticket's email).
 * @param {string} ticketId
 * @param {Object} changes
 * @return {{ok: boolean, data: Object}|Object}
 */
function updateUiCustomerForTicket(ticketId, changes) {
  try {
    const ticketRepository = new SheetTicketRepository();
    const ticket = ticketRepository.findById(ticketId);
    if (!ticket) {
      throw new AppError('Ticket not found: ' + ticketId, 'TICKET_NOT_FOUND', {ticketId: ticketId});
    }
    const customerRepository = new SheetCustomerRepository();
    let customer = ticket.customerId ? customerRepository.findById(ticket.customerId) : null;
    if (!customer && ticket.customerEmail) {
      customer = customerRepository.findByEmail(ticket.customerEmail);
    }
    const updated = customer
      ? customerRepository.update(customer.id, changes || {})
      : customerRepository.upsertByEmail(Object.assign({email: ticket.customerEmail}, changes || {}));
    return {ok: true, data: UiSerializer.toClient(updated)};
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}

/**
 * Extracts best-effort phone/postal code/country/address fields from the
 * synchronized inbound messages of a ticket. Does not save anything —
 * returns candidates for the UI to prefill and the agent to review.
 * @param {string} ticketId
 * @return {{ok: boolean, data: Object}|Object}
 */
function extractUiFieldsFromMessages(ticketId) {
  try {
    const messageRepository = new UiMessageReadRepository();
    const inbound = messageRepository.listByTicketId(ticketId)
      .filter(function(message) { return message.direction === 'INBOUND'; });
    const combinedText = inbound.map(function(message) { return message.body; }).join('\n\n');
    const fromHeader = inbound.length ? inbound[0].from : '';
    const extracted = MessageFieldExtractor.extract(combinedText, fromHeader);

    let suggestedErrors = [];
    let suggestedSolutions = [];
    try {
      const errorCatalog = unwrapCatalog_(getUiErrorCatalog());
      suggestedErrors = MessageFieldExtractor.suggestCatalogMatches(combinedText, errorCatalog).slice(0, 5);
      const solutionCatalog = unwrapCatalog_(getUiSolutionCatalog());
      suggestedSolutions = MessageFieldExtractor.suggestCatalogMatches(combinedText, solutionCatalog).slice(0, 5);
    } catch (catalogError) {
      // Catalog sheets unavailable — field extraction still works without suggestions.
    }
    extracted.suggestedErrors = suggestedErrors;
    extracted.suggestedSolutions = suggestedSolutions;

    return {ok: true, data: extracted};
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}

/** @param {Object} response @return {Array} @private */
function unwrapCatalog_(response) {
  return (response && response.ok && response.data) ? response.data : [];
}

/**
 * Returns every customer with all of their fields, for the "Clientes" directory view.
 * @return {{ok: boolean, data: Array<Object>}|Object}
 */
function getUiCustomerDirectory() {
  try {
    const customers = new SheetCustomerRepository().listAll();
    customers.sort(function(a, b) {
      return String(a.name || a.email).toLowerCase() < String(b.name || b.email).toLowerCase() ? -1 : 1;
    });
    return {ok: true, data: customers.map(function(customer) { return UiSerializer.toClient(customer); })};
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}

/**
 * Returns a compact list of every ticket linked to a customer email, for
 * the "Clientes" directory detail view.
 * @param {string} email
 * @return {{ok: boolean, data: Array<Object>}|Object}
 */
function getUiTicketsForCustomer(email) {
  try {
    const result = new SheetTicketRepository().search({customerEmail: email, limit: 500});
    const tickets = result.items.map(function(ticket) {
      const updated = ticket.updatedAt instanceof Date ? ticket.updatedAt : new Date(ticket.updatedAt);
      return {
        id: String(ticket.id || ''),
        subject: String(ticket.subject || ''),
        status: String(ticket.status || ''),
        priority: String(ticket.priority || ''),
        updatedAt: Number.isNaN(updated.getTime()) ? '' : updated.toISOString()
      };
    });
    return {ok: true, data: UiSerializer.toClient(tickets)};
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}

/**
 * Updates a customer record directly (not through a specific ticket), from
 * the "Clientes" directory. Since every ticket reads the customer by email,
 * this change is automatically reflected on all of that customer's tickets.
 * @param {string} customerId
 * @param {Object} changes
 * @return {{ok: boolean, data: Object}|Object}
 */
function updateUiCustomerRecord(customerId, changes) {
  try {
    const updated = new SheetCustomerRepository().update(customerId, changes || {});
    return {ok: true, data: UiSerializer.toClient(updated)};
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}

/**
 * Computes ticket statistics (by status, priority, category, SLA) for the
 * "Estadísticas" dialog.
 * @return {{ok: boolean, data: Object}|Object}
 */
function getUiTicketStatistics() {
  try {
    const tickets = new SheetTicketRepository().listAll();
    const metrics = TicketMetrics.calculate(tickets, new Date());
    let customerCount = 0;
    try {
      customerCount = new SheetCustomerRepository().listAll().length;
    } catch (customerError) {
      // Customers sheet unavailable — statistics still work without it.
    }
    const timing = calculateTicketTiming_(tickets, new Date());
    return {
      ok: true,
      data: {
        total: metrics.total,
        active: metrics.active,
        breached: metrics.breached,
        byStatus: metrics.byStatus,
        byPriority: metrics.byPriority,
        byCategory: metrics.byCategory,
        byError: countCommaListValues_(tickets, 'detectedErrors'),
        bySolution: countCommaListValues_(tickets, 'detectedSolutions'),
        customerCount: customerCount,
        avgResolutionHours: timing.avgResolutionHours,
        avgOpenHours: timing.avgOpenHours,
        resolvedSampleSize: timing.resolvedSampleSize,
        activeSampleSize: timing.activeSampleSize
      }
    };
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}

/**
 * Computes average resolution time (createdAt -> statusChangedAt, for
 * tickets currently RESOLVED/CLOSED) and average time still open (createdAt
 * -> now, for active tickets), in hours.
 * @param {Array<Object>} tickets
 * @param {Date} now
 * @return {{avgResolutionHours: number, avgOpenHours: number, resolvedSampleSize: number, activeSampleSize: number}}
 * @private
 */
function calculateTicketTiming_(tickets, now) {
  const toDate = function(value) { return value instanceof Date ? value : new Date(value); };
  const hoursBetween = function(start, end) {
    const diff = end.getTime() - start.getTime();
    return diff > 0 ? diff / 36e5 : 0;
  };

  let resolutionTotal = 0;
  let resolutionCount = 0;
  let openTotal = 0;
  let openCount = 0;

  tickets.forEach(function(ticket) {
    const createdAt = toDate(ticket.createdAt);
    if (isNaN(createdAt.getTime())) return;

    if (ticket.status === 'RESOLVED' || ticket.status === 'CLOSED') {
      const changedAt = toDate(ticket.statusChangedAt || ticket.updatedAt);
      if (!isNaN(changedAt.getTime())) {
        resolutionTotal += hoursBetween(createdAt, changedAt);
        resolutionCount += 1;
      }
    } else {
      openTotal += hoursBetween(createdAt, now);
      openCount += 1;
    }
  });

  return {
    avgResolutionHours: resolutionCount ? resolutionTotal / resolutionCount : 0,
    avgOpenHours: openCount ? openTotal / openCount : 0,
    resolvedSampleSize: resolutionCount,
    activeSampleSize: openCount
  };
}

/**
 * Counts occurrences of each value inside a comma-separated field across
 * all tickets (used for Errores/Soluciones frequency in Estadísticas).
 * @param {Array<Object>} tickets
 * @param {string} field
 * @return {Object} map of value -> count
 * @private
 */
function countCommaListValues_(tickets, field) {
  const counts = {};
  tickets.forEach(function(ticket) {
    String(ticket[field] || '').split(',').forEach(function(value) {
      const trimmed = value.trim();
      if (!trimmed) return;
      counts[trimmed] = (counts[trimmed] || 0) + 1;
    });
  });
  return counts;
}

/**
 * Returns the catalog of known error types (from the "Errors" sheet) for
 * the "+" picker in the ticket detail's Errores detectados section.
 * @return {{ok: boolean, data: Array<{code: string, description: string}>}|Object}
 */
function getUiErrorCatalog() {
  try {
    const sheet = AppConfig.getSheet(APP.SHEETS.ERRORS);
    if (sheet.getLastRow() <= 1) return {ok: true, data: []};
    const values = sheet.getRange(2, 1, sheet.getLastRow() - 1, 2).getDisplayValues();
    const catalog = values
      .filter(function(row) { return String(row[0]).trim(); })
      .map(function(row) { return {code: String(row[0]).trim(), description: String(row[1] || '').trim()}; });
    return {ok: true, data: catalog};
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}

/**
 * Returns the catalog of known solutions (from the "Solutions" sheet) for
 * the "+" picker in the ticket detail's Soluciones section.
 * @return {{ok: boolean, data: Array<{code: string, description: string}>}|Object}
 */
function getUiSolutionCatalog() {
  try {
    const sheet = AppConfig.getSheet(APP.SHEETS.SOLUTIONS);
    if (sheet.getLastRow() <= 1) return {ok: true, data: []};
    const values = sheet.getRange(2, 1, sheet.getLastRow() - 1, 2).getDisplayValues();
    const catalog = values
      .filter(function(row) { return String(row[0]).trim(); })
      .map(function(row) { return {code: String(row[0]).trim(), description: String(row[1] || '').trim()}; });
    return {ok: true, data: catalog};
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}
'@
[System.IO.File]::WriteAllText((Join-Path $root "src\uiActions.gs"), $v0, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo html\StatisticsScripts.html..." -ForegroundColor Cyan
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

  const ENUM_LABELS = {
    NEW: 'Nuevo', OPEN: 'Abierto', PENDING_CUSTOMER: 'Esperando cliente', RESOLVED: 'Resuelto', CLOSED: 'Cerrado',
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
    body.appendChild(breakdownSection('Por prioridad', stats.byPriority, stats.total));
    body.appendChild(breakdownSection('Por categoría', stats.byCategory, stats.total));
    body.appendChild(breakdownSection('Errores más frecuentes', stats.byError || {}, stats.total));
    body.appendChild(breakdownSection('Soluciones más aplicadas', stats.bySolution || {}, stats.total));
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
[System.IO.File]::WriteAllText((Join-Path $root "html\StatisticsScripts.html"), $v1, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host ""
Write-Host "Verificando..." -ForegroundColor Cyan
Select-String -Path src\uiActions.gs -Pattern "calculateTicketTiming_"
Select-String -Path html\StatisticsScripts.html -Pattern "formatDuration"

Write-Host ""
Write-Host "Si salieron lineas arriba, ejecuta: npm test  y  npm run deploy" -ForegroundColor Cyan
