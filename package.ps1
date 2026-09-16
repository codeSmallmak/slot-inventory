# Builds the Asset Store / itch.io zip for Slot Inventory.
# Run from the project folder:
#   powershell -ExecutionPolicy Bypass -File .\package.ps1
# Output: slot_inventory_<version>.zip on your Desktop, containing
#   addons/slot_inventory/...   (the addon)
#   demo/...                    (optional example, remove -IncludeDemo to skip)

param(
    [switch]$IncludeDemo = $true
)

$ErrorActionPreference = "Stop"
$project = $PSScriptRoot

# Version comes from plugin.cfg so the zip name never drifts from the plugin.
$cfg = Get-Content "$project\addons\slot_inventory\plugin.cfg" -Raw
if ($cfg -match 'version="([^"]+)"') { $version = $Matches[1] } else { $version = "dev" }

$stage = Join-Path $env:TEMP "slot_inventory_pkg"
$out = Join-Path ([Environment]::GetFolderPath("Desktop")) "slot_inventory_$version.zip"

Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item (Join-Path $stage "addons") -ItemType Directory | Out-Null
Copy-Item "$project\addons\slot_inventory" (Join-Path $stage "addons\slot_inventory") -Recurse

$items = @((Join-Path $stage "addons"))
if ($IncludeDemo) {
    Copy-Item "$project\demo" (Join-Path $stage "demo") -Recurse
    Remove-Item (Join-Path $stage "demo\_icon_preview.png") -ErrorAction SilentlyContinue
    $items += (Join-Path $stage "demo")
}

Remove-Item $out -ErrorAction SilentlyContinue
Compress-Archive -Path $items -DestinationPath $out -CompressionLevel Optimal
Remove-Item $stage -Recurse -Force

Write-Host ""
Write-Host "Created: $out"
Write-Host "Contents (top level):"
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($out)
$zip.Entries | ForEach-Object { ($_.FullName -split "/")[0] } | Sort-Object -Unique | ForEach-Object { Write-Host "  $_/" }
Write-Host "  ($($zip.Entries.Count) files)"
$zip.Dispose()
