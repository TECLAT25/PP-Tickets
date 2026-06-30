# Installation

## Prerequisites

- A Google Workspace account with access to Sheets, Gmail, and Drive.
- A spreadsheet that will own the ERP data.
- An Apps Script project bound to that spreadsheet.

## Deploy

1. Copy or push the repository source into the bound Apps Script project, preserving the manifest.
2. In Apps Script, select `install` and run it once.
3. Review and grant the explicit OAuth permissions.
4. Reload the spreadsheet and use the **PocketPiano ERP** menu.
5. If automated log retention is required, run `TriggerManager.ensureMaintenanceTrigger()` once.

The installer creates or validates these sheets:

- Dashboard
- Tickets
- Messages
- Customers
- Products
- Templates
- Settings
- Logs

Installation is safe to run again and does not delete business rows. If it reports `SHEET_SCHEMA_CONFLICT`, restore the expected header or deliver a versioned migration before retrying.

## Web application

Deploy the script as a web application after installation. Execute as the deploying user and restrict access to the intended Workspace domain. Organization policy controls the effective audience.
