[CmdletBinding()]
param(
    [string]$StageDirectory,
    [switch]$ReuseLocalTools
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $StageDirectory) {
    $StageDirectory = Join-Path $RepoRoot 'dist\windows\stage'
}
$StageDirectory = [IO.Path]::GetFullPath($StageDirectory)
$StageRoot = [IO.Path]::GetPathRoot($StageDirectory)
if ($StageDirectory.TrimEnd('\').Length -le $StageRoot.TrimEnd('\').Length + 5) {
    throw "Refusing to use an unsafe staging directory: $StageDirectory"
}

$Versions = @{
    OssCad = '2026-07-05'
    OssCadFile = '20260705'
    Sv2v = '0.0.13'
    W64DevKit = '2.8.0'
    Tcl = '8.6.17'
    Bawt = '3.2.0'
}
$Cache = Join-Path $RepoRoot 'dist\downloads'

function Get-Download([string]$Url, [string]$Destination) {
    if (Test-Path -LiteralPath $Destination) { return }
    New-Item -ItemType Directory -Force (Split-Path $Destination) | Out-Null
    Write-Host "Downloading $(Split-Path $Destination -Leaf)..."
    & curl.exe -L --fail --retry 3 --output $Destination $Url
    if ($LASTEXITCODE -ne 0) { throw "Download failed: $Url" }
}

function Copy-Directory([string]$Source, [string]$Destination) {
    New-Item -ItemType Directory -Force $Destination | Out-Null
    Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force
}

function Copy-FileToDirectory([string]$SourceFile, [string]$DestinationDirectory) {
    if (-not (Test-Path -LiteralPath $SourceFile)) {
        throw "Required file was not found: $SourceFile"
    }
    New-Item -ItemType Directory -Force $DestinationDirectory | Out-Null
    Copy-Item -LiteralPath $SourceFile -Destination $DestinationDirectory -Force
}

function Copy-OssCadRuntime([string]$Source, [string]$Destination) {
    New-Item -ItemType Directory -Force $Destination | Out-Null

    $BinDestination = Join-Path $Destination 'bin'
    New-Item -ItemType Directory -Force $BinDestination | Out-Null
    Get-ChildItem (Join-Path $Source 'bin') -File -Filter '*.dll' |
        Copy-Item -Destination $BinDestination -Force
    foreach ($name in @('iverilog.exe', 'vvp.exe', 'yosys.exe', 'yosys-abc.exe')) {
        Copy-FileToDirectory (Join-Path $Source "bin\$name") $BinDestination
    }

    $LibSource = Join-Path $Source 'lib'
    $LibDestination = Join-Path $Destination 'lib'
    New-Item -ItemType Directory -Force $LibDestination | Out-Null
    foreach ($name in @('python3.exe', 'python3.11.exe')) {
        $file = Join-Path $LibSource $name
        if (Test-Path -LiteralPath $file) {
            Copy-Item -LiteralPath $file -Destination $LibDestination -Force
        }
    }
    Get-ChildItem $LibSource -File -Filter '*.dll' |
        Copy-Item -Destination $LibDestination -Force

    Copy-Directory (Join-Path $LibSource 'ivl') (Join-Path $LibDestination 'ivl')
    Copy-Directory (Join-Path $LibSource 'python3.11') (Join-Path $LibDestination 'python3.11')
    foreach ($name in @('site-packages', 'test', 'idlelib', 'ensurepip')) {
        Remove-StageItem (Join-Path $LibDestination "python3.11\$name")
    }
    Get-ChildItem (Join-Path $LibDestination 'python3.11') -Recurse -Directory -Filter '__pycache__' |
        ForEach-Object { Remove-StageItem $_.FullName }

    Copy-Directory (Join-Path $Source 'share\yosys') (Join-Path $Destination 'share\yosys')
}

function Remove-StageItem([string]$Path) {
    $FullPath = [IO.Path]::GetFullPath($Path)
    if (-not $FullPath.StartsWith($StageDirectory, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a path outside staging: $FullPath"
    }
    if (Test-Path -LiteralPath $FullPath) {
        Remove-Item -LiteralPath $FullPath -Recurse -Force
    }
}

function Remove-CacheItem([string]$Path) {
    $FullPath = [IO.Path]::GetFullPath($Path)
    $CacheRoot = [IO.Path]::GetFullPath($Cache)
    if (-not $FullPath.StartsWith($CacheRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a path outside download cache: $FullPath"
    }
    if (Test-Path -LiteralPath $FullPath) {
        Remove-Item -LiteralPath $FullPath -Recurse -Force
    }
}

function Reduce-OssCadRuntime([string]$Root) {
    foreach ($name in @('examples', 'include')) {
        Remove-StageItem (Join-Path $Root $name)
    }

    $RequiredBins = @('iverilog.exe', 'vvp.exe', 'yosys.exe', 'yosys-abc.exe')
    Get-ChildItem (Join-Path $Root 'bin') -File |
        Where-Object { $_.Extension -ne '.dll' -and $_.Name -notin $RequiredBins } |
        Remove-Item -Force

    $Lib = Join-Path $Root 'lib'
    Get-ChildItem $Lib -Directory |
        Where-Object { $_.Name -notin @('ivl', 'python3.11') } |
        ForEach-Object { Remove-StageItem $_.FullName }
    Get-ChildItem $Lib -File |
        Where-Object { $_.Extension -ne '.dll' -and $_.Name -notin @('python3.exe', 'python3.11.exe') } |
        Remove-Item -Force
    Remove-StageItem (Join-Path $Lib 'python3.11\site-packages')
    Remove-StageItem (Join-Path $Lib 'python3.11\test')
    Remove-StageItem (Join-Path $Lib 'python3.11\idlelib')
    Remove-StageItem (Join-Path $Lib 'python3.11\ensurepip')
    Get-ChildItem (Join-Path $Lib 'python3.11') -Recurse -Directory -Filter '__pycache__' |
        ForEach-Object { Remove-StageItem $_.FullName }

    $Share = Join-Path $Root 'share'
    Get-ChildItem $Share -Directory |
        Where-Object { $_.Name -ne 'yosys' } |
        ForEach-Object { Remove-StageItem $_.FullName }
}

if (Test-Path -LiteralPath $StageDirectory) {
    Remove-Item -LiteralPath $StageDirectory -Recurse -Force
}
New-Item -ItemType Directory -Force $StageDirectory | Out-Null

foreach ($name in @('src', 'assets', 'sample')) {
    Copy-Item -LiteralPath (Join-Path $RepoRoot $name) -Destination $StageDirectory -Recurse
}
Copy-Item -LiteralPath (Join-Path $RepoRoot 'README.md') -Destination $StageDirectory
Copy-Item -LiteralPath (Join-Path $RepoRoot 'EXPLICACAO_PROJETO.md') -Destination $StageDirectory
Copy-Item -LiteralPath (Join-Path $RepoRoot 'INSTALL.md') -Destination $StageDirectory
Copy-Item -LiteralPath (Join-Path $RepoRoot 'packaging\THIRD_PARTY.md') -Destination $StageDirectory
Get-ChildItem $StageDirectory -Recurse -Directory -Filter '__pycache__' | Remove-Item -Recurse -Force
Get-ChildItem $StageDirectory -Recurse -File -Filter '*.pyc' | Remove-Item -Force

# Tcl/Tk is installed into staging once, then embedded in the final installer.
$TclDestination = Join-Path $StageDirectory 'runtime\tcl'
$LocalTcl = 'D:\RTL_EXP_tools\downloads\tcl-test'
if ($ReuseLocalTools -and (Test-Path -LiteralPath (Join-Path $LocalTcl 'bin\wish86.exe'))) {
    Copy-Directory $LocalTcl $TclDestination
} else {
    $TclInstaller = Join-Path $Cache "SetupTcl-$($Versions.Tcl)-x64_Bawt-$($Versions.Bawt).exe"
    Get-Download "https://www.bawt.tcl3d.org/download/Tcl-Pure/SetupTcl-$($Versions.Tcl)-x64_Bawt-$($Versions.Bawt).exe" $TclInstaller
    New-Item -ItemType Directory -Force (Split-Path $TclDestination) | Out-Null
    $process = Start-Process -FilePath $TclInstaller -Wait -PassThru -ArgumentList @(
        '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=`"$TclDestination`""
    )
    if ($process.ExitCode -ne 0) {
        if (Test-Path -LiteralPath (Join-Path $LocalTcl 'bin\wish86.exe')) {
            Write-Warning "Tcl/Tk installer failed with code $($process.ExitCode). Reusing local Tcl/Tk runtime."
            Remove-StageItem $TclDestination
            Copy-Directory $LocalTcl $TclDestination
        } else {
            throw "Tcl/Tk staging failed with code $($process.ExitCode)."
        }
    }
}
Get-ChildItem $TclDestination -Filter 'unins*' -File | Remove-Item -Force
Remove-StageItem (Join-Path $TclDestination 'include')
Remove-StageItem (Join-Path $TclDestination 'doc')

$ToolsDestination = Join-Path $StageDirectory 'tools'
New-Item -ItemType Directory -Force $ToolsDestination | Out-Null

$LocalOss = 'D:\RTL_EXP_tools\oss-cad-suite\oss-cad-suite'
$OssDestination = Join-Path $ToolsDestination 'oss-cad-suite'
if ($ReuseLocalTools -and (Test-Path -LiteralPath (Join-Path $LocalOss 'bin\yosys.exe'))) {
    Copy-Directory $LocalOss $OssDestination
} else {
    $OssInstaller = Join-Path $Cache "oss-cad-suite-windows-x64-$($Versions.OssCadFile).exe"
    $OssExtract = Join-Path $Cache "oss-cad-suite-$($Versions.OssCadFile)"
    $OssPayload = Join-Path $OssExtract 'oss-cad-suite'
    Get-Download "https://github.com/YosysHQ/oss-cad-suite-build/releases/download/$($Versions.OssCad)/oss-cad-suite-windows-x64-$($Versions.OssCadFile).exe" $OssInstaller
    if ((Test-Path -LiteralPath (Join-Path $OssPayload 'bin\yosys.exe')) -and
        -not (Test-Path -LiteralPath (Join-Path $OssPayload 'lib\libstdc++-6.dll'))) {
        Write-Warning 'Cached OSS CAD Suite extraction is incomplete. Re-extracting it.'
        Remove-CacheItem $OssExtract
    }
    if (-not (Test-Path -LiteralPath (Join-Path $OssPayload 'bin\yosys.exe'))) {
        New-Item -ItemType Directory -Force $OssExtract | Out-Null
        $process = Start-Process -FilePath $OssInstaller -Wait -PassThru -ArgumentList @('-y', "-o$OssExtract")
        $YosysAfterExtract = Join-Path $OssPayload 'bin\yosys.exe'
        if ($process.ExitCode -ne 0 -and -not (Test-Path -LiteralPath $YosysAfterExtract)) {
            throw "OSS CAD Suite extraction failed with code $($process.ExitCode)."
        } elseif ($process.ExitCode -ne 0) {
            Write-Warning "OSS CAD Suite extractor returned code $($process.ExitCode), but yosys.exe was extracted. Continuing."
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $OssPayload 'lib\libstdc++-6.dll'))) {
        throw 'OSS CAD Suite extraction is incomplete: lib\libstdc++-6.dll is missing.'
    }
    Copy-OssCadRuntime $OssPayload $OssDestination
}
Reduce-OssCadRuntime $OssDestination

$LocalCompiler = 'D:\RTL_EXP_tools\w64devkit\w64devkit'
$CompilerDestination = Join-Path $ToolsDestination 'w64devkit'
if ($ReuseLocalTools -and (Test-Path -LiteralPath (Join-Path $LocalCompiler 'bin\g++.exe'))) {
    Copy-Directory $LocalCompiler $CompilerDestination
} else {
    $CompilerArchive = Join-Path $Cache "w64devkit-x64-$($Versions.W64DevKit).7z.exe"
    $CompilerExtract = Join-Path $Cache "w64devkit-$($Versions.W64DevKit)"
    Get-Download "https://github.com/skeeto/w64devkit/releases/download/v$($Versions.W64DevKit)/w64devkit-x64-$($Versions.W64DevKit).7z.exe" $CompilerArchive
    if (-not (Test-Path -LiteralPath (Join-Path $CompilerExtract 'w64devkit\bin\g++.exe'))) {
        New-Item -ItemType Directory -Force $CompilerExtract | Out-Null
        $process = Start-Process -FilePath $CompilerArchive -Wait -PassThru -ArgumentList @('-y', "-o$CompilerExtract")
        if ($process.ExitCode -ne 0) { throw "w64devkit extraction failed." }
    }
    Copy-Directory (Join-Path $CompilerExtract 'w64devkit') $CompilerDestination
}
Remove-StageItem (Join-Path $CompilerDestination 'src')

$Sv2vArchive = Join-Path $Cache "sv2v-Windows-$($Versions.Sv2v).zip"
$Sv2vExtract = Join-Path $Cache "sv2v-Windows-$($Versions.Sv2v)"
Get-Download "https://github.com/zachjs/sv2v/releases/download/v$($Versions.Sv2v)/sv2v-Windows.zip" $Sv2vArchive
if (-not (Test-Path -LiteralPath $Sv2vExtract)) {
    Expand-Archive -LiteralPath $Sv2vArchive -DestinationPath $Sv2vExtract
}
$Sv2vExecutable = Get-ChildItem $Sv2vExtract -Recurse -Filter sv2v.exe | Select-Object -First 1
if (-not $Sv2vExecutable) { throw 'sv2v.exe was not found in its release archive.' }
$Sv2vDestination = Join-Path $ToolsDestination 'sv2v'
New-Item -ItemType Directory -Force $Sv2vDestination | Out-Null
Copy-Item -LiteralPath $Sv2vExecutable.FullName -Destination $Sv2vDestination -Force

$Required = @(
    'runtime\tcl\bin\wish86.exe',
    'tools\oss-cad-suite\bin\yosys.exe',
    'tools\oss-cad-suite\bin\iverilog.exe',
    'tools\oss-cad-suite\bin\vvp.exe',
    'tools\w64devkit\bin\g++.exe',
    'tools\sv2v\sv2v.exe'
)
foreach ($path in $Required) {
    if (-not (Test-Path -LiteralPath (Join-Path $StageDirectory $path))) {
        throw "Incomplete Windows runtime: $path is missing."
    }
}

$OldPath = $env:PATH
$OssRoot = Join-Path $StageDirectory 'tools\oss-cad-suite'
try {
    $env:PATH = "$(Join-Path $OssRoot 'lib');$(Join-Path $OssRoot 'bin');$OldPath"
    $YosysCheck = & (Join-Path $OssRoot 'bin\yosys.exe') -V 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Staged yosys.exe failed to start: $YosysCheck"
    }
} finally {
    $env:PATH = $OldPath
}
Write-Host "Windows runtime staged at $StageDirectory"
