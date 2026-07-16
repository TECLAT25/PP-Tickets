# add-void-status.ps1
# Nuevo estado "Nulo" (VOID) para tickets: excluido de "activos" y de
# la fusion automatica (igual que Cerrado), visible en desplegables,
# filtros y estadisticas.
$ErrorActionPreference = "Stop"
$root = Get-Location
$enc = New-Object System.Text.UTF8Encoding($false)

Write-Host "Escribiendo src\tickets.gs..." -ForegroundColor Cyan
$v0 = @'
/** Ticket lifecycle validation and SLA policy. */
class TicketPolicy {
  /** @param {{get: function(string, *=): *}} settings */
  constructor(settings) {
    this.settings_ = settings;
  }

  /** @return {Array<string>} */
  static statuses() {
    return ['NEW', 'OPEN', 'PENDING_CUSTOMER', 'RESOLVED', 'CLOSED', 'VOID'];
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
      shippingRecipientCity: String(data.shippingRecipientCity || ''),
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
      'shippingRecipientCountry', 'shippingRecipientPostalCode', 'shippingRecipientCity'].forEach(function(field) {
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
      'shippingRecipientCountry', 'shippingRecipientPostalCode', 'shippingRecipientCity'].forEach(function(field) {
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
'@
[System.IO.File]::WriteAllText((Join-Path $root "src\tickets.gs"), $v0, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo src\gmail.gs..." -ForegroundColor Cyan
$v1 = @'
/**
 * Synchronizes normalized Gmail threads with ticket and message repositories.
 * All infrastructure is injected so synchronization behavior can be tested
 * without Google services.
 */
class GmailSyncEngine {
  /**
   * @param {{
   *   gmailGateway: Object,
   *   ticketRepository: Object,
   *   messageRepository: Object,
   *   customerRepository: Object,
   *   attachmentStore: Object,
   *   settings: Object,
   *   ticketIdGenerator: function(): string,
   *   messageIdGenerator: function(): string,
   *   clock: function(): Date,
   *   logger: Object,
   *   version: string
   * }} dependencies
   */
  constructor(dependencies) {
    const required = [
      'gmailGateway', 'ticketRepository', 'messageRepository', 'customerRepository', 'attachmentStore',
      'settings', 'ticketIdGenerator', 'messageIdGenerator', 'clock', 'logger', 'version'
    ];
    required.forEach(function(name) {
      if (!dependencies || dependencies[name] == null) {
        throw new Error('Missing GmailSyncEngine dependency: ' + name);
      }
    });
    this.gmail_ = dependencies.gmailGateway;
    this.tickets_ = dependencies.ticketRepository;
    this.messages_ = dependencies.messageRepository;
    this.customers_ = dependencies.customerRepository;
    this.attachments_ = dependencies.attachmentStore;
    this.settings_ = dependencies.settings;
    this.ticketIdGenerator_ = dependencies.ticketIdGenerator;
    this.messageIdGenerator_ = dependencies.messageIdGenerator;
    this.clock_ = dependencies.clock;
    this.logger_ = dependencies.logger;
    this.version_ = dependencies.version;
  }

  /**
   * Executes one bounded synchronization pass.
   * @return {{threads: number, createdTickets: number, updatedTickets: number,
   *   createdMessages: number, duplicateMessages: number, attachments: number,
   *   customersUpserted: number, failedThreads: number}}
   */
  synchronize() {
    const mailbox = String(this.settings_.get('SUPPORT_EMAIL', 'support@pocketpiano.com')).toLowerCase();
    const baseQuery = this.settings_.get('SUPPORT_GMAIL_QUERY', 'in:anywhere newer_than:30d -in:drafts -in:spam -in:trash');
    const limit = Math.max(1, Math.min(500, Number(this.settings_.get('GMAIL_SYNC_LIMIT', '100')) || 100));
    this.gmail_.assertMailbox(mailbox);

    const query = String(baseQuery).trim() + ' {to:' + mailbox + ' from:' + mailbox + '}';
    const threads = this.gmail_.listThreads(query, limit);
    const summary = {
      threads: threads.length,
      createdTickets: 0,
      updatedTickets: 0,
      createdMessages: 0,
      duplicateMessages: 0,
      attachments: 0,
      customersUpserted: 0,
      failedThreads: 0,
      excludedThreads: 0,
      linkedTickets: 0,
      mergedTickets: 0
    };

    threads.forEach(function(thread) {
      try {
        this.synchronizeThread_(thread, mailbox, summary);
        this.gmail_.markProcessed(thread.id, this.settings_.get('SUPPORT_LABEL', 'PocketPiano/Processed'));
      } catch (error) {
        summary.failedThreads += 1;
        this.logger_.error('Gmail thread synchronization failed.', {
          threadId: thread && thread.id ? thread.id : '',
          error: error && error.message ? error.message : String(error),
          stack: error && error.stack ? error.stack : ''
        });
      }
    }, this);

    this.logger_.info('Gmail synchronization completed.', summary);
    return summary;
  }

  /**
   * @param {{id: string, messages: Array<Object>}} thread
   * @param {string} mailbox
   * @param {Object} summary
   * @private
   */
  synchronizeThread_(thread, mailbox, summary) {
    if (!thread || !thread.id || !Array.isArray(thread.messages) || thread.messages.length === 0) {
      throw new Error('Gmail returned an invalid or empty thread.');
    }

    const orderedMessages = thread.messages.slice().sort(function(left, right) {
      return new Date(left.date).getTime() - new Date(right.date).getTime();
    });
    const firstMessage = orderedMessages[0];
    const lastMessage = orderedMessages[orderedMessages.length - 1];
    const customerEmail = GmailSyncEngine.customerEmail_(orderedMessages, mailbox);

    if (GmailSyncEngine.isExcludedSender_(customerEmail, this.settings_)) {
      summary.excludedThreads = (summary.excludedThreads || 0) + 1;
      this.logger_.info('Gmail thread skipped: sender is excluded.', {threadId: thread.id, sender: customerEmail});
      return;
    }

    let ticket = this.tickets_.findByThreadId(thread.id);
    const customerName = GmailSyncEngine.customerName_(orderedMessages, mailbox);
    const customer = customerEmail ? this.customers_.upsertByEmail({
      email: customerEmail,
      name: customerName,
      notes: 'Created or updated from Gmail thread ' + thread.id
    }) : null;
    if (customer) {
      summary.customersUpserted += 1;
    }

    if (!ticket && customerEmail) {
      const mergeable = this.findMergeableTicket_(customerEmail);
      if (mergeable) {
        const mergeChanges = {updatedAt: this.clock_()};
        if (!mergeable.threadId) mergeChanges.threadId = thread.id;
        ticket = this.tickets_.update(mergeable.id, mergeChanges);
        if (!mergeable.threadId) {
          summary.linkedTickets = (summary.linkedTickets || 0) + 1;
          this.logger_.info('Linked an orphaned threadless ticket to its Gmail thread.', {ticketId: mergeable.id, threadId: thread.id});
        } else {
          summary.mergedTickets = (summary.mergedTickets || 0) + 1;
          this.logger_.info('Merged a new Gmail thread into an existing ticket with a matching subject.', {ticketId: mergeable.id, newThreadId: thread.id, originalThreadId: mergeable.threadId});
        }
      }
    }

    if (!ticket) {
      ticket = this.tickets_.create({
        id: this.ticketIdGenerator_(),
        threadId: thread.id,
        status: 'NEW',
        priority: 'NORMAL',
        subject: firstMessage.subject || '(no subject)',
        customerId: customer ? customer.id : '',
        customerEmail: customerEmail,
        createdAt: new Date(firstMessage.date),
        updatedAt: this.clock_(),
        lastMessageAt: new Date(lastMessage.date),
        version: this.version_
      });
      summary.createdTickets += 1;
    }

    let ticketFolderId = ticket.driveFolderId || '';
    orderedMessages.forEach(function(message) {
      if (this.messages_.hasMessage(message.id)) {
        summary.duplicateMessages += 1;
        return;
      }

      const stored = this.attachments_.save(ticket.id, message.id, message.attachments || []);
      ticketFolderId = stored.folderId || ticketFolderId;
      this.messages_.add({
        id: this.messageIdGenerator_(),
        ticketId: ticket.id,
        gmailMessageId: message.id,
        direction: GmailSyncEngine.direction_(message.from, mailbox),
        from: message.from || '',
        to: message.to || '',
        cc: message.cc || '',
        subject: message.subject || '',
        sentAt: new Date(message.date),
        bodyPreview: GmailSyncEngine.preview_(message.plainBody),
        bodyText: GmailSyncEngine.bodyText_(message.plainBody),
        attachmentCount: stored.count,
        driveFolderId: stored.folderId || '',
        createdAt: this.clock_()
      });
      summary.createdMessages += 1;
      summary.attachments += stored.count;
    }, this);

    this.tickets_.updateConversation(ticket, {
      status: GmailSyncEngine.nextStatus_(ticket.status, lastMessage.from, mailbox),
      subject: lastMessage.subject || ticket.subject || '(no subject)',
      customerId: ticket.customerId || (customer ? customer.id : ''),
      customerEmail: ticket.customerEmail || customerEmail,
      updatedAt: this.clock_(),
      lastMessageAt: new Date(lastMessage.date),
      driveFolderId: ticketFolderId,
      version: this.version_
    });
    summary.updatedTickets += 1;
  }

  /**
   * Finds an existing non-closed ticket for this customer, so a new Gmail
   * thread from them gets merged into it instead of creating a duplicate
   * ticket — regardless of subject. Closed tickets are excluded — a new
   * thread from a customer whose only tickets are closed still becomes
   * its own new ticket.
   * @param {string} customerEmail
   * @return {Object|null}
   * @private
   */
  findMergeableTicket_(customerEmail) {
    if (!customerEmail) return null;

    const result = this.tickets_.search({customerEmail: customerEmail, limit: 50});
    const candidates = result.items.filter(function(candidate) {
      return candidate.status !== 'CLOSED' && candidate.status !== 'VOID';
    });
    if (!candidates.length) return null;

    candidates.sort(function(left, right) {
      return new Date(right.createdAt).getTime() - new Date(left.createdAt).getTime();
    });
    return candidates[0];
  }

  /** @param {string} from @param {string} mailbox @return {string} @private */
  static direction_(from, mailbox) {
    return GmailSyncEngine.addresses_(from).indexOf(mailbox) !== -1 ? 'OUTBOUND' : 'INBOUND';
  }

  /**
   * @param {Array<Object>} messages
   * @param {string} mailbox
   * @return {string}
   * @private
   */
  static customerEmail_(messages, mailbox) {
    for (let index = 0; index < messages.length; index += 1) {
      const candidates = GmailSyncEngine.addresses_(messages[index].from)
        .concat(GmailSyncEngine.addresses_(messages[index].to));
      const customer = candidates.filter(function(address) { return address !== mailbox; })[0];
      if (customer) {
        return customer;
      }
    }
    return '';
  }

  /**
   * @param {Array<Object>} messages
   * @param {string} mailbox
   * @return {string}
   * @private
   */
  static customerName_(messages, mailbox) {
    for (let index = 0; index < messages.length; index += 1) {
      if (GmailSyncEngine.direction_(messages[index].from, mailbox) === 'INBOUND') {
        return GmailSyncEngine.displayName_(messages[index].from);
      }
    }
    return '';
  }

  /**
   * Checks a customer email against the EXCLUDED_SENDERS setting (comma
   * separated), so automated/notification senders never create tickets.
   * @param {string} email
   * @param {GmailSyncSettings} settings
   * @return {boolean}
   * @private
   */
  static isExcludedSender_(email, settings) {
    if (!email) return false;
    const configured = String(settings.get('EXCLUDED_SENDERS', 'no-reply@accounts.google.com, mbe@mbe3024.es') || '');
    const excluded = configured.split(',').map(function(value) { return value.trim().toLowerCase(); }).filter(Boolean);
    return excluded.indexOf(String(email).toLowerCase()) !== -1;
  }

  /** @param {string} value @return {Array<string>} @private */
  static addresses_(value) {
    const matches = String(value || '').toLowerCase().match(/[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9.-]+\.[a-z]{2,}/g);
    return matches || [];
  }

  /** @param {string} value @return {string} @private */
  static displayName_(value) {
    const raw = String(value || '').trim();
    const email = GmailSyncEngine.addresses_(raw)[0] || '';
    const withoutEmail = raw.replace(/<[^>]+>/g, '').replace(email, '').replace(/"/g, '').trim();
    return withoutEmail || '';
  }

  /** @param {*} body @return {string} @private */
  static preview_(body) {
    return String(body || '').replace(/\s+/g, ' ').trim().slice(0, 500);
  }

  /** Preserves readable conversation text within the Sheets cell limit. @param {*} body @return {string} @private */
  static bodyText_(body) {
    return String(body || '').replace(/\r\n/g, '\n').trim().slice(0, 40000);
  }

  /**
   * Reopens resolved conversations when a customer sends a new message.
   * @param {string} currentStatus
   * @param {string} lastFrom
   * @param {string} mailbox
   * @return {string}
   * @private
   */
  static nextStatus_(currentStatus, lastFrom, mailbox) {
    const inbound = GmailSyncEngine.direction_(lastFrom, mailbox) === 'INBOUND';
    if (inbound && (currentStatus === 'RESOLVED' || currentStatus === 'CLOSED')) {
      return 'OPEN';
    }
    return currentStatus || 'NEW';
  }
}

/** Google Apps Script adapter that normalizes Gmail service objects. */
class AppsScriptGmailGateway {
  /**
   * Ensures the effective account owns the support mailbox or alias.
   * @param {string} expectedMailbox
   */
  assertMailbox(expectedMailbox) {
    const effective = String(Session.getEffectiveUser().getEmail() || '').toLowerCase();
    const aliases = GmailApp.getAliases().map(function(alias) { return alias.toLowerCase(); });
    if (effective !== expectedMailbox && aliases.indexOf(expectedMailbox) === -1) {
      throw new AppError(
        'This script must run as ' + expectedMailbox + ' or an account that owns that alias.',
        'GMAIL_MAILBOX_MISMATCH',
        {effectiveUser: effective}
      );
    }
  }

  /**
   * @param {string} query
   * @param {number} limit
   * @return {Array<{id: string, messages: Array<Object>}>}
   */
  listThreads(query, limit) {
    const draftMessageIds = AppsScriptGmailGateway.draftMessageIds_();
    return GmailApp.search(query, 0, limit).map(function(thread) {
      return {
        id: thread.getId(),
        messages: thread.getMessages()
          .filter(function(message) { return !draftMessageIds.has(message.getId()); })
          .map(function(message) {
          return {
            id: message.getId(),
            from: message.getFrom(),
            to: message.getTo(),
            cc: message.getCc(),
            subject: message.getSubject(),
            date: message.getDate(),
            plainBody: message.getPlainBody(),
            attachments: message.getAttachments({
              includeInlineImages: false,
              includeAttachments: true
            }).map(function(attachment) {
              return {
                name: attachment.getName(),
                contentType: attachment.getContentType(),
                size: attachment.getSize(),
                blob: attachment.copyBlob()
              };
            })
          };
        })
      };
    });
  }

  /**
   * Returns the set of Gmail message IDs that are currently unsent drafts,
   * so they can be excluded from sync — only actually sent/received
   * messages should ever become ticket messages.
   * @return {Set<string>}
   * @private
   */
  static draftMessageIds_() {
    const ids = new Set();
    try {
      GmailApp.getDrafts().forEach(function(draft) {
        try {
          ids.add(draft.getMessage().getId());
        } catch (innerError) {
          // Skip drafts whose underlying message can't be read.
        }
      });
    } catch (error) {
      // If drafts can't be listed for any reason, fall back to no filtering
      // rather than failing the whole sync.
    }
    return ids;
  }

  /** @param {string} threadId @param {string} labelName */
  markProcessed(threadId, labelName) {
    let label = GmailApp.getUserLabelByName(labelName);
    if (!label) {
      label = GmailApp.createLabel(labelName);
    }
    GmailApp.getThreadById(threadId).addLabel(label);
  }
}

/** Script setting adapter used by the synchronization engine. */
class GmailSyncSettings {
  /** @param {string} key @param {*=} fallback @return {*} */
  get(key, fallback) {
    return AppConfig.getSetting(key, fallback);
  }
}

/**
 * Public synchronization entry point suitable for manual and trigger execution.
 * @return {Object}
 */
function syncGmail() {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(APP.LOCK_TIMEOUT_MS)) {
    throw new AppError('Another synchronization is already running.', 'GMAIL_SYNC_LOCK_TIMEOUT');
  }
  try {
    const engine = new GmailSyncEngine({
      gmailGateway: new AppsScriptGmailGateway(),
      ticketRepository: new SheetTicketRepository(),
      messageRepository: new SheetMessageRepository(),
      customerRepository: new SheetCustomerRepository(),
      attachmentStore: new DriveAttachmentStore(),
      settings: new GmailSyncSettings(),
      ticketIdGenerator: function() { return TicketNumberService.nextUnlocked_(); },
      messageIdGenerator: function() { return 'MSG-' + AppUtils.uuid(); },
      clock: function() { return new Date(); },
      logger: AppLogger,
      version: APP_VERSION
    });
    return engine.synchronize();
  } finally {
    lock.releaseLock();
  }
}
'@
[System.IO.File]::WriteAllText((Join-Path $root "src\gmail.gs"), $v1, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo html\CustomerDirectoryScripts.html..." -ForegroundColor Cyan
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
[System.IO.File]::WriteAllText((Join-Path $root "html\CustomerDirectoryScripts.html"), $v2, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo html\RelatedTicketsScripts.html..." -ForegroundColor Cyan
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

  const ENUM_LABELS = {
    NEW: 'Nuevo', OPEN: 'Abierto', PENDING_CUSTOMER: 'Esperando cliente', RESOLVED: 'Resuelto', CLOSED: 'Cerrado', VOID: 'Nulo'
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
[System.IO.File]::WriteAllText((Join-Path $root "html\RelatedTicketsScripts.html"), $v3, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo html\Scripts.html..." -ForegroundColor Cyan
$v4 = @'
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
    values.forEach(function (value) {
      const option = document.createElement('option');
      option.value = value;
      option.textContent = ENUM_LABELS[String(value).toUpperCase()] || titleCase(value);
      select.appendChild(option);
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
[System.IO.File]::WriteAllText((Join-Path $root "html\Scripts.html"), $v4, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo html\StatisticsScripts.html..." -ForegroundColor Cyan
$v5 = @'
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
[System.IO.File]::WriteAllText((Join-Path $root "html\StatisticsScripts.html"), $v5, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo html\TicketActions.html..." -ForegroundColor Cyan
$v6 = @'
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
    select.dataset.initialValue = currentValue || '';
    options.forEach(function (value) {
      const option = document.createElement('option');
      option.value = value;
      option.textContent = ENUM_LABELS[value] || value.toLowerCase().replace(/_/g, ' ').replace(/\b\w/g, function (letter) {
        return letter.toUpperCase();
      });
      if (value === currentValue) option.selected = true;
      select.appendChild(option);
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
[System.IO.File]::WriteAllText((Join-Path $root "html\TicketActions.html"), $v6, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo tests\ticketManager.test.js..." -ForegroundColor Cyan
$v7 = @'
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const serialNumbersSource = fs.readFileSync(path.join(__dirname, '..', 'src', 'serialNumbers.gs'), 'utf8');
vm.runInThisContext(
  serialNumbersSource + '\n;globalThis.SerialNumberService = SerialNumberService;',
  {filename: 'src/serialNumbers.gs'}
);

const source = fs.readFileSync(path.join(__dirname, '..', 'src', 'tickets.gs'), 'utf8');
vm.runInThisContext(
  source + '\n;globalThis.TicketManager = TicketManager;' +
  'globalThis.TicketPolicy = TicketPolicy;' +
  'globalThis.TicketMetrics = TicketMetrics;' +
  'globalThis.TicketNumberService = TicketNumberService;',
  {filename: 'src/tickets.gs'}
);

class Repository {
  constructor() { this.items = []; }
  create(record) { const created = Object.assign({}, record); this.items.push(created); return created; }
  findById(id) { return this.items.find(item => item.id === id) || null; }
  update(id, changes) {
    const ticket = this.findById(id);
    if (!ticket) throw new Error('Ticket not found: ' + id);
    Object.assign(ticket, changes);
    return ticket;
  }
  search(criteria) {
    let items = this.items.slice();
    if (criteria.status) items = items.filter(item => item.status === criteria.status);
    if (criteria.priority) items = items.filter(item => item.priority === criteria.priority);
    if (criteria.category) items = items.filter(item => item.category === criteria.category);
    if (criteria.query) {
      const query = criteria.query.toLowerCase();
      items = items.filter(item => (item.id + ' ' + item.subject + ' ' + item.customerEmail)
        .toLowerCase().includes(query));
    }
    return {items, total: items.length, offset: 0, limit: 100};
  }
}

function fixture() {
  const repository = new Repository();
  let sequence = 0;
  let dashboardRefreshes = 0;
  const policy = new TicketPolicy({
    get(key, fallback) {
      return key === 'SLA_HIGH_HOURS' ? '8' : fallback;
    }
  });
  const manager = new TicketManager({
    repository,
    numberGenerator: () => TicketNumberService.format('PP', '2026', ++sequence),
    policy,
    dashboard: {refresh() { dashboardRefreshes += 1; }},
    clock: () => new Date('2026-06-30T10:00:00Z'),
    version: '1.2.0',
    logger: {info() {}}
  });
  return {manager, repository, dashboardRefreshes: () => dashboardRefreshes};
}

function testGenerationNumberingAndSla() {
  const test = fixture();
  const ticket = test.manager.create({
    subject: 'Key does not respond',
    customerEmail: 'PLAYER@EXAMPLE.COM',
    priority: 'HIGH',
    category: 'TECHNICAL',
    tags: ['keyboard', 'keyboard', 'urgent']
  });
  assert.equal(ticket.id, 'PP-2026-000001');
  assert.equal(ticket.status, 'NEW');
  assert.equal(ticket.priority, 'HIGH');
  assert.equal(ticket.category, 'TECHNICAL');
  assert.equal(ticket.customerEmail, 'player@example.com');
  assert.equal(ticket.tags, 'keyboard, urgent');
  assert.equal(ticket.slaDueAt.toISOString(), '2026-06-30T18:00:00.000Z');
  assert.equal(test.dashboardRefreshes(), 1);
}

function testLifecycleValidationAndPrioritySla() {
  const test = fixture();
  const ticket = test.manager.create({subject: 'Warranty', customerEmail: 'a@example.com'});
  assert.throws(() => test.manager.updateStatus(ticket.id, 'UNKNOWN'), /Invalid ticket status/);
  assert.throws(() => test.manager.updateCategory(ticket.id, 'RANDOM'), /Invalid ticket category/);
  test.manager.updateStatus(ticket.id, 'OPEN');
  test.manager.updatePriority(ticket.id, 'CRITICAL');
  test.manager.updateCategory(ticket.id, 'WARRANTY');
  assert.equal(ticket.status, 'OPEN');
  assert.equal(ticket.priority, 'CRITICAL');
  assert.equal(ticket.category, 'WARRANTY');
  assert.equal(ticket.slaDueAt.toISOString(), '2026-06-30T14:00:00.000Z');
}

function testSearchAndFilters() {
  const test = fixture();
  test.manager.create({subject: 'Shipping delay', customerEmail: 'a@example.com', category: 'SHIPPING'});
  test.manager.create({
    subject: 'Broken key', customerEmail: 'b@example.com',
    priority: 'CRITICAL', category: 'TECHNICAL'
  });
  assert.equal(test.manager.search({category: 'TECHNICAL'}).total, 1);
  assert.equal(test.manager.search({priority: 'CRITICAL'}).total, 1);
  assert.equal(test.manager.search({query: 'shipping'}).items[0].category, 'SHIPPING');
  assert.deepEqual(test.manager.filters().statuses, ['NEW', 'OPEN', 'PENDING_CUSTOMER', 'RESOLVED', 'CLOSED', 'VOID']);
}

function testDashboardMetrics() {
  const now = new Date('2026-06-30T12:00:00Z');
  const metrics = TicketMetrics.calculate([
    {status: 'OPEN', priority: 'HIGH', category: 'TECHNICAL', slaDueAt: new Date('2026-06-30T11:00:00Z')},
    {status: 'RESOLVED', priority: 'NORMAL', category: 'GENERAL', slaDueAt: new Date('2026-06-29T10:00:00Z')}
  ], now);
  assert.equal(metrics.total, 2);
  assert.equal(metrics.active, 1);
  assert.equal(metrics.breached, 1);
  assert.equal(metrics.byStatus.RESOLVED, 1);
  assert.equal(metrics.byCategory.TECHNICAL, 1);
}

[
  testGenerationNumberingAndSla,
  testLifecycleValidationAndPrioritySla,
  testSearchAndFilters,
  testDashboardMetrics
].forEach(test => test());

console.log('Ticket manager tests passed.');
'@
[System.IO.File]::WriteAllText((Join-Path $root "tests\ticketManager.test.js"), $v7, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host ""
Write-Host "Verificando..." -ForegroundColor Cyan
Select-String -Path src\tickets.gs -Pattern "VOID"
Select-String -Path html\TicketActions.html -Pattern "Nulo"

Write-Host ""
Write-Host "Si salieron lineas arriba, ejecuta: npm test  y  npm run deploy" -ForegroundColor Cyan
