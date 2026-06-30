/** Managed trigger lifecycle. */
class TriggerManager {
  /**
   * Creates one daily maintenance trigger if absent.
   * @return {GoogleAppsScript.Script.Trigger}
   */
  static ensureMaintenanceTrigger() {
    const handler = 'scheduledMaintenance';
    const existing = ScriptApp.getProjectTriggers().filter(function(trigger) {
      return trigger.getHandlerFunction() === handler;
    });
    return existing.length ? existing[0] :
      ScriptApp.newTrigger(handler).timeBased().everyDays(1).atHour(3).create();
  }

  /** Removes only triggers managed by this application. */
  static removeManagedTriggers() {
    const managedHandlers = ['scheduledMaintenance'];
    ScriptApp.getProjectTriggers().forEach(function(trigger) {
      if (managedHandlers.indexOf(trigger.getHandlerFunction()) !== -1) {
        ScriptApp.deleteTrigger(trigger);
      }
    });
  }
}

/** Performs bounded daily operational housekeeping. */
function scheduledMaintenance() {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(1000)) {
    AppLogger.warn('Scheduled maintenance skipped because another job holds the lock.');
    return;
  }
  try {
    purgeExpiredLogs_();
    AppLogger.info('Scheduled maintenance completed.');
  } catch (error) {
    AppLogger.error('Scheduled maintenance failed.', {error: String(error), stack: error.stack || ''});
    throw error;
  } finally {
    lock.releaseLock();
  }
}

/** Deletes contiguous oldest log rows beyond retention. @private */
function purgeExpiredLogs_() {
  const sheet = AppConfig.getSheet(APP.SHEETS.LOGS);
  if (sheet.getLastRow() <= 1) {
    return;
  }
  const cutoff = new Date(Date.now() - APP.LOG_RETENTION_DAYS * 24 * 60 * 60 * 1000);
  const timestamps = sheet.getRange(2, 1, sheet.getLastRow() - 1, 1).getValues();
  let rowsToDelete = 0;
  for (let index = 0; index < timestamps.length; index += 1) {
    const value = timestamps[index][0];
    if (value instanceof Date && value < cutoff) {
      rowsToDelete += 1;
    } else {
      break;
    }
  }
  if (rowsToDelete > 0) {
    sheet.deleteRows(2, rowsToDelete);
  }
}
