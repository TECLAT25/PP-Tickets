'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

globalThis.APP = {NAME: 'PP Tickets'};
const tickets = fs.readFileSync(path.join(__dirname, '..', 'src', 'tickets.gs'), 'utf8');
vm.runInThisContext(
  tickets + '\n;globalThis.TicketMetrics = TicketMetrics;globalThis.TicketPolicy = TicketPolicy;',
  {filename: 'src/tickets.gs'}
);
const source = fs.readFileSync(path.join(__dirname, '..', 'src', 'ui.gs'), 'utf8');
vm.runInThisContext(
  source + '\n;globalThis.UiQueryService = UiQueryService;globalThis.UiSerializer = UiSerializer;',
  {filename: 'src/ui.gs'}
);

const ticket = {
  id: 'PP-2026-000001', status: 'OPEN', priority: 'HIGH', category: 'TECHNICAL',
  subject: 'Broken key', customerId: 'C-1', customerEmail: 'player@example.com',
  createdAt: new Date('2026-06-30T10:00:00Z'), updatedAt: new Date('2026-06-30T11:00:00Z'),
  lastMessageAt: new Date('2026-06-30T11:00:00Z'), slaDueAt: new Date('2026-06-30T09:00:00Z')
};
const ticketsRepository = {
  listAll: () => [ticket],
  search: () => ({items: [ticket], total: 1, offset: 0, limit: 100}),
  findById: id => id === ticket.id ? ticket : null
};
const service = new UiQueryService({
  ticketRepository: ticketsRepository,
  messageRepository: {listByTicketId: () => [{
    id: 'M-1', direction: 'INBOUND', body: 'Please help',
    sentAt: new Date('2026-06-30T10:00:00Z'), attachmentCount: 1
  }]},
  customerRepository: {findForTicket: () => ({id: 'C-1', email: 'player@example.com', name: 'Player'})},
  clock: () => new Date('2026-06-30T12:00:00Z'),
  version: '1.3.0'
});

const state = service.getState({limit: 100});
assert.equal(state.tickets.total, 1);
assert.equal(state.metrics.active, 1);
assert.equal(state.metrics.breached, 1);
assert.equal(state.filters.categories.includes('TECHNICAL'), true);

const detail = service.getTicketDetail(ticket.id);
assert.equal(detail.messages.length, 1);
assert.equal(detail.messages[0].attachmentCount, 1);
assert.equal(detail.customer.name, 'Player');

const serialized = UiSerializer.toClient(detail);
assert.equal(serialized.ticket.createdAt, '2026-06-30T10:00:00.000Z');
assert.equal(serialized.messages[0].sentAt, '2026-06-30T10:00:00.000Z');

console.log('UI query tests passed.');
