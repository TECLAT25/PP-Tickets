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
      'Remitentes excluidos: ' + (result.excludedThreads || 0) + '\n' +
      'Tickets huérfanos vinculados: ' + (result.linkedTickets || 0),
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