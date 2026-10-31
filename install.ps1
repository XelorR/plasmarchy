# Plasmarchy entry point for Windows 11.
# Forwards all arguments to windows11/install-windows.ps1.
param()

$ErrorActionPreference = 'Stop'
$installer = Join-Path $PSScriptRoot 'windows11\install-windows.ps1'
if (-not (Test-Path $installer)) {
    throw "Missing Windows installer: $installer"
}
& $installer @Args
