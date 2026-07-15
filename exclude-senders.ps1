# exclude-senders.ps1
# Excluye no-reply@accounts.google.com y mbe@mbe3024.es de crear
# tickets al sincronizar Gmail (configurable via Settings > EXCLUDED_SENDERS).
$ErrorActionPreference = "Stop"
$root = Get-Location
$enc = New-Object System.Text.UTF8Encoding($false)

Write-Host "Escribiendo src\gmail.gs..." -ForegroundColor Cyan
$v0 = @'
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
    const baseQuery = this.settings_.get('SUPPORT_GMAIL_QUERY', 'in:anywhere newer_than:30d');
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
      excludedThreads: 0
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
    return GmailApp.search(query, 0, limit).map(function(thread) {
      return {
        id: thread.getId(),
        messages: thread.getMessages().map(function(message) {
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
[System.IO.File]::WriteAllText((Join-Path $root "src\gmail.gs"), $v0, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo src\menu.gs..." -ForegroundColor Cyan
$v1 = @'
/** Creates the spreadsheet menu when the container opens. */
function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu(APP.NAME)
    .addItem('Abrir aplicación', 'showApplicationDialog')
    .addSeparator()
    .addItem('Instalar o reparar', 'installFromMenu')
    .addItem('Sincronizar Gmail ahora', 'syncGmailFromMenu')
    .addItem('Activar sincronización en segundo plano', 'enableBackgroundSyncFromMenu')
    .addItem('Desactivar sincronización en segundo plano', 'disableBackgroundSyncFromMenu')
    .addSeparator()
    .addItem('Actualizar panel', 'refreshDashboard')
    .addSeparator()
    .addItem('Acerca de', 'showAbout')
    .addToUi();
}

/** @param {GoogleAppsScript.Events.SheetsOnOpen=} event */
function onInstall(event) {
  onOpen(event);
}

/** Runs installation with user-facing error handling. */
function installFromMenu() {
  const ui = SpreadsheetApp.getUi();
  try {
    const result = install();
    ui.alert(APP.NAME, 'Instalación completada. La versión ' + result.version + ' está lista.', ui.ButtonSet.OK);
  } catch (error) {
    const response = AppUtils.errorResponse(error);
    ui.alert(APP.NAME, response.error.message + '\n\nReferencia: ' + response.correlationId, ui.ButtonSet.OK);
  }
}

/** Runs Gmail synchronization from the spreadsheet menu. */
function syncGmailFromMenu() {
  const ui = SpreadsheetApp.getUi();
  try {
    const result = syncGmail();
    ui.alert(
      APP.NAME,
      'Sincronización de Gmail completada.\n\n' +
      'Tickets creados: ' + result.createdTickets + '\n' +
      'Mensajes añadidos: ' + result.createdMessages + '\n' +
      'Adjuntos guardados: ' + result.attachments + '\n' +
      'Hilos fallidos: ' + result.failedThreads + '\n' +
      'Remitentes excluidos: ' + (result.excludedThreads || 0),
      ui.ButtonSet.OK
    );
  } catch (error) {
    const response = AppUtils.errorResponse(error);
    ui.alert(APP.NAME, response.error.message + '\n\nReferencia: ' + response.correlationId, ui.ButtonSet.OK);
  }
}

/** Enables managed background triggers from the spreadsheet menu. */
function enableBackgroundSyncFromMenu() {
  const ui = SpreadsheetApp.getUi();
  try {
    TriggerManager.ensureMaintenanceTrigger();
    TriggerManager.ensureGmailSyncTrigger();
    ui.alert(APP.NAME, 'La sincronización en segundo plano está activada.', ui.ButtonSet.OK);
  } catch (error) {
    const response = AppUtils.errorResponse(error);
    ui.alert(APP.NAME, response.error.message + '\n\nReferencia: ' + response.correlationId, ui.ButtonSet.OK);
  }
}

/** Disables managed background triggers from the spreadsheet menu. */
function disableBackgroundSyncFromMenu() {
  const ui = SpreadsheetApp.getUi();
  try {
    TriggerManager.removeManagedTriggers();
    ui.alert(APP.NAME, 'La sincronización en segundo plano está desactivada.', ui.ButtonSet.OK);
  } catch (error) {
    const response = AppUtils.errorResponse(error);
    ui.alert(APP.NAME, response.error.message + '\n\nReferencia: ' + response.correlationId, ui.ButtonSet.OK);
  }
}

/** @return {GoogleAppsScript.HTML.HtmlOutput} @private */
function createApplicationHtml_() {
  const template = HtmlService.createTemplateFromFile('html/Index');
  template.bootstrap = getApplicationBootstrap();
  return template.evaluate()
    .setTitle(APP.NAME)
    .setSandboxMode(HtmlService.SandboxMode.IFRAME);
}

/** Opens the HTMLService application in a large modal dialog. */
function showApplicationDialog() {
  try {
    SpreadsheetApp.getUi().showModalDialog(
      createApplicationHtml_().setWidth(2600).setHeight(1500),
      ' '
    );
  } catch (error) {
    const response = AppUtils.errorResponse(error);
    SpreadsheetApp.getUi().alert(response.error.message + '\nReferencia: ' + response.correlationId);
  }
}

/** Displays release information. */
function showAbout() {
  const version = getVersion();
  SpreadsheetApp.getUi().alert(
    APP.NAME,
    version.name + ' v' + version.version + '\nGoogle Apps Script ' + version.runtime,
    SpreadsheetApp.getUi().ButtonSet.OK
  );
}

/** Refreshes the Dashboard installation metrics. */
function refreshDashboard() {
  const spreadsheet = AppConfig.getSpreadsheet(false);
  AppInstaller.refreshDashboard_(spreadsheet);
  AppLogger.info('Dashboard refreshed.');
}

/**
 * Returns server state required by HTMLService clients.
 * @return {{ok: boolean, app: Object, spreadsheet: Object, user: Object}}
 */
function getApplicationBootstrap() {
  const spreadsheet = AppConfig.getSpreadsheet(false);
  return {
    ok: true,
    app: getVersion(),
    spreadsheet: {
      id: spreadsheet.getId(),
      name: spreadsheet.getName(),
      url: spreadsheet.getUrl()
    },
    user: {email: AppUtils.currentUserEmail()}
  };
}

/** @return {GoogleAppsScript.HTML.HtmlOutput} */
function doGet() {
  try {
    const template = HtmlService.createTemplateFromFile('html/Index');
    template.bootstrap = getApplicationBootstrap();
    return template.evaluate()
      .setTitle(APP.NAME)
      .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.SAMEORIGIN);
  } catch (error) {
    const response = AppUtils.errorResponse(error);
    return HtmlService.createHtmlOutput(
      '<h1>' + AppUtils.escapeHtml(APP.NAME) + '</h1>' +
      '<p>' + AppUtils.escapeHtml(response.error.message) + '</p>' +
      '<p>Referencia: ' + AppUtils.escapeHtml(response.correlationId) + '</p>'
    ).setTitle(APP.NAME);
  }
}
'@
[System.IO.File]::WriteAllText((Join-Path $root "src\menu.gs"), $v1, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo html\SyncScripts.html..." -ForegroundColor Cyan
$v2 = @'
<script>
(function () {
  'use strict';

  function callServer(functionName) {
    const args = Array.prototype.slice.call(arguments, 1);
    return new Promise(function (resolve, reject) {
      const runner = google.script.run
        .withSuccessHandler(resolve)
        .withFailureHandler(reject);
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
    window.setTimeout(function () { snackbar.hidden = true; }, 7000);
  }

  function setButtonBusy(button, busy) {
    if (!button) return;
    if (busy) {
      button.dataset.previousHtml = button.innerHTML;
      button.disabled = true;
      button.innerHTML = '<span class="spinner" aria-hidden="true"></span>Sincronizando…';
    } else {
      button.disabled = false;
      if (button.dataset.previousHtml) button.innerHTML = button.dataset.previousHtml;
      delete button.dataset.previousHtml;
    }
  }

  function summaryText(result) {
    return 'Sincronización de Gmail completada: ' +
      result.createdTickets + ' tickets creados, ' +
      result.createdMessages + ' mensajes añadidos, ' +
      result.attachments + ' adjuntos guardados, ' +
      result.failedThreads + ' hilos fallidos, ' +
      (result.excludedThreads || 0) + ' remitentes excluidos.';
  }

  function clickRefreshButtons() {
    document.querySelectorAll('[data-action="refresh"]').forEach(function (button) {
      button.click();
    });
  }

  function start() {
    const button = document.getElementById('sync-gmail');
    if (!button) return;
    button.addEventListener('click', async function () {
      setButtonBusy(button, true);
      try {
        const result = unwrap(await callServer('syncUiGmail'));
        showSnack(summaryText(result));
        clickRefreshButtons();
      } catch (error) {
        showSnack(error && error.message ? error.message : String(error));
      } finally {
        setButtonBusy(button, false);
      }
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }
})();
</script>
'@
[System.IO.File]::WriteAllText((Join-Path $root "html\SyncScripts.html"), $v2, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host ""
Write-Host "Verificando..." -ForegroundColor Cyan
Select-String -Path src\gmail.gs -Pattern "isExcludedSender_"

Write-Host ""
Write-Host "Si salio arriba, ejecuta: npm test  y  npm run deploy" -ForegroundColor Cyan
