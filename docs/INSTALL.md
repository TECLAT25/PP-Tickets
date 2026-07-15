# Installation guide

PP Tickets is a Google Apps Script application that runs inside Google Workspace.

## Requirements

- Google Workspace account for `support@pocketpiano.com` or an account that owns that alias.
- Google Sheet that will act as the workspace database.
- Gmail, Google Drive and Google Sheets permissions.
- Optional local tooling: Node.js and `@google/clasp`.

## Recommended setup with clasp

1. Clone the repository:

```bash
git clone https://github.com/TECLAT25/PP-Tickets.git
cd PP-Tickets
```

2. Install clasp:

```bash
npm install -g @google/clasp
clasp login
```

3. Create a Google Sheet for the workspace.

4. Open **Extensions → Apps Script** from that spreadsheet.

5. Copy the Apps Script project ID and create `.clasp.json` from the example:

```bash
cp .clasp.json.example .clasp.json
```

Edit `.clasp.json` and replace `PASTE_YOUR_GOOGLE_APPS_SCRIPT_ID_HERE` with the real script ID.

6. Push the project:

```bash
clasp push
```

7. In Apps Script, run:

```javascript
install()
```

8. Authorize the requested Google permissions.

## What install() creates

- Sheets: Dashboard, Tickets, Messages, Customers, Products, Templates, Settings and Logs.
- Drive root folder for PP Tickets.
- Gmail label for processed support conversations.
- Background triggers for Gmail synchronization and maintenance.

## First run checklist

- Confirm `SUPPORT_EMAIL` is `support@pocketpiano.com` in the Settings sheet.
- Confirm the script runs under the support mailbox or an account that owns it as an alias.
- Use the spreadsheet menu: **PP Tickets → Open application**.
- Press **Sync Gmail** once from the UI to validate access.

## Safety

The system creates Gmail drafts but does not send them automatically.
