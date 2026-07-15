/** Ticket lifecycle validation and SLA policy. */
class TicketPolicy {
  /** @param {{get: function(string, *=): *}} settings */
  constructor(settings) {
    this.settings_ = settings;
  }

  /** @return {Array<string>} */
  static statuses() {
    return ['NEW', 'OPEN', 'PENDING_CUSTOMER', 'RESOLVED', 'CLOSED'];
  }

  /** @return {Array<string>} */
  static priorities() {
    return ['LOW', 'NORMAL', 'HIGH', 'CRITICAL'];
  }

  /** @return {Array<string>} */
  static categories() {
    return ['GENERAL', 'TECHNICAL', 'WARRANTY', 'SHIPPING', 'BILLING', 'PRODUCT', 'OTHER'];
  }

  /**
   * @param {string} value
   * @param {Array<string>} allowed
   * @param {string} field
   * @param {string=} fallback
   * @return {string}
   */
  static enumValue(value, allowed, field, fallback) {
    const normalized = String(value || fallback || '').trim().toUpperCase();
    if (allowed.indexOf(normalized) === -1) {
      throw new Error('Invalid ticket ' + field + ': ' + value);
    }
    return normalized;
  }

  /** @param {string} priority @return {number} */
  slaHours(priority) {
    const normalized = TicketPolicy.enumValue(priority, TicketPolicy.priorities(), 'priority', 'NORMAL');
    const defaults = {LOW: 72, NORMAL: 48, HIGH: 12, CRITICAL: 4};
    const configured = Number(this.settings_.get('SLA_' + normalized + '_HOURS', String(defaults[normalized])));
    if (!Number.isFinite(configured) || configured <= 0) {
      throw new Error('SLA_' + normalized + '_HOURS must be a positive number.');
    }
    return configured;
  }

  /**
   * @param {Date} createdAt
   * @param {string} priority
   * @return {Date}
   */
  calculateDueAt(createdAt, priority) {
    const start = new Date(createdAt);
    if (Number.isNaN(start.getTime())) {
      throw new Error('A valid ticket creation date is required.');
    }
    return new Date(start.getTime() + this.slaHours(priority) * 60 * 60 * 1000);
  }

  /** @return {TicketPolicy} */
  static fromAppConfig() {
    return new TicketPolicy({
      get: function(key, fallback) { return AppConfig.getSetting(key, fallback); }
    });
  }
}

/** Atomic, year-scoped human-readable ticket numbering. */
class TicketNumberService {
  /**
   * Returns the next number. The caller must hold the script lock.
   * @param {Date=} date
   * @return {string}
   */
  static nextUnlocked_(date) {
    const now = date || new Date();
    const year = Utilities.formatDate(now, Session.getScriptTimeZone(), 'yyyy');
    const prefix = String(AppConfig.getSetting('TICKET_NUMBER_PREFIX', 'PP'))
      .replace(/[^A-Za-z0-9]/g, '').toUpperCase().slice(0, 8) || 'PP';
    const key = 'TICKET_SEQUENCE_' + year;
    const properties = AppConfig.getProperties();
    let sequence = Number(properties.getProperty(key));
    if (!Number.isInteger(sequence) || sequence < 0) {
      sequence = TicketNumberService.maxExisting_(prefix, year);
    }
    sequence += 1;
    properties.setProperty(key, String(sequence));
    return TicketNumberService.format(prefix, year, sequence);
  }

  /**
   * @param {string} prefix
   * @param {string|number} year
   * @param {number} sequence
   * @return {string}
   */
  static format(prefix, year, sequence) {
    if (!Number.isInteger(sequence) || sequence < 1) {
      throw new Error('Ticket sequence must be a positive integer.');
    }
    return String(prefix) + '-' + String(year) + '-' + String(sequence).padStart(6, '0');
  }

  /** @param {string} prefix @param {string} year @return {number} @private */
  static maxExisting_(prefix, year) {
    const sheet = AppConfig.getSheet(APP.SHEETS.TICKETS);
    if (sheet.getLastRow() <= 1) {
      return 0;
    }
    const pattern = new RegExp('^' + prefix + '-' + year + '-(\\d{6,})$');
    return sheet.getRange(2, 1, sheet.getLastRow() - 1, 1).getDisplayValues()
      .reduce(function(maximum, row) {
        const match = String(row[0]).match(pattern);
        return match ? Math.max(maximum, Number(match[1])) : maximum;
      }, 0);
  }
}

/** Pure ticket aggregate metrics used by the Dashboard. */
class TicketMetrics {
  /**
   * @param {Array<Object>} tickets
   * @param {Date} now
   * @return {Object}
   */
  static calculate(tickets, now) {
    const metrics = {
      total: tickets.length,
      active: 0,
      breached: 0,
      byStatus: {},
      byPriority: {},
      byCategory: {}
    };
    TicketPolicy.statuses().forEach(function(value) { metrics.byStatus[value] = 0; });
    TicketPolicy.priorities().forEach(function(value) { metrics.byPriority[value] = 0; });
    TicketPolicy.categories().forEach(function(value) { metrics.byCategory[value] = 0; });

    tickets.forEach(function(ticket) {
      const status = String(ticket.status || 'NEW').toUpperCase();
      const priority = String(ticket.priority || 'NORMAL').toUpperCase();
      const category = String(ticket.category || 'GENERAL').toUpperCase();
      metrics.byStatus[status] = (metrics.byStatus[status] || 0) + 1;
      metrics.byPriority[priority] = (metrics.byPriority[priority] || 0) + 1;
      metrics.byCategory[category] = (metrics.byCategory[category] || 0) + 1;
      if (['NEW', 'OPEN', 'PENDING_CUSTOMER'].indexOf(status) !== -1) {
        metrics.active += 1;
        const due = ticket.slaDueAt instanceof Date ? ticket.slaDueAt : new Date(ticket.slaDueAt);
        if (!Number.isNaN(due.getTime()) && due < now) {
          metrics.breached += 1;
        }
      }
    });
    return metrics;
  }
}

/** Writes deterministic ticket metrics to the Dashboard sheet. */
class TicketDashboardService {
  /**
   * @param {Object} repository
   * @param {GoogleAppsScript.Spreadsheet.Sheet} sheet
   * @param {function(): Date=} clock
   */
  constructor(repository, sheet, clock) {
    this.repository_ = repository;
    this.sheet_ = sheet;
    this.clock_ = clock || function() { return new Date(); };
  }

  /** @return {Object} */
  refresh() {
    const now = this.clock_();
    const metrics = TicketMetrics.calculate(this.repository_.listAll(), now);
    const rows = [
      ['Application Version', APP_VERSION, now],
      ['Installation Status', 'READY', now],
      ['Total Tickets', metrics.total, now],
      ['Active Tickets', metrics.active, now],
      ['SLA Breached', metrics.breached, now]
    ];
    TicketPolicy.statuses().forEach(function(status) {
      rows.push(['Status: ' + status, metrics.byStatus[status] || 0, now]);
    });
    TicketPolicy.priorities().forEach(function(priority) {
      rows.push(['Priority: ' + priority, metrics.byPriority[priority] || 0, now]);
    });
    TicketPolicy.categories().forEach(function(category) {
      rows.push(['Category: ' + category, metrics.byCategory[category] || 0, now]);
    });

    if (this.sheet_.getLastRow() > 1) {
      this.sheet_.getRange(2, 1, this.sheet_.getLastRow() - 1, 3).clearContent();
    }
    this.sheet_.getRange(2, 1, rows.length, 3).setValues(rows);
    return metrics;
  }
}

/** Application service for ticket generation, lifecycle, and discovery. */
class TicketManager {
  /**
   * @param {{
   *   repository: Object,
   *   numberGenerator: function(): string,
   *   policy: TicketPolicy,
   *   dashboard: Object,
   *   clock: function(): Date,
   *   version: string,
   *   logger: Object
   * }} dependencies
   */
  constructor(dependencies) {
    ['repository', 'numberGenerator', 'policy', 'dashboard', 'clock', 'version', 'logger']
      .forEach(function(name) {
        if (!dependencies || dependencies[name] == null) {
          throw new Error('Missing TicketManager dependency: ' + name);
        }
      });
    this.repository_ = dependencies.repository;
    this.numberGenerator_ = dependencies.numberGenerator;
    this.policy_ = dependencies.policy;
    this.dashboard_ = dependencies.dashboard;
    this.clock_ = dependencies.clock;
    this.version_ = dependencies.version;
    this.logger_ = dependencies.logger;
  }

  /** @param {Object} input @return {Object} */
  create(input) {
    const data = input || {};
    const subject = String(data.subject || '').trim();
    const customerEmail = String(data.customerEmail || '').trim().toLowerCase();
    if (!subject) {
      throw new Error('Ticket subject is required.');
    }
    if (!customerEmail) {
      throw new Error('Customer email is required.');
    }

    const createdAt = this.clock_();
    const priority = TicketPolicy.enumValue(data.priority, TicketPolicy.priorities(), 'priority', 'NORMAL');
    const record = {
      id: this.numberGenerator_(),
      status: TicketPolicy.enumValue(data.status, TicketPolicy.statuses(), 'status', 'NEW'),
      priority: priority,
      category: TicketPolicy.enumValue(data.category, TicketPolicy.categories(), 'category', 'GENERAL'),
      subject: subject,
      customerId: String(data.customerId || ''),
      customerEmail: customerEmail,
      threadId: String(data.threadId || ''),
      assignedTo: String(data.assignedTo || ''),
      createdAt: createdAt,
      updatedAt: createdAt,
      lastMessageAt: data.lastMessageAt ? new Date(data.lastMessageAt) : createdAt,
      slaDueAt: this.policy_.calculateDueAt(createdAt, priority),
      driveFolderId: String(data.driveFolderId || ''),
      tags: TicketManager.normalizeTags_(data.tags),
      version: this.version_,
      shippingAddress: String(data.shippingAddress || ''),
      shippingRecipient: String(data.shippingRecipient || ''),
      shippingRecipientPhone: String(data.shippingRecipientPhone || ''),
      shippingRecipientFirstName: String(data.shippingRecipientFirstName || ''),
      shippingRecipientLastName: String(data.shippingRecipientLastName || ''),
      shippingRecipientCountry: String(data.shippingRecipientCountry || ''),
      shippingRecipientPostalCode: String(data.shippingRecipientPostalCode || ''),
      notes: String(data.notes || ''),
      detectedErrors: String(data.detectedErrors || ''),
      detectedSolutions: String(data.detectedSolutions || ''),
      orderNumber: String(data.orderNumber || ''),
      serialNumber: SerialNumberService.normalize(data.serialNumber || ''),
      statusChangedAt: this.clock_(),
      priorityChangedAt: this.clock_(),
      categoryChangedAt: this.clock_()
    };
    const created = this.repository_.create(record);
    this.dashboard_.refresh();
    this.logger_.info('Ticket created.', {ticketId: created.id});
    return created;
  }

  /** @param {string} ticketId @param {string} status @return {Object} */
  updateStatus(ticketId, status) {
    const normalized = TicketPolicy.enumValue(status, TicketPolicy.statuses(), 'status');
    const updated = this.repository_.update(ticketId, {
      status: normalized,
      updatedAt: this.clock_(),
      version: this.version_
    });
    this.dashboard_.refresh();
    this.logger_.info('Ticket status updated.', {ticketId: ticketId, status: normalized});
    return updated;
  }

  /** @param {string} ticketId @param {string} priority @return {Object} */
  updatePriority(ticketId, priority) {
    const normalized = TicketPolicy.enumValue(priority, TicketPolicy.priorities(), 'priority');
    const ticket = this.repository_.findById(ticketId);
    if (!ticket) {
      throw new Error('Ticket not found: ' + ticketId);
    }
    const updated = this.repository_.update(ticketId, {
      priority: normalized,
      slaDueAt: this.policy_.calculateDueAt(ticket.createdAt, normalized),
      updatedAt: this.clock_(),
      version: this.version_
    });
    this.dashboard_.refresh();
    this.logger_.info('Ticket priority updated.', {ticketId: ticketId, priority: normalized});
    return updated;
  }

  /** @param {string} ticketId @param {string} category @return {Object} */
  updateCategory(ticketId, category) {
    const normalized = TicketPolicy.enumValue(category, TicketPolicy.categories(), 'category');
    const updated = this.repository_.update(ticketId, {
      category: normalized,
      updatedAt: this.clock_(),
      version: this.version_
    });
    this.dashboard_.refresh();
    this.logger_.info('Ticket category updated.', {ticketId: ticketId, category: normalized});
    return updated;
  }

  /** @param {string} ticketId @param {string} assignedTo @return {Object} */
  assign(ticketId, assignedTo) {
    const normalized = String(assignedTo || '').trim();
    const updated = this.repository_.update(ticketId, {
      assignedTo: normalized,
      updatedAt: this.clock_(),
      version: this.version_
    });
    this.dashboard_.refresh();
    this.logger_.info('Ticket assigned.', {ticketId: ticketId, assignedTo: normalized});
    return updated;
  }

  /** @param {string} ticketId @param {*=} tags @return {Object} */
  updateTags(ticketId, tags) {
    const normalized = TicketManager.normalizeTags_(tags);
    const updated = this.repository_.update(ticketId, {
      tags: normalized,
      updatedAt: this.clock_(),
      version: this.version_
    });
    this.dashboard_.refresh();
    this.logger_.info('Ticket tags updated.', {ticketId: ticketId, tags: normalized});
    return updated;
  }

  /**
   * @param {string} ticketId
   * @param {{shippingAddress: string=, shippingRecipient: string=, shippingRecipientPhone: string=}} shipping
   * @return {Object}
   */
  updateShipping(ticketId, shipping) {
    const data = shipping || {};
    const changes = {updatedAt: this.clock_(), version: this.version_};
    ['shippingAddress', 'shippingRecipient', 'shippingRecipientPhone',
      'shippingRecipientFirstName', 'shippingRecipientLastName',
      'shippingRecipientCountry', 'shippingRecipientPostalCode'].forEach(function(field) {
      if (Object.prototype.hasOwnProperty.call(data, field)) {
        changes[field] = String(data[field] || '').trim();
      }
    });
    const updated = this.repository_.update(ticketId, changes);
    this.dashboard_.refresh();
    this.logger_.info('Ticket shipping info updated.', {ticketId: ticketId});
    return updated;
  }

  /**
   * Applies status/priority/category/assignee/tags/shipping changes in a
   * single repository write, instead of one round trip per field.
   * @param {string} ticketId
   * @param {Object} changes
   * @return {Object}
   */
  updateAll(ticketId, changes) {
    const data = changes || {};
    const updates = {updatedAt: this.clock_(), version: this.version_};
    let ticket = null;

    if (Object.prototype.hasOwnProperty.call(data, 'status') || Object.prototype.hasOwnProperty.call(data, 'priority') || Object.prototype.hasOwnProperty.call(data, 'category')) {
      ticket = ticket || this.repository_.findById(ticketId);
      if (!ticket) throw new Error('Ticket not found: ' + ticketId);
    }

    if (Object.prototype.hasOwnProperty.call(data, 'status')) {
      updates.status = TicketPolicy.enumValue(data.status, TicketPolicy.statuses(), 'status');
      if (updates.status !== ticket.status) {
        updates.statusChangedAt = this.clock_();
      }
    }
    if (Object.prototype.hasOwnProperty.call(data, 'priority')) {
      updates.priority = TicketPolicy.enumValue(data.priority, TicketPolicy.priorities(), 'priority');
      updates.slaDueAt = this.policy_.calculateDueAt(ticket.createdAt, updates.priority);
      if (updates.priority !== ticket.priority) {
        updates.priorityChangedAt = this.clock_();
      }
    }
    if (Object.prototype.hasOwnProperty.call(data, 'category')) {
      updates.category = TicketPolicy.enumValue(data.category, TicketPolicy.categories(), 'category');
      if (updates.category !== ticket.category) {
        updates.categoryChangedAt = this.clock_();
      }
    }
    if (Object.prototype.hasOwnProperty.call(data, 'assignedTo')) {
      updates.assignedTo = String(data.assignedTo || '').trim();
    }
    if (Object.prototype.hasOwnProperty.call(data, 'tags')) {
      updates.tags = TicketManager.normalizeTags_(data.tags);
    }
    if (Object.prototype.hasOwnProperty.call(data, 'notes')) {
      updates.notes = String(data.notes || '');
    }
    if (Object.prototype.hasOwnProperty.call(data, 'detectedErrors')) {
      updates.detectedErrors = TicketManager.normalizeTags_(data.detectedErrors);
    }
    if (Object.prototype.hasOwnProperty.call(data, 'detectedSolutions')) {
      updates.detectedSolutions = TicketManager.normalizeTags_(data.detectedSolutions);
    }
    if (Object.prototype.hasOwnProperty.call(data, 'orderNumber')) {
      updates.orderNumber = String(data.orderNumber || '').trim();
    }
    if (Object.prototype.hasOwnProperty.call(data, 'serialNumber')) {
      updates.serialNumber = SerialNumberService.normalize(data.serialNumber || '');
    }
    ['shippingAddress', 'shippingRecipient', 'shippingRecipientPhone',
      'shippingRecipientFirstName', 'shippingRecipientLastName',
      'shippingRecipientCountry', 'shippingRecipientPostalCode'].forEach(function(field) {
      if (Object.prototype.hasOwnProperty.call(data, field)) {
        updates[field] = String(data[field] || '').trim();
      }
    });

    const updated = this.repository_.update(ticketId, updates);
    this.dashboard_.refresh();
    this.logger_.info('Ticket updated in batch.', {ticketId: ticketId, fields: Object.keys(updates)});
    return updated;
  }

  /** @param {Object=} criteria @return {{items: Array<Object>, total: number, offset: number, limit: number}} */
  search(criteria) {
    return this.repository_.search(criteria || {});
  }

  /** @return {{statuses: Array<string>, priorities: Array<string>, categories: Array<string>}} */
  filters() {
    return {
      statuses: TicketPolicy.statuses(),
      priorities: TicketPolicy.priorities(),
      categories: TicketPolicy.categories()
    };
  }

  /** @param {*=} tags @return {string} @private */
  static normalizeTags_(tags) {
    const values = Array.isArray(tags) ? tags : String(tags || '').split(',');
    return values.map(function(tag) { return String(tag).trim(); })
      .filter(function(tag, index, all) { return tag && all.indexOf(tag) === index; })
      .join(', ');
  }
}

/** @return {TicketManager} @private */
function createTicketManager_() {
  const repository = new SheetTicketRepository();
  return new TicketManager({
    repository: repository,
    numberGenerator: function() { return TicketNumberService.nextUnlocked_(); },
    policy: TicketPolicy.fromAppConfig(),
    dashboard: new TicketDashboardService(
      repository,
      AppConfig.getSheet(APP.SHEETS.DASHBOARD),
      function() { return new Date(); }
    ),
    clock: function() { return new Date(); },
    version: APP_VERSION,
    logger: AppLogger
  });
}

/** @param {function(TicketManager): *} callback @return {*} @private */
function withTicketLock_(callback) {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(APP.LOCK_TIMEOUT_MS)) {
    throw new AppError('Another ticket operation is running.', 'TICKET_LOCK_TIMEOUT');
  }
  try {
    return callback(createTicketManager_());
  } finally {
    lock.releaseLock();
  }
}

/** @param {Object} input @return {Object} */
function createTicket(input) {
  return withTicketLock_(function(manager) { return manager.create(input); });
}

/** @param {string} ticketId @param {string} status @return {Object} */
function updateTicketStatus(ticketId, status) {
  return withTicketLock_(function(manager) { return manager.updateStatus(ticketId, status); });
}

/** @param {string} ticketId @param {string} priority @return {Object} */
function updateTicketPriority(ticketId, priority) {
  return withTicketLock_(function(manager) { return manager.updatePriority(ticketId, priority); });
}

/** @param {string} ticketId @param {string} category @return {Object} */
function updateTicketCategory(ticketId, category) {
  return withTicketLock_(function(manager) { return manager.updateCategory(ticketId, category); });
}

/** @param {string} ticketId @param {string} assignedTo @return {Object} */
function assignTicket(ticketId, assignedTo) {
  return withTicketLock_(function(manager) { return manager.assign(ticketId, assignedTo); });
}

/** @param {string} ticketId @param {*=} tags @return {Object} */
function updateTicketTags(ticketId, tags) {
  return withTicketLock_(function(manager) { return manager.updateTags(ticketId, tags); });
}

/** @param {string} ticketId @param {Object} shipping @return {Object} */
function updateTicketShipping(ticketId, shipping) {
  return withTicketLock_(function(manager) { return manager.updateShipping(ticketId, shipping); });
}

/** @param {string} ticketId @param {Object} changes @return {Object} */
function updateTicketAll(ticketId, changes) {
  return withTicketLock_(function(manager) { return manager.updateAll(ticketId, changes); });
}

/** @param {Object=} criteria @return {Object} */
function searchTickets(criteria) {
  return createTicketManager_().search(criteria || {});
}

/** @return {Object} */
function getTicketFilters() {
  return createTicketManager_().filters();
}

/** @return {Object} */
function refreshTicketDashboard() {
  const repository = new SheetTicketRepository();
  return new TicketDashboardService(
    repository,
    AppConfig.getSheet(APP.SHEETS.DASHBOARD),
    function() { return new Date(); }
  ).refresh();
}