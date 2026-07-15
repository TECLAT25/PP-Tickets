# HTML interface

The HTMLService application is available both as a spreadsheet sidebar and as a domain-restricted web application.

## Views

- Dashboard with total, active, breached-SLA, and critical-priority metrics.
- Searchable and filterable ticket list.
- Ticket detail with status, priority, category, assignment, SLA, and tags.
- Chronological conversation viewer with attachment counts.
- Customer profile resolved by Customer ID or email.

All displayed business values are assigned through DOM `textContent`; server data is never injected as HTML. Server dates are converted to ISO strings before crossing the `google.script.run` boundary.

## Responsive behavior

The desktop layout uses a persistent Material-style navigation rail and a two-column ticket workspace. Narrow web views and the Google Sheets sidebar collapse navigation into a compact top row, stack the detail panel, simplify table columns, and reduce metric cards to one column where necessary.

## Dark mode

Color, elevation, shape, and state styles use design tokens. The interface follows the operating-system theme by default and offers a persistent light/dark toggle stored in local storage.

## Deployment

Run `install()` after deploying this release to append the Messages `Body Text` column. Newly synchronized messages retain conversation text up to 40,000 characters; older rows fall back to their existing body preview.
