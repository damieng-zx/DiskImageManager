# Build and run the Disk Image Manager test suite.
# Usage:  .\run-tests.ps1            (plain text output)
#         .\run-tests.ps1 -Xml       (also write results.xml)
param(
    [switch]$Xml
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here

# Locate lazbuild (PATH first, then the default Windows install location)
$lazbuild = (Get-Command lazbuild -ErrorAction SilentlyContinue).Source
if (-not $lazbuild) { $lazbuild = 'C:\lazarus\lazbuild.exe' }
if (-not (Test-Path $lazbuild)) {
    throw "lazbuild not found. Install Lazarus or add lazbuild to PATH."
}

& $lazbuild --ws=win32 DiskImageManagerTests.lpi
if ($LASTEXITCODE -ne 0) { throw "Build failed." }

$exe = Join-Path $here 'DiskImageManagerTests.exe'
if ($Xml) {
    & $exe --format=xml --file=results.xml --format=plain
} else {
    & $exe --format=plain
}
exit $LASTEXITCODE
