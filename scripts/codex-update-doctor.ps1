[CmdletBinding()]
param(
  [switch]$Doctor,
  [switch]$Status,
  [switch]$AppStatus,
  [switch]$CliStatus,
  [switch]$AppServerStatus,
  [switch]$Check,
  [switch]$Install
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Section {
  param([string]$Name)
  Write-Output ""
  Write-Output "== $Name =="
}

function Get-CodexCli {
  Get-Command codex -ErrorAction SilentlyContinue
}

function Get-Winget {
  Get-Command winget -ErrorAction SilentlyContinue
}

function Test-CodexCliUpdate {
  $codex = Get-CodexCli
  if (-not $codex) {
    return $false
  }
  try {
    & $codex.Source update --help *> $null
    return ($LASTEXITCODE -eq 0)
  } catch {
    return $false
  }
}

function Show-CliStatus {
  Write-Section "Codex CLI"
  $codex = Get-CodexCli
  if (-not $codex) {
    Write-Output "status: not found on PATH"
    Write-Output "update: unavailable until Codex CLI is installed"
    return
  }

  Write-Output "path: $($codex.Source)"
  try {
    $version = & $codex.Source --version 2>&1
    Write-Output "version: $version"
  } catch {
    Write-Output "version: unavailable ($($_.Exception.Message))"
  }

  if (Test-CodexCliUpdate) {
    Write-Output "self-update: codex update is available"
  } else {
    Write-Output "self-update: codex update is not available for this install"
  }
}

function Get-WingetCodexPackage {
  $winget = Get-Winget
  if (-not $winget) {
    return $null
  }

  $packages = & $winget.Source list --name Codex --source msstore 2>$null
  if ($LASTEXITCODE -ne 0) {
    return $null
  }
  return ($packages | Where-Object { $_ -match "Codex" } | Select-Object -First 1)
}

function Show-AppStatus {
  Write-Section "Codex Windows App"
  $package = Get-AppxPackage -Name "*Codex*" -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match "Codex|OpenAI" -or $_.PackageFullName -match "Codex|OpenAI" } |
    Select-Object -First 1

  if ($package) {
    Write-Output "appx-name: $($package.Name)"
    Write-Output "package: $($package.PackageFullName)"
    Write-Output "version: $($package.Version)"
    Write-Output "install-location: $($package.InstallLocation)"
  } else {
    Write-Output "appx-status: no Codex-like Appx package found"
  }

  $wingetPackage = Get-WingetCodexPackage
  if ($wingetPackage) {
    Write-Output "winget-msstore: $wingetPackage"
  } else {
    Write-Output "winget-msstore: no Codex package found or winget unavailable"
  }
}

function Show-AppServerStatus {
  Write-Section "Codex app-server"
  $matches = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match "codex app-server" }

  if (-not $matches) {
    Write-Output "status: no codex app-server process found"
    return
  }

  foreach ($process in $matches) {
    Write-Output "process: pid=$($process.ProcessId) $($process.CommandLine)"
  }
}

function Show-Check {
  Write-Section "Update Check"
  $winget = Get-Winget
  if ($winget) {
    Write-Output "Windows app: winget is available; use Microsoft Store source for Codex app updates after verifying package identity."
  } else {
    Write-Output "Windows app: winget not found; use Microsoft Store app updates."
  }

  if (Test-CodexCliUpdate) {
    Write-Output "CLI: codex update command is available"
  } elseif (Get-CodexCli) {
    Write-Output "CLI: codex update command is not available for this install"
  } else {
    Write-Output "CLI: codex not found on PATH"
  }
}

function Invoke-Install {
  if (Test-CodexCliUpdate) {
    if ($env:CODEX_UPDATE_ALLOW_APPLY -ne "1") {
      throw "Set CODEX_UPDATE_ALLOW_APPLY=1 to run codex update on Windows."
    }
    $codex = Get-CodexCli
    & $codex.Source update
    exit $LASTEXITCODE
  }

  $winget = Get-Winget
  if ($winget) {
    throw "Refusing automatic winget upgrade until the exact Codex package id is verified on a real Windows host. Run --Check for guidance."
  }

  throw "No safe automatic Codex update path detected on this Windows host."
}

function Show-Doctor {
  Write-Section "System"
  Write-Output "os: Windows"
  Write-Output "powershell: $($PSVersionTable.PSVersion)"
  Show-AppStatus
  Show-CliStatus
  Show-AppServerStatus
  Show-Check
}

$selected = @($Doctor, $Status, $AppStatus, $CliStatus, $AppServerStatus, $Check, $Install) |
  Where-Object { $_ }
if ($selected.Count -eq 0) {
  $Doctor = $true
}

if ($Install) {
  Invoke-Install
} elseif ($AppStatus) {
  Show-AppStatus
} elseif ($CliStatus) {
  Show-CliStatus
} elseif ($AppServerStatus) {
  Show-AppServerStatus
} elseif ($Check) {
  Show-Check
} else {
  Show-Doctor
}
