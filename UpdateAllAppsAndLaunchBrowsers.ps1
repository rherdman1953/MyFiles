# ------------------------------------------------------------------
#   UpdateAllAppsAndLaunchBrowsers.ps1
#
#   1) Checks if Firefox / Brave are already running; launches them
#      only if they’re not.
#   2) Performs a winget update of all installed applications.
# ------------------------------------------------------------------

function Start-IfNotRunning {
    param (
        [string]$ExePath,
        [string]$DisplayName = $null
    )

    # Determine the process name (e.g., firefox.exe)
    $procName = Split-Path -Leaf $ExePath

    # Look for an existing instance
    $running = Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($procName)) `
                            -ErrorAction SilentlyContinue

    if ($null -ne $running) {
        Write-Host "$DisplayName is already running (PID: $($running.Id)). Skipping launch."
    }
    else {
        Write-Host "Launching $DisplayName..."
        Start-Process -FilePath $ExePath
    }
}

# 1️⃣ Launch browsers only if they’re not running --------------------
$firefoxPath = "$env:ProgramFiles\Mozilla Firefox\firefox.exe"
Start-IfNotRunning -ExePath $firefoxPath -DisplayName "Firefox"

$bravePath   = "C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe"
Start-IfNotRunning -ExePath $bravePath -DisplayName "Brave"

# 2️⃣ Winget update ---------------------------------------------------
Write-Host "`nRunning winget upgrade --all ..."
Start-Process -FilePath winget.exe `
              -ArgumentList 'upgrade', '--all' `
              -NoNewWindow `
              -RedirectStandardOutput "$env:TEMP\winget_update.log" `
              -Wait

Write-Host "Winget update finished. Log written to $env:TEMP\winget_update.log"
