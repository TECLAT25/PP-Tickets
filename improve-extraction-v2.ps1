# improve-extraction-v2.ps1
# Reconocimiento de numero de serie (PP-YY-WWW-NNNNN), evita falsos
# positivos con telefono/codigo postal, y sugiere errores/soluciones
# del catalogo segun el contenido de los mensajes.
$ErrorActionPreference = "Stop"
$root = Get-Location
$enc = New-Object System.Text.UTF8Encoding($false)

Write-Host "Escribiendo src\extraction.gs..." -ForegroundColor Cyan
$v0 = @'
/**
 * Best-effort extraction of structured fields (name, phone, postal code,
 * country, street address) from email headers and free-text bodies. This
 * is heuristic, not a guarantee — always let a human review before
 * trusting the result.
 */
class MessageFieldExtractor {
  /**
   * @param {string} text Combined inbound email body text (any language).
   * @param {string=} fromHeader Raw "From" header of the first inbound message, e.g. "Jane Doe <jane@example.com>".
   * @return {{firstName: string, lastName: string, phone: string, postalCode: string, country: string, address: string, serialNumber: string}}
   */
  static extract(text, fromHeader) {
    const body = String(text || '');
    const name = MessageFieldExtractor.extractName_(String(fromHeader || ''), body);
    const serialNumber = MessageFieldExtractor.extractSerialNumber_(body);
    const bodyWithoutSerial = serialNumber
      ? body.replace(/\bPP[\s_-]?\d{2}[\s_-]\d{3}[\s_-]\d{5}\b/i, ' ')
      : body;
    return {
      firstName: name.firstName,
      lastName: name.lastName,
      phone: MessageFieldExtractor.extractPhone_(bodyWithoutSerial),
      postalCode: MessageFieldExtractor.extractPostalCode_(bodyWithoutSerial),
      country: MessageFieldExtractor.extractCountry_(body),
      address: MessageFieldExtractor.extractAddress_(bodyWithoutSerial),
      serialNumber: serialNumber
    };
  }

  /**
   * Recognizes PocketPiano serial numbers in the app's canonical format
   * (PP-YY-WWW-NNNNN), tolerating spaces or underscores customers might type.
   * @param {string} text
   * @return {string}
   * @private
   */
  static extractSerialNumber_(text) {
    const match = text.match(/\bPP[\s_-]?(\d{2})[\s_-](\d{3})[\s_-](\d{5})\b/i);
    if (!match) return '';
    const candidate = 'PP-' + match[1] + '-' + match[2] + '-' + match[3];
    return SerialNumberService.isValid(candidate) ? candidate : '';
  }

  /**
   * Prefers the display name from the "From" header (most reliable source).
   * Falls back to a signature line at the end of the body (e.g. "Best, Jane Doe").
   * @param {string} fromHeader
   * @param {string} body
   * @return {{firstName: string, lastName: string}}
   * @private
   */
  static extractName_(fromHeader, body) {
    const headerMatch = fromHeader.match(/^\s*"?([^"<]{2,60}?)"?\s*<[^>]+>/);
    let fullName = headerMatch ? headerMatch[1].trim() : '';

    if (!fullName || /@/.test(fullName)) {
      const signOffs = /(?:regards|best|thanks|thank you|sincerely|cordialement|saludos|un saludo|cumprimentos|met vriendelijke groet|mit freundlichen gr[uü][ßs]en|distinti saluti|pozdrawiam|hälsningar)[,:]?\s*\n+\s*([A-ZÀ-ÖØ-Þ][\p{L}'-]+(?:\s+[A-ZÀ-ÖØ-Þ][\p{L}'-]+){0,2})\s*$/imu;
      const match = body.match(signOffs);
      if (match) fullName = match[1].trim();
    }

    if (!fullName) return {firstName: '', lastName: ''};
    const parts = fullName.split(/\s+/).filter(Boolean);
    return {
      firstName: parts[0] || '',
      lastName: parts.length > 1 ? parts.slice(1).join(' ') : ''
    };
  }

  /**
   * Looks for a phone number, preferring one that appears near a labelling
   * word (tel, phone, número, telefon...) to avoid grabbing order numbers
   * or other unrelated digit strings.
   * @param {string} text
   * @return {string}
   * @private
   */
  static extractPhone_(text) {
    const candidates = text.match(/(\+?\d[\d\s().-]{7,17}\d)/g) || [];
    const valid = candidates
      .map(function(raw) { return raw.trim(); })
      .filter(function(raw) {
        const digitCount = raw.replace(/\D/g, '').length;
        if (digitCount < 8 || digitCount > 15) return false;
        // Reject obviously-fake sequences like 000000000 or 123456789.
        const digitsOnly = raw.replace(/\D/g, '');
        if (/^(\d)\1+$/.test(digitsOnly)) return false;
        return true;
      });
    if (!valid.length) return '';

    const labelPattern = /(tel[eé]fono|phone|tel\.?|num[eé]ro|telefon|numero di telefono|telefonnummer)\s*[:\-]?\s*/i;
    for (let i = 0; i < valid.length; i += 1) {
      const index = text.indexOf(valid[i]);
      const before = text.slice(Math.max(0, index - 25), index);
      if (labelPattern.test(before)) return valid[i];
    }
    return valid[0];
  }

  /**
   * @param {string} text
   * @return {string}
   * @private
   */
  static extractPostalCode_(text) {
    const labelPattern = /(postal\s*code|c[oó]digo\s*postal|code\s*postal|postleitzahl|plz|postnummer|kod\s*pocztowy|postcode|zip)\s*[:\-]?\s*([A-Z0-9][A-Z0-9\s-]{2,9})/i;
    const labelled = text.match(labelPattern);
    if (labelled) return labelled[2].trim();

    const patterns = [
      /\b([A-Z]{1,2}\d[A-Z\d]?\s?\d[A-Z]{2})\b/,   // UK style
      /\b(\d{5}-\d{3})\b/,                          // BR style
      /\b(\d{2}-\d{3})\b/,                          // PL style
      /\b(\d{4,6})\b/                                // ES/generic numeric
    ];
    for (let i = 0; i < patterns.length; i += 1) {
      const match = text.match(patterns[i]);
      if (match) return match[1];
    }
    return '';
  }

  /** @param {string} text @return {string} @private */
  static extractCountry_(text) {
    const countries = {
      'spain': 'España', 'españa': 'España', 'espana': 'España',
      'united kingdom': 'United Kingdom', 'uk': 'United Kingdom', 'england': 'United Kingdom', 'great britain': 'United Kingdom',
      'france': 'France', 'francia': 'France',
      'germany': 'Deutschland', 'deutschland': 'Deutschland', 'alemania': 'Deutschland',
      'italy': 'Italia', 'italia': 'Italia',
      'portugal': 'Portugal',
      'netherlands': 'Nederland', 'nederland': 'Nederland', 'holanda': 'Nederland', 'holland': 'Nederland',
      'poland': 'Polska', 'polska': 'Polska', 'polonia': 'Polska',
      'sweden': 'Sverige', 'sverige': 'Sverige', 'suecia': 'Sverige',
      'japan': '日本', '日本': '日本',
      'korea': '대한민국', '대한민국': '대한민국', 'south korea': '대한민국',
      'belgium': 'België', 'belgique': 'België', 'bélgica': 'België',
      'ireland': 'Ireland', 'irlanda': 'Ireland',
      'austria': 'Österreich', 'österreich': 'Österreich',
      'switzerland': 'Schweiz', 'suiza': 'Schweiz',
      'denmark': 'Danmark', 'dinamarca': 'Danmark',
      'norway': 'Norge', 'noruega': 'Norge',
      'finland': 'Suomi', 'finlandia': 'Suomi',
      'united states': 'United States', 'usa': 'United States', 'estados unidos': 'United States'
    };
    const lower = text.toLowerCase();
    const found = Object.keys(countries)
      .filter(function(key) { return new RegExp('\\b' + key + '\\b').test(lower); })
      .sort(function(a, b) { return b.length - a.length; });
    return found.length ? countries[found[0]] : '';
  }

  /**
   * Looks for a short block of 1-3 consecutive lines that reads like a
   * postal address (contains a street-type word and at least one digit).
   * @param {string} text
   * @return {string}
   * @private
   */
  static extractAddress_(text) {
    const lines = text.split(/\n+/).map(function(line) { return line.trim(); }).filter(Boolean);
    const addressWords = /\b(calle|avenida|avda|c\/|street|st\.|road|rd\.|avenue|ave\.|rue|via|viale|rua|ulica|ul\.)\b|[\wäöüß]*stra(?:ß|ss)e\b|[\wäöü]*straat\b|[\wäöü]*laan\b|[\wäö]*v[aä]gen\b|[\wäö]*gata\b/i;
    const labelPrefix = /^[\p{L}\s]{2,30}:\s*/u;
    const otherFieldLine = /(tel[eé]fono|phone|tel\.?|telefon|num[eé]ro|e-?mail)\s*[:\-]/i;

    for (let i = 0; i < lines.length; i += 1) {
      const raw = lines[i];
      if (raw.length > 6 && raw.length < 100 && addressWords.test(raw) && /\d/.test(raw) && !otherFieldLine.test(raw.split(addressWords)[0] || '')) {
        const line = raw.replace(labelPrefix, '');
        const block = [line];
        const next = lines[i + 1];
        if (next && next.length < 80 && /\d/.test(next) && !addressWords.test(next) && !otherFieldLine.test(next)) {
          block.push(next);
        }
        return block.join(', ');
      }
    }
    return '';
  }

  /**
   * Suggests which catalog entries (errors or solutions) might apply to a
   * ticket, based on simple keyword overlap between each entry's code and
   * description and the message text. Best-effort — always let the agent
   * confirm before adding a suggestion.
   * @param {string} text
   * @param {Array<{code: string, description: string}>} catalog
   * @return {Array<string>} matched codes, most relevant first
   * @private-static
   */
  static suggestCatalogMatches(text, catalog) {
    const lower = String(text || '').toLowerCase();
    if (!lower || !catalog || !catalog.length) return [];

    const stopWords = {
      'the': 1, 'and': 1, 'for': 1, 'with': 1, 'from': 1, 'this': 1, 'that': 1,
      'para': 1, 'con': 1, 'del': 1, 'las': 1, 'los': 1, 'una': 1, 'unos': 1, 'que': 1
    };

    const scored = catalog.map(function(entry) {
      const codeWords = String(entry.code || '').toLowerCase().split(/[_\s-]+/);
      const descWords = String(entry.description || '').toLowerCase().split(/\W+/);
      const words = codeWords.concat(descWords)
        .filter(function(word) { return word.length > 3 && !stopWords[word]; });

      let score = 0;
      words.forEach(function(word) {
        if (lower.indexOf(word) !== -1) score += 1;
      });
      return {code: entry.code, score: score};
    });

    return scored
      .filter(function(item) { return item.score > 0; })
      .sort(function(a, b) { return b.score - a.score; })
      .map(function(item) { return item.code; });
  }
}
'@
[System.IO.File]::WriteAllText((Join-Path $root "src\extraction.gs"), $v0, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo src\uiActions.gs..." -ForegroundColor Cyan
$v1 = @'
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
    const ticketFieldNames = ['status', 'priority', 'category', 'assignedTo', 'tags', 'notes', 'detectedErrors', 'detectedSolutions',
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
        customerCount: customerCount
      }
    };
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
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
[System.IO.File]::WriteAllText((Join-Path $root "src\uiActions.gs"), $v1, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo html\CustomerShippingActions.html..." -ForegroundColor Cyan
$v2 = @'
<script>
(function () {
  'use strict';

  function fillIfEmpty(id, value) {
    if (!value) return false;
    const node = document.getElementById(id);
    if (!node || node.value.trim()) return false;
    node.value = value;
    return true;
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

  function showSnack(message) {
    const snackbar = document.getElementById('snackbar');
    if (!snackbar) return;
    snackbar.textContent = message;
    snackbar.hidden = false;
    window.setTimeout(function () { snackbar.hidden = true; }, 6000);
  }

  async function extractFromMessages(ticketId, button) {
    button.disabled = true;
    const previous = button.textContent;
    button.textContent = 'Analizando\u2026';
    try {
      const extracted = await unwrap(await callServer('extractUiFieldsFromMessages', ticketId));
      let filled = 0;
      if (fillIfEmpty('cs-first-name', extracted.firstName)) filled += 1;
      if (fillIfEmpty('cs-last-name', extracted.lastName)) filled += 1;
      if (fillIfEmpty('cs-phone', extracted.phone)) filled += 1;
      if (fillIfEmpty('cs-postal-code', extracted.postalCode)) filled += 1;
      if (fillIfEmpty('cs-country', extracted.country)) filled += 1;
      if (fillIfEmpty('cs-address', extracted.address)) filled += 1;
      if (extracted.serialNumber && fillIfEmpty('ticket-notes', 'Número de serie detectado: ' + extracted.serialNumber)) filled += 1;

      const parts = [];
      parts.push(filled ? 'Se han rellenado ' + filled + ' campos desde los mensajes.' : 'No se encontraron datos nuevos en los mensajes.');
      if (extracted.suggestedErrors && extracted.suggestedErrors.length) {
        parts.push('Posibles errores: ' + extracted.suggestedErrors.join(', ') + ' (añádelos con el + si corresponde).');
      }
      if (extracted.suggestedSolutions && extracted.suggestedSolutions.length) {
        parts.push('Posibles soluciones: ' + extracted.suggestedSolutions.join(', ') + '.');
      }
      showSnack(parts.join(' '));
    } catch (error) {
      showSnack(error && error.message ? error.message : String(error));
    } finally {
      button.disabled = false;
      button.textContent = previous;
    }
  }

  function selectedTicketId() {
    const selected = document.querySelector('[data-ticket-id].is-selected');
    if (selected && selected.dataset.ticketId) return selected.dataset.ticketId;
    const eyebrow = document.querySelector('#ticket-detail .detail-header .eyebrow');
    return eyebrow ? eyebrow.textContent.trim() : '';
  }

  function currentDetail() {
    return window.__ticketDetail || {};
  }

  function injectStyles() {
    if (document.getElementById('customer-shipping-styles')) return;
    const style = document.createElement('style');
    style.id = 'customer-shipping-styles';
    style.textContent = [
      '.customer-shipping-actions { display: grid; grid-template-columns: repeat(3, minmax(140px, 1fr)); gap: 12px; margin-top: 12px; padding: 14px; border-radius: 16px; background: var(--surface-container); }',
      '.customer-shipping-actions .section-label { grid-column: 1 / -1; margin: 4px 0 0; font-size: 11px; font-weight: 800; text-transform: uppercase; letter-spacing: .04em; color: var(--on-surface-variant); }',
      '.customer-shipping-actions .section-label:first-child { margin-top: 0; }',
      '.cs-field { display: grid; gap: 7px; min-width: 0; color: var(--on-surface-variant); font-size: 12px; font-weight: 800; text-transform: uppercase; }',
      '.cs-field-wide { grid-column: 1 / -1; }',
      '.cs-field input { width: 100%; min-height: 40px; padding: 0 12px; border: 1px solid var(--outline); border-radius: 12px; color: var(--on-surface); background: var(--surface-bright); font: inherit; text-transform: none; font-weight: 400; }',
      '.cs-extract-row { grid-column: 1 / -1; display: flex; justify-content: flex-end; }',
      '@media (max-width: 700px) { .customer-shipping-actions { grid-template-columns: 1fr; } }'
    ].join('\n');
    document.head.appendChild(style);
  }

  function createField(fieldId, name, value, placeholder, wide) {
    const label = document.createElement('label');
    label.className = wide ? 'cs-field cs-field-wide' : 'cs-field';
    const caption = document.createElement('span');
    caption.textContent = name;
    const input = document.createElement('input');
    input.type = 'text';
    input.id = fieldId;
    input.value = value || '';
    input.defaultValue = input.value;
    input.placeholder = placeholder || '';
    label.appendChild(caption);
    label.appendChild(input);
    return label;
  }

  function sectionLabel(text) {
    const span = document.createElement('span');
    span.className = 'section-label';
    span.textContent = text;
    return span;
  }

  function ensureCustomerShippingControls() {
    injectStyles();
    const header = document.querySelector('#ticket-detail .detail-header');
    if (!header || header.querySelector('.customer-shipping-actions')) return;
    const ticketId = selectedTicketId();
    if (!ticketId) return;

    const detail = currentDetail();
    const ticket = detail.ticket || {};
    const customer = detail.customer || {};

    const wrap = document.createElement('div');
    wrap.className = 'customer-shipping-actions';

    const extractRow = document.createElement('div');
    extractRow.className = 'cs-extract-row';
    const extractButton = document.createElement('button');
    extractButton.type = 'button';
    extractButton.className = 'text-button';
    extractButton.textContent = 'Extraer datos de los mensajes';
    extractButton.addEventListener('click', function () { extractFromMessages(ticketId, extractButton); });
    extractRow.appendChild(extractButton);
    wrap.appendChild(extractRow);

    wrap.appendChild(sectionLabel('Cliente'));
    wrap.appendChild(createField('cs-first-name', 'Nombre', customer.firstName, 'Jane'));
    wrap.appendChild(createField('cs-last-name', 'Apellidos', customer.lastName, 'Doe'));
    wrap.appendChild(createField('cs-phone', 'Teléfono', customer.phone, '+34 600 000 000'));
    wrap.appendChild(createField('cs-address', 'Dirección', customer.address, 'Calle, ciudad, código postal', true));
    wrap.appendChild(createField('cs-country', 'País', customer.country, 'España'));
    wrap.appendChild(createField('cs-postal-code', 'Código postal', customer.postalCode, '08001'));

    wrap.appendChild(sectionLabel('Envío'));
    wrap.appendChild(createField('cs-recipient-first-name', 'Nombre del destinatario', ticket.shippingRecipientFirstName, 'Quién recibe el paquete'));
    wrap.appendChild(createField('cs-recipient-last-name', 'Apellidos del destinatario', ticket.shippingRecipientLastName, ''));
    wrap.appendChild(createField('cs-recipient-phone', 'Teléfono del destinatario', ticket.shippingRecipientPhone, 'Teléfono de contacto'));
    wrap.appendChild(createField('cs-shipping-address', 'Dirección de envío', ticket.shippingAddress, 'Si es distinta de la dirección del cliente', true));
    wrap.appendChild(createField('cs-recipient-country', 'País del destinatario', ticket.shippingRecipientCountry, 'España'));
    wrap.appendChild(createField('cs-recipient-postal-code', 'Código postal del destinatario', ticket.shippingRecipientPostalCode, '08001'));

    header.appendChild(wrap);
  }

  const observer = new MutationObserver(function () {
    ensureCustomerShippingControls();
  });

  function start() {
    const panel = document.getElementById('ticket-detail');
    if (!panel) return;
    observer.observe(panel, {childList: true, subtree: true});
    ensureCustomerShippingControls();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }
})();
</script>
'@
[System.IO.File]::WriteAllText((Join-Path $root "html\CustomerShippingActions.html"), $v2, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host ""
Write-Host "Verificando..." -ForegroundColor Cyan
Select-String -Path src\extraction.gs -Pattern "extractSerialNumber_"
Select-String -Path src\extraction.gs -Pattern "suggestCatalogMatches"

Write-Host ""
Write-Host "Si salieron lineas arriba, ejecuta: npm test  y  npm run deploy" -ForegroundColor Cyan
