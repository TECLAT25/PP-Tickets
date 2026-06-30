# Architecture

PocketPiano ERP is a spreadsheet-bound Google Apps Script application using the V8 runtime.

## Modules

- `constants.gs`: immutable names, settings, and append-only sheet schemas.
- `config.gs`: Script Properties, cached settings, and resource lookup.
- `install.gs`: idempotent schema installation and Workspace resource provisioning.
- `menu.gs`: spreadsheet UI, HTMLService endpoints, and client bootstrap data.
- `triggers.gs`: managed trigger lifecycle and bounded maintenance jobs.
- `utils.gs`: domain errors, safe serialization, structured logging, and HTML helpers.
- `version.gs`: semantic application version.
- `gmail.gs`: injected synchronization engine and Apps Script Gmail gateway.
- `repositories.gs`: header-aware Sheets repositories, ticket search, and idempotent Drive attachment storage.
- `tickets.gs`: numbering, lifecycle policy, SLA calculations, search API, and dashboard metrics.
- `html/` and `css/`: HTMLService application shell and styles.

## Persistence

Business records are stored in the bound spreadsheet. Stable resource identifiers and the installed version are stored in Script Properties. Settings are read from the `Settings` sheet and cached for five minutes. Attachments belong in the application Drive folder created during installation.

The installer is non-destructive and idempotent. It creates missing sheets and columns but fails on conflicting populated headers to prevent silent data corruption. Schema changes must be append-only or delivered through an explicit migration.

## Reliability and security

- Script locks prevent concurrent installations and maintenance jobs.
- Operational logs are written to Cloud Logging and the `Logs` sheet.
- Client errors expose a correlation ID while server logs retain diagnostic context.
- OAuth scopes are explicit in `appsscript.json`.
- HTML values are escaped before templated rendering.
- Managed triggers are identified by handler name and never modify unrelated triggers.
- Gmail synchronization runs under a script lock, stores immutable Gmail IDs, and labels a thread only after successful persistence.
- Attachment filenames include the Gmail message ID and ordinal, making retries idempotent.

## Versioning

Ticket IDs use a lock-protected yearly sequence. Domain services receive repositories, clocks, policies, loggers, and number generators through their constructors, keeping lifecycle behavior independent of Apps Script services.

The application follows Semantic Versioning. Update `APP.VERSION` for every release. Store schema migrations alongside the release that introduces them; never repurpose an existing sheet column.
