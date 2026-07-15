'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '..', 'src', 'gmail.gs'), 'utf8');
vm.runInThisContext(source + '\n;globalThis.GmailSyncEngine = GmailSyncEngine;', {
  filename: 'src/gmail.gs'
});

class FakeGmailGateway {
  constructor(threads) {
    this.threads = threads;
    this.marked = [];
    this.mailbox = '';
    this.query = '';
  }
  assertMailbox(mailbox) { this.mailbox = mailbox; }
  listThreads(query) { this.query = query; return this.threads; }
  markProcessed(threadId, label) { this.marked.push({threadId, label}); }
}

class FakeTicketRepository {
  constructor(ticket) {
    this.ticket = ticket || null;
    this.created = [];
    this.updated = [];
  }
  findByThreadId(threadId) {
    return this.ticket && this.ticket.threadId === threadId ? this.ticket : null;
  }
  search(criteria) {
    const items = (this.ticket && (!criteria.customerEmail || this.ticket.customerEmail === criteria.customerEmail)) ? [this.ticket] : [];
    return {items: items, total: items.length, offset: 0, limit: criteria.limit || 100};
  }
  update(ticketId, changes) {
    if (this.ticket && this.ticket.id === ticketId) {
      Object.assign(this.ticket, changes);
      this.updated.push({ticket: this.ticket, changes: changes});
      return this.ticket;
    }
    return null;
  }
  create(record) {
    this.ticket = Object.assign({rowNumber: 2, driveFolderId: ''}, record);
    this.created.push(this.ticket);
    return this.ticket;
  }
  updateConversation(ticket, changes) {
    Object.assign(ticket, changes);
    this.updated.push({ticket, changes});
  }
}

class FakeMessageRepository {
  constructor(ids) {
    this.ids = new Set(ids || []);
    this.created = [];
  }
  hasMessage(id) { return this.ids.has(id); }
  add(record) {
    assert.equal(this.ids.has(record.gmailMessageId), false, 'message must be unique');
    this.ids.add(record.gmailMessageId);
    this.created.push(record);
  }
}

class FakeCustomerRepository {
  constructor() {
    this.byEmail = new Map();
    this.upserts = [];
  }
  upsertByEmail(input) {
    const record = Object.assign({email: input.email, name: input.name || ''}, this.byEmail.get(input.email) || {}, input);
    this.byEmail.set(input.email, record);
    this.upserts.push(record);
    return record;
  }
}

class FakeAttachmentStore {
  constructor(fail) {
    this.fail = Boolean(fail);
    this.calls = [];
  }
  save(ticketId, messageId, attachments) {
    if (this.fail) throw new Error('Drive unavailable');
    this.calls.push({ticketId, messageId, attachments});
    return {
      folderId: attachments.length ? 'folder-' + ticketId : '',
      count: attachments.length
    };
  }
}

function message(id, from, date, attachmentCount) {
  return {
    id,
    from,
    to: from.includes('customer') ? 'support@pocketpiano.com' : 'customer@example.com',
    cc: '',
    subject: 'Keyboard support',
    date: new Date(date),
    plainBody: '  Support message  ' + id,
    attachments: Array.from({length: attachmentCount || 0}, (_, index) => ({
      name: 'photo-' + index + '.jpg',
      blob: {}
    }))
  };
}

function build(options) {
  const gateway = new FakeGmailGateway(options.threads);
  const tickets = new FakeTicketRepository(options.ticket);
  const messages = new FakeMessageRepository(options.messageIds);
  const attachments = new FakeAttachmentStore(options.failAttachments);
  const customers = new FakeCustomerRepository();
  let id = 0;
  const engine = new GmailSyncEngine({
    gmailGateway: gateway,
    ticketRepository: tickets,
    messageRepository: messages,
    customerRepository: customers,
    attachmentStore: attachments,
    settings: {
      get(key, fallback) {
        const values = {
          SUPPORT_EMAIL: 'support@pocketpiano.com',
          SUPPORT_GMAIL_QUERY: 'in:anywhere newer_than:30d',
          GMAIL_SYNC_LIMIT: '100',
          SUPPORT_LABEL: 'PocketPiano/Processed'
        };
        return Object.prototype.hasOwnProperty.call(values, key) ? values[key] : fallback;
      }
    },
    ticketIdGenerator: () => 'id-' + (++id),
    messageIdGenerator: () => 'id-' + (++id),
    clock: () => new Date('2026-06-30T16:00:00Z'),
    logger: {info() {}, error() {}},
    version: '1.1.0'
  });
  return {engine, gateway, tickets, messages, attachments, customers};
}

function testCreatesTicketConversationAndAttachments() {
  const fixture = build({
    threads: [{
      id: 'thread-1',
      messages: [
        message('message-1', 'Customer <customer@example.com>', '2026-06-30T10:00:00Z', 1),
        message('message-2', 'Support <support@pocketpiano.com>', '2026-06-30T11:00:00Z', 0)
      ]
    }]
  });
  const result = fixture.engine.synchronize();
  assert.equal(result.createdTickets, 1);
  assert.equal(result.createdMessages, 2);
  assert.equal(result.attachments, 1);
  assert.equal(fixture.tickets.ticket.threadId, 'thread-1');
  assert.equal(fixture.tickets.ticket.customerEmail, 'customer@example.com');
  assert.deepEqual(fixture.messages.created.map(item => item.gmailMessageId), ['message-1', 'message-2']);
  assert.equal(fixture.messages.created[0].direction, 'INBOUND');
  assert.equal(fixture.messages.created[1].direction, 'OUTBOUND');
  assert.equal(fixture.gateway.marked.length, 1);
}

function testUpdatesExistingThreadAndPreventsDuplicates() {
  const existing = {
    id: 'ticket-1',
    threadId: 'thread-1',
    status: 'RESOLVED',
    subject: 'Keyboard support',
    customerEmail: 'customer@example.com',
    driveFolderId: 'folder-ticket-1'
  };
  const fixture = build({
    ticket: existing,
    messageIds: ['message-1'],
    threads: [{
      id: 'thread-1',
      messages: [
        message('message-1', 'Support <support@pocketpiano.com>', '2026-06-30T10:00:00Z', 0),
        message('message-2', 'Customer <customer@example.com>', '2026-06-30T12:00:00Z', 1)
      ]
    }]
  });
  const first = fixture.engine.synchronize();
  assert.equal(first.createdTickets, 0);
  assert.equal(first.createdMessages, 1);
  assert.equal(first.duplicateMessages, 1);
  assert.equal(existing.status, 'OPEN');
  assert.equal(fixture.attachments.calls.length, 1);

  const second = fixture.engine.synchronize();
  assert.equal(second.createdMessages, 0);
  assert.equal(second.duplicateMessages, 2);
  assert.equal(fixture.attachments.calls.length, 1, 'duplicates must not store attachments again');
}

function testFailedThreadIsNotMarkedProcessed() {
  const fixture = build({
    failAttachments: true,
    threads: [{
      id: 'thread-failure',
      messages: [message('message-failure', 'customer@example.com', '2026-06-30T10:00:00Z', 1)]
    }]
  });
  const result = fixture.engine.synchronize();
  assert.equal(result.failedThreads, 1);
  assert.equal(fixture.gateway.marked.length, 0);
}

[
  testCreatesTicketConversationAndAttachments,
  testUpdatesExistingThreadAndPreventsDuplicates,
  testFailedThreadIsNotMarkedProcessed
].forEach(test => test());

console.log('Gmail synchronization tests passed.');