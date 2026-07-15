/** Read-only application service for the HTML interface. */
class UiQueryService {
  /**
   * @param {{
   *   ticketRepository: Object,
   *   messageRepository: Object,
   *   customerRepository: Object,
   *   clock: function(): Date,
   *   version: string
   * }} dependencies
   */
  constructor(dependencies) {
    ['ticketRepository', 'messageRepository', 'customerRepository', 'clock', 'version']
      .forEach(function(name) {
        if (!dependencies || dependencies[name] == null) {
          throw new Error('Missing UiQueryService dependency: ' + name);
        }
      });
    this.tickets_ = dependencies.ticketRepository;
    this.messages_ = dependencies.messageRepository;
    this.customers_ = dependencies.customerRepository;
    this.clock_ = dependencies.clock;
    this.version_ = dependencies.version;
  }

  /**
   * Returns dashboard metrics, filter definitions, and a ticket page.
   * @param {Object=} criteria
   * @return {Object}
   */
  getState(criteria) {
    const filters = criteria || {};
    const page = this.tickets_.search(filters);
    return {
      app: {name: APP.NAME, version: this.version_},
      metrics: TicketMetrics.calculate(this.tickets_.listAll(), this.clock_()),
      filters: {
        statuses: TicketPolicy.statuses(),
        priorities: TicketPolicy.priorities(),
        categories: TicketPolicy.categories()
      },
      tickets: page
    };
  }

  /**
   * Returns a ticket with its conversation and customer read model.
   * @param {string} ticketId
   * @return {Object}
   */
  getTicketDetail(ticketId) {
    const ticket = this.tickets_.findById(String(ticketId || ''));
    if (!ticket) {
      throw new AppError('Ticket not found: ' + ticketId, 'TICKET_NOT_FOUND', {ticketId: ticketId});
    }
    return {
      ticket: ticket,
      messages: this.messages_.listByTicketId(ticket.id),
      customer: this.customers_.findForTicket(ticket) || {
        id: ticket.customerId || '',
        email: ticket.customerEmail || '',
        name: '',
        phone: '',
        locale: '',
        company: '',
        notes: ''
      }
    };
  }
}

/** Recursively converts server values into google.script.run-safe values. */
class UiSerializer {
  /** @param {*} value @return {*} */
  static toClient(value) {
    if (value instanceof Date) {
      return value.toISOString();
    }
    if (Array.isArray(value)) {
      return value.map(UiSerializer.toClient);
    }
    if (value && typeof value === 'object') {
      const output = {};
      Object.keys(value).forEach(function(key) {
        output[key] = UiSerializer.toClient(value[key]);
      });
      return output;
    }
    return value;
  }
}

/** @return {UiQueryService} @private */
function createUiQueryService_() {
  return new UiQueryService({
    ticketRepository: new SheetTicketRepository(),
    messageRepository: new UiMessageReadRepository(),
    customerRepository: new UiCustomerReadRepository(),
    clock: function() { return new Date(); },
    version: APP_VERSION
  });
}

/** @param {Object=} criteria @return {Object} */
function getUiState(criteria) {
  try {
    return {ok: true, data: UiSerializer.toClient(createUiQueryService_().getState(criteria || {}))};
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}

/** @param {string} ticketId @return {Object} */
function getUiTicketDetail(ticketId) {
  try {
    return {ok: true, data: UiSerializer.toClient(createUiQueryService_().getTicketDetail(ticketId))};
  } catch (error) {
    return AppUtils.errorResponse(error);
  }
}
