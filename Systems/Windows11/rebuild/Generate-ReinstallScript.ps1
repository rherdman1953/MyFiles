<#
.SYNOPSIS
  Generates a WinGet-based reinstall script + CSV mapping for the current PC (Windows 11 compatible). 

.DESCRIPTION
  - Enumerates installed apps using: winget list --output json (preferred).
  - Falls back to: winget export (JSON) if list JSON isn't available/works.
  - Generates reinstall script:
      * Human-readable comments explaining each winget id
      * Retry logic with backoff (extra backoff for msstore)
  - Generates CSV mapping:
      Name, Id, Source, Version, Scope, InstallerType, IsPortableGuess
  - Attempts best-effort detection of portable vs machine-wide:
      * Uses winget show --output json (if supported) to read installer Scope/InstallerType
      * Adds heuristic IsPortableGuess

REQUIREMENTS
  - Windows 11
  - WinGet installed (App Installer)
  - PowerShell 5.1+ or PowerShell 7+

USAGE
  .\Generate-ReinstallScript.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-Command {
  param([Parameter(Mandatory)][string]$Name)
  return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-PropValue {
  param(
    [Parameter(Mandatory)]$Obj,
    [Parameter(Mandatory)][string]$Name
  )
  if ($null -eq $Obj) { return $null }
  $p = $Obj.PSObject.Properties[$Name]
  if ($null -eq $p) { return $null }
  return $p.Value
}

function Safe-Trim {
  param([AllowNull()][string]$s)
  if ($null -eq $s) { return '' }
  return $s.Trim()
}

function Guess-IsPortable {
  param(
    [AllowNull()][string]$Name,
    [AllowNull()][string]$Id,
    [AllowNull()][string]$InstallerType
  )
  $n = (Safe-Trim $Name).ToLowerInvariant()
  $i = (Safe-Trim $Id).ToLowerInvariant()
  $t = (Safe-Trim $InstallerType).ToLowerInvariant()

  if ($t -eq 'portable') { return $true }
  if ($i -match '\.portable(\.|$)') { return $true }
  if ($n -match '\bportable\b') { return $true }
  if ($n -match '\bzip\b') { return $true }
  return $false
}

if (-not (Test-Command -Name 'winget')) {
  throw "winget was not found. Install/repair 'App Installer' (Microsoft Store) and try again."
}

$pcName = $env:COMPUTERNAME
$today  = Get-Date -Format 'yyyyMMdd'

$outScript = Join-Path (Get-Location) ("ReinstallApps-{0}-{1}.ps1" -f $pcName, $today)
$outCsv    = Join-Path (Get-Location) ("ReinstallApps-{0}-{1}.csv" -f $pcName, $today)

function Get-WinGetListAsJson {
  $jsonText = & winget list --accept-source-agreements --output json 2>$null
  if (-not $jsonText) { return @() }

  $parsed = $jsonText | ConvertFrom-Json

  $data = Get-PropValue -Obj $parsed -Name 'Data'
  if ($data) { return @($data) }

  if ($parsed -is [System.Collections.IEnumerable] -and -not ($parsed -is [string])) {
    return @($parsed)
  }

  return @()
}

function Get-WinGetExportJson {
  $tmp = Join-Path $env:TEMP ("winget-export-{0}.json" -f ([guid]::NewGuid().ToString('N')))
  try {
    & winget export -o $tmp --accept-source-agreements | Out-Null
    if (-not (Test-Path $tmp)) { return @() }

    $export = Get-Content -Raw -Path $tmp | ConvertFrom-Json
    $sources = Get-PropValue -Obj $export -Name 'Sources'
    if (-not $sources) { return @() }

    $all = @()

    foreach ($src in @($sources)) {
      $srcDetails = Get-PropValue -Obj $src -Name 'SourceDetails'
      $srcName = $null
      if ($srcDetails) { $srcName = Get-PropValue -Obj $srcDetails -Name 'Name' }
      if (-not $srcName) { $srcName = Get-PropValue -Obj $src -Name 'SourceName' }
      if (-not $srcName) { $srcName = Get-PropValue -Obj $src -Name 'Name' }

      $pkgs = Get-PropValue -Obj $src -Name 'Packages'
      if (-not $pkgs) { continue }

      foreach ($pkg in @($pkgs)) {
        $id = Get-PropValue -Obj $pkg -Name 'PackageIdentifier'
        if (-not $id) { $id = Get-PropValue -Obj $pkg -Name 'Id' }
        if (-not $id) { $id = Get-PropValue -Obj $pkg -Name 'Identifier' }

        $name = Get-PropValue -Obj $pkg -Name 'PackageName'
        if (-not $name) { $name = Get-PropValue -Obj $pkg -Name 'Name' }
        if (-not $name) { $name = $id }

        $ver = Get-PropValue -Obj $pkg -Name 'Version'
        if (-not $ver) { $ver = Get-PropValue -Obj $pkg -Name 'InstalledVersion' }

        $all += [pscustomobject]@{
          Name    = [string]$name
          Id      = [string]$id
          Source  = [string]$srcName
          Version = [string]$ver
        }
      }
    }

    return @($all)
  }
  finally {
    Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
  }
}

function Get-WinGetShowMeta {
  param(
    [Parameter(Mandatory)][string]$Id,
    [AllowNull()][string]$Source
  )

  $meta = [pscustomobject]@{
    Scope         = ''
    InstallerType = ''
    Moniker       = ''
  }

  if (-not $Id) { return $meta }

  try {
    $args = @('show','--id', $Id, '-e','--accept-source-agreements','--output','json')
    if ($Source -and $Source.Trim()) {
      $args += @('--source', $Source.Trim())
    }

    $jsonText = & winget @args 2>$null
    if (-not $jsonText) { return $meta }

    $parsed = $jsonText | ConvertFrom-Json

    $moniker = Get-PropValue -Obj $parsed -Name 'Moniker'
    if (-not $moniker) { $moniker = Get-PropValue -Obj $parsed -Name 'moniker' }
    if ($moniker) { $meta.Moniker = [string]$moniker }

    $installers = Get-PropValue -Obj $parsed -Name 'Installers'
    if (-not $installers) { $installers = Get-PropValue -Obj $parsed -Name 'installers' }

    if ($installers -and @($installers).Count -gt 0) {
      $first = @($installers)[0]

      $scope = Get-PropValue -Obj $first -Name 'Scope'
      if (-not $scope) { $scope = Get-PropValue -Obj $first -Name 'scope' }
      if ($scope) { $meta.Scope = [string]$scope }

      $itype = Get-PropValue -Obj $first -Name 'InstallerType'
      if (-not $itype) { $itype = Get-PropValue -Obj $first -Name 'installerType' }
      if ($itype) { $meta.InstallerType = [string]$itype }
    }

    return $meta
  }
  catch {
    return $meta
  }
}

# --- Enumerate installed apps ---
$packages = @()
try {
  $packages = Get-WinGetListAsJson
  if (@($packages).Count -eq 0) { $packages = Get-WinGetExportJson }
} catch {
  $packages = Get-WinGetExportJson
}

if (@($packages).Count -eq 0) {
  throw "Could not enumerate installed apps via winget. Try 'winget list' manually to confirm it works."
}

# --- Normalize list ---
$normalized = foreach ($p in @($packages)) {
  $name = Get-PropValue -Obj $p -Name 'Name'
  if (-not $name) { $name = Get-PropValue -Obj $p -Name 'PackageName' }

  $id = Get-PropValue -Obj $p -Name 'Id'
  if (-not $id) { $id = Get-PropValue -Obj $p -Name 'PackageIdentifier' }

  $source = Get-PropValue -Obj $p -Name 'Source'
  if (-not $source) { $source = Get-PropValue -Obj $p -Name 'SourceName' }

  $ver = Get-PropValue -Obj $p -Name 'Version'
  if (-not $ver) { $ver = Get-PropValue -Obj $p -Name 'InstalledVersion' }

  [pscustomobject]@{
    Name    = [string]$name
    Id      = [string]$id
    Source  = [string]$source
    Version = [string]$ver
  }
}

$installable = @($normalized | Where-Object { $_.Id -and $_.Id.Trim() })
$notInWinget = @($normalized | Where-Object { -not ($_.Id -and $_.Id.Trim()) })
$installable = @($installable | Sort-Object Source, Id, Name -Unique)

# --- Enrich with best-effort metadata from winget show ---
$enriched = @()
foreach ($pkg in @($installable)) {
  $id  = Safe-Trim $pkg.Id
  $src = Safe-Trim $pkg.Source

  $meta = Get-WinGetShowMeta -Id $id -Source $src
  $installerType = Safe-Trim $meta.InstallerType
  $scope = Safe-Trim $meta.Scope
  $isPortableGuess = Guess-IsPortable -Name $pkg.Name -Id $id -InstallerType $installerType

  $enriched += [pscustomobject]@{
    Name            = Safe-Trim $pkg.Name
    Id              = $id
    Source          = $src
    Version         = Safe-Trim $pkg.Version
    Scope           = $scope
    InstallerType   = $installerType
    IsPortableGuess = $isPortableGuess
  }
}

# --- Write CSV mapping ---
$enriched | Sort-Object Source, Name | Export-Csv -Path $outCsv -NoTypeInformation -Encoding UTF8

# --- Generate reinstall script ---
$lines = New-Object System.Collections.Generic.List[string]
$genDate = Get-Date

$lines.Add('<#')
$lines.Add(("  Generated on: {0}" -f $genDate))
$lines.Add(("  Source PC:     {0}" -f $pcName))
$lines.Add(("  Mapping CSV:   {0}" -f (Split-Path -Leaf $outCsv)))
$lines.Add('')
$lines.Add('  Reinstalls apps using WinGet with retry logic.')
$lines.Add('  Each install includes a human-readable comment describing the package.')
$lines.Add('#>')
$lines.Add('')
$lines.Add('Set-StrictMode -Version Latest')
$lines.Add('$ErrorActionPreference = "Continue"')
$lines.Add('')
$lines.Add('if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {')
$lines.Add('  Write-Error "winget not found. Install/repair App Installer, then rerun."')
$lines.Add('  exit 1')
$lines.Add('}')
$lines.Add('')

$lines.Add('function Invoke-WinGetInstallWithRetry {')
$lines.Add('  param(')
$lines.Add('    [Parameter(Mandatory)][string]$Id,')
$lines.Add('    [Parameter(Mandatory)][string]$Name,')
$lines.Add('    [AllowNull()][string]$Source,')
$lines.Add('    [int]$MaxAttempts = 4')
$lines.Add('  )')
$lines.Add('')
$lines.Add('  $attempt = 0')
$lines.Add('  while ($attempt -lt $MaxAttempts) {')
$lines.Add('    $attempt++')
$lines.Add('    Write-Host ("Installing: {0} ({1}) [Attempt {2}/{3}]" -f $Name, $Id, $attempt, $MaxAttempts)')
$lines.Add('')
$lines.Add('    $srcArgs = @()')
$lines.Add('    if ($Source -and $Source.Trim()) { $srcArgs = @("--source", $Source.Trim()) }')
$lines.Add('')
$lines.Add('    winget install --id $Id -e @srcArgs --silent --accept-package-agreements --accept-source-agreements --disable-interactivity')
$lines.Add('    $code = $LASTEXITCODE')
$lines.Add('')
$lines.Add('    if ($code -eq 0) { return $true }')
$lines.Add('')
$lines.Add('    Write-Warning ("Failed: {0} ({1}) exit={2}" -f $Name, $Id, $code)')
$lines.Add('')
$lines.Add('    $sleep = 5 * $attempt')
$lines.Add('    if ($Source -and $Source.Trim().ToLowerInvariant() -eq "msstore") { $sleep = 15 * $attempt }')
$lines.Add('    Start-Sleep -Seconds $sleep')
$lines.Add('  }')
$lines.Add('')
$lines.Add('  return $false')
$lines.Add('}')
$lines.Add('')

if (@($notInWinget).Count -gt 0) {
  $lines.Add('# ---------------------------------------------------------------------------')
  $lines.Add('# Installed apps detected WITHOUT a WinGet Package Id (not reinstallable via winget):')
  foreach ($x in @($notInWinget | Sort-Object Name)) {
    $n = $x.Name
    if (-not $n) { $n = '<unknown name>' }
    $lines.Add('# - ' + $n)
  }
  $lines.Add('# ---------------------------------------------------------------------------')
  $lines.Add('')
}

$lines.Add('Write-Host "Starting reinstalls..."')
$lines.Add('')

foreach ($pkg in @($enriched | Sort-Object Source, Name)) {
  $id   = Safe-Trim $pkg.Id
  $name = Safe-Trim $pkg.Name
  $src  = Safe-Trim $pkg.Source
  if (-not $name) { $name = $id }

  $psId   = $id.Replace('"', "'")
  $psName = $name.Replace('"', "'")
  $psSrc  = $src.Replace('"', "'")

  $metaBits = @()
  if (Safe-Trim $pkg.Scope) { $metaBits += ('scope=' + (Safe-Trim $pkg.Scope)) }
  if (Safe-Trim $pkg.InstallerType) { $metaBits += ('installerType=' + (Safe-Trim $pkg.InstallerType)) }
  if ($pkg.IsPortableGuess -eq $true) { $metaBits += 'portableGuess=true' }

  $metaSuffix = ''
  if ($metaBits.Count -gt 0) { $metaSuffix = ' [' + ($metaBits -join ' ') + ']' }

  if ($src -and $src.Trim().ToLowerInvariant() -eq 'msstore') {
    $lines.Add('# ' + $psName + ' (Microsoft Store app; winget id: ' + $psId + ')' + $metaSuffix)
  } else {
    $lines.Add('# ' + $psName + ' (winget id: ' + $psId + ')' + $metaSuffix)
  }

  $lines.Add('if (-not (Invoke-WinGetInstallWithRetry -Id "' + $psId + '" -Name "' + $psName + '" -Source "' + $psSrc + '")) { Write-Warning "=> Giving up: ' + $psName + ' (' + $psId + ')" }')
  $lines.Add('')
}

$lines.Add('Write-Host "Done."')

$lines | Set-Content -Path $outScript -Encoding UTF8

Write-Host ''
Write-Host 'Generated files:'
Write-Host ("  Script: {0}" -f $outScript)
Write-Host ("  CSV:    {0}" -f $outCsv)
