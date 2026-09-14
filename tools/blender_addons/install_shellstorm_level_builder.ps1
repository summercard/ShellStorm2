param(
    [string]$BlenderVersion = "4.5"
)

$ErrorActionPreference = "Stop"
$source = Join-Path $PSScriptRoot "shellstorm_level_builder"
$addons = Join-Path $env:APPDATA "Blender Foundation\Blender\$BlenderVersion\scripts\addons"
$destination = Join-Path $addons "shellstorm_level_builder"

New-Item -ItemType Directory -Force -Path $destination | Out-Null
$cache = Join-Path $destination "__pycache__"
if (Test-Path $cache) {
    Remove-Item -LiteralPath $cache -Recurse -Force
}
Get-ChildItem -LiteralPath $source -File | Where-Object { $_.Extension -in @(".py", ".md") } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
}
Write-Output "Installed ShellStorm Level Builder to $destination"
