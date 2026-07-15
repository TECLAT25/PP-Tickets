'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const serialNumbersSource = fs.readFileSync(path.join(__dirname, '..', 'src', 'serialNumbers.gs'), 'utf8');
vm.runInThisContext(
  serialNumbersSource + '\n;globalThis.SerialNumberService = SerialNumberService;',
  {filename: 'src/serialNumbers.gs'}
);

const source = fs.readFileSync(path.join(__dirname, '..', 'src', 'tickets.gs'), 'utf8');
vm.runInThisContext(
  source + '\n;globalThis.TicketManager = TicketManager;' +
  'globalThis.TicketPolicy = TicketPolicy;' +
  'globalThis.TicketMetrics = TicketMetrics;' +
  'globalThis.TicketNumberService = TicketNumberService;',
  {filename: 'src/tickets.gs'}
);

class Repository {
  constructor() { this.items = []; }
  create(record) { const created = Object.assign({}, record); this.items.push(created); return created; }
  findById(id) { return this.items.find(item => item.id === id) || null; }
  update(id, changes) {
    const ticket = this.findById(id);
    if (!ticket) throw new Error('Ticket not found: ' + id);
    Object.assign(ticket, changes);
    return ticket;
  }
  search(criteria) {
    let items = this.items.slice();
    if (criteria.status) items = items.filter(item => item.status === criteria.status);
    if (criteria.priority) items = items.filter(item => item.priority === criteria.priority);
    if (criteria.category) items = items.filter(item => item.category === criteria.category);
    if (criteria.query) {
      const query = criteria.query.toLowerCase();
      items = items.filter(item => (item.id + ' ' + item.subject + ' ' + item.customerEmail)
        .toLowerCase().includes(query));
    }
    return {items, total: items.length, offset: 0, limit: 100};
  }
}

function fixture() {
  const repository = new Repository();
  let sequence = 0;
  let dashboardRefreshes = 0;
  const policy = new TicketPolicy({
    get(key, fallback) {
      return key === 'SLA_HIGH_HOURS' ? '8' : fallback;
    }
  });
  const manager = new TicketManager({
    repository,
    numberGenerator: () => TicketNumberService.format('PP', '2026', ++sequence),
    policy,
    dashboard: {refresh() { dashboardRefreshes += 1; }},
    clock: () => new Date('2026-06-30T10:00:00Z'),
    version: '1.2.0',
    logger: {info() {}}
  });
  return {manager, repository, dashboardRefreshes: () => dashboardRefreshes};
}

function testGenerationNumberingAndSla() {
  const test = fixture();
  const ticket = test.manager.create({
    subject: 'Key does not respond',
    customerEmail: 'PLAYER@EXAMPLE.COM',
    priority: 'HIGH',
    category: 'TECHNICAL',
    tags: ['keyboard', 'keyboard', 'urgent']
  });
  assert.equal(ticket.id, 'PP-2026-000001');
  assert.equal(ticket.status, 'NEW');
  assert.equal(ticket.priority, 'HIGH');
  assert.equal(ticket.category, 'TECHNICAL');
  assert.equal(ticket.customerEmail, 'player@example.com');
  assert.equal(ticket.tags, 'keyboard, urgent');
  assert.equal(ticket.slaDueAt.toISOString(), '2026-06-30T18:00:00.000Z');
  assert.equal(test.dashboardRefreshes(), 1);
}

function testLifecycleValidationAndPrioritySla() {
  const test = fixture();
  const ticket = test.manager.create({subject: 'Warranty', customerEmail: 'a@example.com'});
  assert.throws(() => test.manager.updateStatus(ticket.id, 'UNKNOWN'), /Invalid ticket status/);
  assert.throws(() => test.manager.updateCategory(ticket.id, 'RANDOM'), /Invalid ticket category/);
  test.manager.updateStatus(ticket.id, 'OPEN');
  test.manager.updatePriority(ticket.id, 'CRITICAL');
  test.manager.updateCategory(ticket.id, 'WARRANTY');
  assert.equal(ticket.status, 'OPEN');
  assert.equal(ticket.priority, 'CRITICAL');
  assert.equal(ticket.category, 'WARRANTY');
  assert.equal(ticket.slaDueAt.toISOString(), '2026-06-30T14:00:00.000Z');
}

function testSearchAndFilters() {
  const test = fixture();
  test.manager.create({subject: 'Shipping delay', customerEmail: 'a@example.com', category: 'SHIPPING'});
  test.manager.create({
    subject: 'Broken key', customerEmail: 'b@example.com',
    priority: 'CRITICAL', category: 'TECHNICAL'
  });
  assert.equal(test.manager.search({category: 'TECHNICAL'}).total, 1);
  assert.equal(test.manager.search({priority: 'CRITICAL'}).total, 1);
  assert.equal(test.manager.search({query: 'shipping'}).items[0].category, 'SHIPPING');
  assert.deepEqual(test.manager.filters().statuses, ['NEW', 'OPEN', 'PENDING_CUSTOMER', 'RESOLVED', 'CLOSED']);
}

function testDashboardMetrics() {
  const now = new Date('2026-06-30T12:00:00Z');
  const metrics = TicketMetrics.calculate([
    {status: 'OPEN', priority: 'HIGH', category: 'TECHNICAL', slaDueAt: new Date('2026-06-30T11:00:00Z')},
    {status: 'RESOLVED', priority: 'NORMAL', category: 'GENERAL', slaDueAt: new Date('2026-06-29T10:00:00Z')}
  ], now);
  assert.equal(metrics.total, 2);
  assert.equal(metrics.active, 1);
  assert.equal(metrics.breached, 1);
  assert.equal(metrics.byStatus.RESOLVED, 1);
  assert.equal(metrics.byCategory.TECHNICAL, 1);
}

[
  testGenerationNumberingAndSla,
  testLifecycleValidationAndPrioritySla,
  testSearchAndFilters,
  testDashboardMetrics
].forEach(test => test());

console.log('Ticket manager tests passed.');