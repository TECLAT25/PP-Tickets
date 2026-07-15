/**
 * Serial number policy for PocketPiano units.
 *
 * Canonical format:
 * PP-YY-WWW-NNNNN
 * Example: PP-26-027-00154
 */
class SerialNumberService {
  /** @return {RegExp} */
  static pattern() {
    return /^PP-\d{2}-\d{3}-\d{5}$/;
  }

  /**
   * @param {string} serialNumber
   * @return {string}
   */
  static normalize(serialNumber) {
    return String(serialNumber || '').trim().toUpperCase().replace(/_/g, '-');
  }

  /**
   * @param {string} serialNumber
   * @return {boolean}
   */
  static isValid(serialNumber) {
    return SerialNumberService.pattern().test(SerialNumberService.normalize(serialNumber));
  }

  /**
   * @param {string} serialNumber
   * @return {{year: number, week: number, sequence: number}}
   */
  static parse(serialNumber) {
    const normalized = SerialNumberService.normalize(serialNumber);
    if (!SerialNumberService.isValid(normalized)) {
      throw new AppError('Invalid PocketPiano serial number: ' + serialNumber, 'SERIAL_NUMBER_INVALID', {
        serialNumber: serialNumber,
        expectedFormat: 'PP-YY-WWW-NNNNN'
      });
    }
    const parts = normalized.split('-');
    return {
      year: 2000 + Number(parts[1]),
      week: Number(parts[2]),
      sequence: Number(parts[3])
    };
  }

  /**
   * Generates the next serial number for a manufacturing date.
   * The caller should hold a script lock when using this in write workflows.
   *
   * @param {Date=} manufacturingDate
   * @return {string}
   */
  static nextUnlocked_(manufacturingDate) {
    const date = manufacturingDate || new Date();
    const year = Utilities.formatDate(date, Session.getScriptTimeZone(), 'yy');
    const week = SerialNumberService.isoWeek_(date);
    const key = 'SERIAL_SEQUENCE_' + year + '_' + String(week).padStart(3, '0');
    const properties = AppConfig.getProperties();
    let sequence = Number(properties.getProperty(key));
    if (!Number.isInteger(sequence) || sequence < 0) {
      sequence = 0;
    }
    sequence += 1;
    properties.setProperty(key, String(sequence));
    return 'PP-' + year + '-' + String(week).padStart(3, '0') + '-' + String(sequence).padStart(5, '0');
  }

  /**
   * @param {Date} date
   * @return {number}
   * @private
   */
  static isoWeek_(date) {
    const copy = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
    const day = copy.getUTCDay() || 7;
    copy.setUTCDate(copy.getUTCDate() + 4 - day);
    const yearStart = new Date(Date.UTC(copy.getUTCFullYear(), 0, 1));
    return Math.ceil((((copy - yearStart) / 86400000) + 1) / 7);
  }
}

/**
 * Public helper for manual use.
 * @param {Date=} manufacturingDate
 * @return {string}
 */
function generateNextSerialNumber(manufacturingDate) {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(APP.LOCK_TIMEOUT_MS)) {
    throw new AppError('Another serial operation is running.', 'SERIAL_LOCK_TIMEOUT');
  }
  try {
    return SerialNumberService.nextUnlocked_(manufacturingDate || new Date());
  } finally {
    lock.releaseLock();
  }
}
