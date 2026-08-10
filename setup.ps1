$ErrorActionPreference = "Stop"

function Ensure-WingetPackage($Id, $Command) {
  if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
      throw "winget is required on native Windows. Install App Installer, then rerun."
    }
    winget install --exact --id $Id --accept-package-agreements --accept-source-agreements
  }
}

Ensure-WingetPackage "Git.Git" "git"
Ensure-WingetPackage "GoLang.Go" "go"

$bash = (Get-Command bash -ErrorAction SilentlyContinue).Source
if (-not $bash) {
  $bash = "$env:ProgramFiles\Git\bin\bash.exe"
}
if (-not (Test-Path $bash)) {
  throw "Git Bash was installed but bash.exe was not found. Restart PowerShell and rerun."
}

& $bash "$PSScriptRoot/setup" --no-bootstrap @args
exit $LASTEXITCODE
