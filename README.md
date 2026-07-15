# PP Tickets

Production-oriented Google Apps Script foundation for PocketPiano support, customers, products, warranties, and operations across Google Workspace.

## Platform

- Google Apps Script V8
- Google Sheets persistence
- Gmail labels and read access
- Google Drive resource storage
- HTMLService spreadsheet and web UI

## Repository

- `src/` — application modules
- `html/` — HTMLService views
- `css/` — HTMLService style partials
- `docs/` — architecture and deployment guidance
- `appsscript.json` — runtime, scopes, and web app manifest

Run `install()` from a spreadsheet-bound Apps Script project. It creates and validates the complete workbook schema without deleting existing business data.

Open the responsive HTMLService interface from the spreadsheet menu or deploy it as a domain-restricted web application. It includes Dashboard, ticket, conversation, and customer views with light/dark themes.

Use the Ticket Manager server API for numbered tickets, lifecycle updates, SLA tracking, search, filters, and Dashboard metrics.

Run `syncGmail()` manually or install `TriggerManager.ensureGmailSyncTrigger()` to synchronize the configured support mailbox.

See [installation](docs/INSTALLATION.md), [Gmail synchronization](docs/GMAIL_SYNC.md), [Ticket Manager](docs/TICKET_MANAGER.md), [HTML interface](docs/UI.md), and [architecture](docs/ARCHITECTURE.md) for operational details.
