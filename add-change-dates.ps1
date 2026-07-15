# add-change-dates.ps1
# Fechas de cambio de Estado/Prioridad/Categoria, y fecha por cada
# error/solucion detectado anadido (la fecha de cada email ya existia).
$ErrorActionPreference = "Stop"
$root = Get-Location
$enc = New-Object System.Text.UTF8Encoding($false)

Write-Host "Escribiendo src\constants.gs..." -ForegroundColor Cyan
$v0 = @'
/** Immutable application constants. @const */
const APP = Object.freeze({
  NAME: 'PP Tickets',
  VERSION: '2.3.4',
  LOCK_TIMEOUT_MS: 30000,
  LOG_RETENTION_DAYS: 90,
  PROPERTY_KEYS: Object.freeze({
    SPREADSHEET_ID: 'POCKETPIANO_SPREADSHEET_ID',
    DRIVE_FOLDER_ID: 'POCKETPIANO_DRIVE_FOLDER_ID',
    INSTALLED_VERSION: 'POCKETPIANO_INSTALLED_VERSION'
  }),
  SHEETS: Object.freeze({
    DASHBOARD: 'Dashboard',
    TICKETS: 'Tickets',
    MESSAGES: 'Messages',
    CUSTOMERS: 'Customers',
    ERRORS: 'Errors',
    SOLUTIONS: 'Solutions',
    PRODUCTS: 'Products',
    TEMPLATES: 'Templates',
    SETTINGS: 'Settings',
    LOGS: 'Logs'
  }),
  LOG_LEVELS: Object.freeze({DEBUG: 'DEBUG', INFO: 'INFO', WARN: 'WARN', ERROR: 'ERROR'})
});

/**
 * Append-only persistence schemas. Existing columns require a migration before
 * they may be renamed or removed.
 * @const
 */
const SHEET_SCHEMAS = Object.freeze([
  Object.freeze({name: 'Dashboard', headers: Object.freeze(['Metric', 'Value', 'Updated At']), color: '#1A73E8'}),
  Object.freeze({name: 'Tickets', headers: Object.freeze([
    'Ticket ID', 'Status', 'Priority', 'Subject', 'Customer ID', 'Customer Email',
    'Gmail Thread ID', 'Assigned To', 'Created At', 'Updated At', 'Last Message At',
    'SLA Due At', 'Drive Folder ID', 'Tags', 'Version', 'Category',
    'Shipping Address', 'Shipping Recipient', 'Shipping Recipient Phone',
    'Shipping Recipient First Name', 'Shipping Recipient Last Name',
    'Shipping Recipient Country', 'Shipping Recipient Postal Code', 'Notes', 'Detected Errors', 'Detected Solutions', 'Order Number', 'Serial Number',
    'Status Changed At', 'Priority Changed At', 'Category Changed At'
  ]), color: '#D93025'}),
  Object.freeze({name: 'Errors', headers: Object.freeze([
    'Error Code', 'Description'
  ]), color: '#795548'}),
  Object.freeze({name: 'Solutions', headers: Object.freeze([
    'Solution Code', 'Description'
  ]), color: '#00796B'}),
  Object.freeze({name: 'Messages', headers: Object.freeze([
    'Message ID', 'Ticket ID', 'Gmail Message ID', 'Direction', 'From', 'To', 'Cc',
    'Subject', 'Sent At', 'Body Preview', 'Attachment Count', 'Drive Folder ID', 'Created At',
    'Body Text', 'Original Language', 'Translated Body ES'
  ]), color: '#F9AB00'}),
  Object.freeze({name: 'Customers', headers: Object.freeze([
    'Customer ID', 'Email', 'Name', 'Phone', 'Locale', 'Company', 'Created At', 'Updated At', 'Notes',
    'First Name', 'Last Name', 'Address', 'Country', 'Postal Code'
  ]), color: '#188038'}),
  Object.freeze({name: 'Products', headers: Object.freeze([
    'Product ID', 'SKU', 'Name', 'Serial Number', 'Purchase Date', 'Warranty Months',
    'Customer ID', 'Status', 'Notes', 'Created At', 'Updated At'
  ]), color: '#9334E6'}),
  Object.freeze({name: 'Templates', headers: Object.freeze([
    'Template Key', 'Name', 'Subject', 'Body HTML', 'Locale', 'Active', 'Updated At', 'Updated By'
  ]), color: '#12B5CB'}),
  Object.freeze({name: 'Settings', headers: Object.freeze([
    'Key', 'Value', 'Description', 'Updated At', 'Updated By'
  ]), color: '#5F6368'}),
  Object.freeze({name: 'Logs', headers: Object.freeze([
    'Timestamp', 'Level', 'Message', 'Context JSON', 'Correlation ID', 'User', 'Version'
  ]), color: '#3C4043'})
]);

/** Production defaults seeded only when a setting is absent. @const */
const DEFAULT_SETTINGS = Object.freeze([
  Object.freeze(['SUPPORT_EMAIL', 'support@pocketpiano.com', 'Mailbox or alias used for support']),
  Object.freeze(['SUPPORT_GMAIL_QUERY', 'in:inbox newer_than:30d', 'Bounded Gmail search query for synchronization']),
  Object.freeze(['GMAIL_SYNC_LIMIT', '1000', 'Maximum threads processed per synchronization pass']),
  Object.freeze(['SUPPORT_LABEL', 'PocketPiano/Processed', 'Label applied after successful ingestion']),
  Object.freeze(['ATTACHMENTS_FOLDER', 'Ticket Attachments', 'Drive subfolder for ticket attachments']),
  Object.freeze(['DEFAULT_LOCALE', 'es', 'Default template locale']),
  Object.freeze(['DEFAULT_TIME_ZONE', 'Europe/Madrid', 'Application time zone']),
  Object.freeze(['LOG_LEVEL', 'INFO', 'Minimum operational log level']),
  Object.freeze(['TICKET_NUMBER_PREFIX', 'PP', 'Prefix for human-readable ticket numbers']),
  Object.freeze(['SLA_LOW_HOURS', '72', 'Response target for low-priority tickets']),
  Object.freeze(['SLA_NORMAL_HOURS', '48', 'Response target for normal-priority tickets']),
  Object.freeze(['SLA_HIGH_HOURS', '12', 'Response target for high-priority tickets']),
  Object.freeze(['SLA_CRITICAL_HOURS', '4', 'Response target for critical tickets'])
]);
'@
[System.IO.File]::WriteAllText((Join-Path $root "src\constants.gs"), $v0, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo src\repositories.gs..." -ForegroundColor Cyan
$v1 = @'
/** Header-aware Sheets repository for ticket lifecycle and discovery. */
class SheetTicketRepository {
  constructor() {
    this.sheet_ = AppConfig.getSheet(APP.SHEETS.TICKETS);
    this.headers_ = this.sheet_.getRange(1, 1, 1, this.sheet_.getLastColumn()).getDisplayValues()[0];
    this.headerIndex_ = {};
    this.headers_.forEach(function(header, index) {
      if (header) this.headerIndex_[header] = index;
    }, this);
    ['Ticket ID', 'Status', 'Priority', 'Subject', 'Customer Email', 'Gmail Thread ID',
      'Created At', 'Updated At', 'Last Message At', 'SLA Due At', 'Drive Folder ID',
      'Tags', 'Version', 'Category'].forEach(function(header) {
      if (this.headerIndex_[header] == null) {
        throw new AppError('Tickets sheet is missing the "' + header + '" column. Run install().', 'TICKET_SCHEMA_OUTDATED', {header: header});
      }
    }, this);
    this.reload_();
  }

  reload_() {
    this.byId_ = {};
    this.byThreadId_ = {};
    this.listAll().forEach(function(ticket) {
      this.byId_[ticket.id] = ticket;
      if (ticket.threadId) this.byThreadId_[ticket.threadId] = ticket;
    }, this);
  }

  findById(id) { return this.byId_[String(id)] || null; }
  findByThreadId(threadId) { return this.byThreadId_[String(threadId)] || null; }

  listAll() {
    if (this.sheet_.getLastRow() <= 1) return [];
    return this.sheet_.getRange(2, 1, this.sheet_.getLastRow() - 1, this.headers_.length)
      .getValues()
      .map(function(row, index) { return this.fromRow_(row, index + 2); }, this);
  }

  create(record) {
    if (!record.id) throw new AppError('Ticket ID is required.', 'TICKET_ID_REQUIRED');
    if (this.findById(record.id)) throw new AppError('Ticket ID already exists: ' + record.id, 'TICKET_DUPLICATE_ID');
    if (record.threadId && this.findByThreadId(record.threadId)) throw new AppError('Gmail thread already has a ticket.', 'TICKET_DUPLICATE_THREAD');

    const createdAt = record.createdAt || new Date();
    const priority = record.priority || 'NORMAL';
    const data = Object.assign({}, record, {
      status: record.status || 'NEW',
      priority: priority,
      category: record.category || 'GENERAL',
      createdAt: createdAt,
      updatedAt: record.updatedAt || createdAt,
      lastMessageAt: record.lastMessageAt || createdAt,
      slaDueAt: record.slaDueAt || TicketPolicy.fromAppConfig().calculateDueAt(createdAt, priority),
      version: record.version || APP_VERSION
    });
    const row = this.emptyRow_();
    SheetTicketRepository.fields_().forEach(function(mapping) {
      if (this.headerIndex_[mapping.header] != null && data[mapping.field] != null) row[this.headerIndex_[mapping.header]] = data[mapping.field];
    }, this);
    this.sheet_.appendRow(row);
    const ticket = this.fromRow_(row, this.sheet_.getLastRow());
    this.byId_[ticket.id] = ticket;
    if (ticket.threadId) this.byThreadId_[ticket.threadId] = ticket;
    return ticket;
  }

  update(ticketId, changes) {
    const ticket = this.findById(ticketId);
    if (!ticket) throw new AppError('Ticket not found: ' + ticketId, 'TICKET_NOT_FOUND', {ticketId: ticketId});
    const row = this.sheet_.getRange(ticket.rowNumber, 1, 1, this.headers_.length).getValues()[0];
    const allowed = ['status', 'priority', 'category', 'subject', 'customerId', 'customerEmail', 'threadId',
      'assignedTo', 'updatedAt', 'lastMessageAt', 'slaDueAt', 'driveFolderId', 'tags', 'version',
      'shippingAddress', 'shippingRecipient', 'shippingRecipientPhone',
      'shippingRecipientFirstName', 'shippingRecipientLastName',
      'shippingRecipientCountry', 'shippingRecipientPostalCode', 'notes', 'detectedErrors', 'detectedSolutions', 'orderNumber', 'serialNumber',
      'statusChangedAt', 'priorityChangedAt', 'categoryChangedAt'];
    SheetTicketRepository.fields_().forEach(function(mapping) {
      if (allowed.indexOf(mapping.field) !== -1 && Object.prototype.hasOwnProperty.call(changes, mapping.field)) {
        row[this.headerIndex_[mapping.header]] = changes[mapping.field];
      }
    }, this);
    this.sheet_.getRange(ticket.rowNumber, 1, 1, row.length).setValues([row]);
    const updated = this.fromRow_(row, ticket.rowNumber);
    this.byId_[updated.id] = updated;
    if (updated.threadId) this.byThreadId_[updated.threadId] = updated;
    return updated;
  }

  updateConversation(ticket, changes) {
    const finalChanges = Object.assign({}, changes);
    if (Object.prototype.hasOwnProperty.call(changes, 'status') && changes.status !== ticket.status) {
      finalChanges.statusChangedAt = new Date();
    }
    const updated = this.update(ticket.id, finalChanges);
    Object.assign(ticket, updated);
    return updated;
  }

  search(criteria) {
    const filters = criteria || {};
    const query = String(filters.query || '').trim().toLowerCase();
    const customerIndex = query ? this.customerIndex_() : null;
    let tickets = this.listAll().filter(function(ticket) {
      if (!SheetTicketRepository.matches_(ticket.status, filters.status)) return false;
      if (!SheetTicketRepository.matches_(ticket.priority, filters.priority)) return false;
      if (!SheetTicketRepository.matches_(ticket.category, filters.category)) return false;
      if (!SheetTicketRepository.matches_(ticket.assignedTo, filters.assignedTo)) return false;
      if (filters.customerEmail && ticket.customerEmail.toLowerCase() !== String(filters.customerEmail).toLowerCase()) return false;
      if (filters.slaBreached === true) {
        const due = ticket.slaDueAt instanceof Date ? ticket.slaDueAt : new Date(ticket.slaDueAt);
        if (['RESOLVED', 'CLOSED'].indexOf(ticket.status) !== -1 || Number.isNaN(due.getTime()) || due >= new Date()) return false;
      }
      if (filters.createdFrom && new Date(ticket.createdAt) < new Date(filters.createdFrom)) return false;
      if (filters.createdTo && new Date(ticket.createdAt) > new Date(filters.createdTo)) return false;
      if (query) {
        const customer = customerIndex ? customerIndex[String(ticket.customerEmail).toLowerCase()] : null;
        const haystack = [
          ticket.id, ticket.subject, ticket.status, ticket.priority, ticket.category,
          ticket.customerEmail, ticket.customerId, ticket.assignedTo, ticket.tags,
          ticket.shippingAddress, ticket.shippingRecipientFirstName, ticket.shippingRecipientLastName,
          ticket.shippingRecipientPhone, ticket.shippingRecipientCountry, ticket.shippingRecipientPostalCode,
          customer ? customer.firstName : '', customer ? customer.lastName : '', customer ? customer.name : '',
          customer ? customer.phone : '', customer ? customer.address : '', customer ? customer.country : '',
          customer ? customer.postalCode : '', customer ? customer.company : ''
        ].join(' ').toLowerCase();
        if (haystack.indexOf(query) === -1) return false;
      }
      return true;
    });

    tickets.sort(function(left, right) { return new Date(right.updatedAt).getTime() - new Date(left.updatedAt).getTime(); });
    const total = tickets.length;
    const offset = Math.max(0, Number(filters.offset) || 0);
    const limit = Math.max(1, Math.min(1000, Number(filters.limit) || 100));
    return {items: tickets.slice(offset, offset + limit), total: total, offset: offset, limit: limit};
  }

  /**
   * Lazily loads and caches a lowercase-email -> customer map, so free-text
   * ticket search can also match against the linked customer's own fields.
   * @return {Object}
   * @private
   */
  customerIndex_() {
    if (this.customerIndex_cache_) return this.customerIndex_cache_;
    const index = {};
    try {
      new SheetCustomerRepository().listAll().forEach(function(customer) {
        if (customer.email) index[String(customer.email).toLowerCase()] = customer;
      });
    } catch (error) {
      // Customers sheet unavailable or outdated schema — search still works on ticket fields alone.
    }
    this.customerIndex_cache_ = index;
    return index;
  }

  emptyRow_() { return this.headers_.map(function() { return ''; }); }

  fromRow_(row, rowNumber) {
    const ticket = {rowNumber: rowNumber};
    SheetTicketRepository.fields_().forEach(function(mapping) {
      const index = this.headerIndex_[mapping.header];
      ticket[mapping.field] = index == null ? '' : row[index];
    }, this);
    ['id', 'status', 'priority', 'category', 'subject', 'customerId', 'customerEmail', 'threadId', 'assignedTo', 'driveFolderId', 'tags', 'version',
      'shippingAddress', 'shippingRecipient', 'shippingRecipientPhone',
      'shippingRecipientFirstName', 'shippingRecipientLastName',
      'shippingRecipientCountry', 'shippingRecipientPostalCode', 'notes', 'detectedErrors', 'detectedSolutions', 'orderNumber', 'serialNumber'].forEach(function(field) {
      ticket[field] = String(ticket[field] || '');
    });
    return ticket;
  }

  static matches_(actual, expected) {
    if (expected == null || expected === '') return true;
    const values = Array.isArray(expected) ? expected : [expected];
    return values.map(function(value) { return String(value).toUpperCase(); }).indexOf(String(actual).toUpperCase()) !== -1;
  }

  static fields_() {
    return [
      {field: 'id', header: 'Ticket ID'}, {field: 'status', header: 'Status'}, {field: 'priority', header: 'Priority'},
      {field: 'subject', header: 'Subject'}, {field: 'customerId', header: 'Customer ID'}, {field: 'customerEmail', header: 'Customer Email'},
      {field: 'threadId', header: 'Gmail Thread ID'}, {field: 'assignedTo', header: 'Assigned To'}, {field: 'createdAt', header: 'Created At'},
      {field: 'updatedAt', header: 'Updated At'}, {field: 'lastMessageAt', header: 'Last Message At'}, {field: 'slaDueAt', header: 'SLA Due At'},
      {field: 'driveFolderId', header: 'Drive Folder ID'}, {field: 'tags', header: 'Tags'}, {field: 'version', header: 'Version'}, {field: 'category', header: 'Category'},
      {field: 'shippingAddress', header: 'Shipping Address'}, {field: 'shippingRecipient', header: 'Shipping Recipient'}, {field: 'shippingRecipientPhone', header: 'Shipping Recipient Phone'},
      {field: 'shippingRecipientFirstName', header: 'Shipping Recipient First Name'}, {field: 'shippingRecipientLastName', header: 'Shipping Recipient Last Name'},
      {field: 'shippingRecipientCountry', header: 'Shipping Recipient Country'}, {field: 'shippingRecipientPostalCode', header: 'Shipping Recipient Postal Code'},
      {field: 'notes', header: 'Notes'}, {field: 'detectedErrors', header: 'Detected Errors'}, {field: 'detectedSolutions', header: 'Detected Solutions'}, {field: 'orderNumber', header: 'Order Number'}, {field: 'serialNumber', header: 'Serial Number'},
      {field: 'statusChangedAt', header: 'Status Changed At'}, {field: 'priorityChangedAt', header: 'Priority Changed At'}, {field: 'categoryChangedAt', header: 'Category Changed At'}
    ];
  }
}

/** Sheets-backed message repository indexed by immutable Gmail message ID. */
class SheetMessageRepository {
  constructor() {
    this.sheet_ = AppConfig.getSheet(APP.SHEETS.MESSAGES);
    this.headers_ = this.sheet_.getRange(1, 1, 1, this.sheet_.getLastColumn()).getDisplayValues()[0];
    this.headerIndex_ = {};
    this.headers_.forEach(function(header, index) { if (header) this.headerIndex_[header] = index; }, this);
    this.gmailMessageIds_ = {};
    if (this.sheet_.getLastRow() > 1) {
      this.sheet_.getRange(2, 3, this.sheet_.getLastRow() - 1, 1).getDisplayValues()
        .forEach(function(row) { if (row[0]) this.gmailMessageIds_[row[0]] = true; }, this);
    }
  }

  hasMessage(gmailMessageId) { return Boolean(this.gmailMessageIds_[String(gmailMessageId)]); }

  add(record) {
    if (this.hasMessage(record.gmailMessageId)) return;
    const row = this.headers_.map(function() { return ''; });
    SheetMessageRepository.fields_().forEach(function(mapping) {
      if (this.headerIndex_[mapping.header] != null && record[mapping.field] != null) {
        row[this.headerIndex_[mapping.header]] = record[mapping.field];
      }
    }, this);
    this.sheet_.appendRow(row);
    this.gmailMessageIds_[String(record.gmailMessageId)] = true;
  }

  updateTranslation(messageId, originalLanguage, translatedBodyEs) {
    if (!messageId) return;
    const idColumn = this.headerIndex_['Message ID'];
    const langColumn = this.headerIndex_['Original Language'];
    const translatedColumn = this.headerIndex_['Translated Body ES'];
    if (idColumn == null || langColumn == null || translatedColumn == null) {
      throw new AppError('Messages sheet translation columns are missing. Run install().', 'MESSAGE_TRANSLATION_SCHEMA_OUTDATED');
    }
    const lastRow = this.sheet_.getLastRow();
    if (lastRow <= 1) return;
    const ids = this.sheet_.getRange(2, idColumn + 1, lastRow - 1, 1).getDisplayValues();
    for (let index = 0; index < ids.length; index += 1) {
      if (String(ids[index][0]) === String(messageId)) {
        const rowNumber = index + 2;
        this.sheet_.getRange(rowNumber, langColumn + 1).setValue(originalLanguage || '');
        this.sheet_.getRange(rowNumber, translatedColumn + 1).setValue(translatedBodyEs || '');
        return;
      }
    }
  }

  static fields_() {
    return [
      {field: 'id', header: 'Message ID'}, {field: 'ticketId', header: 'Ticket ID'}, {field: 'gmailMessageId', header: 'Gmail Message ID'},
      {field: 'direction', header: 'Direction'}, {field: 'from', header: 'From'}, {field: 'to', header: 'To'}, {field: 'cc', header: 'Cc'},
      {field: 'subject', header: 'Subject'}, {field: 'sentAt', header: 'Sent At'}, {field: 'bodyPreview', header: 'Body Preview'},
      {field: 'attachmentCount', header: 'Attachment Count'}, {field: 'driveFolderId', header: 'Drive Folder ID'}, {field: 'createdAt', header: 'Created At'},
      {field: 'bodyText', header: 'Body Text'}, {field: 'originalLanguage', header: 'Original Language'}, {field: 'translatedBodyEs', header: 'Translated Body ES'}
    ];
  }
}

/** Idempotent Drive attachment persistence, partitioned by ticket. */
class DriveAttachmentStore {
  constructor() { this.root_ = null; }

  save(ticketId, gmailMessageId, attachments) {
    if (!attachments.length) return {folderId: '', count: 0};
    const folder = this.ticketFolder_(ticketId);
    let stored = 0;
    attachments.forEach(function(attachment, index) {
      const original = DriveAttachmentStore.safeName_(attachment.name || 'attachment');
      const fileName = gmailMessageId + '_' + (index + 1) + '_' + original;
      if (!folder.getFilesByName(fileName).hasNext()) folder.createFile(attachment.blob).setName(fileName);
      stored += 1;
    });
    return {folderId: folder.getId(), count: stored};
  }

  ticketFolder_(ticketId) {
    const root = this.rootFolder_();
    const folders = root.getFoldersByName(ticketId);
    return folders.hasNext() ? folders.next() : root.createFolder(ticketId);
  }

  rootFolder_() {
    if (this.root_) return this.root_;
    const id = AppConfig.getProperties().getProperty(APP.PROPERTY_KEYS.DRIVE_FOLDER_ID);
    if (!id) throw new AppError('The application Drive folder is not configured. Run install().', 'DRIVE_NOT_CONFIGURED');
    this.root_ = DriveApp.getFolderById(id);
    return this.root_;
  }

  static safeName_(name) {
    return String(name).replace(/[\/:*?"<>|\u0000-\u001F]/g, '_').slice(0, 180);
  }
}
'@
[System.IO.File]::WriteAllText((Join-Path $root "src\repositories.gs"), $v1, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo src\tickets.gs..." -ForegroundColor Cyan
$v2 = @'
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
'@
[System.IO.File]::WriteAllText((Join-Path $root "src\tickets.gs"), $v2, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo html\Scripts.html..." -ForegroundColor Cyan
$v3 = @'
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

  function populateSelect(select, values) {
    values.forEach(function (value) {
      const option = document.createElement('option');
      option.value = value;
      option.textContent = ENUM_LABELS[String(value).toUpperCase()] || titleCase(value);
      select.appendChild(option);
    });
  }

  const ENUM_LABELS = {
    NEW: 'Nuevo', OPEN: 'Abierto', PENDING_CUSTOMER: 'Esperando cliente', RESOLVED: 'Resuelto', CLOSED: 'Cerrado',
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
[System.IO.File]::WriteAllText((Join-Path $root "html\Scripts.html"), $v3, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo html\IssuesSectionScripts.html..." -ForegroundColor Cyan
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
    if (document.getElementById('detected-issues-styles')) return;
    const style = document.createElement('style');
    style.id = 'detected-issues-styles';
    style.textContent = [
      '.issues-section { padding: 16px 22px; border-top: 1px solid var(--outline-variant); display: grid; grid-template-columns: 1fr 1fr; gap: 26px; }',
      '.issues-column h3 { margin: 0 0 10px; font-size: 14px; }',
      '.issues-add-button { width: 30px; height: 30px; border-radius: 50%; border: 1px dashed var(--outline); background: transparent; color: var(--primary); cursor: pointer; font-size: 16px; line-height: 1; }',
      '.issues-list { margin-top: 10px; display: grid; gap: 6px; }',
      '.issue-row { display: flex; align-items: center; justify-content: space-between; gap: 10px; padding: 8px 8px 8px 14px; border: 1px solid var(--outline-variant); border-radius: 10px; background: var(--surface-container); font-size: 13px; }',
      '.issue-row-text { display: flex; flex-direction: column; gap: 2px; min-width: 0; }',
      '.issue-row-label { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }',
      '.issue-row-date { font-size: 11px; color: var(--on-surface-variant); }',
      '.issue-delete-button { display: inline-flex; align-items: center; justify-content: center; width: 30px; height: 30px; border: 0; border-radius: 8px; background: transparent; color: var(--error); cursor: pointer; }',
      '.issue-delete-button:hover { background: var(--error-container); }',
      '.issue-delete-button .material-symbols-rounded { font-size: 18px; }',
      '.issues-empty { font-size: 12px; color: var(--on-surface-variant); }',
      '.issues-picker { position: relative; margin-top: 4px; }',
      '.issues-picker-menu { position: absolute; top: 36px; left: 0; z-index: 20; width: 280px; max-height: 260px; overflow-y: auto; border: 1px solid var(--outline-variant); border-radius: 12px; background: var(--surface-bright); box-shadow: var(--shadow); padding: 6px; }',
      '.issues-picker-item { display: block; width: 100%; text-align: left; padding: 8px 10px; border: 0; border-radius: 8px; background: transparent; cursor: pointer; font-size: 12px; color: var(--on-surface); }',
      '.issues-picker-item:hover { background: var(--surface-container); }',
      '.issues-picker-item strong { display: block; font-size: 12px; }',
      '.issues-picker-item span { display: block; font-size: 10px; color: var(--on-surface-variant); }',
      '.issues-picker-empty { padding: 10px; font-size: 12px; color: var(--on-surface-variant); }',
      '@media (max-width: 900px) { .issues-section { grid-template-columns: 1fr; } }'
    ].join('\n');
    document.head.appendChild(style);
  }

  /**
   * Builds one column (Errores or Soluciones). Each column keeps its own
   * catalog cache and hidden input, but shares all the rendering logic.
   * @param {{title:string, ticketField:string, hiddenId:string, catalogFn:string, sheetName:string, addLabel:string, emptyLabel:string, deleteLabel:string}} config
   */
  function createColumn(config) {
    let catalogCache = null;
    let originalValue = null;
    let lastContainer = null;
    function loadCatalog() {
      if (catalogCache) return Promise.resolve(catalogCache);
      return callServer(config.catalogFn).then(unwrap).then(function (catalog) {
        catalogCache = catalog || [];
        return catalogCache;
      });
    }

    function descriptionFor(code) {
      if (!catalogCache) return code;
      const entry = catalogCache.find(function (item) { return item.code === code; });
      return (entry && entry.description) ? entry.description : code;
    }

    function parseToken(token) {
      const atIndex = token.lastIndexOf('@');
      if (atIndex === -1) return {code: token, timestamp: ''};
      return {code: token.slice(0, atIndex), timestamp: token.slice(atIndex + 1)};
    }

    function formatTokenDate(timestamp) {
      if (!timestamp) return '';
      const date = new Date(timestamp);
      if (isNaN(date.getTime())) return '';
      return date.toLocaleString('es-ES', {day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit'});
    }

    function currentItems() {
      const detail = currentDetail();
      const raw = (detail.ticket && detail.ticket[config.ticketField]) || '';
      return raw.split(',').map(function (item) { return item.trim(); }).filter(Boolean);
    }

    function closePicker() {
      const menu = document.querySelector('.issues-picker-menu[data-owner="' + config.hiddenId + '"]');
      if (menu) menu.remove();
      document.removeEventListener('click', onOutsideClick);
    }

    function onOutsideClick(event) {
      if (!event.target.closest('.issues-picker[data-owner="' + config.hiddenId + '"]')) closePicker();
    }

    function openPicker(picker, container, currentList) {
      const menu = document.createElement('div');
      menu.className = 'issues-picker-menu';
      menu.dataset.owner = config.hiddenId;
      menu.innerHTML = '<div class="issues-picker-empty">Cargando…</div>';
      picker.appendChild(menu);
      window.setTimeout(function () { document.addEventListener('click', onOutsideClick); }, 0);

      loadCatalog().then(function (catalog) {
        const currentCodes = currentList.map(function (token) { return parseToken(token).code; });
        const available = catalog.filter(function (entry) { return currentCodes.indexOf(entry.code) === -1; });
        menu.replaceChildren();
        if (!available.length) {
          const empty = document.createElement('div');
          empty.className = 'issues-picker-empty';
          empty.textContent = catalog.length ? 'Ya están todos añadidos.' : 'No hay elementos definidos en la hoja "' + config.sheetName + '".';
          menu.appendChild(empty);
          return;
        }
        available.forEach(function (entry) {
          const item = document.createElement('button');
          item.type = 'button';
          item.className = 'issues-picker-item';
          item.innerHTML = '<strong>' + entry.code + '</strong>' + (entry.description ? '<span>' + entry.description + '</span>' : '');
          item.addEventListener('click', function () {
            const hidden = document.getElementById(config.hiddenId);
            const updated = currentList.concat([entry.code + '@' + new Date().toISOString()]);
            hidden.value = updated.join(', ');
            closePicker();
            render(container, updated);
          });
          menu.appendChild(item);
        });
      }).catch(function (error) {
        menu.innerHTML = '<div class="issues-picker-empty">' + (error && error.message ? error.message : String(error)) + '</div>';
      });
    }

    function render(container, overrideItems) {
      lastContainer = container;
      container.replaceChildren();
      container.className = 'issues-column';

      const heading = document.createElement('h3');
      heading.textContent = config.title;
      container.appendChild(heading);

      const items = overrideItems || currentItems();
      if (originalValue === null) originalValue = currentItems().join(', ');
      const hidden = document.createElement('input');
      hidden.type = 'hidden';
      hidden.id = config.hiddenId;
      hidden.value = items.join(', ');
      hidden.dataset.original = originalValue;
      container.appendChild(hidden);

      const picker = document.createElement('div');
      picker.className = 'issues-picker';
      picker.dataset.owner = config.hiddenId;
      const addButton = document.createElement('button');
      addButton.type = 'button';
      addButton.className = 'issues-add-button';
      addButton.title = config.addLabel;
      addButton.setAttribute('aria-label', config.addLabel);
      addButton.textContent = '+';
      addButton.addEventListener('click', function (event) {
        event.stopPropagation();
        closePicker();
        openPicker(picker, container, items);
      });
      picker.appendChild(addButton);
      container.appendChild(picker);

      const list = document.createElement('div');
      list.className = 'issues-list';

      if (!items.length) {
        const empty = document.createElement('span');
        empty.className = 'issues-empty';
        empty.textContent = config.emptyLabel;
        list.appendChild(empty);
      }

      items.forEach(function (token) {
        const parsed = parseToken(token);
        const row = document.createElement('div');
        row.className = 'issue-row';
        const textWrap = document.createElement('span');
        textWrap.className = 'issue-row-text';
        const label = document.createElement('span');
        label.className = 'issue-row-label';
        label.textContent = descriptionFor(parsed.code);
        label.title = parsed.code;
        textWrap.appendChild(label);
        const formattedDate = formatTokenDate(parsed.timestamp);
        if (formattedDate) {
          const dateSpan = document.createElement('span');
          dateSpan.className = 'issue-row-date';
          dateSpan.textContent = formattedDate;
          textWrap.appendChild(dateSpan);
        }
        const removeButton = document.createElement('button');
        removeButton.type = 'button';
        removeButton.className = 'issue-delete-button';
        removeButton.title = 'Eliminar';
        removeButton.setAttribute('aria-label', config.deleteLabel);
        removeButton.innerHTML = '<span class="material-symbols-rounded" aria-hidden="true">delete</span>';
        removeButton.addEventListener('click', function () {
          const updated = items.filter(function (item) { return item !== token; });
          hidden.value = updated.join(', ');
          render(container, updated);
        });
        row.appendChild(textWrap);
        row.appendChild(removeButton);
        list.appendChild(row);
      });

      container.appendChild(list);

      if (items.length && !catalogCache) {
        loadCatalog().then(function () {
          if (lastContainer) render(lastContainer, items);
        }).catch(function () { /* keep showing codes if the catalog can't be loaded */ });
      }
    }

    return {
      render: render,
      reset: function () { originalValue = null; },
      addItems: function (codes) {
        if (!lastContainer || !codes || !codes.length) return 0;
        const hidden = document.getElementById(config.hiddenId);
        const existing = hidden ? hidden.value.split(',').map(function (item) { return item.trim(); }).filter(Boolean) : currentItems();
        const existingCodes = existing.map(function (token) { return parseToken(token).code; });
        const newCodes = codes.filter(function (code) { return existingCodes.indexOf(code) === -1; });
        if (!newCodes.length) return 0;
        const now = new Date().toISOString();
        const additions = newCodes.map(function (code) { return code + '@' + now; });
        const updated = existing.concat(additions);
        if (hidden) hidden.value = updated.join(', ');
        render(lastContainer, updated);
        return additions.length;
      }
    };
  }

  const errorsColumn = createColumn({
    title: 'Errores detectados',
    ticketField: 'detectedErrors',
    hiddenId: 'ticket-detected-errors',
    catalogFn: 'getUiErrorCatalog',
    sheetName: 'Errors',
    addLabel: 'Añadir error',
    emptyLabel: 'Sin errores registrados.',
    deleteLabel: 'Eliminar error'
  });

  const solutionsColumn = createColumn({
    title: 'Soluciones',
    ticketField: 'detectedSolutions',
    hiddenId: 'ticket-detected-solutions',
    catalogFn: 'getUiSolutionCatalog',
    sheetName: 'Solutions',
    addLabel: 'Añadir solución',
    emptyLabel: 'Sin soluciones registradas.',
    deleteLabel: 'Eliminar solución'
  });

  window.__ppIssuesColumns = {errors: errorsColumn, solutions: solutionsColumn};

  function ensureIssuesSection() {
    const section = document.getElementById('detected-errors-section');
    if (!section || section.dataset.rendered === 'true') return;
    section.dataset.rendered = 'true';
    injectStyles();
    section.className = 'issues-section';

    const left = document.createElement('div');
    const right = document.createElement('div');
    section.appendChild(left);
    section.appendChild(right);

    errorsColumn.reset();
    solutionsColumn.reset();
    errorsColumn.render(left);
    solutionsColumn.render(right);
  }

  const observer = new MutationObserver(function () {
    ensureIssuesSection();
  });

  function start() {
    const panel = document.getElementById('ticket-detail');
    if (!panel) return;
    observer.observe(panel, {childList: true, subtree: true});
    ensureIssuesSection();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
</script>
'@
[System.IO.File]::WriteAllText((Join-Path $root "html\IssuesSectionScripts.html"), $v4, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host ""
Write-Host "Verificando..." -ForegroundColor Cyan
Select-String -Path src\constants.gs -Pattern "Status Changed At"
Select-String -Path html\IssuesSectionScripts.html -Pattern "formatTokenDate"

Write-Host ""
Write-Host "Si salieron lineas arriba, ejecuta: npm test  y  npm run deploy" -ForegroundColor Cyan
Write-Host "Luego ejecuta install() una vez para crear las 3 columnas nuevas." -ForegroundColor Cyan
