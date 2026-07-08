/**
 * Mutating UI actions used by the HTMLService client.
 *
 * These wrappers always return the same ok/data envelope as read-only UI calls.
 */

/**
 * Creates a Gmail draft reply for a support ticket from the UI.
 * This action never sends email.
 *
 * @param {string} ticketId
 * @param {string=} templateKey
 * @return {{ok: boolean, data: Object}|Object}
 */
function createUiDraftForTicket(ticketId, templateKey) {
  try {
    const result = createDraftForTicket(ticketId, templateKey || 'DEFAULT_SUPPORT_REPLY');
    return {ok: true, data: UiSerializer.toClient(result)};
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}

/**
 * Runs one bounded Gmail synchronization pass from the UI.
 *
 * @return {{ok: boolean, data: Object}|Object}
 */
function syncUiGmail() {
  try {
    const result = syncGmail();
    return {ok: true, data: UiSerializer.toClient(result)};
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}

/**
 * Translates the synchronized message bodies for a ticket to Spanish and persists
 * the results in the Messages sheet.
 * @param {string} ticketId
 * @return {{ok: boolean, data: Object}|Object}
 */
function translateUiTicketToSpanish(ticketId) {
  try {
    const ticketRepository = new SheetTicketRepository();
    const ticket = ticketRepository.findById(ticketId);
    if (!ticket) {
      throw new AppError('Ticket not found: ' + ticketId, 'TICKET_NOT_FOUND', {ticketId: ticketId});
    }
    const messages = new UiMessageReadRepository().listByTicketId(ticketId);
    const result = TranslationService.translateMessagesToSpanish(messages);
    const messageRepository = new SheetMessageRepository();
    result.forEach(function(message) {
      if (message.id && message.translatedBody) {
        messageRepository.updateTranslation(
          message.id,
          message.detectedLanguage || message.originalLanguage || '',
          message.translatedBody
        );
      }
    });
    return {ok: true, data: UiSerializer.toClient({ticketId: ticketId, messages: result})};
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}

/** @param {string} ticketId @param {string} status @return {{ok: boolean, data: Object}|Object} */
function updateUiTicketStatus(ticketId, status) {
  try {
    const result = updateTicketStatus(ticketId, status);
    return {ok: true, data: UiSerializer.toClient(result)};
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}

/** @param {string} ticketId @param {string} priority @return {{ok: boolean, data: Object}|Object} */
function updateUiTicketPriority(ticketId, priority) {
  try {
    const result = updateTicketPriority(ticketId, priority);
    return {ok: true, data: UiSerializer.toClient(result)};
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}

/** @param {string} ticketId @param {string} category @return {{ok: boolean, data: Object}|Object} */
function updateUiTicketCategory(ticketId, category) {
  try {
    const result = updateTicketCategory(ticketId, category);
    return {ok: true, data: UiSerializer.toClient(result)};
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}

/** @param {string} ticketId @param {string} assignedTo @return {{ok: boolean, data: Object}|Object} */
function assignUiTicket(ticketId, assignedTo) {
  try {
    const result = assignTicket(ticketId, assignedTo || '');
    return {ok: true, data: UiSerializer.toClient(result)};
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}

/** @param {string} ticketId @param {string} tags @return {{ok: boolean, data: Object}|Object} */
function updateUiTicketTags(ticketId, tags) {
  try {
    const result = updateTicketTags(ticketId, tags || '');
    return {ok: true, data: UiSerializer.toClient(result)};
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}
