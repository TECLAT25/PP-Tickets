/** Domain error with a stable machine-readable code. */
class AppError extends Error {
  /**
   * @param {string} message
   * @param {string=} code
   * @param {Object=} context
   */
  constructor(message, code, context) {
    super(message);
    this.name = 'AppError';
    this.code = code || 'APPLICATION_ERROR';
    this.context = context || {};
  }
}

/** Shared application utilities. */
class AppUtils {
  /** @return {string} */
  static uuid() {
    return Utilities.getUuid();
  }

  /** @return {string} */
  static currentUserEmail() {
    try {
      return Session.getActiveUser().getEmail() || Session.getEffectiveUser().getEmail() || '';
    } catch (error) {
      return '';
    }
  }

  /**
   * Serializes arbitrary values without failing on cycles.
   * @param {*} value
   * @return {string}
   */
  static safeJson(value) {
    const seen = [];
    try {
      return JSON.stringify(value, function(key, item) {
        if (item instanceof Error) {
          return {name: item.name, message: item.message, stack: item.stack};
        }
        if (item && typeof item === 'object') {
          if (seen.indexOf(item) !== -1) {
            return '[Circular]';
          }
          seen.push(item);
        }
        return item;
      });
    } catch (error) {
      return JSON.stringify({serializationError: String(error)});
    }
  }

  /**
   * Logs a thrown value and returns a client-safe error.
   * @param {*} error
   * @param {string=} correlationId
   * @return {{ok: boolean, error: {code: string, message: string}, correlationId: string}}
   */
  static errorResponse(error, correlationId) {
    const id = correlationId || AppUtils.uuid();
    AppLogger.error(error && error.message ? error.message : String(error), {
      code: error && error.code ? error.code : 'UNEXPECTED_ERROR',
      stack: error && error.stack ? error.stack : '',
      context: error && error.context ? error.context : {}
    }, id);
    return {
      ok: false,
      error: {
        code: error && error.code ? error.code : 'UNEXPECTED_ERROR',
        message: error && error.message ? error.message : 'An unexpected error occurred.'
      },
      correlationId: id
    };
  }

  /** @param {*} value @return {string} */
  static escapeHtml(value) {
    return String(value == null ? '' : value)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }
}

/** Structured logger with Cloud Logging and Sheets sinks. */
class AppLogger {
  /** @param {string} message @param {Object=} context @param {string=} id */
  static debug(message, context, id) { AppLogger.write(APP.LOG_LEVELS.DEBUG, message, context, id); }
  /** @param {string} message @param {Object=} context @param {string=} id */
  static info(message, context, id) { AppLogger.write(APP.LOG_LEVELS.INFO, message, context, id); }
  /** @param {string} message @param {Object=} context @param {string=} id */
  static warn(message, context, id) { AppLogger.write(APP.LOG_LEVELS.WARN, message, context, id); }
  /** @param {string} message @param {Object=} context @param {string=} id */
  static error(message, context, id) { AppLogger.write(APP.LOG_LEVELS.ERROR, message, context, id); }

  /**
   * @param {string} level
   * @param {string} message
   * @param {Object=} context
   * @param {string=} correlationId
   */
  static write(level, message, context, correlationId) {
    const id = correlationId || AppUtils.uuid();
    const user = AppUtils.currentUserEmail();
    const payload = {
      timestamp: new Date().toISOString(), level: level, message: String(message),
      context: context || {}, correlationId: id, user: user, version: APP_VERSION
    };
    const method = level === APP.LOG_LEVELS.ERROR ? 'error' :
      (level === APP.LOG_LEVELS.WARN ? 'warn' : 'log');
    console[method](AppUtils.safeJson(payload));

    try {
      const spreadsheetId = AppConfig.getProperties().getProperty(APP.PROPERTY_KEYS.SPREADSHEET_ID);
      if (!spreadsheetId) {
        return;
      }
      const sheet = SpreadsheetApp.openById(spreadsheetId).getSheetByName(APP.SHEETS.LOGS);
      if (sheet) {
        sheet.appendRow([
          new Date(), level, String(message), AppUtils.safeJson(context || {}), id, user, APP_VERSION
        ]);
      }
    } catch (loggingError) {
      console.error(AppUtils.safeJson({message: 'Sheet logging failed', error: String(loggingError)}));
    }
  }
}

/** @param {string} filename @return {string} */
function include(filename) {
  return HtmlService.createHtmlOutputFromFile(filename).getContent();
}
