/** Header-aware Sheets repository for ticket lifecycle and discovery. */
class SheetTicketRepository {
  constructor() {
    this.sheet_ = AppConfig.getSheet(APP.SHEETS.TICKETS);
    this.headers_ = this.sheet_.getRange(1, 1, 1, this.sheet_.getLastColumn()).getDisplayValues()[0];
    this.headerIndex_ = {};
    this.headers_.forEach(function(header, index) {
      if (header) {
        this.headerIndex_[header] = index;
      }
    }, this);
    ['Ticket ID', 'Status', 'Priority', 'Subject', 'Customer Email', 'Gmail Thread ID',
      'Created At', 'Updated At', 'Last Message At', 'SLA Due At', 'Drive Folder ID',
      'Tags', 'Version', 'Category'].forEach(function(header) {
      if (this.headerIndex_[header] == null) {
        throw new AppError(
          'Tickets sheet is missing the "' + header + '" column. Run install().',
          'TICKET_SCHEMA_OUTDATED',
          {header: header}
        );
      }
    }, this);
    this.reload_();
  }

  /** Rebuilds immutable ID indexes after external writes. @private */
  reload_() {
    this.byId_ = {};
    this.byThreadId_ = {};
    this.listAll().forEach(function(ticket) {
      this.byId_[ticket.id] = ticket;
      if (ticket.threadId) {
        this.byThreadId_[ticket.threadId] = ticket;
      }
    }, this);
  }

  /** @param {string} id @return {Object|null} */
  findById(id) {
    return this.byId_[String(id)] || null;
  }

  /** @param {string} threadId @return {Object|null} */
  findByThreadId(threadId) {
    return this.byThreadId_[String(threadId)] || null;
  }

  /** @return {Array<Object>} */
  listAll() {
    if (this.sheet_.getLastRow() <= 1) {
      return [];
    }
    return this.sheet_.getRange(2, 1, this.sheet_.getLastRow() - 1, this.headers_.length)
      .getValues()
      .map(function(row, index) { return this.fromRow_(row, index + 2); }, this);
  }

  /** @param {Object} record @return {Object} */
  create(record) {
    if (!record.id) {
      throw new AppError('Ticket ID is required.', 'TICKET_ID_REQUIRED');
    }
    if (this.findById(record.id)) {
      throw new AppError('Ticket ID already exists: ' + record.id, 'TICKET_DUPLICATE_ID');
    }
    if (record.threadId && this.findByThreadId(record.threadId)) {
      throw new AppError('Gmail thread already has a ticket.', 'TICKET_DUPLICATE_THREAD');
    }

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
      if (this.headerIndex_[mapping.header] != null && data[mapping.field] != null) {
        row[this.headerIndex_[mapping.header]] = data[mapping.field];
      }
    }, this);
    this.sheet_.appendRow(row);
    const ticket = this.fromRow_(row, this.sheet_.getLastRow());
    this.byId_[ticket.id] = ticket;
    if (ticket.threadId) {
      this.byThreadId_[ticket.threadId] = ticket;
    }
    return ticket;
  }

  /**
   * @param {string} ticketId
   * @param {Object} changes
   * @return {Object}
   */
  update(ticketId, changes) {
    const ticket = this.findById(ticketId);
    if (!ticket) {
      throw new AppError('Ticket not found: ' + ticketId, 'TICKET_NOT_FOUND', {ticketId: ticketId});
    }
    const row = this.sheet_.getRange(ticket.rowNumber, 1, 1, this.headers_.length).getValues()[0];
    const allowed = [
      'status', 'priority', 'category', 'subject', 'customerId', 'customerEmail',
      'assignedTo', 'updatedAt', 'lastMessageAt', 'slaDueAt', 'driveFolderId', 'tags', 'version'
    ];
    SheetTicketRepository.fields_().forEach(function(mapping) {
      if (allowed.indexOf(mapping.field) !== -1 &&
          Object.prototype.hasOwnProperty.call(changes, mapping.field)) {
        row[this.headerIndex_[mapping.header]] = changes[mapping.field];
      }
    }, this);
    this.sheet_.getRange(ticket.rowNumber, 1, 1, row.length).setValues([row]);
    const updated = this.fromRow_(row, ticket.rowNumber);
    this.byId_[updated.id] = updated;
    if (updated.threadId) {
      this.byThreadId_[updated.threadId] = updated;
    }
    return updated;
  }

  /** @param {Object} ticket @param {Object} changes @return {Object} */
  updateConversation(ticket, changes) {
    const updated = this.update(ticket.id, changes);
    Object.assign(ticket, updated);
    return updated;
  }

  /**
   * Searches and filters tickets in memory after a single Sheets read.
   * @param {Object} criteria
   * @return {{items: Array<Object>, total: number, offset: number, limit: number}}
   */
  search(criteria) {
    const filters = criteria || {};
    const query = String(filters.query || '').trim().toLowerCase();
    let tickets = this.listAll().filter(function(ticket) {
      if (!SheetTicketRepository.matches_(ticket.status, filters.status)) return false;
      if (!SheetTicketRepository.matches_(ticket.priority, filters.priority)) return false;
      if (!SheetTicketRepository.matches_(ticket.category, filters.category)) return false;
      if (!SheetTicketRepository.matches_(ticket.assignedTo, filters.assignedTo)) return false;
      if (filters.customerEmail &&
          ticket.customerEmail.toLowerCase() !== String(filters.customerEmail).toLowerCase()) return false;
      if (filters.slaBreached === true) {
        const due = ticket.slaDueAt instanceof Date ? ticket.slaDueAt : new Date(ticket.slaDueAt);
        if (['RESOLVED', 'CLOSED'].indexOf(ticket.status) !== -1 || Number.isNaN(due.getTime()) || due >= new Date()) {
          return false;
        }
      }
      if (filters.createdFrom && new Date(ticket.createdAt) < new Date(filters.createdFrom)) return false;
      if (filters.createdTo && new Date(ticket.createdAt) > new Date(filters.createdTo)) return false;
      if (query) {
        const haystack = [
          ticket.id, ticket.subject, ticket.customerEmail, ticket.customerId,
          ticket.assignedTo, ticket.tags, ticket.category
        ].join(' ').toLowerCase();
        if (haystack.indexOf(query) === -1) return false;
      }
      return true;
    });

    tickets.sort(function(left, right) {
      return new Date(right.updatedAt).getTime() - new Date(left.updatedAt).getTime();
    });
    const total = tickets.length;
    const offset = Math.max(0, Number(filters.offset) || 0);
    const limit = Math.max(1, Math.min(500, Number(filters.limit) || 100));
    return {items: tickets.slice(offset, offset + limit), total: total, offset: offset, limit: limit};
  }

  /** @return {Array<*>} @private */
  emptyRow_() {
    return this.headers_.map(function() { return ''; });
  }

  /** @param {Array<*>} row @param {number} rowNumber @return {Object} @private */
  fromRow_(row, rowNumber) {
    const ticket = {rowNumber: rowNumber};
    SheetTicketRepository.fields_().forEach(function(mapping) {
      const index = this.headerIndex_[mapping.header];
      ticket[mapping.field] = index == null ? '' : row[index];
    }, this);
    ['id', 'status', 'priority', 'category', 'subject', 'customerId', 'customerEmail',
      'threadId', 'assignedTo', 'driveFolderId', 'tags', 'version'].forEach(function(field) {
      ticket[field] = String(ticket[field] || '');
    });
    return ticket;
  }

  /** @param {*} actual @param {*=} expected @return {boolean} @private */
  static matches_(actual, expected) {
    if (expected == null || expected === '') return true;
    const values = Array.isArray(expected) ? expected : [expected];
    return values.map(function(value) { return String(value).toUpperCase(); })
      .indexOf(String(actual).toUpperCase()) !== -1;
  }

  /** @return {Array<{field: string, header: string}>} @private */
  static fields_() {
    return [
      {field: 'id', header: 'Ticket ID'},
      {field: 'status', header: 'Status'},
      {field: 'priority', header: 'Priority'},
      {field: 'subject', header: 'Subject'},
      {field: 'customerId', header: 'Customer ID'},
      {field: 'customerEmail', header: 'Customer Email'},
      {field: 'threadId', header: 'Gmail Thread ID'},
      {field: 'assignedTo', header: 'Assigned To'},
      {field: 'createdAt', header: 'Created At'},
      {field: 'updatedAt', header: 'Updated At'},
      {field: 'lastMessageAt', header: 'Last Message At'},
      {field: 'slaDueAt', header: 'SLA Due At'},
      {field: 'driveFolderId', header: 'Drive Folder ID'},
      {field: 'tags', header: 'Tags'},
      {field: 'version', header: 'Version'},
      {field: 'category', header: 'Category'}
    ];
  }
}

/** Sheets-backed message repository indexed by immutable Gmail message ID. */
class SheetMessageRepository {
  constructor() {
    this.sheet_ = AppConfig.getSheet(APP.SHEETS.MESSAGES);
    this.gmailMessageIds_ = {};
    if (this.sheet_.getLastRow() > 1) {
      this.sheet_.getRange(2, 3, this.sheet_.getLastRow() - 1, 1).getDisplayValues()
        .forEach(function(row) {
          if (row[0]) {
            this.gmailMessageIds_[row[0]] = true;
          }
        }, this);
    }
  }

  /** @param {string} gmailMessageId @return {boolean} */
  hasMessage(gmailMessageId) {
    return Boolean(this.gmailMessageIds_[String(gmailMessageId)]);
  }

  /** @param {Object} record */
  add(record) {
    if (this.hasMessage(record.gmailMessageId)) {
      return;
    }
    this.sheet_.appendRow([
      record.id, record.ticketId, record.gmailMessageId, record.direction, record.from,
      record.to, record.cc, record.subject, record.sentAt, record.bodyPreview,
      record.attachmentCount, record.driveFolderId, record.createdAt, record.bodyText || record.bodyPreview || ''
    ]);
    this.gmailMessageIds_[String(record.gmailMessageId)] = true;
  }
}

/** Idempotent Drive attachment persistence, partitioned by ticket. */
class DriveAttachmentStore {
  constructor() {
    this.root_ = null;
  }

  /**
   * @param {string} ticketId
   * @param {string} gmailMessageId
   * @param {Array<Object>} attachments
   * @return {{folderId: string, count: number}}
   */
  save(ticketId, gmailMessageId, attachments) {
    if (!attachments.length) {
      return {folderId: '', count: 0};
    }

    const folder = this.ticketFolder_(ticketId);
    let stored = 0;
    attachments.forEach(function(attachment, index) {
      const original = DriveAttachmentStore.safeName_(attachment.name || 'attachment');
      const fileName = gmailMessageId + '_' + (index + 1) + '_' + original;
      if (!folder.getFilesByName(fileName).hasNext()) {
        folder.createFile(attachment.blob).setName(fileName);
      }
      stored += 1;
    });
    return {folderId: folder.getId(), count: stored};
  }

  /** @param {string} ticketId @return {GoogleAppsScript.Drive.Folder} @private */
  ticketFolder_(ticketId) {
    const root = this.rootFolder_();
    const folders = root.getFoldersByName(ticketId);
    return folders.hasNext() ? folders.next() : root.createFolder(ticketId);
  }

  /** @return {GoogleAppsScript.Drive.Folder} @private */
  rootFolder_() {
    if (this.root_) {
      return this.root_;
    }
    const id = AppConfig.getProperties().getProperty(APP.PROPERTY_KEYS.DRIVE_FOLDER_ID);
    if (!id) {
      throw new AppError('The application Drive folder is not configured. Run install().', 'DRIVE_NOT_CONFIGURED');
    }
    this.root_ = DriveApp.getFolderById(id);
    return this.root_;
  }

  /** @param {string} name @return {string} @private */
  static safeName_(name) {
    return String(name).replace(/[\\/:*?"<>|\u0000-\u001F]/g, '_').slice(0, 180);
  }
}
