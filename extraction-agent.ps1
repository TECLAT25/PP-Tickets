# extraction-agent.ps1
# Agente completo: lee los mensajes del ticket y rellena todos los
# campos posibles (cliente, envio, numero de pedido, numero de serie),
# y anade directamente los errores/soluciones que coincidan con el
# catalogo (no solo los sugiere).
$ErrorActionPreference = "Stop"
$root = Get-Location
$enc = New-Object System.Text.UTF8Encoding($false)

Write-Host "Escribiendo src\extraction.gs..." -ForegroundColor Cyan
$v0 = @'
/**
 * Best-effort extraction of structured fields (name, phone, postal code,
 * country, street address) from email headers and free-text bodies. This
 * is heuristic, not a guarantee — always let a human review before
 * trusting the result.
 */
class MessageFieldExtractor {
  /**
   * @param {string} text Combined inbound email body text (any language).
   * @param {string=} fromHeader Raw "From" header of the first inbound message, e.g. "Jane Doe <jane@example.com>".
   * @return {{firstName: string, lastName: string, phone: string, postalCode: string, country: string, address: string, serialNumber: string}}
   */
  static extract(text, fromHeader) {
    const body = String(text || '');
    const name = MessageFieldExtractor.extractName_(String(fromHeader || ''), body);
    const emailMatch = String(fromHeader || '').match(/[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9.-]+\.[a-z]{2,}/i);
    const senderEmail = emailMatch ? emailMatch[0] : '';
    const serialNumber = MessageFieldExtractor.extractSerialNumber_(body);
    const orderNumber = MessageFieldExtractor.extractOrderNumber_(body);
    let bodyWithoutSerial = serialNumber
      ? body.replace(/\bPP[\s_-]?\d{2}[\s_-]\d{3}[\s_-]\d{5}\b/i, ' ')
      : body;
    if (orderNumber) {
      bodyWithoutSerial = bodyWithoutSerial.replace(MessageFieldExtractor.ORDER_NUMBER_PATTERN_, ' ');
    }
    const shippingMarker = MessageFieldExtractor.SHIPPING_MARKER_.exec(body);
    const bodyBeforeShipping = shippingMarker ? bodyWithoutSerial.slice(0, shippingMarker.index) : bodyWithoutSerial;
    const shipping = MessageFieldExtractor.extractShippingBlock_(body);
    return {
      firstName: name.firstName,
      lastName: name.lastName,
      phone: MessageFieldExtractor.extractPhone_(bodyBeforeShipping),
      postalCode: MessageFieldExtractor.extractPostalCode_(bodyBeforeShipping),
      country: MessageFieldExtractor.extractCountry_(body, senderEmail),
      address: MessageFieldExtractor.extractAddress_(bodyBeforeShipping),
      serialNumber: serialNumber,
      orderNumber: orderNumber,
      shippingRecipientFirstName: shipping.firstName,
      shippingRecipientLastName: shipping.lastName,
      shippingAddress: shipping.address,
      shippingRecipientPhone: shipping.phone,
      shippingRecipientCountry: shipping.address ? MessageFieldExtractor.extractCountry_(shipping.address, '') : '',
      shippingRecipientPostalCode: shipping.address ? MessageFieldExtractor.extractPostalCode_(shipping.address) : ''
    };
  }

  /** @private */
  static get SHIPPING_MARKER_() {
    return /(?:ship\s*to|deliver\s*to|shipping\s*address|enviar\s*a|env[ií]o\s*a|direcci[oó]n\s*de\s*env[ií]o|livrer\s*[aà]|liefern\s*an)\s*[:\-]?\s*/i;
  }

  /** @private */
  static get ORDER_NUMBER_PATTERN_() {
    return /(?:pedido|order|reference|referencia|n[uú]mero de pedido|order\s*number)\s*[:#\-]?\s*#?\s*\d{3,10}/i;
  }

  /**
   * Looks for an explicit order/reference number, e.g. "Pedido #04521",
   * "Order number: 12345", "Nº pedido 00812".
   * @param {string} text
   * @return {string}
   * @private
   */
  static extractOrderNumber_(text) {
    const match = MessageFieldExtractor.ORDER_NUMBER_PATTERN_.exec(text);
    if (!match) return '';
    const digits = match[0].match(/\d{3,10}/)[0];
    return '#' + digits.replace(/^0+(?=\d)/, '').padStart(5, '0');
  }

  /**
   * Looks for a "ship to / deliver to / enviar a" block naming a different
   * recipient than the customer themselves, with its own address/phone.
   * @param {string} text
   * @return {{firstName: string, lastName: string, address: string, phone: string}}
   * @private
   */
  static extractShippingBlock_(text) {
    const match = MessageFieldExtractor.SHIPPING_MARKER_.exec(text);
    if (!match) return {firstName: '', lastName: '', address: '', phone: ''};

    const otherFieldLine = /(tel[eé]fono|phone|tel\.?|telefon|num[eé]ro|e-?mail)\s*[:\-]/i;
    const afterMarker = text.slice(match.index + match[0].length, match.index + match[0].length + 200);
    const lines = afterMarker.split(/\n+/).map(function(line) { return line.trim(); }).filter(Boolean);
    if (!lines.length) return {firstName: '', lastName: '', address: '', phone: ''};

    const nameLine = /^[A-ZÀ-ÖØ-Þ][\p{L}'-]+(?:\s+[A-ZÀ-ÖØ-Þ][\p{L}'-]+){0,2}$/u;
    let firstName = '';
    let lastName = '';
    let addressLines = lines;
    if (nameLine.test(lines[0])) {
      const parts = lines[0].split(/\s+/);
      firstName = parts[0];
      lastName = parts.slice(1).join(' ');
      addressLines = lines.slice(1);
    }

    // Only keep lines that look like a real address continuation (has a
    // digit, e.g. a house number or postal code) — rejects sign-offs like
    // "Un saludo," or "Best regards" that might follow in the same block.
    const addressOnlyLines = addressLines.filter(function(line) {
      return !otherFieldLine.test(line) && /\d/.test(line);
    });
    const address = addressOnlyLines.slice(0, 2).join(', ');
    const phone = MessageFieldExtractor.extractPhone_(afterMarker);
    return {firstName: firstName, lastName: lastName, address: address, phone: phone};
  }

  /**
   * Recognizes PocketPiano serial numbers in the app's canonical format
   * (PP-YY-WWW-NNNNN), tolerating spaces or underscores customers might type.
   * @param {string} text
   * @return {string}
   * @private
   */
  static extractSerialNumber_(text) {
    const match = text.match(/\bPP[\s_-]?(\d{2})[\s_-](\d{3})[\s_-](\d{5})\b/i);
    if (!match) return '';
    const candidate = 'PP-' + match[1] + '-' + match[2] + '-' + match[3];
    return SerialNumberService.isValid(candidate) ? candidate : '';
  }

  /**
   * Prefers the display name from the "From" header (most reliable source).
   * Falls back to a signature line at the end of the body (e.g. "Best, Jane Doe").
   * @param {string} fromHeader
   * @param {string} body
   * @return {{firstName: string, lastName: string}}
   * @private
   */
  static extractName_(fromHeader, body) {
    const headerMatch = fromHeader.match(/^\s*"?([^"<]{2,60}?)"?\s*<[^>]+>/);
    let fullName = headerMatch ? headerMatch[1].trim() : '';

    if (!fullName || /@/.test(fullName)) {
      const signOffs = /(?:regards|best|thanks|thank you|sincerely|cordialement|saludos|un saludo|cumprimentos|met vriendelijke groet|mit freundlichen gr[uü][ßs]en|distinti saluti|pozdrawiam|hälsningar)[,:]?\s*\n+\s*([A-ZÀ-ÖØ-Þ][\p{L}'-]+(?:\s+[A-ZÀ-ÖØ-Þ][\p{L}'-]+){0,2})\s*$/imu;
      const match = body.match(signOffs);
      if (match) fullName = match[1].trim();
    }

    if (!fullName) return {firstName: '', lastName: ''};
    const parts = fullName.split(/\s+/).filter(Boolean);
    return {
      firstName: parts[0] || '',
      lastName: parts.length > 1 ? parts.slice(1).join(' ') : ''
    };
  }

  /**
   * Looks for a phone number, preferring one that appears near a labelling
   * word (tel, phone, número, telefon...) to avoid grabbing order numbers
   * or other unrelated digit strings.
   * @param {string} text
   * @return {string}
   * @private
   */
  static extractPhone_(text) {
    const candidates = text.match(/(\+?\d[\d\s().-]{7,17}\d)/g) || [];
    const valid = candidates
      .map(function(raw) { return raw.trim(); })
      .filter(function(raw) {
        const digitCount = raw.replace(/\D/g, '').length;
        if (digitCount < 8 || digitCount > 15) return false;
        // Reject obviously-fake sequences like 000000000 or 123456789.
        const digitsOnly = raw.replace(/\D/g, '');
        if (/^(\d)\1+$/.test(digitsOnly)) return false;
        return true;
      });
    if (!valid.length) return '';

    const labelPattern = /(tel[eé]fono|phone|tel\.?|num[eé]ro|telefon|numero di telefono|telefonnummer)\s*[:\-]?\s*/i;
    for (let i = 0; i < valid.length; i += 1) {
      const index = text.indexOf(valid[i]);
      const before = text.slice(Math.max(0, index - 25), index);
      if (labelPattern.test(before)) return valid[i];
    }
    return valid[0];
  }

  /**
   * @param {string} text
   * @return {string}
   * @private
   */
  static extractPostalCode_(text) {
    const labelPattern = /(postal\s*code|c[oó]digo\s*postal|code\s*postal|postleitzahl|plz|postnummer|kod\s*pocztowy|postcode|zip)\s*[:\-]?\s*([A-Z0-9][A-Z0-9\s-]{2,9})/i;
    const labelled = text.match(labelPattern);
    if (labelled) return labelled[2].trim();

    const isYear = function(value) {
      const num = parseInt(value, 10);
      return value.length === 4 && num >= 1900 && num <= 2099;
    };

    const structuredPatterns = [
      /\b([A-Z]{1,2}\d[A-Z\d]?\s?\d[A-Z]{2})\b/,   // UK style
      /\b(\d{5}-\d{3})\b/,                          // BR style
      /\b(\d{2}-\d{3})\b/                           // PL style
    ];
    for (let i = 0; i < structuredPatterns.length; i += 1) {
      const match = text.match(structuredPatterns[i]);
      if (match) return match[1];
    }

    // Generic 4-6 digit fallback: collect every candidate, reject plausible
    // years (e.g. "2026" from a message date/timestamp), prefer one that
    // sits on the same line as the detected address.
    const candidates = text.match(/\b\d{4,6}\b/g) || [];
    const valid = candidates.filter(function(value) { return !isYear(value); });
    if (!valid.length) return '';

    const addressLine = MessageFieldExtractor.extractAddress_(text);
    const onAddressLine = valid.filter(function(value) { return addressLine.indexOf(value) !== -1; });
    return onAddressLine[0] || valid[0];
  }

  /**
   * @param {string} text
   * @param {string=} email Customer email, used as a fallback signal via its country-code TLD.
   * @return {string}
   * @private
   */
  static extractCountry_(text, email) {
    const countries = {
      'spain': 'España', 'españa': 'España', 'espana': 'España',
      'united kingdom': 'United Kingdom', 'uk': 'United Kingdom', 'england': 'United Kingdom', 'great britain': 'United Kingdom',
      'france': 'France', 'francia': 'France',
      'germany': 'Deutschland', 'deutschland': 'Deutschland', 'alemania': 'Deutschland',
      'italy': 'Italia', 'italia': 'Italia',
      'portugal': 'Portugal',
      'netherlands': 'Nederland', 'nederland': 'Nederland', 'holanda': 'Nederland', 'holland': 'Nederland',
      'poland': 'Polska', 'polska': 'Polska', 'polonia': 'Polska',
      'sweden': 'Sverige', 'sverige': 'Sverige', 'suecia': 'Sverige',
      'japan': '日本', '日本': '日本',
      'korea': '대한민국', '대한민국': '대한민국', 'south korea': '대한민국',
      'belgium': 'België', 'belgique': 'België', 'bélgica': 'België',
      'ireland': 'Ireland', 'irlanda': 'Ireland',
      'austria': 'Österreich', 'österreich': 'Österreich',
      'switzerland': 'Schweiz', 'suiza': 'Schweiz',
      'denmark': 'Danmark', 'dinamarca': 'Danmark',
      'norway': 'Norge', 'noruega': 'Norge',
      'finland': 'Suomi', 'finlandia': 'Suomi',
      'united states': 'United States', 'usa': 'United States', 'estados unidos': 'United States',
      'mexico': 'México', 'méxico': 'México',
      'argentina': 'Argentina',
      'brazil': 'Brasil', 'brasil': 'Brasil',
      'canada': 'Canada', 'canadá': 'Canada',
      'greece': 'Ελλάδα', 'grecia': 'Ελλάδα',
      'czech republic': 'Česko', 'czechia': 'Česko', 'republica checa': 'Česko',
      'hungary': 'Magyarország', 'hungria': 'Magyarország',
      'romania': 'România', 'rumania': 'România',
      'turkey': 'Türkiye', 'turquia': 'Türkiye',
      'china': '中国',
      'india': 'India',
      'australia': 'Australia',
      'new zealand': 'New Zealand', 'nueva zelanda': 'New Zealand'
    };
    const lower = text.toLowerCase();
    const found = Object.keys(countries)
      .filter(function(key) { return new RegExp('\\b' + key + '\\b').test(lower); })
      .sort(function(a, b) { return b.length - a.length; });
    if (found.length) return countries[found[0]];

    const tldMap = {
      es: 'España', uk: 'United Kingdom', fr: 'France', de: 'Deutschland', it: 'Italia',
      pt: 'Portugal', nl: 'Nederland', pl: 'Polska', se: 'Sverige', jp: '日本', kr: '대한민국',
      be: 'België', ie: 'Ireland', at: 'Österreich', ch: 'Schweiz', dk: 'Danmark', no: 'Norge',
      fi: 'Suomi', mx: 'México', ar: 'Argentina', br: 'Brasil', ca: 'Canada', gr: 'Ελλάδα',
      cz: 'Česko', hu: 'Magyarország', ro: 'România', tr: 'Türkiye', cn: '中国', in: 'India',
      au: 'Australia', nz: 'New Zealand'
    };
    const domainMatch = String(email || '').match(/\.([a-z]{2})$/i);
    if (domainMatch) {
      const tld = domainMatch[1].toLowerCase();
      if (tldMap[tld]) return tldMap[tld];
    }
    return '';
  }

  /**
   * Looks for a short block of 1-3 consecutive lines that reads like a
   * postal address (contains a street-type word and at least one digit).
   * @param {string} text
   * @return {string}
   * @private
   */
  static extractAddress_(text) {
    const lines = text.split(/\n+/).map(function(line) { return line.trim(); }).filter(Boolean);
    const addressWords = /\b(calle|avenida|avda|c\/|street|st\.|road|rd\.|avenue|ave\.|rue|via|viale|rua|ulica|ul\.)\b|[\wäöüß]*stra(?:ß|ss)e\b|[\wäöü]*straat\b|[\wäöü]*laan\b|[\wäö]*v[aä]gen\b|[\wäö]*gata\b/i;
    const labelPrefix = /^[\p{L}\s]{2,30}:\s*/u;
    const otherFieldLine = /(tel[eé]fono|phone|tel\.?|telefon|num[eé]ro|e-?mail)\s*[:\-]/i;

    for (let i = 0; i < lines.length; i += 1) {
      const raw = lines[i];
      if (raw.length > 6 && raw.length < 100 && addressWords.test(raw) && /\d/.test(raw) && !otherFieldLine.test(raw.split(addressWords)[0] || '')) {
        const line = raw.replace(labelPrefix, '');
        const block = [line];
        const next = lines[i + 1];
        if (next && next.length < 80 && /\d/.test(next) && !addressWords.test(next) && !otherFieldLine.test(next)) {
          block.push(next);
        }
        return block.join(', ');
      }
    }
    return '';
  }

  /**
   * Suggests which catalog entries (errors or solutions) might apply to a
   * ticket, based on simple keyword overlap between each entry's code and
   * description and the message text. Best-effort — always let the agent
   * confirm before adding a suggestion.
   * @param {string} text
   * @param {Array<{code: string, description: string}>} catalog
   * @return {Array<string>} matched codes, most relevant first
   * @private-static
   */
  static suggestCatalogMatches(text, catalog) {
    const lower = String(text || '').toLowerCase();
    if (!lower || !catalog || !catalog.length) return [];

    const stopWords = {
      'the': 1, 'and': 1, 'for': 1, 'with': 1, 'from': 1, 'this': 1, 'that': 1,
      'para': 1, 'con': 1, 'del': 1, 'las': 1, 'los': 1, 'una': 1, 'unos': 1, 'que': 1
    };

    const scored = catalog.map(function(entry) {
      const codeWords = String(entry.code || '').toLowerCase().split(/[_\s-]+/);
      const descWords = String(entry.description || '').toLowerCase().split(/\W+/);
      const words = codeWords.concat(descWords)
        .filter(function(word) { return word.length > 3 && !stopWords[word]; });

      let score = 0;
      words.forEach(function(word) {
        if (lower.indexOf(word) !== -1) score += 1;
      });
      return {code: entry.code, score: score};
    });

    return scored
      .filter(function(item) { return item.score > 0; })
      .sort(function(a, b) { return b.score - a.score; })
      .map(function(item) { return item.code; });
  }
}
'@
[System.IO.File]::WriteAllText((Join-Path $root "src\extraction.gs"), $v0, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo html\IssuesSectionScripts.html..." -ForegroundColor Cyan
$v1 = @'
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

  function selectedTicketId() {
    const selected = document.querySelector('[data-ticket-id].is-selected');
    if (selected && selected.dataset.ticketId) return selected.dataset.ticketId;
    const eyebrow = document.querySelector('#ticket-detail .detail-header .eyebrow');
    return eyebrow ? eyebrow.textContent.trim() : '';
  }

  function currentDetail() {
    return window.__ticketDetail || {};
  }

  function injectStyles() {
    if (document.getElementById('detected-issues-styles')) return;
    const style = document.createElement('style');
    style.id = 'detected-issues-styles';
    style.textContent = [
      '.issues-section { padding: 16px 22px; border-top: 1px solid var(--outline-variant); display: grid; grid-template-columns: 1fr 1fr; gap: 26px; }',
      '.issues-column h3 { margin: 0 0 10px; font-size: 14px; }',
      '.issues-add-button { width: 30px; height: 30px; border-radius: 50%; border: 1px dashed var(--outline); background: transparent; color: var(--primary); cursor: pointer; font-size: 16px; line-height: 1; }',
      '.issues-list { margin-top: 10px; display: grid; gap: 6px; }',
      '.issue-row { display: flex; align-items: center; justify-content: space-between; gap: 10px; padding: 8px 8px 8px 14px; border: 1px solid var(--outline-variant); border-radius: 10px; background: var(--surface-container); font-size: 13px; }',
      '.issue-delete-button { display: inline-flex; align-items: center; justify-content: center; width: 30px; height: 30px; border: 0; border-radius: 8px; background: transparent; color: var(--error); cursor: pointer; }',
      '.issue-delete-button:hover { background: var(--error-container); }',
      '.issue-delete-button .material-symbols-rounded { font-size: 18px; }',
      '.issues-empty { font-size: 12px; color: var(--on-surface-variant); }',
      '.issues-picker { position: relative; margin-top: 4px; }',
      '.issues-picker-menu { position: absolute; top: 36px; left: 0; z-index: 20; width: 280px; max-height: 260px; overflow-y: auto; border: 1px solid var(--outline-variant); border-radius: 12px; background: var(--surface-bright); box-shadow: var(--shadow); padding: 6px; }',
      '.issues-picker-item { display: block; width: 100%; text-align: left; padding: 8px 10px; border: 0; border-radius: 8px; background: transparent; cursor: pointer; font-size: 12px; color: var(--on-surface); }',
      '.issues-picker-item:hover { background: var(--surface-container); }',
      '.issues-picker-item strong { display: block; font-size: 12px; }',
      '.issues-picker-item span { display: block; font-size: 10px; color: var(--on-surface-variant); }',
      '.issues-picker-empty { padding: 10px; font-size: 12px; color: var(--on-surface-variant); }',
      '@media (max-width: 900px) { .issues-section { grid-template-columns: 1fr; } }'
    ].join('\n');
    document.head.appendChild(style);
  }

  /**
   * Builds one column (Errores or Soluciones). Each column keeps its own
   * catalog cache and hidden input, but shares all the rendering logic.
   * @param {{title:string, ticketField:string, hiddenId:string, catalogFn:string, sheetName:string, addLabel:string, emptyLabel:string, deleteLabel:string}} config
   */
  function createColumn(config) {
    let catalogCache = null;
    let originalValue = null;
    let lastContainer = null;
    function loadCatalog() {
      if (catalogCache) return Promise.resolve(catalogCache);
      return callServer(config.catalogFn).then(unwrap).then(function (catalog) {
        catalogCache = catalog || [];
        return catalogCache;
      });
    }

    function currentItems() {
      const detail = currentDetail();
      const raw = (detail.ticket && detail.ticket[config.ticketField]) || '';
      return raw.split(',').map(function (item) { return item.trim(); }).filter(Boolean);
    }

    function closePicker() {
      const menu = document.querySelector('.issues-picker-menu[data-owner="' + config.hiddenId + '"]');
      if (menu) menu.remove();
      document.removeEventListener('click', onOutsideClick);
    }

    function onOutsideClick(event) {
      if (!event.target.closest('.issues-picker[data-owner="' + config.hiddenId + '"]')) closePicker();
    }

    function openPicker(picker, container, currentList) {
      const menu = document.createElement('div');
      menu.className = 'issues-picker-menu';
      menu.dataset.owner = config.hiddenId;
      menu.innerHTML = '<div class="issues-picker-empty">Cargando…</div>';
      picker.appendChild(menu);
      window.setTimeout(function () { document.addEventListener('click', onOutsideClick); }, 0);

      loadCatalog().then(function (catalog) {
        const available = catalog.filter(function (entry) { return currentList.indexOf(entry.code) === -1; });
        menu.replaceChildren();
        if (!available.length) {
          const empty = document.createElement('div');
          empty.className = 'issues-picker-empty';
          empty.textContent = catalog.length ? 'Ya están todos añadidos.' : 'No hay elementos definidos en la hoja "' + config.sheetName + '".';
          menu.appendChild(empty);
          return;
        }
        available.forEach(function (entry) {
          const item = document.createElement('button');
          item.type = 'button';
          item.className = 'issues-picker-item';
          item.innerHTML = '<strong>' + entry.code + '</strong>' + (entry.description ? '<span>' + entry.description + '</span>' : '');
          item.addEventListener('click', function () {
            const hidden = document.getElementById(config.hiddenId);
            const updated = currentList.concat([entry.code]);
            hidden.value = updated.join(', ');
            closePicker();
            render(container, updated);
          });
          menu.appendChild(item);
        });
      }).catch(function (error) {
        menu.innerHTML = '<div class="issues-picker-empty">' + (error && error.message ? error.message : String(error)) + '</div>';
      });
    }

    function render(container, overrideItems) {
      lastContainer = container;
      container.replaceChildren();
      container.className = 'issues-column';

      const heading = document.createElement('h3');
      heading.textContent = config.title;
      container.appendChild(heading);

      const items = overrideItems || currentItems();
      if (originalValue === null) originalValue = currentItems().join(', ');
      const hidden = document.createElement('input');
      hidden.type = 'hidden';
      hidden.id = config.hiddenId;
      hidden.value = items.join(', ');
      hidden.dataset.original = originalValue;
      container.appendChild(hidden);

      const picker = document.createElement('div');
      picker.className = 'issues-picker';
      picker.dataset.owner = config.hiddenId;
      const addButton = document.createElement('button');
      addButton.type = 'button';
      addButton.className = 'issues-add-button';
      addButton.title = config.addLabel;
      addButton.setAttribute('aria-label', config.addLabel);
      addButton.textContent = '+';
      addButton.addEventListener('click', function (event) {
        event.stopPropagation();
        closePicker();
        openPicker(picker, container, items);
      });
      picker.appendChild(addButton);
      container.appendChild(picker);

      const list = document.createElement('div');
      list.className = 'issues-list';

      if (!items.length) {
        const empty = document.createElement('span');
        empty.className = 'issues-empty';
        empty.textContent = config.emptyLabel;
        list.appendChild(empty);
      }

      items.forEach(function (code) {
        const row = document.createElement('div');
        row.className = 'issue-row';
        const label = document.createElement('span');
        label.textContent = code;
        const removeButton = document.createElement('button');
        removeButton.type = 'button';
        removeButton.className = 'issue-delete-button';
        removeButton.title = 'Eliminar';
        removeButton.setAttribute('aria-label', config.deleteLabel);
        removeButton.innerHTML = '<span class="material-symbols-rounded" aria-hidden="true">delete</span>';
        removeButton.addEventListener('click', function () {
          const updated = items.filter(function (item) { return item !== code; });
          hidden.value = updated.join(', ');
          render(container, updated);
        });
        row.appendChild(label);
        row.appendChild(removeButton);
        list.appendChild(row);
      });

      container.appendChild(list);
    }

    return {
      render: render,
      reset: function () { originalValue = null; },
      addItems: function (codes) {
        if (!lastContainer || !codes || !codes.length) return 0;
        const hidden = document.getElementById(config.hiddenId);
        const existing = hidden ? hidden.value.split(',').map(function (item) { return item.trim(); }).filter(Boolean) : currentItems();
        const additions = codes.filter(function (code) { return existing.indexOf(code) === -1; });
        if (!additions.length) return 0;
        const updated = existing.concat(additions);
        if (hidden) hidden.value = updated.join(', ');
        render(lastContainer, updated);
        return additions.length;
      }
    };
  }

  const errorsColumn = createColumn({
    title: 'Errores detectados',
    ticketField: 'detectedErrors',
    hiddenId: 'ticket-detected-errors',
    catalogFn: 'getUiErrorCatalog',
    sheetName: 'Errors',
    addLabel: 'Añadir error',
    emptyLabel: 'Sin errores registrados.',
    deleteLabel: 'Eliminar error'
  });

  const solutionsColumn = createColumn({
    title: 'Soluciones',
    ticketField: 'detectedSolutions',
    hiddenId: 'ticket-detected-solutions',
    catalogFn: 'getUiSolutionCatalog',
    sheetName: 'Solutions',
    addLabel: 'Añadir solución',
    emptyLabel: 'Sin soluciones registradas.',
    deleteLabel: 'Eliminar solución'
  });

  window.__ppIssuesColumns = {errors: errorsColumn, solutions: solutionsColumn};

  function ensureIssuesSection() {
    const section = document.getElementById('detected-errors-section');
    if (!section || section.dataset.rendered === 'true') return;
    section.dataset.rendered = 'true';
    injectStyles();
    section.className = 'issues-section';

    const left = document.createElement('div');
    const right = document.createElement('div');
    section.appendChild(left);
    section.appendChild(right);

    errorsColumn.reset();
    solutionsColumn.reset();
    errorsColumn.render(left);
    solutionsColumn.render(right);
  }

  const observer = new MutationObserver(function () {
    ensureIssuesSection();
  });

  function start() {
    const panel = document.getElementById('ticket-detail');
    if (!panel) return;
    observer.observe(panel, {childList: true, subtree: true});
    ensureIssuesSection();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
</script>
'@
[System.IO.File]::WriteAllText((Join-Path $root "html\IssuesSectionScripts.html"), $v1, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "Escribiendo html\CustomerShippingActions.html..." -ForegroundColor Cyan
$v2 = @'
<script>
(function () {
  'use strict';

  function fillIfEmpty(id, value) {
    if (!value) return false;
    const node = document.getElementById(id);
    if (!node || node.value.trim()) return false;
    node.value = value;
    return true;
  }

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

  function showSnack(message) {
    const snackbar = document.getElementById('snackbar');
    if (!snackbar) return;
    snackbar.textContent = message;
    snackbar.hidden = false;
    window.setTimeout(function () { snackbar.hidden = true; }, 6000);
  }

  async function extractFromMessages(ticketId, button) {
    button.disabled = true;
    const previous = button.textContent;
    button.textContent = 'Analizando\u2026';
    try {
      const extracted = await unwrap(await callServer('extractUiFieldsFromMessages', ticketId));
      let filled = 0;
      if (fillIfEmpty('cs-first-name', extracted.firstName)) filled += 1;
      if (fillIfEmpty('cs-last-name', extracted.lastName)) filled += 1;
      if (fillIfEmpty('cs-phone', extracted.phone)) filled += 1;
      if (fillIfEmpty('cs-postal-code', extracted.postalCode)) filled += 1;
      if (fillIfEmpty('cs-country', extracted.country)) filled += 1;
      if (fillIfEmpty('cs-address', extracted.address)) filled += 1;
      if (fillIfEmpty('cs-shipping-address', extracted.shippingAddress)) filled += 1;
      if (fillIfEmpty('cs-recipient-first-name', extracted.shippingRecipientFirstName)) filled += 1;
      if (fillIfEmpty('cs-recipient-last-name', extracted.shippingRecipientLastName)) filled += 1;
      if (fillIfEmpty('cs-recipient-phone', extracted.shippingRecipientPhone)) filled += 1;
      if (fillIfEmpty('cs-recipient-country', extracted.shippingRecipientCountry)) filled += 1;
      if (fillIfEmpty('cs-recipient-postal-code', extracted.shippingRecipientPostalCode)) filled += 1;
      if (extracted.serialNumber && fillIfEmpty('ta-serial-number', extracted.serialNumber)) filled += 1;
      if (extracted.orderNumber && fillIfEmpty('ta-order-number', extracted.orderNumber)) filled += 1;

      let addedErrors = 0;
      let addedSolutions = 0;
      const columns = window.__ppIssuesColumns;
      if (columns && extracted.suggestedErrors && extracted.suggestedErrors.length) {
        addedErrors = columns.errors.addItems(extracted.suggestedErrors);
      }
      if (columns && extracted.suggestedSolutions && extracted.suggestedSolutions.length) {
        addedSolutions = columns.solutions.addItems(extracted.suggestedSolutions);
      }

      const parts = [];
      parts.push(filled ? 'Se han rellenado ' + filled + ' campos desde los mensajes.' : 'No se encontraron datos nuevos en los mensajes.');
      if (addedErrors) parts.push(addedErrors + ' error' + (addedErrors === 1 ? '' : 'es') + ' añadido' + (addedErrors === 1 ? '' : 's') + ' automáticamente.');
      if (addedSolutions) parts.push(addedSolutions + ' solución' + (addedSolutions === 1 ? '' : 'es') + ' añadida' + (addedSolutions === 1 ? '' : 's') + ' automáticamente.');
      if (addedErrors || addedSolutions) parts.push('Revísalos antes de guardar.');
      showSnack(parts.join(' '));
    } catch (error) {
      showSnack(error && error.message ? error.message : String(error));
    } finally {
      button.disabled = false;
      button.textContent = previous;
    }
  }

  function selectedTicketId() {
    const selected = document.querySelector('[data-ticket-id].is-selected');
    if (selected && selected.dataset.ticketId) return selected.dataset.ticketId;
    const eyebrow = document.querySelector('#ticket-detail .detail-header .eyebrow');
    return eyebrow ? eyebrow.textContent.trim() : '';
  }

  function currentDetail() {
    return window.__ticketDetail || {};
  }

  function injectStyles() {
    if (document.getElementById('customer-shipping-styles')) return;
    const style = document.createElement('style');
    style.id = 'customer-shipping-styles';
    style.textContent = [
      '.customer-shipping-actions { display: grid; grid-template-columns: repeat(3, minmax(140px, 1fr)); gap: 12px; margin-top: 12px; padding: 14px; border-radius: 16px; background: var(--surface-container); }',
      '.customer-shipping-actions .section-label { grid-column: 1 / -1; margin: 4px 0 0; font-size: 11px; font-weight: 800; text-transform: uppercase; letter-spacing: .04em; color: var(--on-surface-variant); }',
      '.customer-shipping-actions .section-label:first-child { margin-top: 0; }',
      '.cs-field { display: grid; gap: 7px; min-width: 0; color: var(--on-surface-variant); font-size: 12px; font-weight: 800; text-transform: uppercase; }',
      '.cs-field-wide { grid-column: 1 / -1; }',
      '.cs-field input { width: 100%; min-height: 40px; padding: 0 12px; border: 1px solid var(--outline); border-radius: 12px; color: var(--on-surface); background: var(--surface-bright); font: inherit; text-transform: none; font-weight: 400; }',
      '.cs-extract-row { grid-column: 1 / -1; display: flex; justify-content: flex-end; }',
      '@media (max-width: 700px) { .customer-shipping-actions { grid-template-columns: 1fr; } }'
    ].join('\n');
    document.head.appendChild(style);
  }

  function createField(fieldId, name, value, placeholder, wide) {
    const label = document.createElement('label');
    label.className = wide ? 'cs-field cs-field-wide' : 'cs-field';
    const caption = document.createElement('span');
    caption.textContent = name;
    const input = document.createElement('input');
    input.type = 'text';
    input.id = fieldId;
    input.value = value || '';
    input.defaultValue = input.value;
    input.placeholder = placeholder || '';
    label.appendChild(caption);
    label.appendChild(input);
    return label;
  }

  function sectionLabel(text) {
    const span = document.createElement('span');
    span.className = 'section-label';
    span.textContent = text;
    return span;
  }

  function ensureCustomerShippingControls() {
    injectStyles();
    const header = document.querySelector('#ticket-detail .detail-header');
    if (!header || header.querySelector('.customer-shipping-actions')) return;
    const ticketId = selectedTicketId();
    if (!ticketId) return;

    const detail = currentDetail();
    const ticket = detail.ticket || {};
    const customer = detail.customer || {};

    const wrap = document.createElement('div');
    wrap.className = 'customer-shipping-actions';

    const extractRow = document.createElement('div');
    extractRow.className = 'cs-extract-row';
    const extractButton = document.createElement('button');
    extractButton.type = 'button';
    extractButton.className = 'text-button';
    extractButton.textContent = 'Analizar mensajes y rellenar todo';
    extractButton.addEventListener('click', function () { extractFromMessages(ticketId, extractButton); });
    extractRow.appendChild(extractButton);
    wrap.appendChild(extractRow);

    wrap.appendChild(sectionLabel('Cliente'));
    wrap.appendChild(createField('cs-first-name', 'Nombre', customer.firstName, 'Jane'));
    wrap.appendChild(createField('cs-last-name', 'Apellidos', customer.lastName, 'Doe'));
    wrap.appendChild(createField('cs-phone', 'Teléfono', customer.phone, '+34 600 000 000'));
    wrap.appendChild(createField('cs-address', 'Dirección', customer.address, 'Calle, ciudad, código postal', true));
    wrap.appendChild(createField('cs-country', 'País', customer.country, 'España'));
    wrap.appendChild(createField('cs-postal-code', 'Código postal', customer.postalCode, '08001'));

    wrap.appendChild(sectionLabel('Envío'));
    wrap.appendChild(createField('cs-recipient-first-name', 'Nombre del destinatario', ticket.shippingRecipientFirstName, 'Quién recibe el paquete'));
    wrap.appendChild(createField('cs-recipient-last-name', 'Apellidos del destinatario', ticket.shippingRecipientLastName, ''));
    wrap.appendChild(createField('cs-recipient-phone', 'Teléfono del destinatario', ticket.shippingRecipientPhone, 'Teléfono de contacto'));
    wrap.appendChild(createField('cs-shipping-address', 'Dirección de envío', ticket.shippingAddress, 'Si es distinta de la dirección del cliente', true));
    wrap.appendChild(createField('cs-recipient-country', 'País del destinatario', ticket.shippingRecipientCountry, 'España'));
    wrap.appendChild(createField('cs-recipient-postal-code', 'Código postal del destinatario', ticket.shippingRecipientPostalCode, '08001'));

    header.appendChild(wrap);
  }

  const observer = new MutationObserver(function () {
    ensureCustomerShippingControls();
  });

  function start() {
    const panel = document.getElementById('ticket-detail');
    if (!panel) return;
    observer.observe(panel, {childList: true, subtree: true});
    ensureCustomerShippingControls();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }
})();
</script>
'@
[System.IO.File]::WriteAllText((Join-Path $root "html\CustomerShippingActions.html"), $v2, $enc)
Write-Host "  [OK]" -ForegroundColor Green

Write-Host ""
Write-Host "Verificando..." -ForegroundColor Cyan
Select-String -Path src\extraction.gs -Pattern "extractShippingBlock_"
Select-String -Path html\IssuesSectionScripts.html -Pattern "addItems"
Select-String -Path html\CustomerShippingActions.html -Pattern "Analizar mensajes y rellenar todo"

Write-Host ""
Write-Host "Si salieron lineas arriba, ejecuta: npm test  y  npm run deploy" -ForegroundColor Cyan
