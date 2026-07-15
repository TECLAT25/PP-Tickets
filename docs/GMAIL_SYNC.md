# Gmail synchronization

## Mailbox

Synchronization is restricted to `support@pocketpiano.com` by default. The effective Google Workspace account must own that mailbox or expose it through a Gmail alias. Change `SUPPORT_EMAIL` only when intentionally migrating the support address.

The default query processes up to 100 threads from the last 30 days. Both the query and limit are controlled by `SUPPORT_GMAIL_QUERY` and `GMAIL_SYNC_LIMIT` in the Settings sheet.

## Behavior

`syncGmail()` performs one bounded, lock-protected pass:

1. Gmail threads are normalized through the gateway.
2. Tickets are matched by immutable Gmail Thread ID.
3. Missing tickets are created.
4. Messages are matched by immutable Gmail Message ID and appended once.
5. Attachments are stored in a ticket-specific Drive folder using deterministic names.
6. Ticket conversation timestamps and status are updated.
7. The configured Gmail label is applied only after the full thread succeeds.

Resolved or closed tickets reopen when the latest message is inbound. A failed thread is logged and remains eligible for retry; other threads continue processing.

## Scheduling

Run `TriggerManager.ensureGmailSyncTrigger()` once to create a five-minute trigger. The operation is idempotent. `TriggerManager.removeManagedTriggers()` removes both synchronization and maintenance triggers without touching unrelated project triggers.

## Testing

Run `npm test` with Node.js. Tests use injected in-memory gateways, repositories, clocks, and attachment stores; they never access Gmail, Sheets, or Drive.
