/**
 * Gmail draft generation for support tickets.
 *
 * The service intentionally creates drafts only. It never sends emails.
 */
class DraftReplyService {
  /**
   * @param {{ticketRepository: Object, settings: Object, clock: function(): Date, logger: Object}} dependencies
   */
  constructor(dependencies) {
    ['ticketRepository', 'settings', 'clock', 'logger'].forEach(function(name) {
      if (!dependencies || dependencies[name] == null) {
        throw new Error('Missing DraftReplyService dependency: ' + name);
      }
    });
    this.tickets_ = dependencies.ticketRepository;
    this.settings_ = dependencies.settings;
    this.clock_ = dependencies.clock;
    this.logger_ = dependencies.logger;
  }

  /**
   * Creates a Gmail draft response for an existing ticket.
   * @param {string} ticketId
   * @param {string=} templateKey
   * @param {string=} customBody
   * @return {{ok: boolean, ticketId: string, draftId: string, subject: string}}
   */
  createForTicket(ticketId, templateKey, customBody) {
    const ticket = this.tickets_.findById(ticketId);
    if (!ticket) {
      throw new AppError('Ticket not found: ' + ticketId, 'DRAFT_TICKET_NOT_FOUND', {ticketId: ticketId});
    }
    if (!ticket.threadId) {
      throw new AppError('Ticket has no Gmail Thread ID: ' + ticketId, 'DRAFT_THREAD_MISSING', {ticketId: ticketId});
    }

    const thread = GmailApp.getThreadById(ticket.threadId);
    const messages = thread.getMessages();
    if (!messages.length) {
      throw new AppError('Gmail thread is empty: ' + ticket.threadId, 'DRAFT_EMPTY_THREAD', {ticketId: ticketId});
    }

    const latestMessage = messages[messages.length - 1];
    const trimmedCustomBody = String(customBody || '').trim();
    const body = trimmedCustomBody || this.renderBody_(ticket, templateKey || 'DEFAULT_SUPPORT_REPLY');
    const htmlBody = trimmedCustomBody
      ? DraftReplyService.plainToHtml_(trimmedCustomBody)
      : this.renderHtmlBody_(ticket, templateKey || 'DEFAULT_SUPPORT_REPLY');
    const draft = latestMessage.createDraftReply(body, {htmlBody: htmlBody});

    this.logger_.info('Draft reply created.', {
      ticketId: ticketId,
      templateKey: templateKey || 'DEFAULT_SUPPORT_REPLY',
      customBody: Boolean(trimmedCustomBody)
    });
    return {
      ok: true,
      ticketId: ticketId,
      draftId: draft.getId(),
      subject: latestMessage.getSubject()
    };
  }

  /**
   * @param {Object} ticket
   * @param {string} templateKey
   * @return {string}
   * @private
   */
  renderBody_(ticket, templateKey) {
    const template = this.findTemplate_(templateKey);
    const body = template && template.bodyText ? template.bodyText : DraftReplyService.defaultPlainBody_();
    return DraftReplyService.interpolate_(body, ticket, this.clock_());
  }

  /**
   * @param {Object} ticket
   * @param {string} templateKey
   * @return {string}
   * @private
   */
  renderHtmlBody_(ticket, templateKey) {
    const template = this.findTemplate_(templateKey);
    const html = template && template.bodyHtml ? template.bodyHtml : DraftReplyService.defaultHtmlBody_();
    return DraftReplyService.interpolate_(html, ticket, this.clock_());
  }

  /**
   * @param {string} templateKey
   * @return {{key: string, bodyHtml: string, bodyText: string}|null}
   * @private
   */
  findTemplate_(templateKey) {
    const sheet = AppConfig.getSheet(APP.SHEETS.TEMPLATES);
    if (sheet.getLastRow() <= 1) {
      return null;
    }
    const headers = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getDisplayValues()[0];
    const keyIndex = headers.indexOf('Template Key');
    const bodyHtmlIndex = headers.indexOf('Body HTML');
    if (keyIndex === -1 || bodyHtmlIndex === -1) {
      return null;
    }
    const values = sheet.getRange(2, 1, sheet.getLastRow() - 1, headers.length).getDisplayValues();
    for (let rowIndex = 0; rowIndex < values.length; rowIndex += 1) {
      const row = values[rowIndex];
      if (String(row[keyIndex]).trim() === templateKey) {
        return {
          key: templateKey,
          bodyHtml: row[bodyHtmlIndex] || '',
          bodyText: DraftReplyService.htmlToPlain_(row[bodyHtmlIndex] || '')
        };
      }
    }
    return null;
  }

  /** @return {string} @private */
  static defaultPlainBody_() {
    return 'Hola,\n\nGracias por contactar con PocketPiano.\n\nHemos recibido tu incidencia {{ticketId}} y la estamos revisando.\n\nPara poder ayudarte mejor, por favor indícanos el número de serie del PocketPiano y adjunta una foto o vídeo donde se vea el problema.\n\nUn saludo,\nPocketPiano Support';
  }

  /** @return {string} @private */
  static defaultHtmlBody_() {
    return '<p>Hola,</p>' +
      '<p>Gracias por contactar con PocketPiano.</p>' +
      '<p>Hemos recibido tu incidencia <strong>{{ticketId}}</strong> y la estamos revisando.</p>' +
      '<p>Para poder ayudarte mejor, por favor indícanos el número de serie del PocketPiano y adjunta una foto o vídeo donde se vea el problema.</p>' +
      '<p>Un saludo,<br>PocketPiano Support</p>';
  }

  /**
   * @param {string} value
   * @param {Object} ticket
   * @param {Date} now
   * @return {string}
   * @private
   */
  static interpolate_(value, ticket, now) {
    const replacements = {
      ticketId: ticket.id || '',
      subject: ticket.subject || '',
      customerEmail: ticket.customerEmail || '',
      status: ticket.status || '',
      priority: ticket.priority || '',
      category: ticket.category || '',
      date: Utilities.formatDate(now, Session.getScriptTimeZone(), 'yyyy-MM-dd')
    };
    return String(value || '').replace(/{{\s*([A-Za-z0-9_]+)\s*}}/g, function(match, key) {
      return Object.prototype.hasOwnProperty.call(replacements, key) ? replacements[key] : match;
    });
  }

  /** @param {string} html @return {string} @private */
  static htmlToPlain_(html) {
    return String(html || '')
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<\/p>/gi, '\n\n')
      .replace(/<[^>]+>/g, '')
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .trim();
  }

  /** @param {string} text @return {string} @private */
  static plainToHtml_(text) {
    const escaped = String(text || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
    return '<p>' + escaped.replace(/\n/g, '<br>') + '</p>';
  }
}

/** @return {DraftReplyService} @private */
function createDraftReplyService_() {
  return new DraftReplyService({
    ticketRepository: new SheetTicketRepository(),
    settings: new GmailSyncSettings(),
    clock: function() { return new Date(); },
    logger: AppLogger
  });
}

/**
 * Public entry point used by the UI and menu actions.
 * @param {string} ticketId
 * @param {string=} templateKey
 * @return {{ok: boolean, ticketId: string, draftId: string, subject: string}}
 */
function createDraftForTicket(ticketId, templateKey, customBody) {
  return createDraftReplyService_().createForTicket(ticketId, templateKey || 'DEFAULT_SUPPORT_REPLY', customBody);
}
