# fix-forced-closures.ps1
# Quita el cierre automatico de tickets al fusionar, y revierte a
# Abierto cualquier ticket que se cerrara por error con la version
# anterior.
$ErrorActionPreference = "Stop"
$root = Get-Location
$enc = New-Object System.Text.UTF8Encoding($false)

Write-Host "Escribiendo src/install.gs..." -ForegroundColor Cyan
$v0 = @'
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
   * One-time fix for an earlier version of the merge step that incorrectly
   * closed merged-away tickets automatically. Reopens any ticket that was
   * force-closed that way (identified by the "Fusionado con" note this app
   * itself writes), setting it back to OPEN so a human decides its real
   * status. Runs only once (separate guard from the merge step itself).
   * @private
   */
  static revertForcedTicketClosures_() {
    const properties = AppConfig.getProperties();
    const flagKey = 'FORCED_CLOSURES_REVERTED_V1';
    if (properties.getProperty(flagKey)) return;

    try {
      const ticketRepo = new SheetTicketRepository();
      const reverted = [];
      ticketRepo.listAll().forEach(function(ticket) {
        const notes = String(ticket.notes || '');
        if (ticket.status === 'CLOSED' && notes.indexOf('Fusionado con ') !== -1) {
          ticketRepo.update(ticket.id, {status: 'OPEN', updatedAt: new Date()});
          reverted.push(ticket.id);
        }
      });
      AppLogger.info('Reverted tickets that an earlier version incorrectly auto-closed during merge.', {
        count: reverted.length,
        ticketIds: reverted.join(', ')
      });
    } catch (error) {
      AppLogger.error('Reverting forced ticket closures failed; will retry on next install().', {error: error.message});
      return;
    }

    properties.setProperty(flagKey, new Date().toISOString());
  }

  /**
   * One-time cleanup: merges any pre-existing duplicate non-closed tickets
   * per customer into a single ticket, moving their messages and combining
   * notes/tags/errors/solutions. Runs only once ever (guarded by a script
   * property), so re-running install() later is a no-op here.
   * @private
   */
  static mergeDuplicateOpenTickets_() {
    const properties = AppConfig.getProperties();
    const flagKey = 'DUPLICATE_TICKETS_MERGED_V1';
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

          ticketRepo.update(other.id, {
            notes: (other.notes ? other.notes + '\n---\n' : '') + 'Fusionado con ' + primary.id,
            updatedAt: new Date()
          });

          mergedIds.push(other.id + ' (' + moved + ' mensajes)');
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
[System.IO.File]::WriteAllText((Join-Path $root "src\install.gs"), $v0, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host ""
Write-Host "Verificando..." -ForegroundColor Cyan
Select-String -Path src\install.gs -Pattern "revertForcedTicketClosures_"

Write-Host ""
Write-Host "Si salio arriba, ejecuta: npm test  y  npm run deploy" -ForegroundColor Cyan
Write-Host "Luego ejecuta install() una vez para revertir los tickets cerrados por error." -ForegroundColor Cyan
