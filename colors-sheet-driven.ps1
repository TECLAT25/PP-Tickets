# colors-sheet-driven.ps1
# Nueva hoja "Colors": el color de cada Estado/Prioridad/Categoria
# viene del relleno de su celda en Sheets, no del codigo.
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
    COLORS: 'Colors',
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
  Object.freeze({name: 'Colors', headers: Object.freeze([
    'Type', 'Value', 'Label', 'Color'
  ]), color: '#F439A0'}),
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

Write-Host "Escribiendo src\install.gs..." -ForegroundColor Cyan
$v1 = @'
/** Installer for the complete PP Tickets workspace. */
class AppInstaller {
  /**
   * Installs or repairs the application without deleting existing business data.
   * @return {{ok: boolean, version: string, spreadsheetId: string, sheets: Array<string>}}
   */
  static run() {
    const lock = LockService.getScriptLock();
    if (!lock.tryLock(APP.LOCK_TIMEOUT_MS)) {
      throw new AppError('Another installation is already running.', 'INSTALL_LOCK_TIMEOUT');
    }

    const correlationId = AppUtils.uuid();
    try {
      const spreadsheet = AppConfig.getSpreadsheet(true);
      AppConfig.setSpreadsheetId(spreadsheet.getId());
      AppLogger.info('Installation started.', {spreadsheetId: spreadsheet.getId()}, correlationId);

      SHEET_SCHEMAS.forEach(function(schema) {
        AppInstaller.ensureSheet_(spreadsheet, schema);
      });
      SpreadsheetApp.flush();
      AppInstaller.seedSettings_(spreadsheet);
      AppInstaller.seedColors_(spreadsheet);
      AppInstaller.ensureDriveResources_();
      AppInstaller.ensureGmailResources_();
      AppInstaller.mergeDuplicateOpenTickets_();
      AppInstaller.revertForcedTicketClosures_();
      const triggerStatus = AppInstaller.ensureTriggers_();
      AppInstaller.refreshDashboard_(spreadsheet);

      AppConfig.getProperties().setProperty(APP.PROPERTY_KEYS.INSTALLED_VERSION, APP_VERSION);
      AppConfig.clearCache();
      SpreadsheetApp.flush();
      AppLogger.info('Installation completed.', {version: APP_VERSION, triggers: triggerStatus}, correlationId);

      return {
        ok: true,
        version: APP_VERSION,
        spreadsheetId: spreadsheet.getId(),
        sheets: SHEET_SCHEMAS.map(function(schema) { return schema.name; }),
        triggers: triggerStatus
      };
    } catch (error) {
      AppLogger.error('Installation failed.', {
        error: error && error.message ? error.message : String(error),
        stack: error && error.stack ? error.stack : ''
      }, correlationId);
      throw error;
    } finally {
      lock.releaseLock();
    }
  }

  /**
   * Creates and formats a sheet, rejecting conflicting populated headers.
   * @param {GoogleAppsScript.Spreadsheet.Spreadsheet} spreadsheet
   * @param {{name: string, headers: Array<string>, color: string}} schema
   * @private
   */
  static ensureSheet_(spreadsheet, schema) {
    let sheet = spreadsheet.getSheetByName(schema.name);
    if (!sheet) {
      sheet = spreadsheet.insertSheet(schema.name);
    }

    const columnCount = schema.headers.length;
    if (sheet.getMaxColumns() < columnCount) {
      sheet.insertColumnsAfter(sheet.getMaxColumns(), columnCount - sheet.getMaxColumns());
    }

    const headerRange = sheet.getRange(1, 1, 1, columnCount);
    const existing = headerRange.getDisplayValues()[0];
    schema.headers.forEach(function(header, index) {
      if (existing[index] && existing[index] !== header) {
        throw new AppError(
          'Schema conflict in ' + schema.name + ' column ' + (index + 1) + '.',
          'SHEET_SCHEMA_CONFLICT',
          {sheet: schema.name, expected: header, actual: existing[index]}
        );
      }
    });

    headerRange.setValues([schema.headers.slice()])
      .setFontWeight('bold')
      .setFontColor('#FFFFFF')
      .setBackground('#202124')
      .setHorizontalAlignment('left');
    sheet.setFrozenRows(1);
    sheet.setTabColor(schema.color);
    const tableRange = sheet.getRange(1, 1, sheet.getMaxRows(), columnCount);
    const filter = sheet.getFilter();
    if (filter && filter.getRange().getNumColumns() !== columnCount) {
      filter.remove();
    }
    if (!sheet.getFilter()) {
      tableRange.createFilter();
    }
    const dataRange = sheet.getRange(2, 1, sheet.getMaxRows() - 1, columnCount);
    const bandings = sheet.getBandings();
    if (bandings.length === 0 && sheet.getMaxRows() > 1) {
      dataRange.applyRowBanding(SpreadsheetApp.BandingTheme.LIGHT_GREY, false, false);
    } else if (bandings.length > 0) {
      bandings[0].setRange(dataRange);
    }
    sheet.autoResizeColumns(1, columnCount);

    AppInstaller.forcePlainTextColumns_(sheet, schema, columnCount);
  }

  /**
   * Prevents Sheets from silently reinterpreting version-like text (e.g. "2.3.2")
   * as a date, which happens for locale-sensitive dotted numeric strings.
   * @param {GoogleAppsScript.Spreadsheet.Sheet} sheet
   * @param {{name: string, headers: Array<string>}} schema
   * @param {number} columnCount
   * @private
   */
  static forcePlainTextColumns_(sheet, schema, columnCount) {
    const textHeaders = schema.name === 'Dashboard' ? ['Value'] : ['Version'];
    textHeaders.forEach(function(header) {
      const columnIndex = schema.headers.indexOf(header);
      if (columnIndex === -1) return;
      sheet.getRange(2, columnIndex + 1, sheet.getMaxRows() - 1, 1).setNumberFormat('@');
    });
  }

  /** @param {GoogleAppsScript.Spreadsheet.Spreadsheet} spreadsheet @private */
  /**
   * One-time seed of the "Colors" sheet: one row per Status/Priority/
   * Category value, with a default background color painted onto the
   * "Color" cell. The app reads each cell's fill color at runtime, so the
   * agent can change any value's color just by repainting that cell in
   * Sheets — no code changes needed.
   * @param {Spreadsheet} spreadsheet
   * @private
   */
  static seedColors_(spreadsheet) {
    const sheet = spreadsheet.getSheetByName(APP.SHEETS.COLORS);
    const existing = sheet.getLastRow() > 1
      ? sheet.getRange(2, 1, sheet.getLastRow() - 1, 2).getDisplayValues().map(function(row) { return row[0] + '|' + row[1]; })
      : [];

    const defaults = [
      ['STATUS', 'NEW', 'Nuevo', '#dcecfa'],
      ['STATUS', 'OPEN', 'Abierto', '#faf0dd'],
      ['STATUS', 'PENDING_CUSTOMER', 'Esperando cliente', '#fce4d1'],
      ['STATUS', 'RESOLVED', 'Resuelto', '#e3f3e8'],
      ['STATUS', 'CLOSED', 'Cerrado', '#e6e0d6'],
      ['STATUS', 'VOID', 'Nulo', '#e6e0d6'],
      ['PRIORITY', 'LOW', 'Baja', '#e3f3e8'],
      ['PRIORITY', 'NORMAL', 'Normal', '#faf0dd'],
      ['PRIORITY', 'HIGH', 'Alta', '#fce4d1'],
      ['PRIORITY', 'CRITICAL', 'Crítica', '#fbe7e2'],
      ['CATEGORY', 'GENERAL', 'General', '#e6e0d6'],
      ['CATEGORY', 'TECHNICAL', 'Técnico', '#e9e4f9'],
      ['CATEGORY', 'WARRANTY', 'Garantía', '#d9f0ec'],
      ['CATEGORY', 'SHIPPING', 'Envío', '#dcecfa'],
      ['CATEGORY', 'BILLING', 'Facturación', '#fbdeeb'],
      ['CATEGORY', 'PRODUCT', 'Producto', '#f1e2f8'],
      ['CATEGORY', 'OTHER', 'Otro', '#e6e0d6']
    ].filter(function(row) { return existing.indexOf(row[0] + '|' + row[1]) === -1; });

    if (!defaults.length) return;

    const startRow = sheet.getLastRow() + 1;
    const values = defaults.map(function(row) { return [row[0], row[1], row[2], row[3]]; });
    sheet.getRange(startRow, 1, values.length, 4).setValues(values);
    const colorColumn = sheet.getRange(startRow, 4, values.length, 1);
    colorColumn.setBackgrounds(defaults.map(function(row) { return [row[3]]; }));
  }

  static seedSettings_(spreadsheet) {
    const sheet = spreadsheet.getSheetByName(APP.SHEETS.SETTINGS);
    const existingKeys = sheet.getLastRow() > 1 ?
      sheet.getRange(2, 1, sheet.getLastRow() - 1, 1).getDisplayValues().map(function(row) {
        return row[0];
      }) : [];
    const user = AppUtils.currentUserEmail();
    const now = new Date();
    const rows = DEFAULT_SETTINGS
      .filter(function(setting) { return existingKeys.indexOf(setting[0]) === -1; })
      .map(function(setting) { return [setting[0], setting[1], setting[2], now, user]; });
    if (rows.length) {
      sheet.getRange(sheet.getLastRow() + 1, 1, rows.length, rows[0].length).setValues(rows);
    }
  }

  /**
   * One-time fix for an earlier version of the merge step that left
   * merged-away tickets behind (either force-closed, or reopened by a
   * previous fix) instead of removing them. Deletes any ticket that has
   * zero messages and a "Fusionado con" note — it's a redundant, empty
   * artifact of an earlier merge, not a real ticket needing attention.
   * Runs only once (separate guard from the merge step itself).
   * @private
   */
  static revertForcedTicketClosures_() {
    const properties = AppConfig.getProperties();
    const flagKey = 'EMPTY_MERGED_TICKETS_DELETED_V1';
    if (properties.getProperty(flagKey)) return;

    try {
      const ticketRepo = new SheetTicketRepository();
      const messagesSheet = AppConfig.getSheet(APP.SHEETS.MESSAGES);
      const messagesHeaders = messagesSheet.getRange(1, 1, 1, messagesSheet.getLastColumn()).getDisplayValues()[0];
      const ticketIdCol = messagesHeaders.indexOf('Ticket ID') + 1;
      const lastMessageRow = messagesSheet.getLastRow();
      const messageTicketIds = lastMessageRow > 1
        ? messagesSheet.getRange(2, ticketIdCol, lastMessageRow - 1, 1).getValues().map(function(row) { return String(row[0]); })
        : [];

      const toDelete = ticketRepo.listAll().filter(function(ticket) {
        const notes = String(ticket.notes || '');
        if (notes.indexOf('Fusionado con ') === -1) return false;
        return messageTicketIds.indexOf(ticket.id) === -1;
      });

      const deletedIds = [];
      toDelete.forEach(function(ticket) {
        if (ticketRepo.delete(ticket.id)) deletedIds.push(ticket.id);
      });

      AppLogger.info('Deleted empty tickets left behind by an earlier merge.', {
        count: deletedIds.length,
        ticketIds: deletedIds.join(', ')
      });
    } catch (error) {
      AppLogger.error('Deleting empty merged tickets failed; will retry on next install().', {error: error.message});
      return;
    }

    properties.setProperty(flagKey, new Date().toISOString());
  }

  /**
   * One-time cleanup: merges any pre-existing duplicate non-closed tickets
   * per customer into a single ticket, moving their messages and combining
   * notes/tags/errors/solutions. The merged-away ticket rows are deleted
   * (their content already lives in the kept ticket) — never closed, that
   * decision stays with the agent. Runs only once ever (guarded by a
   * script property), so re-running install() later is a no-op here.
   * @private
   */
  static mergeDuplicateOpenTickets_() {
    const properties = AppConfig.getProperties();
    const flagKey = 'DUPLICATE_TICKETS_MERGED_V2';
    if (properties.getProperty(flagKey)) return;

    try {
      const ticketRepo = new SheetTicketRepository();
      const allTickets = ticketRepo.listAll();

      const byCustomer = {};
      allTickets.forEach(function(ticket) {
        const email = String(ticket.customerEmail || '').trim().toLowerCase();
        if (!email || ticket.status === 'CLOSED') return;
        if (!byCustomer[email]) byCustomer[email] = [];
        byCustomer[email].push(ticket);
      });

      const messagesSheet = AppConfig.getSheet(APP.SHEETS.MESSAGES);
      const messagesHeaders = messagesSheet.getRange(1, 1, 1, messagesSheet.getLastColumn()).getDisplayValues()[0];
      const ticketIdCol = messagesHeaders.indexOf('Ticket ID') + 1;
      const lastMessageRow = messagesSheet.getLastRow();
      const messageTicketIds = lastMessageRow > 1
        ? messagesSheet.getRange(2, ticketIdCol, lastMessageRow - 1, 1).getValues()
        : [];

      let totalMerged = 0;
      const summaryLines = [];

      Object.keys(byCustomer).forEach(function(email) {
        const group = byCustomer[email];
        if (group.length < 2) return;

        group.sort(function(a, b) {
          const aHasThread = a.threadId ? 1 : 0;
          const bHasThread = b.threadId ? 1 : 0;
          if (aHasThread !== bHasThread) return bHasThread - aHasThread;
          return new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime();
        });

        let primary = group[0];
        const others = group.slice(1);
        const mergedIds = [];

        others.forEach(function(other) {
          let moved = 0;
          for (let i = 0; i < messageTicketIds.length; i += 1) {
            if (String(messageTicketIds[i][0]) === other.id) {
              messagesSheet.getRange(i + 2, ticketIdCol).setValue(primary.id);
              moved += 1;
            }
          }

          const combinedNotes = [primary.notes, other.notes].filter(Boolean).join('\n---\n');
          const combinedTags = TicketManager.normalizeTags_([primary.tags, other.tags].filter(Boolean).join(','));
          const combinedErrors = TicketManager.normalizeTags_([primary.detectedErrors, other.detectedErrors].filter(Boolean).join(','));
          const combinedSolutions = TicketManager.normalizeTags_([primary.detectedSolutions, other.detectedSolutions].filter(Boolean).join(','));

          const primaryUpdates = {
            notes: combinedNotes,
            tags: combinedTags,
            detectedErrors: combinedErrors,
            detectedSolutions: combinedSolutions,
            updatedAt: new Date()
          };
          ['shippingAddress', 'shippingRecipient', 'shippingRecipientPhone',
            'shippingRecipientFirstName', 'shippingRecipientLastName',
            'shippingRecipientCountry', 'shippingRecipientPostalCode',
            'orderNumber', 'serialNumber'].forEach(function(field) {
            if (!primary[field] && other[field]) primaryUpdates[field] = other[field];
          });
          primary = ticketRepo.update(primary.id, primaryUpdates);

          ticketRepo.delete(other.id);

          mergedIds.push(other.id + ' (' + moved + ' mensajes, ticket eliminado)');
          totalMerged += 1;
        });

        summaryLines.push(email + ': se mantiene ' + primary.id + ', fusionados -> ' + mergedIds.join(', '));
      });

      AppLogger.info('One-time duplicate ticket merge completed.', {
        totalMerged: totalMerged,
        details: summaryLines.join(' | ')
      });
    } catch (error) {
      AppLogger.error('One-time duplicate ticket merge failed; will retry on next install().', {error: error.message});
      return; // Don't set the flag — try again next time install() runs.
    }

    properties.setProperty(flagKey, new Date().toISOString());
  }

  /** Creates or validates the application's root Drive folder. @private */
  static ensureDriveResources_() {
    const properties = AppConfig.getProperties();
    const existingId = properties.getProperty(APP.PROPERTY_KEYS.DRIVE_FOLDER_ID);
    if (existingId) {
      try {
        DriveApp.getFolderById(existingId).getName();
        return;
      } catch (error) {
        AppLogger.warn('Configured Drive folder is unavailable; recreating it.', {folderId: existingId});
      }
    }
    const folders = DriveApp.getFoldersByName(APP.NAME);
    const folder = folders.hasNext() ? folders.next() : DriveApp.createFolder(APP.NAME);
    properties.setProperty(APP.PROPERTY_KEYS.DRIVE_FOLDER_ID, folder.getId());
  }

  /** Creates the configured Gmail processing label. @private */
  static ensureGmailResources_() {
    const labelName = DEFAULT_SETTINGS.filter(function(setting) {
      return setting[0] === 'SUPPORT_LABEL';
    })[0][1];
    if (!GmailApp.getUserLabelByName(labelName)) {
      GmailApp.createLabel(labelName);
    }
  }

  /** Creates managed background triggers when the manifest permission is available. @private */
  static ensureTriggers_() {
    try {
      TriggerManager.ensureMaintenanceTrigger();
      TriggerManager.ensureGmailSyncTrigger();
      return {ok: true, enabled: true};
    } catch (error) {
      const message = error && error.message ? error.message : String(error);
      if (message.indexOf('script.scriptapp') !== -1 || message.indexOf('ScriptApp.getProjectTriggers') !== -1) {
        AppLogger.warn('Background triggers were not installed because script.scriptapp permission is missing.', {
          error: message,
          nextStep: 'Add https://www.googleapis.com/auth/script.scriptapp to appsscript.json and run clasp push, then authorize again.'
        });
        return {ok: false, enabled: false, reason: 'MISSING_SCRIPTAPP_SCOPE'};
      }
      throw error;
    }
  }

  /**
   * Rebuilds installation metrics without overwriting user data elsewhere.
   * @param {GoogleAppsScript.Spreadsheet.Spreadsheet} spreadsheet
   */
  static refreshDashboard_(spreadsheet) {
    const repository = new SheetTicketRepository();
    new TicketDashboardService(
      repository,
      spreadsheet.getSheetByName(APP.SHEETS.DASHBOARD),
      function() { return new Date(); }
    ).refresh();
  }
}

/**
 * Public installation entry point.
 * @return {{ok: boolean, version: string, spreadsheetId: string, sheets: Array<string>}}
 */
function install() {
  return AppInstaller.run();
}
'@
[System.IO.File]::WriteAllText((Join-Path $root "src\install.gs"), $v1, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo src\uiActions.gs..." -ForegroundColor Cyan
$v2 = @'
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
'@
[System.IO.File]::WriteAllText((Join-Path $root "src\uiActions.gs"), $v2, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo html\ColorSchemeScripts.html..." -ForegroundColor Cyan
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

  let colorMap = null;

  function typeForValue(value) {
    if (['NEW', 'OPEN', 'PENDING_CUSTOMER', 'RESOLVED', 'CLOSED', 'VOID'].indexOf(value) !== -1) return 'STATUS';
    if (['LOW', 'NORMAL', 'HIGH', 'CRITICAL'].indexOf(value) !== -1) return 'PRIORITY';
    if (['GENERAL', 'TECHNICAL', 'WARRANTY', 'SHIPPING', 'BILLING', 'PRODUCT', 'OTHER'].indexOf(value) !== -1) return 'CATEGORY';
    return '';
  }

  // Picks black or white text for readable contrast against a given hex background.
  function readableTextColor(hex) {
    const clean = String(hex || '').replace('#', '');
    if (clean.length !== 6) return '';
    const r = parseInt(clean.substr(0, 2), 16);
    const g = parseInt(clean.substr(2, 2), 16);
    const b = parseInt(clean.substr(4, 2), 16);
    const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
    return luminance > 0.6 ? '#1a1a1a' : '#ffffff';
  }

  function colorFor(value) {
    if (!colorMap) return null;
    const type = typeForValue(value);
    if (!type || !colorMap[type]) return null;
    return colorMap[type][value] || null;
  }

  function applyColors() {
    if (!colorMap) return;

    document.querySelectorAll('.chip[data-value]').forEach(function (chip) {
      const bg = colorFor(chip.dataset.value);
      if (!bg) return;
      chip.style.backgroundColor = bg;
      chip.style.color = readableTextColor(bg);
    });

    document.querySelectorAll('select.color-coded[data-value]').forEach(function (select) {
      const bg = colorFor(select.dataset.value);
      if (!bg) {
        select.style.backgroundColor = '';
        select.style.color = '';
        select.style.borderColor = '';
        return;
      }
      select.style.backgroundColor = bg;
      select.style.color = readableTextColor(bg);
      select.style.borderColor = bg;
    });
  }

  function start() {
    callServer('getUiColorMap').then(unwrap).then(function (map) {
      colorMap = map;
      applyColors();
    }).catch(function () {
      // If this fails, the CSS defaults already in place still apply.
    });

    let pending = false;
    const observer = new MutationObserver(function () {
      if (pending) return;
      pending = true;
      window.setTimeout(function () {
        pending = false;
        applyColors();
      }, 150);
    });
    observer.observe(document.body, {childList: true, subtree: true});

    document.addEventListener('change', function (event) {
      if (event.target && event.target.matches && event.target.matches('select.color-coded')) {
        applyColors();
      }
    });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
</script>
'@
[System.IO.File]::WriteAllText((Join-Path $root "html\ColorSchemeScripts.html"), $v3, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo html\Index.html..." -ForegroundColor Cyan
$v4 = @'
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
    <?!= include('html/ColorSchemeScripts'); ?>
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
[System.IO.File]::WriteAllText((Join-Path $root "html\Index.html"), $v4, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host ""
Write-Host "Verificando..." -ForegroundColor Cyan
Select-String -Path src\install.gs -Pattern "seedColors_"
Select-String -Path html\ColorSchemeScripts.html -Pattern "getUiColorMap"

Write-Host ""
Write-Host "Si salieron lineas arriba, ejecuta: npm test  y  npm run deploy" -ForegroundColor Cyan
Write-Host "Luego ejecuta install() una vez para crear y rellenar la hoja Colors." -ForegroundColor Cyan
