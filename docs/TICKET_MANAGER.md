# Ticket Manager

## Ticket lifecycle

Ticket IDs use the immutable format `PP-YYYY-NNNNNN`. The prefix is configured with `TICKET_NUMBER_PREFIX`; yearly counters are stored in Script Properties and reconciled against existing ticket IDs if a counter is missing.

Supported statuses:

- `NEW`
- `OPEN`
- `PENDING_CUSTOMER`
- `RESOLVED`
- `CLOSED`

Priorities are `LOW`, `NORMAL`, `HIGH`, and `CRITICAL`. Categories are `GENERAL`, `TECHNICAL`, `WARRANTY`, `SHIPPING`, `BILLING`, `PRODUCT`, and `OTHER`.

## SLA

Each priority has a configurable response target in the Settings sheet:

- `SLA_LOW_HOURS`
- `SLA_NORMAL_HOURS`
- `SLA_HIGH_HOURS`
- `SLA_CRITICAL_HOURS`

Changing a ticket priority recalculates its SLA deadline from the original creation time. Resolved and closed tickets are excluded from breach counts.

## Server API

- `createTicket(input)`
- `updateTicketStatus(ticketId, status)`
- `updateTicketPriority(ticketId, priority)`
- `updateTicketCategory(ticketId, category)`
- `searchTickets(criteria)`
- `getTicketFilters()`
- `refreshTicketDashboard()`

Search supports free text, status, priority, category, assignee, customer email, created-date range, SLA breach, offset, and limit. Results are ordered by most recently updated.

Run `install()` after deploying this release to append the Category column and seed the new SLA and numbering settings.
