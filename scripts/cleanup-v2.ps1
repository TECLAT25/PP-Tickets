param(
  [switch]$SkipBackup
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

Write-Host ''
Write-Host 'PP Tickets v2 cleanup' -ForegroundColor Cyan
Write-Host 'Repository:' $Root
Write-Host ''

if (-not (Test-Path '.clasp.json')) {
  if (Test-Path '.clasp.json.example') {
    Copy-Item '.clasp.json.example' '.clasp.json'
    Write-Host '[OK] Created .clasp.json from example.' -ForegroundColor Green
  } else {
    throw '.clasp.json is missing and .clasp.json.example was not found.'
  }
}

if (-not $SkipBackup) {
  $Backup = Join-Path (Split-Path -Parent $Root) ('PP-Tickets-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
  New-Item -ItemType Directory -Path $Backup | Out-Null
  robocopy $Root $Backup /E /XD .git node_modules PP-Tickets /XF package-lock.json | Out-Null
  Write-Host '[OK] Backup created:' $Backup -ForegroundColor Green
}

if (Test-Path '.\PP-Tickets') {
  Remove-Item '.\PP-Tickets' -Recurse -Force
  Write-Host '[OK] Removed duplicated PP-Tickets folder.' -ForegroundColor Green
}

if (Test-Path '.\src') {
  Get-ChildItem '.\src' -Filter '*.gs' | ForEach-Object {
    $Target = $_.FullName -replace '\.gs$', '.js'
    Copy-Item $_.FullName $Target -Force
  }
  Write-Host '[OK] Normalized src/*.gs into src/*.js.' -ForegroundColor Green
}

@'
**/*.gs
PP-Tickets/**
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
scripts/**
'@ | Set-Content '.claspignore' -Encoding UTF8
Write-Host '[OK] Wrote clean .claspignore.' -ForegroundColor Green

Write-Host ''
Write-Host 'Next:' -ForegroundColor Cyan
Write-Host '  clasp status'
Write-Host '  clasp push --force'
Write-Host ''
