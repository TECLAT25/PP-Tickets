# poblacion-completo.ps1
# Version combinada y definitiva: pais en espanol + campo Poblacion
# (ciudad) en cliente y destinatario, con el esquema ya corregido
# (Shipping Recipient City al final, no en medio).
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
    'Status Changed At', 'Priority Changed At', 'Category Changed At', 'Shipping Recipient City'
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
    'First Name', 'Last Name', 'Address', 'Country', 'Postal Code', 'City'
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

Write-Host "Escribiendo src\customers.gs..." -ForegroundColor Cyan
$v1 = @'
/**
 * CRM customer persistence for support workflows.
 */
class SheetCustomerRepository {
  constructor() {
    this.sheet_ = AppConfig.getSheet(APP.SHEETS.CUSTOMERS);
    this.headers_ = this.sheet_.getRange(1, 1, 1, this.sheet_.getLastColumn()).getDisplayValues()[0];
    this.headerIndex_ = {};
    this.headers_.forEach(function(header, index) {
      if (header) this.headerIndex_[header] = index;
    }, this);
    ['Customer ID', 'Email', 'Name', 'Created At', 'Updated At'].forEach(function(header) {
      if (this.headerIndex_[header] == null) {
        throw new AppError(
          'Customers sheet is missing the "' + header + '" column. Run install().',
          'CUSTOMER_SCHEMA_OUTDATED',
          {header: header}
        );
      }
    }, this);
    this.reload_();
  }

  /** @private */
  reload_() {
    this.byId_ = {};
    this.byEmail_ = {};
    this.listAll().forEach(function(customer) {
      this.byId_[customer.id] = customer;
      if (customer.email) this.byEmail_[customer.email.toLowerCase()] = customer;
    }, this);
  }

  /** @return {Array<Object>} */
  listAll() {
    if (this.sheet_.getLastRow() <= 1) return [];
    return this.sheet_.getRange(2, 1, this.sheet_.getLastRow() - 1, this.headers_.length)
      .getValues()
      .map(function(row, index) { return this.fromRow_(row, index + 2); }, this);
  }

  /** @param {string} id @return {Object|null} */
  findById(id) {
    return this.byId_[String(id || '')] || null;
  }

  /** @param {string} email @return {Object|null} */
  findByEmail(email) {
    return this.byEmail_[String(email || '').trim().toLowerCase()] || null;
  }

  /**
   * Creates or updates a customer by email.
   * @param {{email: string, name: string, locale: string, company: string, notes: string}=} input
   * @return {Object}
   */
  upsertByEmail(input) {
    const data = input || {};
    const email = String(data.email || '').trim().toLowerCase();
    if (!email) {
      throw new AppError('Customer email is required.', 'CUSTOMER_EMAIL_REQUIRED');
    }
    const existing = this.findByEmail(email);
    if (existing) {
      const changes = {
        name: data.name || existing.name,
        locale: data.locale || existing.locale,
        company: data.company || existing.company,
        notes: data.notes || existing.notes,
        firstName: data.firstName || existing.firstName,
        lastName: data.lastName || existing.lastName,
        address: data.address || existing.address,
        country: data.country || existing.country,
        postalCode: data.postalCode || existing.postalCode,
        city: data.city || existing.city,
        updatedAt: new Date()
      };
      return this.update(existing.id, changes);
    }

    const now = new Date();
    const record = {
      id: SheetCustomerRepository.nextCustomerId_(),
      email: email,
      name: String(data.name || '').trim(),
      phone: '',
      locale: String(data.locale || AppConfig.getSetting('DEFAULT_LOCALE', 'es')).trim(),
      company: String(data.company || '').trim(),
      createdAt: now,
      updatedAt: now,
      notes: String(data.notes || '').trim(),
      firstName: String(data.firstName || '').trim(),
      lastName: String(data.lastName || '').trim(),
      address: String(data.address || '').trim(),
      country: String(data.country || '').trim(),
      postalCode: String(data.postalCode || '').trim(),
      city: String(data.city || '').trim()
    };
    const row = this.emptyRow_();
    SheetCustomerRepository.fields_().forEach(function(mapping) {
      if (this.headerIndex_[mapping.header] != null) {
        row[this.headerIndex_[mapping.header]] = record[mapping.field] || '';
      }
    }, this);
    this.sheet_.appendRow(row);
    const created = this.fromRow_(row, this.sheet_.getLastRow());
    this.byId_[created.id] = created;
    this.byEmail_[created.email.toLowerCase()] = created;
    return created;
  }

  /** @param {string} customerId @param {Object} changes @return {Object} */
  update(customerId, changes) {
    const customer = this.findById(customerId);
    if (!customer) {
      throw new AppError('Customer not found: ' + customerId, 'CUSTOMER_NOT_FOUND', {customerId: customerId});
    }
    const row = this.sheet_.getRange(customer.rowNumber, 1, 1, this.headers_.length).getValues()[0];
    const allowed = ['email', 'name', 'phone', 'locale', 'company', 'updatedAt', 'notes', 'firstName', 'lastName', 'address', 'country', 'postalCode', 'city'];
    SheetCustomerRepository.fields_().forEach(function(mapping) {
      if (allowed.indexOf(mapping.field) !== -1 &&
          Object.prototype.hasOwnProperty.call(changes, mapping.field)) {
        row[this.headerIndex_[mapping.header]] = changes[mapping.field];
      }
    }, this);
    this.sheet_.getRange(customer.rowNumber, 1, 1, row.length).setValues([row]);
    const updated = this.fromRow_(row, customer.rowNumber);
    this.byId_[updated.id] = updated;
    if (updated.email) this.byEmail_[updated.email.toLowerCase()] = updated;
    return updated;
  }

  /** @return {Array<*>} @private */
  emptyRow_() {
    return this.headers_.map(function() { return ''; });
  }

  /** @param {Array<*>} row @param {number} rowNumber @return {Object} @private */
  fromRow_(row, rowNumber) {
    const customer = {rowNumber: rowNumber};
    SheetCustomerRepository.fields_().forEach(function(mapping) {
      const index = this.headerIndex_[mapping.header];
      customer[mapping.field] = index == null ? '' : row[index];
    }, this);
    ['id', 'email', 'name', 'phone', 'locale', 'company', 'notes', 'firstName', 'lastName', 'address', 'country', 'postalCode', 'city'].forEach(function(field) {
      customer[field] = String(customer[field] || '');
    });
    return customer;
  }

  /** @return {string} @private */
  static nextCustomerId_() {
    const properties = AppConfig.getProperties();
    const key = 'CUSTOMER_SEQUENCE';
    let sequence = Number(properties.getProperty(key));
    if (!Number.isInteger(sequence) || sequence < 0) sequence = 0;
    sequence += 1;
    properties.setProperty(key, String(sequence));
    return 'CUST-' + String(sequence).padStart(6, '0');
  }

  /** @return {Array<{field: string, header: string}>} @private */
  static fields_() {
    return [
      {field: 'id', header: 'Customer ID'},
      {field: 'email', header: 'Email'},
      {field: 'name', header: 'Name'},
      {field: 'phone', header: 'Phone'},
      {field: 'locale', header: 'Locale'},
      {field: 'company', header: 'Company'},
      {field: 'createdAt', header: 'Created At'},
      {field: 'updatedAt', header: 'Updated At'},
      {field: 'notes', header: 'Notes'},
      {field: 'firstName', header: 'First Name'},
      {field: 'lastName', header: 'Last Name'},
      {field: 'address', header: 'Address'},
      {field: 'country', header: 'Country'},
      {field: 'postalCode', header: 'Postal Code'},
      {field: 'city', header: 'City'}
    ];
  }
}
'@
[System.IO.File]::WriteAllText((Join-Path $root "src\customers.gs"), $v1, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo src\repositories.gs..." -ForegroundColor Cyan
$v2 = @'
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

  /**
   * Permanently removes a ticket row. Used when merging tickets — the
   * merged-away ticket's messages/data have already been moved elsewhere,
   * so the empty row is deleted rather than left behind with any status.
   * @param {string} id
   * @return {boolean} true if a row was deleted
   */
  delete(id) {
    const ticket = this.findById(id);
    if (!ticket || !ticket.rowNumber) return false;
    this.sheet_.deleteRow(ticket.rowNumber);
    this.reload_();
    return true;
  }

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
      'shippingRecipientCountry', 'shippingRecipientPostalCode', 'shippingRecipientCity', 'notes', 'detectedErrors', 'detectedSolutions', 'orderNumber', 'serialNumber',
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
      'shippingRecipientCountry', 'shippingRecipientPostalCode', 'shippingRecipientCity', 'notes', 'detectedErrors', 'detectedSolutions', 'orderNumber', 'serialNumber'].forEach(function(field) {
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
      {field: 'shippingRecipientCountry', header: 'Shipping Recipient Country'}, {field: 'shippingRecipientPostalCode', header: 'Shipping Recipient Postal Code'}, {field: 'shippingRecipientCity', header: 'Shipping Recipient City'},
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
[System.IO.File]::WriteAllText((Join-Path $root "src\repositories.gs"), $v2, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo src\tickets.gs..." -ForegroundColor Cyan
$v3 = @'
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
[System.IO.File]::WriteAllText((Join-Path $root "src\tickets.gs"), $v3, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo src\uiActions.gs..." -ForegroundColor Cyan
$v4 = @'
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
'@
[System.IO.File]::WriteAllText((Join-Path $root "src\uiActions.gs"), $v4, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo src\extraction.gs..." -ForegroundColor Cyan
$v5 = @'
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
    const emailMatch = String(fromHeader || '').match(/[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9.-]+\.[a-z]{2,}/i);
    const senderEmail = emailMatch ? emailMatch[0] : '';
    const serialNumber = MessageFieldExtractor.extractSerialNumber_(body);
    const orderNumber = MessageFieldExtractor.extractOrderNumber_(body);
    let bodyWithoutSerial = serialNumber
      ? body.replace(/\bPP[\s_-]?\d{2}[\s_-]\d{3}[\s_-]\d{5}\b/i, ' ')
      : body;
    if (orderNumber) {
      bodyWithoutSerial = bodyWithoutSerial.replace(MessageFieldExtractor.ORDER_NUMBER_PATTERN_, ' ');
    }
    const shippingMarker = MessageFieldExtractor.SHIPPING_MARKER_.exec(body);
    const bodyBeforeShipping = shippingMarker ? bodyWithoutSerial.slice(0, shippingMarker.index) : bodyWithoutSerial;
    const shipping = MessageFieldExtractor.extractShippingBlock_(body);
    const customerPostalCode = MessageFieldExtractor.extractPostalCode_(bodyBeforeShipping);
    const shippingPostalCode = shipping.address ? MessageFieldExtractor.extractPostalCode_(shipping.address) : '';
    return {
      firstName: name.firstName,
      lastName: name.lastName,
      phone: MessageFieldExtractor.extractPhone_(bodyBeforeShipping),
      postalCode: customerPostalCode,
      country: MessageFieldExtractor.extractCountry_(body, senderEmail),
      address: MessageFieldExtractor.extractAddress_(bodyBeforeShipping),
      city: MessageFieldExtractor.extractCity_(bodyBeforeShipping, customerPostalCode),
      serialNumber: serialNumber,
      orderNumber: orderNumber,
      shippingRecipientFirstName: shipping.firstName,
      shippingRecipientLastName: shipping.lastName,
      shippingAddress: shipping.address,
      shippingRecipientPhone: shipping.phone,
      shippingRecipientCountry: shipping.address ? MessageFieldExtractor.extractCountry_(shipping.address, '') : '',
      shippingRecipientPostalCode: shippingPostalCode,
      shippingRecipientCity: shipping.address ? MessageFieldExtractor.extractCity_(shipping.address, shippingPostalCode) : ''
    };
  }

  /** @private */
  static get SHIPPING_MARKER_() {
    return /(?:ship\s*to|deliver\s*to|shipping\s*address|enviar\s*a|env[ií]o\s*a|direcci[oó]n\s*de\s*env[ií]o|livrer\s*[aà]|liefern\s*an)\s*[:\-]?\s*/i;
  }

  /** @private */
  static get ORDER_NUMBER_PATTERN_() {
    return /(?:pedido|order|reference|referencia|n[uú]mero de pedido|order\s*number)\s*[:#\-]?\s*#?\s*\d{3,10}/i;
  }

  /**
   * Looks for an explicit order/reference number, e.g. "Pedido #04521",
   * "Order number: 12345", "Nº pedido 00812".
   * @param {string} text
   * @return {string}
   * @private
   */
  static extractOrderNumber_(text) {
    const match = MessageFieldExtractor.ORDER_NUMBER_PATTERN_.exec(text);
    if (!match) return '';
    const digits = match[0].match(/\d{3,10}/)[0];
    return '#' + digits.replace(/^0+(?=\d)/, '').padStart(5, '0');
  }

  /**
   * Looks for a "ship to / deliver to / enviar a" block naming a different
   * recipient than the customer themselves, with its own address/phone.
   * @param {string} text
   * @return {{firstName: string, lastName: string, address: string, phone: string}}
   * @private
   */
  static extractShippingBlock_(text) {
    const match = MessageFieldExtractor.SHIPPING_MARKER_.exec(text);
    if (!match) return {firstName: '', lastName: '', address: '', phone: ''};

    const otherFieldLine = /(tel[eé]fono|phone|tel\.?|telefon|num[eé]ro|e-?mail)\s*[:\-]/i;
    const afterMarker = text.slice(match.index + match[0].length, match.index + match[0].length + 200);
    const lines = afterMarker.split(/\n+/).map(function(line) { return line.trim(); }).filter(Boolean);
    if (!lines.length) return {firstName: '', lastName: '', address: '', phone: ''};

    const nameLine = /^[A-ZÀ-ÖØ-Þ][\p{L}'-]+(?:\s+[A-ZÀ-ÖØ-Þ][\p{L}'-]+){0,2}$/u;
    let firstName = '';
    let lastName = '';
    let addressLines = lines;
    if (nameLine.test(lines[0])) {
      const parts = lines[0].split(/\s+/);
      firstName = parts[0];
      lastName = parts.slice(1).join(' ');
      addressLines = lines.slice(1);
    }

    // Only keep lines that look like a real address continuation (has a
    // digit, e.g. a house number or postal code) — rejects sign-offs like
    // "Un saludo," or "Best regards" that might follow in the same block.
    const addressOnlyLines = addressLines.filter(function(line) {
      return !otherFieldLine.test(line) && /\d/.test(line);
    });
    const address = addressOnlyLines.slice(0, 2).join(', ');
    const phone = MessageFieldExtractor.extractPhone_(afterMarker);
    return {firstName: firstName, lastName: lastName, address: address, phone: phone};
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

    const isYear = function(value) {
      const num = parseInt(value, 10);
      return value.length === 4 && num >= 1900 && num <= 2099;
    };

    const structuredPatterns = [
      /\b([A-Z]{1,2}\d[A-Z\d]?\s?\d[A-Z]{2})\b/,   // UK style
      /\b(\d{5}-\d{3})\b/,                          // BR style
      /\b(\d{2}-\d{3})\b/                           // PL style
    ];
    for (let i = 0; i < structuredPatterns.length; i += 1) {
      const match = text.match(structuredPatterns[i]);
      if (match) return match[1];
    }

    // Generic 4-6 digit fallback: collect every candidate, reject plausible
    // years (e.g. "2026" from a message date/timestamp), prefer one that
    // sits on the same line as the detected address.
    const candidates = text.match(/\b\d{4,6}\b/g) || [];
    const valid = candidates.filter(function(value) { return !isYear(value); });
    if (!valid.length) return '';

    const addressLine = MessageFieldExtractor.extractAddress_(text);
    const onAddressLine = valid.filter(function(value) { return addressLine.indexOf(value) !== -1; });
    return onAddressLine[0] || valid[0];
  }

  /**
   * @param {string} text
   * @param {string=} email Customer email, used as a fallback signal via its country-code TLD.
   * @return {string}
   * @private
   */
  static extractCountry_(text, email) {
    const countries = {
      'spain': 'España', 'españa': 'España', 'espana': 'España',
      'united kingdom': 'Reino Unido', 'uk': 'Reino Unido', 'england': 'Reino Unido', 'great britain': 'Reino Unido', 'reino unido': 'Reino Unido',
      'france': 'Francia', 'francia': 'Francia',
      'germany': 'Alemania', 'deutschland': 'Alemania', 'alemania': 'Alemania',
      'italy': 'Italia', 'italia': 'Italia',
      'portugal': 'Portugal',
      'netherlands': 'Países Bajos', 'nederland': 'Países Bajos', 'holanda': 'Países Bajos', 'holland': 'Países Bajos', 'países bajos': 'Países Bajos',
      'poland': 'Polonia', 'polska': 'Polonia', 'polonia': 'Polonia',
      'sweden': 'Suecia', 'sverige': 'Suecia', 'suecia': 'Suecia',
      'japan': 'Japón', '日本': 'Japón', 'japon': 'Japón', 'japón': 'Japón',
      'korea': 'Corea del Sur', '대한민국': 'Corea del Sur', 'south korea': 'Corea del Sur', 'corea del sur': 'Corea del Sur',
      'belgium': 'Bélgica', 'belgique': 'Bélgica', 'bélgica': 'Bélgica', 'belgica': 'Bélgica',
      'ireland': 'Irlanda', 'irlanda': 'Irlanda',
      'austria': 'Austria', 'österreich': 'Austria',
      'switzerland': 'Suiza', 'suiza': 'Suiza',
      'denmark': 'Dinamarca', 'dinamarca': 'Dinamarca',
      'norway': 'Noruega', 'noruega': 'Noruega',
      'finland': 'Finlandia', 'finlandia': 'Finlandia',
      'united states': 'Estados Unidos', 'usa': 'Estados Unidos', 'estados unidos': 'Estados Unidos',
      'mexico': 'México', 'méxico': 'México',
      'argentina': 'Argentina',
      'brazil': 'Brasil', 'brasil': 'Brasil',
      'canada': 'Canadá', 'canadá': 'Canadá',
      'greece': 'Grecia', 'grecia': 'Grecia',
      'czech republic': 'República Checa', 'czechia': 'República Checa', 'republica checa': 'República Checa', 'república checa': 'República Checa',
      'hungary': 'Hungría', 'hungria': 'Hungría', 'hungría': 'Hungría',
      'romania': 'Rumanía', 'rumania': 'Rumanía', 'rumanía': 'Rumanía',
      'turkey': 'Turquía', 'turquia': 'Turquía', 'turquía': 'Turquía',
      'china': 'China',
      'india': 'India',
      'australia': 'Australia',
      'new zealand': 'Nueva Zelanda', 'nueva zelanda': 'Nueva Zelanda'
    };
    const lower = text.toLowerCase();
    const found = Object.keys(countries)
      .filter(function(key) { return new RegExp('\\b' + key + '\\b').test(lower); })
      .sort(function(a, b) { return b.length - a.length; });
    if (found.length) return countries[found[0]];

    const tldMap = {
      es: 'España', uk: 'Reino Unido', fr: 'Francia', de: 'Alemania', it: 'Italia',
      pt: 'Portugal', nl: 'Países Bajos', pl: 'Polonia', se: 'Suecia', jp: 'Japón', kr: 'Corea del Sur',
      be: 'Bélgica', ie: 'Irlanda', at: 'Austria', ch: 'Suiza', dk: 'Dinamarca', no: 'Noruega',
      fi: 'Finlandia', mx: 'México', ar: 'Argentina', br: 'Brasil', ca: 'Canadá', gr: 'Grecia',
      cz: 'República Checa', hu: 'Hungría', ro: 'Rumanía', tr: 'Turquía', cn: 'China', in: 'India',
      au: 'Australia', nz: 'Nueva Zelanda'
    };
    const domainMatch = String(email || '').match(/\.([a-z]{2})$/i);
    if (domainMatch) {
      const tld = domainMatch[1].toLowerCase();
      if (tldMap[tld]) return tldMap[tld];
    }
    return '';
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
   * Best-effort city/town extraction: looks for the text immediately
   * following the given postal code on the same line (a very common
   * pattern: "Calle Mayor 5, 28013 Madrid"). Falls back to empty if no
   * postal code was found or nothing meaningful follows it.
   * @param {string} text
   * @param {string} postalCode
   * @return {string}
   * @private
   */
  static extractCity_(text, postalCode) {
    if (!postalCode) return '';
    const escaped = postalCode.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const match = text.match(new RegExp(escaped + '\\s+([\\p{L}][\\p{L}\\s\\-\'.]{1,40})', 'u'));
    if (!match) return '';
    const city = match[1].split(/[,\n]/)[0].trim();
    const otherFieldLine = /(tel[eé]fono|phone|telefon|num[eé]ro|e-?mail|pa[ií]s|country)/i;
    if (!city || otherFieldLine.test(city)) return '';
    return city;
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
[System.IO.File]::WriteAllText((Join-Path $root "src\extraction.gs"), $v5, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo html\CustomerShippingActions.html..." -ForegroundColor Cyan
$v6 = @'
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
      if (fillIfEmpty('cs-city', extracted.city)) filled += 1;
      if (fillIfEmpty('cs-country', extracted.country)) filled += 1;
      if (fillIfEmpty('cs-address', extracted.address)) filled += 1;
      if (fillIfEmpty('cs-shipping-address', extracted.shippingAddress)) filled += 1;
      if (fillIfEmpty('cs-recipient-first-name', extracted.shippingRecipientFirstName)) filled += 1;
      if (fillIfEmpty('cs-recipient-last-name', extracted.shippingRecipientLastName)) filled += 1;
      if (fillIfEmpty('cs-recipient-phone', extracted.shippingRecipientPhone)) filled += 1;
      if (fillIfEmpty('cs-recipient-country', extracted.shippingRecipientCountry)) filled += 1;
      if (fillIfEmpty('cs-recipient-postal-code', extracted.shippingRecipientPostalCode)) filled += 1;
      if (fillIfEmpty('cs-recipient-city', extracted.shippingRecipientCity)) filled += 1;
      if (extracted.serialNumber && fillIfEmpty('ta-serial-number', extracted.serialNumber)) filled += 1;
      if (extracted.orderNumber && fillIfEmpty('ta-order-number', extracted.orderNumber)) filled += 1;

      let addedErrors = 0;
      let addedSolutions = 0;
      const columns = window.__ppIssuesColumns;
      if (columns && extracted.suggestedErrors && extracted.suggestedErrors.length) {
        addedErrors = columns.errors.addItems(extracted.suggestedErrors);
      }
      if (columns && extracted.suggestedSolutions && extracted.suggestedSolutions.length) {
        addedSolutions = columns.solutions.addItems(extracted.suggestedSolutions);
      }

      const parts = [];
      parts.push(filled ? 'Se han rellenado ' + filled + ' campos desde los mensajes.' : 'No se encontraron datos nuevos en los mensajes.');
      if (addedErrors) parts.push(addedErrors + ' error' + (addedErrors === 1 ? '' : 'es') + ' añadido' + (addedErrors === 1 ? '' : 's') + ' automáticamente.');
      if (addedSolutions) parts.push(addedSolutions + ' solución' + (addedSolutions === 1 ? '' : 'es') + ' añadida' + (addedSolutions === 1 ? '' : 's') + ' automáticamente.');
      if (addedErrors || addedSolutions) parts.push('Revísalos antes de guardar.');
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
    extractButton.textContent = 'Analizar mensajes y rellenar todo';
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
    wrap.appendChild(createField('cs-city', 'Población', customer.city, 'Madrid'));

    wrap.appendChild(sectionLabel('Envío'));
    wrap.appendChild(createField('cs-recipient-first-name', 'Nombre del destinatario', ticket.shippingRecipientFirstName, 'Quién recibe el paquete'));
    wrap.appendChild(createField('cs-recipient-last-name', 'Apellidos del destinatario', ticket.shippingRecipientLastName, ''));
    wrap.appendChild(createField('cs-recipient-phone', 'Teléfono del destinatario', ticket.shippingRecipientPhone, 'Teléfono de contacto'));
    wrap.appendChild(createField('cs-shipping-address', 'Dirección de envío', ticket.shippingAddress, 'Si es distinta de la dirección del cliente', true));
    wrap.appendChild(createField('cs-recipient-country', 'País del destinatario', ticket.shippingRecipientCountry, 'España'));
    wrap.appendChild(createField('cs-recipient-postal-code', 'Código postal del destinatario', ticket.shippingRecipientPostalCode, '08001'));
    wrap.appendChild(createField('cs-recipient-city', 'Población del destinatario', ticket.shippingRecipientCity, 'Madrid'));

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
[System.IO.File]::WriteAllText((Join-Path $root "html\CustomerShippingActions.html"), $v6, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo html\NewTicketScripts.html..." -ForegroundColor Cyan
$v7 = @'
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
            '<select id="nt-priority">' +
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
[System.IO.File]::WriteAllText((Join-Path $root "html\NewTicketScripts.html"), $v7, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host ""
Write-Host "Verificando..." -ForegroundColor Cyan
Select-String -Path html\CustomerShippingActions.html -Pattern "Poblacion|Poblaci.n"
Select-String -Path html\NewTicketScripts.html -Pattern "Poblacion|Poblaci.n"

Write-Host ""
Write-Host "Si salieron 2-4 lineas arriba, ejecuta: npm test  y  npm run deploy" -ForegroundColor Cyan
Write-Host "Luego ejecuta install() una vez." -ForegroundColor Cyan
