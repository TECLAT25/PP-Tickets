/**
 * Product persistence for individual PocketPiano units.
 */
class SheetProductRepository {
  constructor() {
    this.sheet_ = AppConfig.getSheet(APP.SHEETS.PRODUCTS);
    this.headers_ = this.sheet_.getRange(1, 1, 1, this.sheet_.getLastColumn()).getDisplayValues()[0];
    this.headerIndex_ = {};
    this.headers_.forEach(function(header, index) {
      if (header) this.headerIndex_[header] = index;
    }, this);
    ['Product ID', 'Serial Number', 'Name', 'Customer ID', 'Status', 'Created At', 'Updated At'].forEach(function(header) {
      if (this.headerIndex_[header] == null) {
        throw new AppError(
          'Products sheet is missing the "' + header + '" column. Run install().',
          'PRODUCT_SCHEMA_OUTDATED',
          {header: header}
        );
      }
    }, this);
    this.reload_();
  }

  /** @private */
  reload_() {
    this.byId_ = {};
    this.bySerial_ = {};
    this.listAll().forEach(function(product) {
      this.byId_[product.id] = product;
      if (product.serialNumber) this.bySerial_[product.serialNumber] = product;
    }, this);
  }

  /** @return {Array<Object>} */
  listAll() {
    if (this.sheet_.getLastRow() <= 1) return [];
    return this.sheet_.getRange(2, 1, this.sheet_.getLastRow() - 1, this.headers_.length)
      .getValues()
      .map(function(row, index) { return this.fromRow_(row, index + 2); }, this);
  }

  /** @param {string} id @return {Object|null} */
  findById(id) {
    return this.byId_[String(id || '')] || null;
  }

  /** @param {string} serialNumber @return {Object|null} */
  findBySerialNumber(serialNumber) {
    return this.bySerial_[SerialNumberService.normalize(serialNumber)] || null;
  }

  /**
   * @param {Object=} criteria
   * @return {{items: Array<Object>, total: number, offset: number, limit: number}}
   */
  search(criteria) {
    const filters = criteria || {};
    const query = String(filters.query || '').trim().toLowerCase();
    let products = this.listAll().filter(function(product) {
      if (filters.customerId && product.customerId !== String(filters.customerId)) return false;
      if (filters.status && product.status.toUpperCase() !== String(filters.status).toUpperCase()) return false;
      if (query) {
        const haystack = [
          product.id, product.serialNumber, product.sku, product.name, product.customerId,
          product.status, product.notes
        ].join(' ').toLowerCase();
        if (haystack.indexOf(query) === -1) return false;
      }
      return true;
    });
    products.sort(function(left, right) {
      return new Date(right.updatedAt).getTime() - new Date(left.updatedAt).getTime();
    });
    const total = products.length;
    const offset = Math.max(0, Number(filters.offset) || 0);
    const limit = Math.max(1, Math.min(500, Number(filters.limit) || 100));
    return {items: products.slice(offset, offset + limit), total: total, offset: offset, limit: limit};
  }

  /**
   * @param {{serialNumber: string, sku: string, name: string, purchaseDate: Date, warrantyMonths: number, customerId: string, status: string, notes: string}=} input
   * @return {Object}
   */
  create(input) {
    const data = input || {};
    const serialNumber = SerialNumberService.normalize(data.serialNumber || SerialNumberService.nextUnlocked_(new Date()));
    if (!SerialNumberService.isValid(serialNumber)) {
      throw new AppError('Invalid serial number: ' + serialNumber, 'PRODUCT_SERIAL_INVALID', {serialNumber: serialNumber});
    }
    if (this.findBySerialNumber(serialNumber)) {
      throw new AppError('Serial number already exists: ' + serialNumber, 'PRODUCT_SERIAL_DUPLICATE', {serialNumber: serialNumber});
    }
    const now = new Date();
    const record = {
      id: SheetProductRepository.nextProductId_(),
      sku: String(data.sku || 'POCKETPIANO').trim(),
      name: String(data.name || 'PocketPiano').trim(),
      serialNumber: serialNumber,
      purchaseDate: data.purchaseDate || '',
      warrantyMonths: Number(data.warrantyMonths || AppConfig.getSetting('DEFAULT_WARRANTY_MONTHS', '36')),
      customerId: String(data.customerId || ''),
      status: String(data.status || 'MANUFACTURED').trim().toUpperCase(),
      notes: String(data.notes || '').trim(),
      createdAt: now,
      updatedAt: now
    };
    const row = this.emptyRow_();
    SheetProductRepository.fields_().forEach(function(mapping) {
      if (this.headerIndex_[mapping.header] != null) {
        row[this.headerIndex_[mapping.header]] = record[mapping.field] || '';
      }
    }, this);
    this.sheet_.appendRow(row);
    const created = this.fromRow_(row, this.sheet_.getLastRow());
    this.byId_[created.id] = created;
    this.bySerial_[created.serialNumber] = created;
    return created;
  }

  /** @param {string} productId @param {Object} changes @return {Object} */
  update(productId, changes) {
    const product = this.findById(productId);
    if (!product) {
      throw new AppError('Product not found: ' + productId, 'PRODUCT_NOT_FOUND', {productId: productId});
    }
    const row = this.sheet_.getRange(product.rowNumber, 1, 1, this.headers_.length).getValues()[0];
    const allowed = ['sku', 'name', 'purchaseDate', 'warrantyMonths', 'customerId', 'status', 'notes', 'updatedAt'];
    SheetProductRepository.fields_().forEach(function(mapping) {
      if (allowed.indexOf(mapping.field) !== -1 &&
          Object.prototype.hasOwnProperty.call(changes, mapping.field)) {
        row[this.headerIndex_[mapping.header]] = changes[mapping.field];
      }
    }, this);
    row[this.headerIndex_['Updated At']] = changes.updatedAt || new Date();
    this.sheet_.getRange(product.rowNumber, 1, 1, row.length).setValues([row]);
    const updated = this.fromRow_(row, product.rowNumber);
    this.byId_[updated.id] = updated;
    if (updated.serialNumber) this.bySerial_[updated.serialNumber] = updated;
    return updated;
  }

  /** @return {Array<*>} @private */
  emptyRow_() {
    return this.headers_.map(function() { return ''; });
  }

  /** @param {Array<*>} row @param {number} rowNumber @return {Object} @private */
  fromRow_(row, rowNumber) {
    const product = {rowNumber: rowNumber};
    SheetProductRepository.fields_().forEach(function(mapping) {
      const index = this.headerIndex_[mapping.header];
      product[mapping.field] = index == null ? '' : row[index];
    }, this);
    ['id', 'sku', 'name', 'serialNumber', 'customerId', 'status', 'notes'].forEach(function(field) {
      product[field] = String(product[field] || '');
    });
    product.serialNumber = SerialNumberService.normalize(product.serialNumber);
    product.warrantyMonths = Number(product.warrantyMonths || 0);
    return product;
  }

  /** @return {string} @private */
  static nextProductId_() {
    const properties = AppConfig.getProperties();
    const key = 'PRODUCT_SEQUENCE';
    let sequence = Number(properties.getProperty(key));
    if (!Number.isInteger(sequence) || sequence < 0) sequence = 0;
    sequence += 1;
    properties.setProperty(key, String(sequence));
    return 'PROD-' + String(sequence).padStart(6, '0');
  }

  /** @return {Array<{field: string, header: string}>} @private */
  static fields_() {
    return [
      {field: 'id', header: 'Product ID'},
      {field: 'sku', header: 'SKU'},
      {field: 'name', header: 'Name'},
      {field: 'serialNumber', header: 'Serial Number'},
      {field: 'purchaseDate', header: 'Purchase Date'},
      {field: 'warrantyMonths', header: 'Warranty Months'},
      {field: 'customerId', header: 'Customer ID'},
      {field: 'status', header: 'Status'},
      {field: 'notes', header: 'Notes'},
      {field: 'createdAt', header: 'Created At'},
      {field: 'updatedAt', header: 'Updated At'}
    ];
  }
}

/** @param {Object=} input @return {Object} */
function createProduct(input) {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(APP.LOCK_TIMEOUT_MS)) {
    throw new AppError('Another product operation is running.', 'PRODUCT_LOCK_TIMEOUT');
  }
  try {
    return new SheetProductRepository().create(input || {});
  } finally {
    lock.releaseLock();
  }
}

/** @param {Object=} criteria @return {Object} */
function searchProducts(criteria) {
  return new SheetProductRepository().search(criteria || {});
}
