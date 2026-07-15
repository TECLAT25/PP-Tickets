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