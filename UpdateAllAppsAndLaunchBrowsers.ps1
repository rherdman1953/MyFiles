# ------------------------------------------------------------------
#   UpdateAllAppsAndLaunchBrowsers.ps1
#
#   1) Launches Firefox and Brave (if they exist)
#   2) Performs a winget update of all installed applications
# ------------------------------------------------------------------

function Start-IfExists {
    param (
        [string]$ExePath,
        [string]$DisplayName = $null
    )

    if (Test-Path -LiteralPath $ExePath) {
        Write-Host "Launching $DisplayName..."
        Start-Process -FilePath $ExePath
    } else {
        Write-Warning "$DisplayName not found at $ExePath"
    }
}

# 1️⃣ Launch browsers -------------------------------------------------
$firefoxPath = "$env:ProgramFiles\Mozilla Firefox\firefox.exe"
Start-IfExists -ExePath $firefoxPath -DisplayName "Firefox"

# Brave – updated location
$bravePath   = "C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe"
Start-IfExists -ExePath $bravePath -DisplayName "Brave"

# 2️⃣ Winget update ---------------------------------------------------
Write-Host "`nRunning winget upgrade --all ..."
Start-Process -FilePath winget.exe -ArgumentList 'upgrade', '--all' `
              -NoNewWindow -RedirectStandardOutput "$env:TEMP\winget_update.log" `
              -Wait

Write-Host "Winget update finished. Log written to $env:TEMP\winget_update.log"
