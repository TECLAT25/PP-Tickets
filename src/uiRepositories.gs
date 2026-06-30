/** Read model for ticket conversation messages. */
class UiMessageReadRepository {
  constructor() {
    this.sheet_ = AppConfig.getSheet(APP.SHEETS.MESSAGES);
    this.headers_ = UiSheetMapper.headerMap(this.sheet_);
  }

  /** @param {string} ticketId @return {Array<Object>} */
  listByTicketId(ticketId) {
    if (this.sheet_.getLastRow() <= 1) {
      return [];
    }
    const values = this.sheet_.getRange(
      2, 1, this.sheet_.getLastRow() - 1, this.sheet_.getLastColumn()
    ).getValues();
    return values
      .filter(function(row) {
        return String(UiSheetMapper.value(row, this.headers_, 'Ticket ID')) === String(ticketId);
      }, this)
      .map(function(row) {
        return {
          id: String(UiSheetMapper.value(row, this.headers_, 'Message ID') || ''),
          gmailMessageId: String(UiSheetMapper.value(row, this.headers_, 'Gmail Message ID') || ''),
          direction: String(UiSheetMapper.value(row, this.headers_, 'Direction') || ''),
          from: String(UiSheetMapper.value(row, this.headers_, 'From') || ''),
          to: String(UiSheetMapper.value(row, this.headers_, 'To') || ''),
          cc: String(UiSheetMapper.value(row, this.headers_, 'Cc') || ''),
          subject: String(UiSheetMapper.value(row, this.headers_, 'Subject') || ''),
          sentAt: UiSheetMapper.value(row, this.headers_, 'Sent At'),
          body: String(
            UiSheetMapper.value(row, this.headers_, 'Body Text') ||
            UiSheetMapper.value(row, this.headers_, 'Body Preview') || ''
          ),
          attachmentCount: Number(UiSheetMapper.value(row, this.headers_, 'Attachment Count') || 0),
          driveFolderId: String(UiSheetMapper.value(row, this.headers_, 'Drive Folder ID') || '')
        };
      }, this)
      .sort(function(left, right) {
        return new Date(left.sentAt).getTime() - new Date(right.sentAt).getTime();
      });
  }
}

/** Read model for the customer associated with a ticket. */
class UiCustomerReadRepository {
  constructor() {
    this.sheet_ = AppConfig.getSheet(APP.SHEETS.CUSTOMERS);
    this.headers_ = UiSheetMapper.headerMap(this.sheet_);
  }

  /** @param {Object} ticket @return {Object|null} */
  findForTicket(ticket) {
    if (this.sheet_.getLastRow() <= 1) {
      return null;
    }
    const rows = this.sheet_.getRange(
      2, 1, this.sheet_.getLastRow() - 1, this.sheet_.getLastColumn()
    ).getValues();
    const customerId = String(ticket.customerId || '');
    const email = String(ticket.customerEmail || '').toLowerCase();
    const row = rows.filter(function(candidate) {
      const candidateId = String(UiSheetMapper.value(candidate, this.headers_, 'Customer ID') || '');
      const candidateEmail = String(UiSheetMapper.value(candidate, this.headers_, 'Email') || '').toLowerCase();
      return (customerId && candidateId === customerId) || (email && candidateEmail === email);
    }, this)[0];
    if (!row) {
      return null;
    }
    return {
      id: String(UiSheetMapper.value(row, this.headers_, 'Customer ID') || ''),
      email: String(UiSheetMapper.value(row, this.headers_, 'Email') || ''),
      name: String(UiSheetMapper.value(row, this.headers_, 'Name') || ''),
      phone: String(UiSheetMapper.value(row, this.headers_, 'Phone') || ''),
      locale: String(UiSheetMapper.value(row, this.headers_, 'Locale') || ''),
      company: String(UiSheetMapper.value(row, this.headers_, 'Company') || ''),
      createdAt: UiSheetMapper.value(row, this.headers_, 'Created At'),
      updatedAt: UiSheetMapper.value(row, this.headers_, 'Updated At'),
      notes: String(UiSheetMapper.value(row, this.headers_, 'Notes') || '')
    };
  }
}

/** Shared header-based mapping helpers for UI read models. */
class UiSheetMapper {
  /** @param {GoogleAppsScript.Spreadsheet.Sheet} sheet @return {Object<string, number>} */
  static headerMap(sheet) {
    const headers = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getDisplayValues()[0];
    const map = {};
    headers.forEach(function(header, index) {
      if (header) {
        map[header] = index;
      }
    });
    return map;
  }

  /** @param {Array<*>} row @param {Object<string, number>} map @param {string} header @return {*} */
  static value(row, map, header) {
    return map[header] == null ? '' : row[map[header]];
  }
}
