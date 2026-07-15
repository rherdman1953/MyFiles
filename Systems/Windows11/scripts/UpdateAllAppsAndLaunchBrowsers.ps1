# =============================================================================
# UpdateAllAppsAndLaunchBrowsers.ps1
#
# Version : 1.3
# Date    : 2026-07-15
#
# Purpose:
#   - Optionally start Vivaldi, Firefox, and Discord when they are not running.
#   - Update installed applications through the Winget repository.
#   - Write activity to a rotating log file in C:\apps.
#
# Recommended Task Scheduler settings:
#   Trigger:
#     At log on
#
#   Security option:
#     Run only when user is logged on
#
#   Program:
#     powershell.exe
#
#   Arguments:
#     -NoProfile -ExecutionPolicy Bypass -File "C:\apps\UpdateAllAppsAndLaunchBrowsers.ps1"
# =============================================================================

[CmdletBinding()]
param(
    [int]$WingetMaxWaitSeconds = 120,

    # This command-line switch overrides the $RunWinget flag below.
    [switch]$SkipWinget
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# =============================================================================
# Configuration flags
#
# Set each value to $true to enable it or $false to disable it.
# =============================================================================

$StartVivaldi = $true
$StartFirefox = $true
$StartDiscord = $true
$RunWinget    = $true

# =============================================================================
# Application configuration
# =============================================================================

$VivaldiAppId = "Vivaldi.KWE5PORE7EELRD3UFCBIASRRVM"

$FirefoxPaths = @(
    "$env:ProgramFiles\Mozilla Firefox\firefox.exe",
    "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe",
    "$env:LocalAppData\Mozilla Firefox\firefox.exe"
)

$DiscordUpdaterPaths = @(
    "$env:LocalAppData\Discord\Update.exe",
    "$env:LocalAppData\Discord\app-*\Discord.exe"
)

# =============================================================================
# Log configuration
# =============================================================================

$LogDirectory = "C:\apps"
$LogFile      = Join-Path $LogDirectory "UpdateAllAppsAndLaunchBrowsers.log"

$MaximumLogSizeBytes = 2MB
$MaximumLogBackups   = 5

# =============================================================================
# Logging functions
# =============================================================================

function Initialize-LogDirectory {
    if (-not (Test-Path -LiteralPath $LogDirectory)) {
        New-Item `
            -ItemType Directory `
            -Path $LogDirectory `
            -Force | Out-Null
    }
}

function Rotate-Log {
    if (-not (Test-Path -LiteralPath $LogFile)) {
        return
    }

    try {
        $logLength = (Get-Item -LiteralPath $LogFile -ErrorAction Stop).Length

        if ($logLength -lt $MaximumLogSizeBytes) {
            return
        }

        $oldestBackup = "$LogFile.$MaximumLogBackups"

        if (Test-Path -LiteralPath $oldestBackup) {
            Remove-Item `
                -LiteralPath $oldestBackup `
                -Force `
                -ErrorAction SilentlyContinue
        }

        for ($index = $MaximumLogBackups - 1; $index -ge 1; $index--) {
            $sourceBackup      = "$LogFile.$index"
            $destinationBackup = "$LogFile." + ($index + 1)

            if (Test-Path -LiteralPath $sourceBackup) {
                Move-Item `
                    -LiteralPath $sourceBackup `
                    -Destination $destinationBackup `
                    -Force `
                    -ErrorAction SilentlyContinue
            }
        }

        Move-Item `
            -LiteralPath $LogFile `
            -Destination "$LogFile.1" `
            -Force `
            -ErrorAction SilentlyContinue
    }
    catch {
        # Logging may not be available yet, so do not call Write-Log here.
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp  [$Level]  $Message"

    $entry | Out-File `
        -FilePath $LogFile `
        -Append `
        -Encoding UTF8
}

# =============================================================================
# Process functions
# =============================================================================

function Test-ProcessRunning {
    param(
        [Parameter(Mandatory)]
        [string]$ProcessName
    )

    return [bool](
        Get-Process `
            -Name $ProcessName `
            -ErrorAction SilentlyContinue
    )
}

function Test-ProcessRunningLike {
    param(
        [Parameter(Mandatory)]
        [string]$NamePattern
    )

    return [bool](
        Get-Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.ProcessName -like $NamePattern
            } |
            Select-Object -First 1
    )
}

# =============================================================================
# Generic application launcher
# =============================================================================

function Start-AppIfNotRunning {
    param(
        [Parameter(Mandatory)]
        [string]$DisplayName,

        [Parameter(Mandatory)]
        [string]$ProcessName,

        [Parameter(Mandatory)]
        [string[]]$CandidatePaths,

        [string[]]$Arguments
    )

    if (Test-ProcessRunning -ProcessName $ProcessName) {
        Write-Log "$DisplayName is already running."
        return $true
    }

    Write-Log "$DisplayName is not running. Attempting to start it."

    foreach ($candidatePath in $CandidatePaths) {
        if ([string]::IsNullOrWhiteSpace($candidatePath)) {
            continue
        }

        if (-not (Test-Path -LiteralPath $candidatePath)) {
            continue
        }

        try {
            Write-Log "Starting $DisplayName using: $candidatePath"

            if ($Arguments -and $Arguments.Count -gt 0) {
                Start-Process `
                    -FilePath $candidatePath `
                    -ArgumentList $Arguments | Out-Null
            }
            else {
                Start-Process `
                    -FilePath $candidatePath | Out-Null
            }

            Start-Sleep -Seconds 3

            if (Test-ProcessRunning -ProcessName $ProcessName) {
                Write-Log "$DisplayName started successfully."
                return $true
            }

            Write-Log `
                "$DisplayName launch was attempted, but its process was not detected." `
                -Level 'WARNING'
        }
        catch {
            Write-Log `
                "Failed to start $DisplayName from '$candidatePath': $($_.Exception.Message)" `
                -Level 'WARNING'
        }
    }

    try {
        Write-Log "Attempting to start $DisplayName through PATH using: $ProcessName"

        if ($Arguments -and $Arguments.Count -gt 0) {
            Start-Process `
                -FilePath $ProcessName `
                -ArgumentList $Arguments | Out-Null
        }
        else {
            Start-Process `
                -FilePath $ProcessName | Out-Null
        }

        Start-Sleep -Seconds 3

        if (Test-ProcessRunning -ProcessName $ProcessName) {
            Write-Log "$DisplayName started successfully through PATH."
            return $true
        }
    }
    catch {
        Write-Log `
            "Could not start $DisplayName through PATH: $($_.Exception.Message)" `
            -Level 'WARNING'
    }

    Write-Log "Unable to start $DisplayName." -Level 'ERROR'
    return $false
}

# =============================================================================
# Vivaldi launcher
# =============================================================================

function Start-VivaldiIfNotRunning {
    if (Test-ProcessRunningLike -NamePattern "vivaldi*") {
        Write-Log "Vivaldi is already running."
        return $true
    }

    Write-Log "Vivaldi is not running. Attempting Microsoft Store launch."

    try {
        $shellTarget = "shell:AppsFolder\$VivaldiAppId"

        Write-Log "Starting Vivaldi using AppID: $VivaldiAppId"

        Start-Process `
            -FilePath "explorer.exe" `
            -ArgumentList $shellTarget | Out-Null

        Start-Sleep -Seconds 5

        if (Test-ProcessRunningLike -NamePattern "vivaldi*") {
            Write-Log "Vivaldi started successfully through its Store AppID."
            return $true
        }

        Write-Log `
            "Vivaldi Store launch was attempted, but its process was not detected." `
            -Level 'WARNING'
    }
    catch {
        Write-Log `
            "Vivaldi Store launch failed: $($_.Exception.Message)" `
            -Level 'WARNING'
    }

    $vivaldiFallbackPaths = @(
        "$env:LocalAppData\Vivaldi\Application\vivaldi.exe",
        "$env:ProgramFiles\Vivaldi\Application\vivaldi.exe",
        "${env:ProgramFiles(x86)}\Vivaldi\Application\vivaldi.exe"
    )

    foreach ($vivaldiPath in $vivaldiFallbackPaths) {
        if (-not (Test-Path -LiteralPath $vivaldiPath)) {
            continue
        }

        try {
            Write-Log "Starting Vivaldi using executable fallback: $vivaldiPath"

            Start-Process `
                -FilePath $vivaldiPath `
                -ArgumentList "--no-first-run" | Out-Null

            Start-Sleep -Seconds 5

            if (Test-ProcessRunningLike -NamePattern "vivaldi*") {
                Write-Log "Vivaldi started successfully using the executable fallback."
                return $true
            }
        }
        catch {
            Write-Log `
                "Vivaldi executable fallback failed from '$vivaldiPath': $($_.Exception.Message)" `
                -Level 'WARNING'
        }
    }

    Write-Log "Unable to start Vivaldi." -Level 'ERROR'
    return $false
}

# =============================================================================
# Discord launcher
# =============================================================================

function Start-DiscordIfNotRunning {
    if (Test-ProcessRunning -ProcessName "Discord") {
        Write-Log "Discord is already running."
        return $true
    }

    Write-Log "Discord is not running. Attempting to start it."

    $discordUpdater = "$env:LocalAppData\Discord\Update.exe"

    if (Test-Path -LiteralPath $discordUpdater) {
        try {
            Write-Log "Starting Discord through Update.exe."

            Start-Process `
                -FilePath $discordUpdater `
                -ArgumentList "--processStart Discord.exe" | Out-Null

            Start-Sleep -Seconds 5

            if (Test-ProcessRunning -ProcessName "Discord") {
                Write-Log "Discord started successfully."
                return $true
            }

            Write-Log `
                "Discord launch was attempted through Update.exe, but its process was not detected." `
                -Level 'WARNING'
        }
        catch {
            Write-Log `
                "Discord Update.exe launch failed: $($_.Exception.Message)" `
                -Level 'WARNING'
        }
    }
    else {
        Write-Log `
            "Discord Update.exe was not found at: $discordUpdater" `
            -Level 'WARNING'
    }

    $discordExecutables = @(
        Get-ChildItem `
            -Path "$env:LocalAppData\Discord\app-*\Discord.exe" `
            -File `
            -ErrorAction SilentlyContinue |
            Sort-Object -Property FullName -Descending
    )

    foreach ($discordExecutable in $discordExecutables) {
        try {
            Write-Log "Starting Discord using executable: $($discordExecutable.FullName)"

            Start-Process `
                -FilePath $discordExecutable.FullName | Out-Null

            Start-Sleep -Seconds 5

            if (Test-ProcessRunning -ProcessName "Discord") {
                Write-Log "Discord started successfully using its executable."
                return $true
            }
        }
        catch {
            Write-Log `
                "Discord executable launch failed from '$($discordExecutable.FullName)': $($_.Exception.Message)" `
                -Level 'WARNING'
        }
    }

    try {
        Write-Log "Attempting to start Discord through PATH."

        Start-Process -FilePath "Discord" | Out-Null
        Start-Sleep -Seconds 5

        if (Test-ProcessRunning -ProcessName "Discord") {
            Write-Log "Discord started successfully through PATH."
            return $true
        }
    }
    catch {
        Write-Log `
            "Discord PATH launch failed: $($_.Exception.Message)" `
            -Level 'WARNING'
    }

    Write-Log "Unable to start Discord." -Level 'ERROR'
    return $false
}

# =============================================================================
# Winget functions
# =============================================================================

function Get-WingetPath {
    $wingetCommand = Get-Command `
        -Name "winget.exe" `
        -ErrorAction SilentlyContinue

    if ($wingetCommand) {
        return $wingetCommand.Source
    }

    $fallbackPath = Join-Path `
        $env:LocalAppData `
        "Microsoft\WindowsApps\winget.exe"

    if (Test-Path -LiteralPath $fallbackPath) {
        return $fallbackPath
    }

    return $null
}

function Get-CleanWingetOutput {
    param(
        [AllowNull()]
        [string]$Output
    )

    if ([string]::IsNullOrWhiteSpace($Output)) {
        return ""
    }

    $cleanLines = foreach ($line in ($Output -split "`r?`n")) {
        $trimmedLine = $line.TrimEnd()

        if ([string]::IsNullOrWhiteSpace($trimmedLine)) {
            continue
        }

        # Remove lines that contain only Winget progress-bar characters.
        if ($trimmedLine -match '^[\s\\/\-\|█▒░]+(\d+%)?$') {
            continue
        }

        $trimmedLine
    }

    return ($cleanLines -join [Environment]::NewLine).Trim()
}

function Invoke-WingetUpdates {
    if ($SkipWinget) {
        Write-Log "Winget updates were skipped by the -SkipWinget command-line switch."
        return
    }

    if (-not $RunWinget) {
        Write-Log "Winget updates are disabled by the RunWinget configuration flag."
        return
    }

    $wingetPath = $null
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    while (
        -not $wingetPath -and
        $stopwatch.Elapsed.TotalSeconds -lt $WingetMaxWaitSeconds
    ) {
        $wingetPath = Get-WingetPath

        if (-not $wingetPath) {
            Start-Sleep -Seconds 3
        }
    }

    $stopwatch.Stop()

    if (-not $wingetPath) {
        Write-Log `
            "Winget was not found after waiting $WingetMaxWaitSeconds seconds." `
            -Level 'ERROR'
        return
    }

    Write-Log "Using Winget executable: $wingetPath"

    try {
        Write-Log "Updating Winget sources."

        $sourceOutput = & $wingetPath `
            source update `
            --disable-interactivity 2>&1 |
            Out-String

        $sourceExitCode = $LASTEXITCODE
        $cleanSourceOutput = Get-CleanWingetOutput -Output $sourceOutput

        Write-Log "Winget source update exit code: $sourceExitCode"

        if ($cleanSourceOutput) {
            Write-Log "Winget source update output:`r`n$cleanSourceOutput"
        }

        if ($sourceExitCode -ne 0) {
            Write-Log `
                "Winget source update returned a nonzero exit code." `
                -Level 'WARNING'
        }
    }
    catch {
        Write-Log `
            "Winget source update failed: $($_.Exception.Message)" `
            -Level 'WARNING'
    }

    try {
        Write-Log "Checking for available Winget repository upgrades."

        $upgradeOutput = & $wingetPath `
            upgrade `
            --all `
            --source winget `
            --accept-source-agreements `
            --accept-package-agreements `
            --silent `
            --disable-interactivity 2>&1 |
            Out-String

        $upgradeExitCode = $LASTEXITCODE
        $cleanUpgradeOutput = Get-CleanWingetOutput -Output $upgradeOutput

        Write-Log "Winget upgrade exit code: $upgradeExitCode"

        if (
            $cleanUpgradeOutput -match
            "No installed package found matching input criteria"
        ) {
            Write-Log "Winget found no available upgrades."
        }
        elseif (
            $cleanUpgradeOutput -match
            "No applicable upgrade found"
        ) {
            Write-Log "Winget found no applicable upgrades."
        }
        elseif ($cleanUpgradeOutput) {
            Write-Log "Winget upgrade output:`r`n$cleanUpgradeOutput"
        }
        else {
            Write-Log "Winget completed without returning output."
        }

        if ($upgradeExitCode -ne 0) {
            Write-Log `
                "Winget upgrade returned a nonzero exit code." `
                -Level 'WARNING'
        }
    }
    catch {
        Write-Log `
            "Winget upgrade failed: $($_.Exception.Message)" `
            -Level 'ERROR'
    }
}

# =============================================================================
# Main
# =============================================================================

Initialize-LogDirectory
Rotate-Log

Write-Log "============================================================"
Write-Log "Script started."
Write-Log "Computer: $env:COMPUTERNAME"
Write-Log "User: $env:USERNAME"
Write-Log "StartVivaldi: $StartVivaldi"
Write-Log "StartFirefox: $StartFirefox"
Write-Log "StartDiscord: $StartDiscord"
Write-Log "RunWinget: $RunWinget"
Write-Log "SkipWinget parameter: $SkipWinget"

if ($StartVivaldi) {
    Write-Log "Vivaldi startup is enabled."
    $null = Start-VivaldiIfNotRunning
}
else {
    Write-Log "Vivaldi startup is disabled."
}

if ($StartFirefox) {
    Write-Log "Firefox startup is enabled."

    $null = Start-AppIfNotRunning `
        -DisplayName "Firefox" `
        -ProcessName "firefox" `
        -CandidatePaths $FirefoxPaths
}
else {
    Write-Log "Firefox startup is disabled."
}

if ($StartDiscord) {
    Write-Log "Discord startup is enabled."
    $null = Start-DiscordIfNotRunning
}
else {
    Write-Log "Discord startup is disabled."
}

Invoke-WingetUpdates

Write-Log "Script completed."
Write-Log "============================================================"