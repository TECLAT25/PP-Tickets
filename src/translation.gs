/** Google Cloud Translation integration for support conversations. */
class TranslationService {
  /**
   * Translates a batch of UI messages to Spanish. Existing sheet translations are reused.
   * @param {Array<Object>} messages
   * @return {Array<Object>}
   */
  static translateMessagesToSpanish(messages) {
    const items = messages || [];
    if (!items.length) return [];
    return items.map(function(message) {
      const text = String(message.body || '');
      const storedTranslation = String(message.translatedBodyEs || '');
      const storedLanguage = String(message.originalLanguage || '');
      if (storedTranslation) {
        return Object.assign({}, message, {
          translatedBody: storedTranslation,
          detectedLanguage: storedLanguage,
          translated: storedLanguage.toLowerCase() !== 'es',
          cached: true
        });
      }
      if (!text.trim()) {
        return Object.assign({}, message, {translatedBody: '', detectedLanguage: storedLanguage, translated: false, cached: false});
      }
      const translated = TranslationService.translateText_(text);
      Utilities.sleep(350);
      const textChanged = translated.text.trim().toLowerCase() !== text.trim().toLowerCase();
      return Object.assign({}, message, {
        translatedBody: translated.text,
        translatedBodyEs: translated.text,
        detectedLanguage: translated.detectedLanguage,
        originalLanguage: translated.detectedLanguage,
        translated: textChanged,
        cached: false
      });
    });
  }

  /**
   * Stores service account credentials in Script Properties.
   * Paste the full JSON downloaded from Google Cloud.
   * @param {string} jsonText
   * @return {{ok: boolean, clientEmail: string, projectId: string}}
   */
  static saveServiceAccount(jsonText) {
    const credentials = TranslationService.parseServiceAccount_(jsonText);
    AppConfig.getProperties().setProperty('GOOGLE_CLOUD_SERVICE_ACCOUNT_JSON', JSON.stringify(credentials));
    return {ok: true, clientEmail: credentials.client_email, projectId: credentials.project_id};
  }

  /** @param {string} text @return {{text: string, detectedLanguage: string}} @private */
  static translateText_(text) {
    try {
      return TranslationService.translateTextWithLanguageApp_(text);
    } catch (languageAppError) {
      // Fall through to Cloud Translation API methods if LanguageApp is unavailable or fails.
    }
    const serviceAccount = TranslationService.getServiceAccount_();
    if (serviceAccount) return TranslationService.translateTextWithServiceAccount_(text, serviceAccount);
    const apiKey = String(AppConfig.getSetting('GOOGLE_TRANSLATE_API_KEY', '') || '').trim();
    if (apiKey) return TranslationService.translateTextWithApiKey_(text, apiKey);
    throw new AppError(
      'No se pudo traducir. El servicio gratuito integrado no está disponible ahora mismo, y no hay una clave de Cloud Translation configurada como alternativa.',
      'TRANSLATE_CREDENTIALS_MISSING'
    );
  }

  /**
   * Uses Apps Script's built-in LanguageApp service. Free, no API key or
   * billing required, but with its own daily quota.
   * @param {string} text
   * @return {{text: string, detectedLanguage: string}}
   * @private
   */
  static translateTextWithLanguageApp_(text) {
    const translated = LanguageApp.translate(text, '', 'es');
    if (!translated) {
      throw new AppError('LanguageApp returned an empty translation.', 'TRANSLATE_LANGUAGEAPP_EMPTY');
    }
    return {text: translated, detectedLanguage: ''};
  }

  /**
   * @param {string} text
   * @param {Object} serviceAccount
   * @return {{text: string, detectedLanguage: string}}
   * @private
   */
  static translateTextWithServiceAccount_(text, serviceAccount) {
    const token = TranslationService.getAccessToken_(serviceAccount);
    const response = TranslationService.fetchWithRetry_('https://translation.googleapis.com/language/translate/v2', {
      method: 'post',
      contentType: 'application/json; charset=utf-8',
      headers: {Authorization: 'Bearer ' + token},
      muteHttpExceptions: true,
      payload: JSON.stringify({q: text, target: 'es', format: 'text'})
    });
    return TranslationService.parseTranslationResponse_(response);
  }

  /**
   * @param {string} text
   * @param {string} apiKey
   * @return {{text: string, detectedLanguage: string}}
   * @private
   */
  static translateTextWithApiKey_(text, apiKey) {
    const url = 'https://translation.googleapis.com/language/translate/v2?key=' + encodeURIComponent(apiKey);
    const response = TranslationService.fetchWithRetry_(url, {
      method: 'post',
      contentType: 'application/json; charset=utf-8',
      muteHttpExceptions: true,
      payload: JSON.stringify({q: text, target: 'es', format: 'text'})
    });
    return TranslationService.parseTranslationResponse_(response);
  }

  /**
   * Calls UrlFetchApp with retries and exponential backoff for rate-limit responses.
   * @param {string} url
   * @param {Object} options
   * @return {GoogleAppsScript.URL_Fetch.HTTPResponse}
   * @private
   */
  static fetchWithRetry_(url, options) {
    const maxAttempts = 4;
    let lastResponse = null;
    for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
      const response = UrlFetchApp.fetch(url, options);
      const status = response.getResponseCode();
      const isRateLimited = status === 429 ||
        (status === 403 && /rate limit/i.test(response.getContentText()));
      if (!isRateLimited || attempt === maxAttempts) {
        return response;
      }
      lastResponse = response;
      Utilities.sleep(Math.pow(2, attempt) * 500);
    }
    return lastResponse;
  }

  /**
   * @param {GoogleAppsScript.URL_Fetch.HTTPResponse} response
   * @return {{text: string, detectedLanguage: string}}
   * @private
   */
  static parseTranslationResponse_(response) {
    const status = response.getResponseCode();
    const body = response.getContentText();
    let parsed;
    try {
      parsed = JSON.parse(body);
    } catch (error) {
      throw new AppError('Invalid translation response from Google Cloud.', 'TRANSLATE_INVALID_RESPONSE', {status: status});
    }
    if (status < 200 || status >= 300) {
      const rawMessage = (parsed.error && parsed.error.message) || 'Google Cloud Translation request failed.';
      const isRateLimited = status === 429 || (status === 403 && /rate limit/i.test(rawMessage));
      const message = isRateLimited
        ? rawMessage + ' (persiste tras varios reintentos; puede que la clave de API tenga una cuota muy baja en Google Cloud Console — revisa Cuotas y límites de la Cloud Translation API).'
        : rawMessage;
      throw new AppError(message, 'TRANSLATE_REQUEST_FAILED', {status: status});
    }
    const result = parsed.data && parsed.data.translations && parsed.data.translations[0];
    return {
      text: result ? String(result.translatedText || '') : '',
      detectedLanguage: result ? String(result.detectedSourceLanguage || '') : ''
    };
  }

  /** @return {Object|null} @private */
  static getServiceAccount_() {
    const raw = AppConfig.getProperties().getProperty('GOOGLE_CLOUD_SERVICE_ACCOUNT_JSON');
    if (!raw) return null;
    return TranslationService.parseServiceAccount_(raw);
  }

  /** @param {string} jsonText @return {Object} @private */
  static parseServiceAccount_(jsonText) {
    let credentials;
    try {
      credentials = JSON.parse(jsonText);
    } catch (error) {
      throw new AppError('Invalid Google Cloud service account JSON.', 'SERVICE_ACCOUNT_JSON_INVALID');
    }
    ['client_email', 'private_key', 'token_uri', 'project_id'].forEach(function(key) {
      if (!credentials[key]) throw new AppError('Service account JSON is missing: ' + key, 'SERVICE_ACCOUNT_JSON_INCOMPLETE', {key: key});
    });
    return credentials;
  }

  /** @param {Object} serviceAccount @return {string} @private */
  static getAccessToken_(serviceAccount) {
    const now = Math.floor(Date.now() / 1000);
    const header = {alg: 'RS256', typ: 'JWT'};
    const claim = {
      iss: serviceAccount.client_email,
      scope: 'https://www.googleapis.com/auth/cloud-translation',
      aud: serviceAccount.token_uri,
      exp: now + 3600,
      iat: now
    };
    const unsignedJwt = TranslationService.base64Url_(JSON.stringify(header)) + '.' + TranslationService.base64Url_(JSON.stringify(claim));
    const signature = Utilities.computeRsaSha256Signature(unsignedJwt, serviceAccount.private_key);
    const jwt = unsignedJwt + '.' + TranslationService.base64UrlBytes_(signature);

    const response = UrlFetchApp.fetch(serviceAccount.token_uri, {
      method: 'post',
      payload: {grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: jwt},
      muteHttpExceptions: true
    });
    const status = response.getResponseCode();
    const body = response.getContentText();
    let parsed;
    try {
      parsed = JSON.parse(body);
    } catch (error) {
      throw new AppError('Invalid Google OAuth token response.', 'GOOGLE_TOKEN_INVALID_RESPONSE', {status: status});
    }
    if (status < 200 || status >= 300 || !parsed.access_token) {
      throw new AppError((parsed.error_description || parsed.error || 'Could not obtain Google Cloud access token.'), 'GOOGLE_TOKEN_REQUEST_FAILED', {status: status});
    }
    return parsed.access_token;
  }

  /** @param {string} text @return {string} @private */
  static base64Url_(text) {
    return Utilities.base64EncodeWebSafe(text).replace(/=+$/, '');
  }

  /** @param {Byte[]} bytes @return {string} @private */
  static base64UrlBytes_(bytes) {
    return Utilities.base64EncodeWebSafe(bytes).replace(/=+$/, '');
  }
}

/**
 * Run once from Apps Script and paste the downloaded service-account JSON.
 * @param {string} serviceAccountJson
 * @return {{ok: boolean, clientEmail: string, projectId: string}}
 */
function setupGoogleCloudServiceAccount(serviceAccountJson) {
  return TranslationService.saveServiceAccount(serviceAccountJson);
}
