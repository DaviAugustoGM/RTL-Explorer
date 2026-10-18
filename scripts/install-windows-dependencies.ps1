[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitOperatingSystem) {
    throw 'This script requires 64-bit Windows.'
}
if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
    throw 'curl.exe is required (included in current Windows 10/11 releases).'
}
$RepoRoot = Split-Path $PSScriptRoot -Parent
$Tools = Join-Path $RepoRoot '.tools'
if ($Tools -match '\s') {
    throw 'Move the checkout to a path without spaces (for example D:\RTL-Explorer); Icarus cannot reliably run from a path containing spaces.'
}
$Cache = Join-Path $Tools 'downloads'
New-Item -ItemType Directory -Force $Cache | Out-Null
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Get-Download([string]$Url, [string]$Name) {
    $file = Join-Path $Cache $Name
    if (-not (Test-Path -LiteralPath $file)) {
        Write-Host "Downloading $Name ..."
        $partial = "$file.partial"
        & curl.exe -L --fail --retry 3 --output $partial $Url
        if ($LASTEXITCODE -ne 0) { throw "Download failed: $Url" }
        Move-Item -LiteralPath $partial -Destination $file -Force
    }
    return $file
}

function Invoke-Installer([string]$File, [string[]]$Arguments) {
    $process = Start-Process -FilePath $File -ArgumentList $Arguments -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Installer failed ($($process.ExitCode)): $File" }
}

# Versions match the Windows packaging toolchain. All tools stay inside the checkout.
$Oss = Join-Path $Tools 'oss-cad-suite'
if (-not (Test-Path "$Oss\bin\yosys.exe") -or
    -not (Test-Path "$Oss\lib\python3.exe") -or
    -not (Test-Path "$Oss\lib\libstdc++-6.dll")) {
    $archive = Get-Download 'https://github.com/YosysHQ/oss-cad-suite-build/releases/download/2026-07-05/oss-cad-suite-windows-x64-20260705.exe' 'oss-cad-suite-windows-x64-20260705.exe'
    Invoke-Installer $archive @('-y', "-o`"$Tools`"")
}
$Compiler = Join-Path $Tools 'w64devkit'
if (-not (Test-Path "$Compiler\bin\g++.exe")) {
    $archive = Get-Download 'https://github.com/skeeto/w64devkit/releases/download/v2.8.0/w64devkit-x64-2.8.0.7z.exe' 'w64devkit-x64-2.8.0.7z.exe'
    Invoke-Installer $archive @('-y', "-o`"$Tools`"")
}
$Sv2v = Join-Path $Tools 'sv2v\sv2v-Windows\sv2v.exe'
if (-not (Test-Path $Sv2v)) {
    $archive = Get-Download 'https://github.com/zachjs/sv2v/releases/download/v0.0.13/sv2v-Windows.zip' 'sv2v-Windows-0.0.13.zip'
    Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $Tools 'sv2v') -Force
}
$Tcl = Join-Path $Tools 'tcl'
if (-not (Test-Path "$Tcl\bin\wish86.exe")) {
    $installer = Get-Download 'https://www.bawt.tcl3d.org/download/Tcl-Pure/SetupTcl-8.6.17-x64_Bawt-3.2.0.exe' 'SetupTcl-8.6.17-x64_Bawt-3.2.0.exe'
    Invoke-Installer $installer @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CURRENTUSER', "/DIR=`"$Tcl`"")
}

$env:PATH = "$Oss\lib;$Oss\bin;$Compiler\bin;$env:PATH"
foreach ($check in @(
    @{ File = "$Oss\bin\yosys.exe"; Args = @('-V') },
    @{ File = "$Oss\lib\python3.exe"; Args = @('--version') },
    @{ File = $Sv2v; Args = @('--version') },
    @{ File = "$Oss\bin\iverilog.exe"; Args = @('-V') },
    @{ File = "$Oss\bin\vvp.exe"; Args = @('-V') },
    @{ File = "$Compiler\bin\g++.exe"; Args = @('--version') }
)) {
    & $check.File @($check.Args)
    if ($LASTEXITCODE -ne 0) { throw "Tool check failed: $($check.File)" }
}
& "$Tcl\bin\tclsh86.exe" (Join-Path $PSScriptRoot 'check-toolchain.tcl')
if ($LASTEXITCODE -ne 0) { throw 'Toolchain check failed.' }
$tkProbe = Join-Path $Cache 'check-tk.tcl'
@'
if {[catch {package require Tk 8.6} message]} {
    puts stderr $message
    exit 1
}
wm withdraw .
puts "Tcl [info patchlevel], Tk [package provide Tk]: ready"
destroy .
exit 0
'@ | Set-Content -LiteralPath $tkProbe -Encoding Ascii
& "$Tcl\bin\tclsh86.exe" $tkProbe
if ($LASTEXITCODE -ne 0) { throw 'Tcl/Tk check failed.' }
Write-Host 'Dependencies installed. Start RTL Explorer with .\run-windows.cmd'
