/** Centralized configuration and persistent resource access. */
class AppConfig {
  /** @return {GoogleAppsScript.Properties.Properties} */
  static getProperties() {
    return PropertiesService.getScriptProperties();
  }

  /** @param {string} spreadsheetId */
  static setSpreadsheetId(spreadsheetId) {
    if (!spreadsheetId) {
      throw new AppError('A spreadsheet ID is required.', 'CONFIG_SPREADSHEET_ID_REQUIRED');
    }
    AppConfig.getProperties().setProperty(APP.PROPERTY_KEYS.SPREADSHEET_ID, spreadsheetId);
  }

  /**
   * Resolves the configured spreadsheet.
   * @param {boolean=} allowActive Allow the active container during installation.
   * @return {GoogleAppsScript.Spreadsheet.Spreadsheet}
   */
  static getSpreadsheet(allowActive) {
    const id = AppConfig.getProperties().getProperty(APP.PROPERTY_KEYS.SPREADSHEET_ID);
    if (id) {
      return SpreadsheetApp.openById(id);
    }
    if (allowActive) {
      const active = SpreadsheetApp.getActiveSpreadsheet();
      if (active) {
        return active;
      }
    }
    throw new AppError(
      'PP Tickets is not installed. Open the target spreadsheet and run install().',
      'APP_NOT_INSTALLED'
    );
  }

  /**
   * Returns a required sheet.
   * @param {string} sheetName
   * @return {GoogleAppsScript.Spreadsheet.Sheet}
   */
  static getSheet(sheetName) {
    const sheet = AppConfig.getSpreadsheet(false).getSheetByName(sheetName);
    if (!sheet) {
      throw new AppError('Required sheet is missing: ' + sheetName, 'SHEET_NOT_FOUND', {sheetName: sheetName});
    }
    return sheet;
  }

  /** @return {Object<string, string>} */
  static getSettings() {
    const cache = CacheService.getScriptCache();
    const cached = cache.get('settings');
    if (cached) {
      return JSON.parse(cached);
    }
    const sheet = AppConfig.getSheet(APP.SHEETS.SETTINGS);
    const settings = {};
    if (sheet.getLastRow() > 1) {
      sheet.getRange(2, 1, sheet.getLastRow() - 1, 2).getDisplayValues().forEach(function(row) {
        if (row[0]) {
          settings[row[0]] = row[1];
        }
      });
    }
    cache.put('settings', JSON.stringify(settings), 300);
    return settings;
  }

  /**
   * @param {string} key
   * @param {*=} fallback
   * @return {*}
   */
  static getSetting(key, fallback) {
    const settings = AppConfig.getSettings();
    return Object.prototype.hasOwnProperty.call(settings, key) ? settings[key] : fallback;
  }

  /** Clears cached runtime configuration. */
  static clearCache() {
    CacheService.getScriptCache().remove('settings');
  }
}
