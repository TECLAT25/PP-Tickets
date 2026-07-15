# related-tickets-warning.ps1
# Aviso en el panel del ticket cuando el mismo cliente tiene otros
# tickets (hilos de Gmail distintos) con un asunto parecido.
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
        activeSampleSize: timing.activeSampleSize,
        avgTimeInStatusHours: timing.avgTimeInStatusHours
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
  const statusTimeTotals = {};
  const statusTimeCounts = {};
  TicketPolicy.statuses().forEach(function(status) {
    statusTimeTotals[status] = 0;
    statusTimeCounts[status] = 0;
  });

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

    const statusSince = toDate(ticket.statusChangedAt || ticket.createdAt);
    if (!isNaN(statusSince.getTime()) && Object.prototype.hasOwnProperty.call(statusTimeTotals, ticket.status)) {
      statusTimeTotals[ticket.status] += hoursBetween(statusSince, now);
      statusTimeCounts[ticket.status] += 1;
    }
  });

  const avgTimeInStatusHours = {};
  Object.keys(statusTimeTotals).forEach(function(status) {
    avgTimeInStatusHours[status] = statusTimeCounts[status] ? statusTimeTotals[status] / statusTimeCounts[status] : 0;
  });

  return {
    avgResolutionHours: resolutionCount ? resolutionTotal / resolutionCount : 0,
    avgOpenHours: openCount ? openTotal / openCount : 0,
    resolvedSampleSize: resolutionCount,
    activeSampleSize: openCount,
    avgTimeInStatusHours: avgTimeInStatusHours
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

/**
 * Returns the count of tickets created each month for a given year, plus
 * the list of years that actually have tickets (for the year picker).
 * @param {number=} year Defaults to the current year.
 * @return {{ok: boolean, data: {year: number, months: Array<number>, availableYears: Array<number>}}|Object}
 */
function getUiTicketsCreatedByMonth(year) {
  try {
    const tickets = new SheetTicketRepository().listAll();
    const years = {};
    tickets.forEach(function(ticket) {
      const createdAt = ticket.createdAt instanceof Date ? ticket.createdAt : new Date(ticket.createdAt);
      if (!isNaN(createdAt.getTime())) years[createdAt.getFullYear()] = true;
    });
    const availableYears = Object.keys(years).map(Number).sort(function(a, b) { return b - a; });

    const currentYear = new Date().getFullYear();
    const targetYear = Number(year) || currentYear;
    const months = new Array(12).fill(0);
    tickets.forEach(function(ticket) {
      const createdAt = ticket.createdAt instanceof Date ? ticket.createdAt : new Date(ticket.createdAt);
      if (isNaN(createdAt.getTime())) return;
      if (createdAt.getFullYear() === targetYear) months[createdAt.getMonth()] += 1;
    });

    return {
      ok: true,
      data: {
        year: targetYear,
        months: months,
        availableYears: availableYears.length ? availableYears : [currentYear]
      }
    };
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}

/**
 * Finds other tickets from the same customer with a similar (normalized)
 * subject — different Gmail threads about what looks like the same topic.
 * Used to warn the agent in the ticket detail panel.
 * @param {string} ticketId
 * @return {{ok: boolean, data: Array<{id: string, subject: string, status: string}>}|Object}
 */
function findUiRelatedTickets(ticketId) {
  try {
    const ticket = new SheetTicketRepository().findById(ticketId);
    if (!ticket || !ticket.customerEmail || !ticket.subject) return {ok: true, data: []};

    const normalize = function(value) {
      return String(value || '')
        .replace(/^(re|fwd?|fw)\s*:\s*/gi, '')
        .trim()
        .toLowerCase();
    };
    const targetSubject = normalize(ticket.subject);
    if (!targetSubject) return {ok: true, data: []};

    const result = new SheetTicketRepository().search({customerEmail: ticket.customerEmail, limit: 50});
    const related = result.items
      .filter(function(candidate) { return candidate.id !== ticketId && normalize(candidate.subject) === targetSubject; })
      .map(function(candidate) { return {id: candidate.id, subject: candidate.subject, status: candidate.status}; });

    return {ok: true, data: related};
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}
'@
[System.IO.File]::WriteAllText((Join-Path $root "src\uiActions.gs"), $v0, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo html\Index.html..." -ForegroundColor Cyan
$v1 = @'
<!DOCTYPE html>
<html lang="es">
  <head>
    <base target="_top">
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="color-scheme" content="light dark">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@20..48,400,0,0">
    <?!= include('css/Styles'); ?>
  </head>
  <body>
    <div class="app support-shell">
      <aside class="navigation" aria-label="Navegación principal">
        <div class="brand">
          <span class="brand-mark material-symbols-rounded" aria-hidden="true">piano</span>
          <div>
            <strong><?= AppUtils.escapeHtml(bootstrap.app.name) ?></strong>
            <small>Espacio de soporte</small>
          </div>
        </div>
        <nav class="nav-list">
          <button class="nav-item is-active" type="button" data-view="dashboard">
            <span class="material-symbols-rounded" aria-hidden="true">dashboard</span>
            <span>Panel</span>
          </button>
          <button class="nav-item" type="button" data-view="tickets">
            <span class="material-symbols-rounded" aria-hidden="true">confirmation_number</span>
            <span>Tickets</span>
          </button>
          <button class="nav-item" type="button" data-view="customer">
            <span class="material-symbols-rounded" aria-hidden="true">person</span>
            <span>Cliente</span>
          </button>
        </nav>
        <div class="navigation-footer">
          <span><?= AppUtils.escapeHtml(bootstrap.user.email || 'Usuario del espacio') ?></span>
          <small>v<?= AppUtils.escapeHtml(bootstrap.app.version) ?></small>
        </div>
      </aside>

      <main class="main support-main">
        <header class="top-app-bar support-topbar">
          <span class="topbar-brand"><?= AppUtils.escapeHtml(bootstrap.app.name) ?> <small>v<?= AppUtils.escapeHtml(bootstrap.app.version) ?></small></span>
          <label class="search-field" for="global-search">
            <span class="material-symbols-rounded" aria-hidden="true">search</span>
            <input id="global-search" type="search" placeholder="Buscar cliente, ticket, número de serie…" autocomplete="off">
          </label>
          <button id="sync-gmail" class="tonal-button top-action" type="button" aria-label="Sincronizar Gmail">
            <span class="material-symbols-rounded" aria-hidden="true">sync</span>Sincronizar
          </button>
          <button class="tonal-button top-action" type="button" data-action="refresh">
            <span class="material-symbols-rounded" aria-hidden="true">refresh</span>Actualizar
          </button>
          <button id="global-save-button" class="tonal-button top-action" type="button">
            <span class="material-symbols-rounded" aria-hidden="true">save</span>Guardar
          </button>
          <button id="customer-directory-button" class="tonal-button top-action" type="button">
            <span class="material-symbols-rounded" aria-hidden="true">group</span>Clientes
          </button>
          <button id="statistics-button" class="tonal-button top-action" type="button">
            <span class="material-symbols-rounded" aria-hidden="true">bar_chart</span>Estadísticas
          </button>
          <button id="theme-toggle" class="icon-button" type="button" aria-label="Cambiar modo oscuro">
            <span class="material-symbols-rounded" aria-hidden="true">dark_mode</span>
          </button>
        </header>

        <div id="loading" class="loading" role="status">
          <span class="spinner" aria-hidden="true"></span>
          <span>Cargando espacio de trabajo…</span>
        </div>

        <section id="view-dashboard" class="view is-active" aria-labelledby="dashboard-title">
          <div class="page-heading">
            <div><p class="eyebrow">Resumen</p><h1 id="dashboard-title">Panel</h1></div>
            <button class="tonal-button" type="button" data-action="refresh">
              <span class="material-symbols-rounded" aria-hidden="true">refresh</span>Actualizar
            </button>
          </div>
          <div id="metric-grid" class="metric-grid" aria-label="Métricas de tickets"></div>
          <section class="surface">
            <div class="section-heading">
              <div><h2>Tickets recientes</h2><p>Conversaciones actualizadas más recientemente</p></div>
              <button class="text-button" type="button" data-view-link="tickets">Ver todos</button>
            </div>
            <div id="recent-tickets" class="ticket-cards"></div>
          </section>
        </section>

        <section id="view-tickets" class="view support-workbench" aria-labelledby="tickets-title">
          <aside class="queue-panel surface" aria-label="Colas de tickets">
            <div class="queue-title">
              <p class="eyebrow">Colas</p>
              <button id="new-ticket-button" class="icon-button" type="button" title="Nuevo ticket" aria-label="Nuevo ticket" aria-haspopup="dialog">
                <span class="material-symbols-rounded" aria-hidden="true">add</span>
              </button>
            </div>
            <div id="queue-list" class="queue-list">
              <button class="queue-item is-active" type="button" data-queue="all"><span>Bandeja</span><strong>0</strong></button>
              <button class="queue-item" type="button" data-queue="breached"><span>SLA incumplido</span><strong>0</strong></button>
            </div>
            <div class="filters compact-filters" aria-label="Filtros de tickets">
              <label><span>Estado</span><select id="filter-status"><option value="">Todo</option></select></label>
              <label><span>Prioridad</span><select id="filter-priority"><option value="">Todo</option></select></label>
              <label><span>Categoría</span><select id="filter-category"><option value="">Todo</option></select></label>
              <label class="breach-filter"><input id="filter-breached" type="checkbox"><span>SLA incumplido</span></label>
            </div>
          </aside>

          <section class="ticket-list-panel surface" aria-labelledby="tickets-title">
            <div class="ticket-list-header">
              <div><p class="eyebrow">Soporte</p><h1 id="tickets-title">Tickets</h1></div>
              <span id="ticket-count" class="count-badge">0 tickets</span>
            </div>
            <div class="ticket-list-tools">
              <span class="muted">Ordenado por última actualización</span>
            </div>
            <div class="table-wrap ticket-card-table">
              <table>
                <thead><tr><th>Ticket</th><th>Estado</th><th>Prioridad</th><th>Cliente</th><th>Actualizado</th></tr></thead>
                <tbody id="ticket-table-body"></tbody>
              </table>
            </div>
            <div id="ticket-empty" class="empty-state" hidden>
              <span class="material-symbols-rounded" aria-hidden="true">inbox</span>
              <h3>No se encontraron tickets</h3>
              <p>Prueba a quitar algún filtro.</p>
            </div>
          </section>

          <aside id="ticket-detail" class="surface detail-panel support-detail" aria-live="polite">
            <div class="empty-state">
              <span class="material-symbols-rounded" aria-hidden="true">select_check_box</span>
              <h3>Selecciona un ticket</h3>
              <p>Aquí aparecerán los detalles del ticket, el historial del cliente y la conversación.</p>
            </div>
          </aside>
        </section>

        <section id="view-customer" class="view" aria-labelledby="customer-title">
          <div class="page-heading">
            <div><p class="eyebrow">Relación</p><h1 id="customer-title">Cliente</h1></div>
          </div>
          <div id="customer-view" class="surface customer-view">
            <div class="empty-state">
              <span class="material-symbols-rounded" aria-hidden="true">person_search</span>
              <h3>Ningún cliente seleccionado</h3>
              <p>Selecciona un ticket para ver la ficha de su cliente.</p>
            </div>
          </div>
        </section>
      </main>
    </div>

    <div id="snackbar" class="snackbar" role="alert" aria-live="assertive" hidden></div>
    <?!= include('html/BootGuardScripts'); ?>
    <?!= include('html/Scripts'); ?>
    <?!= include('html/DraftScripts'); ?>
    <?!= include('html/SyncScripts'); ?>
    <?!= include('html/TicketActions'); ?>
    <?!= include('html/CustomerShippingActions'); ?>
    <?!= include('html/IssuesSectionScripts'); ?>
    <?!= include('html/RelatedTicketsScripts'); ?>
    <?!= include('html/NewTicketScripts'); ?>
    <?!= include('html/UsabilityScripts'); ?>
    <?!= include('html/QueueScripts'); ?>
    <?!= include('html/WorkbenchScripts'); ?>
    <?!= include('html/ReplyBoxScripts'); ?>
    <?!= include('html/DashboardEnhancements'); ?>
    <?!= include('html/GlobalSaveScripts'); ?>
    <?!= include('html/CustomerDirectoryScripts'); ?>
    <?!= include('html/StatisticsScripts'); ?>
  </body>
</html>
'@
[System.IO.File]::WriteAllText((Join-Path $root "html\Index.html"), $v1, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo html\RelatedTicketsScripts.html..." -ForegroundColor Cyan
$v2 = @'
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
    NEW: 'Nuevo', OPEN: 'Abierto', PENDING_CUSTOMER: 'Esperando cliente', RESOLVED: 'Resuelto', CLOSED: 'Cerrado'
  };

  function injectStyles() {
    if (document.getElementById('related-tickets-styles')) return;
    const style = document.createElement('style');
    style.id = 'related-tickets-styles';
    style.textContent = [
      '.related-tickets-banner { margin-top: 8px; padding: 10px 14px; border-radius: 12px; background: var(--tertiary-container, var(--surface-container)); font-size: 12px; }',
      '.related-tickets-banner strong { display: block; margin-bottom: 6px; }',
      '.related-tickets-list { display: flex; flex-wrap: wrap; gap: 6px; }',
      '.related-ticket-chip { display: inline-flex; align-items: center; gap: 6px; padding: 4px 10px; border-radius: 14px; border: 1px solid var(--outline-variant); background: var(--surface-bright); cursor: pointer; font-size: 11px; color: var(--on-surface); }',
      '.related-ticket-chip:hover { background: var(--surface-container); }',
      '.related-ticket-chip span { color: var(--on-surface-variant); }'
    ].join('\n');
    document.head.appendChild(style);
  }

  function selectedTicketId() {
    const selected = document.querySelector('[data-ticket-id].is-selected');
    if (selected && selected.dataset.ticketId) return selected.dataset.ticketId;
    const eyebrow = document.querySelector('#ticket-detail .detail-header .eyebrow');
    return eyebrow ? eyebrow.textContent.trim() : '';
  }

  function openTicket(ticketId) {
    const searchInput = document.getElementById('global-search');
    if (searchInput) {
      searchInput.value = ticketId;
      searchInput.dispatchEvent(new Event('input', {bubbles: true}));
    }
    const ticketsNav = document.querySelector('[data-view="tickets"]');
    if (ticketsNav) ticketsNav.click();
  }

  function ensureBanner() {
    const header = document.querySelector('#ticket-detail .detail-header');
    if (!header || header.querySelector('.related-tickets-banner') || header.dataset.relatedChecked === 'true') return;
    header.dataset.relatedChecked = 'true';

    const ticketId = selectedTicketId();
    if (!ticketId) return;

    callServer('findUiRelatedTickets', ticketId).then(unwrap).then(function (related) {
      if (!related || !related.length) return;
      injectStyles();

      const banner = document.createElement('div');
      banner.className = 'related-tickets-banner';
      const title = document.createElement('strong');
      title.textContent = 'Este cliente tiene otro' + (related.length === 1 ? '' : 's') + ' ' + related.length + ' ticket' + (related.length === 1 ? '' : 's') + ' con un asunto parecido:';
      banner.appendChild(title);

      const list = document.createElement('div');
      list.className = 'related-tickets-list';
      related.forEach(function (ticket) {
        const chip = document.createElement('button');
        chip.type = 'button';
        chip.className = 'related-ticket-chip';
        chip.innerHTML = '<strong>' + ticket.id + '</strong><span>' + (ENUM_LABELS[ticket.status] || ticket.status) + '</span>';
        chip.addEventListener('click', function () { openTicket(ticket.id); });
        list.appendChild(chip);
      });
      banner.appendChild(list);

      header.appendChild(banner);
    }).catch(function () {
      // Silently skip the banner if this lookup fails — not critical to the ticket workflow.
    });
  }

  const observer = new MutationObserver(function () {
    ensureBanner();
  });

  function start() {
    const panel = document.getElementById('ticket-detail');
    if (!panel) return;
    observer.observe(panel, {childList: true, subtree: true});
    ensureBanner();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
</script>
'@
[System.IO.File]::WriteAllText((Join-Path $root "html\RelatedTicketsScripts.html"), $v2, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo html\WorkbenchScripts.html..." -ForegroundColor Cyan
$v3 = @'
<script>
(function () {
  'use strict';

  var queues = {
    all: {},
    breached: {breached: true}
  };

  function addCss() {
    if (document.getElementById('workbench-css')) return;
    var css = '.app.support-shell{display:grid!important;grid-template-columns:1fr!important;width:100vw!important;max-width:100vw!important;overflow:hidden!important}' +
      '.navigation{display:none!important}' +
      '.main.support-main{width:100vw!important;max-width:100vw!important;height:100vh!important;padding:4px!important;overflow:hidden!important}' +
      '.support-topbar{height:46px!important;min-height:46px!important;margin-bottom:6px!important;padding:0 18px!important}' +
      '.topbar-brand{font-size:13px!important;margin-right:12px!important}' +
      '.topbar-brand small{font-size:11px!important}' +
      '#view-dashboard{display:none!important}' +
      '#view-customer{display:none!important}' +
      '#view-tickets.view.is-active{display:grid!important}' +
      '.support-workbench{display:grid!important;grid-template-columns:315px minmax(0,1fr)!important;grid-template-rows:150px minmax(0,1fr)!important;gap:6px!important;height:calc(100vh - 58px)!important;min-height:0!important;width:100%!important;max-width:100%!important;overflow:hidden!important}' +
      '.queue-panel{grid-column:1!important;grid-row:1!important;height:150px!important;min-height:0!important;overflow:hidden!important;padding:7px!important}' +
      '.ticket-list-panel{grid-column:1!important;grid-row:2!important;height:100%!important;min-height:0!important;overflow:auto!important;padding:7px!important}' +
      '.support-detail{grid-column:2!important;grid-row:1 / span 2!important;height:100%!important;min-height:0!important;overflow:hidden!important}' +
      '.queue-title{display:flex!important;align-items:center!important;justify-content:space-between!important;margin-bottom:5px!important}' +
      '.queue-title h2{font-size:13px!important;margin:0!important}' +
      '.queue-title .eyebrow{font-size:9px!important}' +
      '.queue-list{display:grid!important;grid-template-columns:repeat(2,minmax(0,1fr))!important;gap:4px!important;margin:0!important}' +
      '.queue-item{display:flex;justify-content:space-between;align-items:center;min-height:22px;padding:0 6px;border:1px solid var(--outline-variant);border-radius:8px;background:var(--surface-bright);color:var(--on-surface);cursor:pointer;font-size:10px;white-space:nowrap!important;overflow:hidden!important}' +
      '.queue-item span{overflow:hidden!important;text-overflow:ellipsis!important}' +
      '.queue-item strong{font-size:10px!important}' +
      '.queue-item.is-active{background:var(--primary-container);color:var(--on-primary-container);font-weight:800}' +
      '.compact-filters{display:grid!important;grid-template-columns:repeat(3,minmax(0,1fr))!important;gap:4px!important;margin:5px 0 6px!important}' +
      '.compact-filters label{display:grid!important;gap:2px!important;font-size:8px!important;text-transform:uppercase!important;font-weight:800!important;color:var(--on-surface-variant)!important;min-width:0!important}' +
      '.compact-filters select{width:100%!important;min-width:0!important;max-width:100%!important;box-sizing:border-box!important;min-height:24px!important;border-radius:7px!important;border:1px solid var(--outline-variant)!important;background:var(--surface-bright)!important;color:var(--on-surface)!important;font-size:9px!important;padding:0 3px!important}' +
      '.compact-filters .breach-filter{display:none!important}' +
      '.breach-filter{display:flex!important;align-items:center!important;gap:5px!important;min-height:26px!important}' +
      '.ticket-list-header{display:none!important}' +
      '.ticket-sortbar{display:grid!important;grid-template-columns:repeat(2,minmax(0,1fr))!important;gap:5px!important;margin:0 0 6px!important;padding:0 0 6px!important;border-bottom:1px solid var(--outline-variant)!important}' +
      '.sort-button{min-height:28px!important;border:1px solid var(--outline-variant)!important;border-radius:9px!important;background:var(--surface-bright)!important;color:var(--on-surface)!important;cursor:pointer!important;font-size:11px!important;font-weight:700!important}' +
      '.sort-button.is-active{background:var(--primary-container)!important;color:var(--on-primary-container)!important;border-color:var(--primary)!important}' +
      '.ticket-list-header .eyebrow,.muted{font-size:10px!important;color:var(--on-surface-variant)}' +
      '.count-badge{font-size:10px!important;padding:3px 7px!important}' +
      '.ticket-list-tools{display:none!important}' +
      '.ticket-card-table thead{display:none}' +
      '.ticket-card-table table,.ticket-card-table tbody,.ticket-card-table tr,.ticket-card-table td{display:block}' +
      '.ticket-card-table tbody{display:grid;gap:5px}' +
      '.ticket-card-table tr{padding:6px;border:1px solid var(--outline-variant);border-radius:9px;background:var(--surface-bright);cursor:pointer}' +
      '.ticket-card-table tr.is-selected{border-color:var(--primary);background:var(--primary-container)}' +
      '.ticket-card-table td{border:0!important;padding:0!important}' +
      '.ticket-card-table td:nth-child(1){font-weight:800;margin-bottom:5px;font-size:11px!important}' +
      '.ticket-subject{font-size:11px!important;line-height:1.2!important;max-height:28px!important;overflow:hidden!important}' +
      '.ticket-card-table td:nth-child(2),.ticket-card-table td:nth-child(3){display:inline-flex;margin:0 4px 5px 0;padding:2px 6px!important;border-radius:12px;background:var(--surface-container-high);font-size:9px;text-transform:uppercase}' +
      '.ticket-card-table td:nth-child(4),.ticket-card-table td:nth-child(5){font-size:10px!important;color:var(--on-surface-variant)!important;white-space:nowrap!important;overflow:hidden!important;text-overflow:ellipsis!important}' +
      '.support-detail{display:flex!important;flex-direction:column!important;padding:0!important}' +
      '.detail-scroll-area{flex:1!important;min-height:0!important;overflow-y:scroll!important;overflow-x:hidden!important}' +
      '.detail-scroll-area::-webkit-scrollbar{width:10px!important}' +
      '.detail-scroll-area::-webkit-scrollbar-track{background:var(--surface-container)!important}' +
      '.detail-scroll-area::-webkit-scrollbar-thumb{background:var(--outline)!important;border-radius:6px!important}' +
      '.detail-scroll-area::-webkit-scrollbar-thumb:hover{background:var(--on-surface-variant)!important}' +
      '.reply-box{flex:none!important}' +
      '.support-detail .detail-header{position:relative!important;top:auto!important;z-index:2!important;padding:6px 9px!important;border-bottom:1px solid var(--outline-variant)!important;background:var(--surface)!important}' +
      '.support-detail .detail-header .eyebrow{font-size:9px!important;line-height:1!important}' +
      '.support-detail .detail-header h2{font-size:16px!important;line-height:1.12!important;margin:1px 0 4px!important}' +
      '.support-detail .detail-chips{display:inline-flex!important;gap:4px!important;margin:0 6px 0 0!important;vertical-align:middle!important}' +
      '.related-tickets-banner{padding:6px 9px!important;margin-top:5px!important;font-size:10px!important}' +
      '.related-tickets-banner strong{margin-bottom:4px!important;font-size:10px!important}' +
      '.related-ticket-chip{padding:2px 8px!important;font-size:9px!important}' +
      '.support-detail .detail-chips .chip{font-size:8px!important;padding:2px 6px!important}' +
      '.support-detail .detail-grid{display:none!important}' +
      '.ticket-actions{display:grid!important;grid-template-columns:repeat(6,minmax(0,1fr))!important;gap:5px!important;padding:6px!important;margin-top:5px!important;border-radius:10px!important}' +
      '.ticket-action-field{grid-column:span 2!important;gap:2px!important;font-size:8px!important}' +
      '.ticket-action-field span{font-size:8px!important}' +
      '.ticket-action-field select,.ticket-action-field input{min-height:28px!important;font-size:10px!important;padding:0 6px!important;border-radius:8px!important}' +
      '.ticket-action-field-wide{grid-column:span 3!important}' +
      '.detail-title-row{display:flex!important;align-items:flex-start!important;justify-content:space-between!important;gap:6px!important}' +
      '.detail-title-block{min-width:0!important}' +
      '.detail-header-actions{display:flex!important;gap:3px!important;flex-shrink:0!important}' +
      '.detail-header-actions .icon-button{width:24px!important;height:24px!important}' +
      '.detail-header-actions .icon-button .material-symbols-rounded{font-size:15px!important}' +
      '.customer-shipping-actions{grid-template-columns:repeat(3,minmax(0,1fr))!important;gap:5px!important;padding:6px!important;margin-top:5px!important;border-radius:10px!important}' +
      '.cs-extract-row{margin-bottom:2px!important}' +
      '.cs-extract-row .text-button{min-height:22px!important;padding:0 6px!important;font-size:9px!important}' +
      '.cs-field-wide{grid-column:1/-1!important}' +
      '.customer-shipping-actions .section-label{font-size:7px!important;margin:2px 0 0!important}' +
      '.cs-field{gap:2px!important;font-size:8px!important}' +
      '.cs-field input{min-height:26px!important;font-size:10px!important;padding:0 6px!important;border-radius:8px!important}' +
      '.quick-summary{grid-template-columns:repeat(3,minmax(0,1fr))!important;gap:5px!important;margin-top:4px!important}' +
      '.quick-summary-card{padding:4px 6px!important}' +
      '.quick-summary-card span{font-size:8px!important}' +
      '.quick-summary-card strong{margin-top:1px!important;font-size:11px!important}' +
      '.sla-alert{margin-top:5px!important;padding:5px 7px!important;font-size:11px!important}' +
      '.support-detail .conversation{flex:none!important;min-height:360px!important;overflow:visible!important;padding:7px 9px!important;margin:0!important;background:var(--surface-container-lowest)!important;border-top:1px solid var(--outline-variant)!important}' +
      '.conversation-empty{min-height:0!important;padding:20px 12px!important}' +
      '.issues-section{padding:7px 9px!important;gap:10px!important}' +
      '.issues-column h3{font-size:11px!important;margin:0 0 6px!important}' +
      '.issues-list{gap:4px!important;margin-top:6px!important}' +
      '.issue-row{padding:5px 5px 5px 9px!important;font-size:10px!important;border-radius:8px!important}' +
      '.issue-delete-button{width:22px!important;height:22px!important}' +
      '.issue-delete-button .material-symbols-rounded{font-size:14px!important}' +
      '.issues-add-button{width:24px!important;height:24px!important;font-size:14px!important}' +
      '.ticket-notes-section{padding:7px 9px!important}' +
      '.ticket-notes-section h3{font-size:11px!important;margin:0 0 4px!important}' +
      '.ticket-notes-section textarea{min-height:56px!important;padding:6px 8px!important;font-size:11px!important;border-radius:8px!important}' +
      '.conversation-empty .material-symbols-rounded{font-size:26px!important;margin-bottom:6px!important}' +
      '.conversation-empty h3{font-size:12px!important;margin-bottom:2px!important}' +
      '.conversation-empty p{font-size:11px!important}' +
      '.email-chain-heading{position:static!important;display:flex!important;align-items:center!important;justify-content:space-between!important;background:transparent!important;padding:0 0 6px!important;margin:0!important;z-index:auto!important}' +
      '.email-chain-heading h3{margin:0!important;font-size:14px!important}' +
      '.email-chain-heading span{font-size:10px!important;color:var(--on-surface-variant)!important}' +
      '.support-detail .email-message{padding:8px!important;margin-bottom:7px!important;border:1px solid var(--outline-variant)!important;border-radius:12px!important;background:var(--surface)!important;line-height:1.4!important;box-shadow:0 1px 2px rgba(0,0,0,.04)!important}' +
      '.email-message-top{display:flex!important;justify-content:space-between!important;gap:12px!important;margin-bottom:7px!important;border-bottom:1px solid var(--outline-variant)!important;padding-bottom:7px!important}' +
      '.email-message-identity{display:grid!important;gap:2px!important;min-width:0!important}' +
      '.email-message-identity strong{font-size:13px!important;white-space:normal!important;word-break:break-word!important}' +
      '.email-message-identity span,.email-message-top time{font-size:10px!important;color:var(--on-surface-variant)!important}' +
      '.email-subject{display:grid!important;grid-template-columns:52px minmax(0,1fr)!important;gap:7px!important;align-items:start!important;margin-bottom:7px!important}' +
      '.email-subject span,.email-meta dt{font-size:9px!important;color:var(--on-surface-variant)!important;text-transform:uppercase!important;font-weight:800!important}' +
      '.email-subject strong{font-size:12px!important;white-space:normal!important;word-break:break-word!important}' +
      '.email-meta{display:grid!important;grid-template-columns:repeat(3,minmax(0,1fr))!important;gap:5px 8px!important;margin:0 0 8px!important;padding:7px!important;border-radius:9px!important;background:var(--surface-container)!important}' +
      '.email-meta div{min-width:0!important}' +
      '.email-meta dd{margin:1px 0 0!important;font-size:10px!important;white-space:normal!important;word-break:break-word!important}' +
      '.email-body{white-space:pre-wrap!important;font-size:12px!important;line-height:1.45!important;word-break:break-word!important;overflow-wrap:anywhere!important}' +
      '.email-attachment{display:inline-flex!important;margin-top:8px!important}' +
      '.reply-box{margin:0!important;border-radius:0!important;border-left:0!important;border-right:0!important;border-bottom:0!important;max-height:40px!important;overflow:hidden!important;padding:6px 9px!important}' +
      '.reply-box-header{gap:6px!important}' +
      '.reply-box-header h3{font-size:12px!important;margin:0!important}' +
      '.reply-header-actions{gap:4px!important;flex-wrap:wrap!important}' +
      '.reply-toggle,.mail-customer-button{min-height:24px!important;padding:0 8px!important;font-size:10px!important;border-radius:10px!important}' +
      '.translate-toggle{min-height:24px!important;padding:0 8px!important;font-size:10px!important}' +
      '.reply-toolbar{gap:5px!important;margin:6px 0!important}' +
      '.reply-chip{padding:3px 8px!important;font-size:10px!important;border-radius:10px!important}' +
      '.reply-box textarea{padding:8px!important;font-size:12px!important}' +
      '.reply-actions{gap:5px!important;margin-top:6px!important}' +
      '.reply-box.is-open{max-height:150px!important;overflow:auto!important}' +
      '.reply-box textarea{min-height:44px!important}' +
      '@media(max-width:1150px){.support-workbench{grid-template-columns:285px minmax(0,1fr)!important}.ticket-actions{grid-template-columns:repeat(3,minmax(0,1fr))!important}.ticket-action-field{grid-column:span 1!important}.ticket-action-field-wide{grid-column:span 3!important}.email-meta{grid-template-columns:1fr!important}}' +
      '@media(max-width:850px){.main.support-main{overflow:auto!important}.support-workbench{display:grid!important;grid-template-columns:1fr!important;grid-template-rows:auto auto auto!important;height:auto!important;overflow:visible!important}.queue-panel,.ticket-list-panel,.support-detail{grid-column:1!important;grid-row:auto!important;height:auto!important;max-height:none!important}.support-detail{display:block!important}.compact-filters{display:grid!important}}';
    var style = document.createElement('style');
    style.id = 'workbench-css';
    style.textContent = css;
    document.head.appendChild(style);
  }

  function normalize(value) {
    return String(value || '').trim().toUpperCase().replace(/ /g, '_');
  }

  function setFilter(id, value) {
    var control = document.getElementById(id);
    if (!control) return;
    if (control.type === 'checkbox') control.checked = Boolean(value);
    else control.value = value || '';
    control.dispatchEvent(new Event('change', {bubbles: true}));
  }

  function applyQueue(name) {
    var criteria = queues[name] || {};
    document.querySelectorAll('.queue-item').forEach(function (button) {
      button.classList.toggle('is-active', button.dataset.queue === name);
    });
    setFilter('filter-status', criteria.status || '');
    setFilter('filter-priority', criteria.priority || '');
    setFilter('filter-category', criteria.category || '');
    setFilter('filter-breached', Boolean(criteria.breached));
  }

  function bindQueues() {
    document.querySelectorAll('.queue-item').forEach(function (button) {
      if (button.dataset.bound === 'true') return;
      button.dataset.bound = 'true';
      button.addEventListener('click', function () {
        applyQueue(button.dataset.queue || 'all');
      });
    });
  }

  function writeCount(selector, value) {
    var node = document.querySelector(selector);
    if (!node) return;
    var next = String(value);
    if (node.textContent !== next) node.textContent = next;
  }

  function updateCounts() {
    var rows = Array.prototype.slice.call(document.querySelectorAll('#ticket-table-body tr'));
    writeCount('.queue-item[data-queue="all"] strong', rows.length);
  }

  function forceWorkspace() {
    var button = document.querySelector('[data-view="tickets"]');
    if (button) button.click();
  }

  function scheduleUpdate() {
    window.clearTimeout(scheduleUpdate.timer);
    scheduleUpdate.timer = window.setTimeout(function () {
      bindQueues();
      updateCounts();
    }, 50);
  }

  function start() {
    addCss();
    bindQueues();
    updateCounts();
    forceWorkspace();
    window.setTimeout(forceWorkspace, 250);
    var body = document.getElementById('ticket-table-body');
    if (body) {
      new MutationObserver(scheduleUpdate).observe(body, {childList: true});
    }
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
</script>
'@
[System.IO.File]::WriteAllText((Join-Path $root "html\WorkbenchScripts.html"), $v3, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host ""
Write-Host "Verificando..." -ForegroundColor Cyan
Select-String -Path src\uiActions.gs -Pattern "findUiRelatedTickets"
Select-String -Path html\RelatedTicketsScripts.html -Pattern "ensureBanner"

Write-Host ""
Write-Host "Si salieron lineas arriba, ejecuta: npm test  y  npm run deploy" -ForegroundColor Cyan
