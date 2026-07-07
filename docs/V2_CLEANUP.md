# PocketPiano ERP v2 cleanup

This procedure cleans the local Windows repository before deploying to Google Apps Script.

## Goal

Keep only the files that Google Apps Script needs:

- `appsscript.json`
- `css/*.html`
- `html/*.html`
- `src/*.js`

Do not push tests, documentation, npm files or duplicated nested folders to Apps Script.

## One-time cleanup in PowerShell

Run from the repository root:

```powershell
cd C:\Users\jl\documents\pocketpiano-erp
```

### 1. Convert current `.gs` sources to `.js`

```powershell
Get-ChildItem .\src -Filter *.gs | ForEach-Object {
  Copy-Item $_.FullName ($_.FullName -replace '\.gs$', '.js') -Force
}
```

### 2. Remove duplicated nested folder if it exists

```powershell
if (Test-Path .\PocketPiano-ERP) {
  Remove-Item .\PocketPiano-ERP -Recurse -Force
}
```

### 3. Clean `.claspignore`

```powershell
@"
**/*.gs
PocketPiano-ERP/**
tests/**
node_modules/**
.git/**
.gitignore
.clasprc.json
README.md
docs/**
package.json
package-lock.json
deploy.bat
"@ | Set-Content .claspignore
```

### 4. Verify files that will be pushed

```powershell
clasp status
```

Expected pushed files should be only:

- `appsscript.json`
- files under `css/`
- files under `html/`
- files under `src/` as `.js`

### 5. Push

```powershell
clasp push --force
```

### 6. Apps Script

Open Apps Script and run:

```javascript
install()
```

Reload the Google Sheet and open:

```text
PocketPiano ERP -> Open application
```
