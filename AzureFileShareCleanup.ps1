<#
.SYNOPSIS
    Daily maintenance script for Azure File Share.

.DESCRIPTION
    - Connects with Automation Account managed identity
    - Collects metadata (LastModified, size) for all files
    - Exports metadata to CSV in 'Export' folder
    - Deletes files older than N days

.PARAMETER resourceGroupName
    Resource group containing the storage account.

.PARAMETER storageAccName
    Name of the storage account.

.PARAMETER fileShareName
    Name of the file share.

.PARAMETER exportFolderName
    Name of the folder in the file share where CSV file be saved.

.PARAMETER csvFileName
    Name of the CSV file.

.PARAMETER retentionDays
    Number of days. Files that have not been modified in last $retentionDays will be deleted.

.NOTES
    Author: Handover2AI-byExistence
    Date:   2025-12-01
    Requires: Az.Storage module >= 6.1.0
#>

# Parameters
$resourceGroupName = "<RESOURCE GROUP OF THE STORAGE ACCOUNT>"
$storageAccName    = "<NAME OF THE STORAGE ACCOUNT>"
$fileShareName     = "<NAME OF THE FILE SHARE>"
$exportFolderName  = "Export"
$csvFileName       = "FileMetadata.csv"
$retentionDays     = 7

# Connect with managed identity
Connect-AzAccount -Identity

# Get the first storage account key
$key = (Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccName)[0].Value

# Build context using the key
$ctx = New-AzStorageContext -StorageAccountName $storageAccName -StorageAccountKey $key

<#
.SYNOPSIS
    Recursively collects file metadata from an Azure File Share.

.DESCRIPTION
    Given a share name and context, this function traverses all directories
    and returns a list of files with their relative path, name, last modified
    timestamp, and size in bytes.

.PARAMETER ShareName
    The name of the Azure File Share.

.PARAMETER Context
    The storage context created with New-AzStorageContext.

.PARAMETER Path
    The relative path inside the share. Defaults to root.

.OUTPUTS
    PSCustomObject with FilePath, Name, LastModified, LengthBytes.
#>

function Get-AfsFilesWithMetadata {
    param(
        [Parameter(Mandatory=$true)][string]$ShareName,
        [Parameter(Mandatory=$true)]$Context,
        [string]$Path = ""   # relative path inside the share; empty = root
    )

    $files = @()

    # Get entries at root vs inside a directory
    if ([string]::IsNullOrEmpty($Path)) {
        $entries = Get-AzStorageFile -ShareName $ShareName -Path "" -Context $Context
    } else {
        $dirObj  = Get-AzStorageFile -ShareName $ShareName -Path $Path -Context $Context
        $entries = $dirObj | Get-AzStorageFile
    }

    foreach ($e in $entries) {
        $type = $e.GetType().FullName

        if ($type -like "*Directory") {
            # Recurse into the child directory
            $childPath = if ([string]::IsNullOrEmpty($Path)) { $e.Name } else { "$Path/$($e.Name)" }
            $files += Get-AfsFilesWithMetadata -ShareName $ShareName -Context $Context -Path $childPath
        }
        elseif ($type -like "*File") {
            # Build file relative path
            $filePath = if ([string]::IsNullOrEmpty($Path)) { $e.Name } else { "$Path/$($e.Name)" }

            # Try to extract LastModified and Length from available properties
            $lastModified = $null
            $length       = $null

            # Common locations for metadata returned by Az cmdlets
            if ($null -ne $e.Properties) {
                if ($e.Properties.PSObject.Properties.Match('LastModified')) { $lastModified = $e.Properties.LastModified }
                if ($e.Properties.PSObject.Properties.Match('ContentLength')) { $length = $e.Properties.ContentLength }
            }

            if (-not $lastModified -and $e.PSObject.Properties.Match('LastModified')) {
                $lastModified = $e.LastModified
            }

            if (-not $lastModified -and $e.PSObject.Properties.Match('ICloudFile')) {
                try { $lastModified = $e.ICloudFile.Properties.LastModified } catch {}
            }

            if (-not $length -and $e.PSObject.Properties.Match('ICloudFile')) {
                try { $length = $e.ICloudFile.Properties.Length } catch {}
            }

            # Normalize LastModified to DateTime (or $null)
            if ($lastModified -is [string]) {
                [datetime]$lm = $lastModified 2>$null
                if ($?) { $lastModified = $lm } else { $lastModified = $lastModified }
            }

            $files += [PSCustomObject]@{
                FilePath     = $filePath
                Name         = $e.Name
                LastModified = $lastModified
                LengthBytes  = $length
            }
        }
    }

    return $files
}

# Run and capture results
$allFilesWithMeta = Get-AfsFilesWithMetadata -ShareName $fileShareName -Context $ctx -Path ""

# Show results sorted by LastModified descending
$allFilesWithMeta | Sort-Object @{Expression={$_.LastModified};Descending=$true} | Format-Table -AutoSize

# Check if Export folder exists
$exportFolder = Get-AzStorageFile -ShareName $fileShareName -Path "" -Context $ctx |
                Where-Object { $_.Name -eq $exportFolderName -and $_.GetType().FullName -like "*Directory" }

if (-not $exportFolder) {
    Write-Output "Export folder not found. Creating..."
    New-AzStorageDirectory -ShareName $fileShareName -Path $exportFolderName -Context $ctx | Out-Null
} else {
    Write-Output "Export folder already exists."
}

$tempCsv = Join-Path $env:TEMP $csvFileName
$allFilesWithMeta | Export-Csv -Path $tempCsv -NoTypeInformation -Force

# Upload CSV into Export folder in the file share
$destPath = "$exportFolderName/$csvFileName"
Set-AzStorageFileContent -ShareName $fileShareName -Source $tempCsv -Path $destPath -Context $ctx -Force

Write-Output "CSV uploaded to $fileShareName/$destPath"

# ---------------------------------------------- #
# Delete files older than certain number of days #
# ---------------------------------------------- #

# Calculate cutoff date
$cutoff = (Get-Date).AddDays(-$retentionDays)

# Filter files with LastModified older than cutoff
$oldFiles = $allFilesWithMeta | Where-Object {
    $_.LastModified -and ($_.LastModified -lt $cutoff)
}

Write-Output "Found $($oldFiles.Count) files older than $retentionDays days."

foreach ($f in $oldFiles) {
    try {
        Write-Output "Deleting $($f.FilePath) (LastModified: $($f.LastModified))"
        Remove-AzStorageFile -ShareName $fileShareName -Path $f.FilePath -Context $ctx
    }
    catch {
        Write-Warning "Failed to delete $($f.FilePath): $($_.Exception.Message)"
    }
}
