<#
.SYNOPSIS
    Moves all files from subdirectories up to the root folder.

.DESCRIPTION
    The script recursively walks through every subdirectory of the folder where
    the script itself resides.  All non‑temporary files are moved into that
    root folder, preserving file names (overwrites will be avoided by appending
    a timestamp if needed).  Files that cannot be accessed (e.g., because they
    are in use or read‑only) are skipped and logged.

.PARAMETER MaxDepth
    The maximum recursion depth.  
    - Set to 0 for unlimited depth.  
    - Set to N (>0) to limit the walk to N levels below the root.

.EXAMPLE
    .\Move-Flat.ps1 -MaxDepth 5

.NOTES
    Requires PowerShell 5.1+ (or PowerShell Core).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateRange(0,1000)]
    [int]$MaxDepth = 0          # 0 → unlimited depth
)

#region Helper functions

function Test-FileInUse {
    <#
    .SYNOPSIS
        Checks whether a file is currently opened by another process.
    #>
    param([string]$Path)
    try {
        $stream = [System.IO.File]::Open($Path, 'Open', 'ReadWrite', 'None')
        $stream.Close()
        return $false
    } catch {
        return $true
    }
}

function Move-FileSafe {
    <#
    .SYNOPSIS
        Moves a file to the destination folder.
        If a file with the same name already exists, appends a timestamp.
    #>
    param(
        [string]$Source,
        [string]$DestinationFolder
    )

    $fileName = Split-Path -Leaf $Source
    $destPath  = Join-Path -Path $DestinationFolder -ChildPath $fileName

    if (Test-Path -LiteralPath $destPath) {
        # Append timestamp to avoid overwrite
        $name   = [IO.Path]::GetFileNameWithoutExtension($fileName)
        $ext    = [IO.Path]::GetExtension($fileName)
        $ts     = Get-Date -Format "yyyyMMddHHmmss"
        $newName= "$name`_$ts$ext"
        $destPath = Join-Path -Path $DestinationFolder -ChildPath $newName
    }

    try {
        Move-Item -LiteralPath $Source -Destination $destPath -ErrorAction Stop
        Write-Verbose "Moved: '$Source' → '$destPath'"
    } catch [System.IO.IOException] {
        # File may be in use or locked; skip it.
        Write-Warning "Could not move file (likely in use): $Source"
    } catch {
        Write-Warning "Unexpected error moving file: $Source. $_"
    }
}

#endregion

#region Main logic

# Determine the folder that contains this script
$RootFolder = Split-Path -Parent $MyInvocation.MyCommand.Definition

Write-Host "Root folder:" $RootFolder -ForegroundColor Cyan
if ($MaxDepth -eq 0) {
    Write-Host "Recursion depth: Unlimited" -ForegroundColor Yellow
} else {
    Write-Host ("Recursion depth: {0}" -f $MaxDepth) -ForegroundColor Yellow
}

# Build the file search options
$searchOptions = @{
    Path        = $RootFolder
    Recurse     = $true
    File        = $true
}
if ($MaxDepth -gt 0) {
    # PowerShell 7+ supports -Depth; for older PS we’ll implement manual depth check
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $searchOptions.Depth = $MaxDepth
    } else {
        # For PS5.1, we will filter after enumeration
        Write-Host "Note: Depth limiting is not supported in PowerShell 5.x; all sub‑folders will be processed." -ForegroundColor Magenta
    }
}

# Temporary file patterns to skip (add/remove as needed)
$TempPatterns = @(
    '*.tmp',
    '~$*',            # Office temp files
    '*.log.bak',
    '*.swp'
)

# Get the list of all files in subdirectories
$filesToMove = Get-ChildItem @searchOptions |
    Where-Object { $_.PSIsContainer -eq $false } |          # only files
    Where-Object {
        # Skip temporary patterns
        foreach ($pat in $TempPatterns) {
            if ($_ -like $pat) { return $false }
        }
        return $true
    }

# If we’re on PS5.x and depth limiting is needed, filter manually
if (($MaxDepth -gt 0) -and ($PSVersionTable.PSVersion.Major -lt 7)) {
    $filesToMove = $filesToMove | Where-Object {
        # Calculate relative depth from root
        $relPath = Resolve-Path -LiteralPath $_.FullName -Relative
        ($relPath.Split([IO.Path]::DirectorySeparatorChar)).Count - 1 -le $MaxDepth
    }
}

Write-Host ("Found {0} file(s) to consider." -f $filesToMove.Count) -ForegroundColor Green

foreach ($file in $filesToMove) {
    # Skip if the file is currently locked / in use
    if (Test-FileInUse -Path $file.FullName) {
        Write-Warning "Skipping locked file: $($file.FullName)"
        continue
    }

    Move-FileSafe -Source $file.FullName -DestinationFolder $RootFolder
}

Write-Host "Operation completed." -ForegroundColor Cyan

#endregion
