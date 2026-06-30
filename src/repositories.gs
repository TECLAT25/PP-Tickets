/** Sheets-backed ticket repository with an in-memory thread index. */
class SheetTicketRepository {
  constructor() {
    this.sheet_ = AppConfig.getSheet(APP.SHEETS.TICKETS);
    this.byThreadId_ = {};
    if (this.sheet_.getLastRow() > 1) {
      this.sheet_.getRange(2, 1, this.sheet_.getLastRow() - 1, 15).getValues()
        .forEach(function(row, index) {
          if (row[6]) {
            this.byThreadId_[String(row[6])] = SheetTicketRepository.fromRow_(row, index + 2);
          }
        }, this);
    }
  }

  /** @param {string} threadId @return {Object|null} */
  findByThreadId(threadId) {
    return this.byThreadId_[String(threadId)] || null;
  }

  /**
   * @param {Object} record
   * @return {Object}
   */
  create(record) {
    const row = [
      record.id, record.status, record.priority, record.subject, '', record.customerEmail,
      record.threadId, '', record.createdAt, record.updatedAt, record.lastMessageAt, '',
      '', '', record.version
    ];
    this.sheet_.appendRow(row);
    const ticket = SheetTicketRepository.fromRow_(row, this.sheet_.getLastRow());
    this.byThreadId_[String(record.threadId)] = ticket;
    return ticket;
  }

  /** @param {Object} ticket @param {Object} changes */
  updateConversation(ticket, changes) {
    const row = this.sheet_.getRange(ticket.rowNumber, 1, 1, 15).getValues()[0];
    row[1] = changes.status;
    row[3] = changes.subject;
    row[5] = changes.customerEmail;
    row[9] = changes.updatedAt;
    row[10] = changes.lastMessageAt;
    row[12] = changes.driveFolderId;
    row[14] = changes.version;
    this.sheet_.getRange(ticket.rowNumber, 1, 1, row.length).setValues([row]);
    const updated = SheetTicketRepository.fromRow_(row, ticket.rowNumber);
    this.byThreadId_[String(updated.threadId)] = updated;
  }

  /** @param {Array<*>} row @param {number} rowNumber @return {Object} @private */
  static fromRow_(row, rowNumber) {
    return {
      rowNumber: rowNumber,
      id: String(row[0]),
      status: String(row[1]),
      priority: String(row[2]),
      subject: String(row[3]),
      customerEmail: String(row[5]),
      threadId: String(row[6]),
      createdAt: row[8],
      updatedAt: row[9],
      lastMessageAt: row[10],
      driveFolderId: String(row[12] || ''),
      version: String(row[14] || '')
    };
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
      record.attachmentCount, record.driveFolderId, record.createdAt
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
