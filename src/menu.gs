/** Creates the spreadsheet menu when the container opens. */
function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu(APP.NAME)
    .addItem('Open application', 'showApplicationDialog')
    .addItem('Open narrow sidebar', 'showSidebar')
    .addSeparator()
    .addItem('Install or repair', 'installFromMenu')
    .addItem('Synchronize Gmail now', 'syncGmailFromMenu')
    .addItem('Enable background sync', 'enableBackgroundSyncFromMenu')
    .addItem('Disable background sync', 'disableBackgroundSyncFromMenu')
    .addSeparator()
    .addItem('Refresh dashboard', 'refreshDashboard')
    .addSeparator()
    .addItem('About', 'showAbout')
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
    ui.alert(APP.NAME, 'Installation completed. Version ' + result.version + ' is ready.', ui.ButtonSet.OK);
  } catch (error) {
    const response = AppUtils.errorResponse(error);
    ui.alert(APP.NAME, response.error.message + '\n\nReference: ' + response.correlationId, ui.ButtonSet.OK);
  }
}

/** Runs Gmail synchronization from the spreadsheet menu. */
function syncGmailFromMenu() {
  const ui = SpreadsheetApp.getUi();
  try {
    const result = syncGmail();
    ui.alert(
      APP.NAME,
      'Gmail synchronization completed.\n\n' +
      'Tickets created: ' + result.createdTickets + '\n' +
      'Messages added: ' + result.createdMessages + '\n' +
      'Attachments saved: ' + result.attachments + '\n' +
      'Failed threads: ' + result.failedThreads,
      ui.ButtonSet.OK
    );
  } catch (error) {
    const response = AppUtils.errorResponse(error);
    ui.alert(APP.NAME, response.error.message + '\n\nReference: ' + response.correlationId, ui.ButtonSet.OK);
  }
}

/** Enables managed background triggers from the spreadsheet menu. */
function enableBackgroundSyncFromMenu() {
  const ui = SpreadsheetApp.getUi();
  try {
    TriggerManager.ensureMaintenanceTrigger();
    TriggerManager.ensureGmailSyncTrigger();
    ui.alert(APP.NAME, 'Background synchronization is enabled.', ui.ButtonSet.OK);
  } catch (error) {
    const response = AppUtils.errorResponse(error);
    ui.alert(APP.NAME, response.error.message + '\n\nReference: ' + response.correlationId, ui.ButtonSet.OK);
  }
}

/** Disables managed background triggers from the spreadsheet menu. */
function disableBackgroundSyncFromMenu() {
  const ui = SpreadsheetApp.getUi();
  try {
    TriggerManager.removeManagedTriggers();
    ui.alert(APP.NAME, 'Background synchronization is disabled.', ui.ButtonSet.OK);
  } catch (error) {
    const response = AppUtils.errorResponse(error);
    ui.alert(APP.NAME, response.error.message + '\n\nReference: ' + response.correlationId, ui.ButtonSet.OK);
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
      createApplicationHtml_().setWidth(2200).setHeight(1250),
      APP.NAME
    );
  } catch (error) {
    const response = AppUtils.errorResponse(error);
    SpreadsheetApp.getUi().alert(response.error.message + '\nReference: ' + response.correlationId);
  }
}

/** Opens the HTMLService application sidebar. */
function showSidebar() {
  try {
    SpreadsheetApp.getUi().showSidebar(createApplicationHtml_().setTitle(APP.NAME));
  } catch (error) {
    const response = AppUtils.errorResponse(error);
    SpreadsheetApp.getUi().alert(response.error.message + '\nReference: ' + response.correlationId);
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
      '<p>Reference: ' + AppUtils.escapeHtml(response.correlationId) + '</p>'
    ).setTitle(APP.NAME);
  }
}
