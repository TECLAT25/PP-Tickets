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
      'shippingRecipientCountry', 'shippingRecipientPostalCode', 'shippingRecipientCity'];
    const customerFieldNames = ['firstName', 'lastName', 'phone', 'address', 'country', 'postalCode', 'city'];

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
        byError: countCommaListValues_(tickets, 'detectedErrors', buildCatalogLabelMap_(APP.SHEETS.ERRORS)),
        bySolution: countCommaListValues_(tickets, 'detectedSolutions', buildCatalogLabelMap_(APP.SHEETS.SOLUTIONS)),
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
function countCommaListValues_(tickets, field, labelMap) {
  const counts = {};
  tickets.forEach(function(ticket) {
    String(ticket[field] || '').split(',').forEach(function(value) {
      const trimmed = value.trim();
      if (!trimmed) return;
      const atIndex = trimmed.lastIndexOf('@');
      const code = atIndex === -1 ? trimmed : trimmed.slice(0, atIndex);
      const label = (labelMap && labelMap[code]) ? labelMap[code] : code;
      counts[label] = (counts[label] || 0) + 1;
    });
  });
  return counts;
}

/** @return {Object} map of code -> description for a catalog sheet @private */
function buildCatalogLabelMap_(sheetName) {
  const map = {};
  try {
    const sheet = AppConfig.getSheet(sheetName);
    if (sheet.getLastRow() <= 1) return map;
    sheet.getRange(2, 1, sheet.getLastRow() - 1, 2).getDisplayValues().forEach(function(row) {
      const code = String(row[0] || '').trim();
      const description = String(row[1] || '').trim();
      if (code) map[code] = description || code;
    });
  } catch (error) {
    // Catalog sheet unavailable — counts will fall back to raw codes.
  }
  return map;
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

/**
 * Reads the "Colors" sheet and returns each Status/Priority/Category
 * value's color, taken from the background fill of its "Color" cell.
 * The agent customizes colors just by repainting cells in Sheets.
 * @return {{ok: boolean, data: {STATUS: Object, PRIORITY: Object, CATEGORY: Object}}|Object}
 */
function getUiColorMap() {
  try {
    const sheet = AppConfig.getSheet(APP.SHEETS.COLORS);
    const map = {STATUS: {}, PRIORITY: {}, CATEGORY: {}};
    if (sheet.getLastRow() <= 1) return {ok: true, data: map};

    const rowCount = sheet.getLastRow() - 1;
    const values = sheet.getRange(2, 1, rowCount, 2).getDisplayValues();
    const backgrounds = sheet.getRange(2, 4, rowCount, 1).getBackgrounds();

    values.forEach(function(row, index) {
      const type = String(row[0] || '').trim().toUpperCase();
      const value = String(row[1] || '').trim().toUpperCase();
      const color = backgrounds[index][0];
      if (!type || !value || !map[type]) return;
      if (color && color !== '#ffffff') map[type][value] = color;
    });

    return {ok: true, data: map};
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}