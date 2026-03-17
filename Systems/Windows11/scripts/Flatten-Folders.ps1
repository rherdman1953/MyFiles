<#
.SYNOPSIS
  Flatten subfolders by moving files up to a root directory with a max depth,
  skipping temp/locked files, then removing empty directories.

  .PROMPT
  create a powershell script that will loop through sub-directories (with a recursive limit set 
  in the script that is adjustable) and move all files up to the root folder. Skip all temporary 
  files and any files that are in use. when done remove all empty directories. add an optional 
  parameter to specify the root folder. 

.EXAMPLE
  .\Flatten-Folders.ps1 -Root "D:\Media\Mixed" -MaxDepth 3

.EXAMPLE
  .\Flatten-Folders.ps1 -MaxDepth 5 -DryRun
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    # Root folder to move files into; defaults to current directory
    [Parameter(Position=0)]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$Root = (Get-Location).Path,

    # How deep to search below root (1 = only immediate child folders)
    [ValidateRange(1, 100)]
    [int]$MaxDepth = 3,

    # Preview actions without making changes
    [switch]$DryRun
)

begin {
    # Normalize to full path (no trailing slash issues)
    $Root = (Resolve-Path -LiteralPath $Root).Path

    Write-Verbose "Root      : $Root"
    Write-Verbose "MaxDepth  : $MaxDepth"
    Write-Verbose "DryRun    : $DryRun"

    # Define temporary file name patterns to skip
    $TempNamePatterns = @(
        '*.tmp', '*.temp', '*.part', '*.partial',
        '*.crdownload', '*.download', '~*', '*.~*', '~$*'
    )

    function Test-FileIsTempName([IO.FileInfo]$File) {
        foreach ($pat in $TempNamePatterns) {
            if ($File.Name -like $pat) { return $true }
        }
        return $false
    }

    function Test-FileLocked([string]$Path) {
        try {
            $fs = [System.IO.File]::Open($Path,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::None)
            $fs.Close()
            return $false
        }
        catch {
            # If the exception is an IO or UnauthorizedAccess, treat as locked
            return $true
        }
    }

    function Get-UniqueDestinationPath([string]$DestFolder, [string]$FileName) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
        $ext      = [System.IO.Path]::GetExtension($FileName)
        $candidate = Join-Path $DestFolder $FileName
        $i = 1
        while (Test-Path -LiteralPath $candidate) {
            $candidate = Join-Path $DestFolder ("{0} ({1}){2}" -f $baseName, $i, $ext)
            $i++
        }
        return $candidate
    }

    function Remove-EmptyDirectories([string]$Start) {
        # Remove empty folders deepest-first; never remove the root itself
        Get-ChildItem -LiteralPath $Start -Directory -Recurse -Force |
            Sort-Object FullName -Descending |
            ForEach-Object {
                try {
                    $hasChildren =
                        (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction Stop | Measure-Object).Count -gt 0
                    if (-not $hasChildren) {
                        if ($DryRun) {
                            Write-Host "[DryRun] Remove-Item -LiteralPath '$($_.FullName)' -Force"
                        } else {
                            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                        }
                    }
                } catch {
                    Write-Warning "Could not evaluate/remove '$($_.FullName)': $($_.Exception.Message)"
                }
            }
    }

    # Check if Get-ChildItem supports -Depth; if not, we’ll do manual breadth-first traversal
    $SupportsDepth = $false
    try {
        $null = Get-Command Get-ChildItem | Where-Object { $_.Parameters.ContainsKey('Depth') }
        if ($null) { $SupportsDepth = $true }
    } catch { $SupportsDepth = $false }
}

process {
    # Collect target files
    $files = @()

    if ($SupportsDepth) {
        # Use native -Depth if available
        $files = Get-ChildItem -LiteralPath $Root -Recurse -Depth $MaxDepth -File -Force -ErrorAction Stop |
                 Where-Object { $_.DirectoryName -ne $Root }
    } else {
        # Manual traversal with a queue to enforce depth
        $queue = New-Object System.Collections.Generic.Queue[object]
        $queue.Enqueue([pscustomobject]@{ Path = $Root; Depth = 0 })

        while ($queue.Count -gt 0) {
            $node = $queue.Dequeue()
            $currPath = $node.Path
            $depth    = $node.Depth

            if ($depth -ge 1) {
                $files += Get-ChildItem -LiteralPath $currPath -File -Force -ErrorAction SilentlyContinue
            }

            if ($depth -lt $MaxDepth) {
                Get-ChildItem -LiteralPath $currPath -Directory -Force -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        $queue.Enqueue([pscustomobject]@{ Path = $_.FullName; Depth = $depth + 1 })
                    }
            }
        }

        # Exclude files already at root just in case
        $files = $files | Where-Object { $_.DirectoryName -ne $Root }
    }

    $moved = 0
    $skippedTemp = 0
    $skippedLocked = 0
    $skippedOther = 0

    foreach ($file in $files) {
        try {
            # Skip by name patterns
            if (Test-FileIsTempName $file) {
                $skippedTemp++
                continue
            }

            # Attempt to skip likely temp by attribute as well
            if (($file.Attributes -band [IO.FileAttributes]::Temporary) -ne 0) {
                $skippedTemp++
                continue
            }

            # Skip in-use files
            if (Test-FileLocked $file.FullName) {
                $skippedLocked++
                continue
            }

            $dest = Get-UniqueDestinationPath -DestFolder $Root -FileName $file.Name

            if ($DryRun) {
                Write-Host "[DryRun] Move-Item -LiteralPath '$($file.FullName)' -Destination '$dest'"
                $moved++
                continue
            }

            Move-Item -LiteralPath $file.FullName -Destination $dest -ErrorAction Stop
            $moved++
        }
        catch {
            $skippedOther++
            Write-Warning "Skipped '$($file.FullName)': $($_.Exception.Message)"
        }
    }

    # Clean up empty directories
    Remove-EmptyDirectories -Start $Root

    Write-Host "Done."
    Write-Host "Moved   : $moved"
    Write-Host "Skipped : Temp=$skippedTemp, Locked=$skippedLocked, Other=$skippedOther"
}

end {
    # no-op
}
