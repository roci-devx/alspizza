# Deploys the committed backend to server1 (the Ubuntu box on Tailscale).
#   .\backend\deploy.ps1        (PowerShell, from anywhere in the repo)
# Only what is committed gets deployed; uncommitted edits stay on this PC.
# On the server, app-deploy backs up the database, installs packages, updates the tables,
# builds, restarts the API and rolls back by itself if the new version doesn't come up.
# Needs the `server1` SSH alias and key in ~/.ssh (set up 2026-11-20). Server notes: /srv/README.md
$ErrorActionPreference = 'Stop'
Set-Location (git rev-parse --show-toplevel)
git diff --quiet HEAD -- backend
if ($LASTEXITCODE -ne 0) { Write-Warning 'backend/ has uncommitted changes - they will NOT be deployed (only the last commit is).' }
$sha = git rev-parse --short HEAD
Write-Host "Deploying backend @ $sha to server1..." -ForegroundColor Cyan
# cmd pipes raw bytes; a Windows PowerShell pipe would corrupt the archive.
cmd /c "git archive --format=tar HEAD:backend | ssh server1 sudo app-deploy alspizza $sha"
if ($LASTEXITCODE -ne 0) { throw "Deploy failed (exit $LASTEXITCODE). The previous version is still running." }
