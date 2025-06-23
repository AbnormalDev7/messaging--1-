param (
    [Parameter(Mandatory = $true)][string]$ServiceName,
    [Parameter(Mandatory = $true)][string]$TempPath,
    [Parameter(Mandatory = $true)][string]$AppPath
)

$nssmPath = "C:\projects\nssm.exe"

function Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
}

function Validate-Path {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        throw "[ERROR] Path does not exist: $Path"
    }
}

function Get-ServiceState {
    param([string]$Service)
    $output = sc.exe query $Service 2>&1
    if ($output -match "FAILED 1060") {
        throw "[ERROR] Service '$Service' does not exist."
    }

    $match = [regex]::Match($output, "STATE\s*:\s*\d+\s+(\w+)")
    if ($match.Success) {
        return $match.Groups[1].Value.ToUpper()
    }

    throw "[ERROR] Unable to determine state of service '$Service'"
}

function Stop-ServiceWithNssm {
  param([string]$Service)

  $state = Get-ServiceState $Service
  if ($state -ne "RUNNING") {
    Log "Service '$Service' is not running. Skipping stop."
    return
  }

  Log "Stopping service: $Service"
  & $nssmPath stop $Service | Out-Null

  for ($i = 0; $i -lt 5; $i++) {
    Start-Sleep -Seconds 20
    $state = Get-ServiceState -Service $Service
    if ($state -eq "STOPPED") {
      Log "Service '$Service' stopped."
      return
    }
  }

  throw "Service '$Service' did not stop in time."
}

function Start-ServiceWithNssm {
  param([string]$Service)

  Log "Starting service: $Service"
  & $nssmPath start $Service | Out-Null

  for ($i = 0; $i -lt 5; $i++) {
    Start-Sleep -Seconds 20
    $state = Get-ServiceState $Service
    if ($state -eq "RUNNING") {
      Log "Service '$Service' is now running."
      return
    }
  }

  throw "Service '$Service' failed to start in time."
}

try {
    Log "Starting deployment for service: $ServiceName"

    Validate-Path $nssmPath
    Validate-Path $TempPath

    Stop-ServiceWithNssm -Service $ServiceName

    Log "Deploying files to: $AppPath"
    if (-not (Test-Path $AppPath)) {
        New-Item -ItemType Directory -Path $AppPath -Force | Out-Null
    }
    Copy-Item -Path "$TempPath\*" -Destination $AppPath -Recurse -Force

    Start-ServiceWithNssm -Service $ServiceName

    Log "Deployment completed successfully." "SUCCESS"
    exit 0
}
catch {
    Log $_.Exception.Message "ERROR"
    exit 1
}
