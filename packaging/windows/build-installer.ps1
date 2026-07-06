[CmdletBinding()]
param(
    [switch]$ReuseLocalTools,
    [switch]$SkipRuntimePreparation,
    [string]$WorkDirectory
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $WorkDirectory) {
    $WorkDirectory = if ($env:RTL_EXPLORER_BUILD_DIR) {
        $env:RTL_EXPLORER_BUILD_DIR
    } else {
        Join-Path $RepoRoot 'dist\windows\work'
    }
}
$Stage = Join-Path ([IO.Path]::GetFullPath($WorkDirectory)) 'stage'
if (-not $SkipRuntimePreparation) {
    & (Join-Path $PSScriptRoot 'prepare-runtime.ps1') -StageDirectory $Stage -ReuseLocalTools:$ReuseLocalTools
}

$Candidates = @(
    (Get-Command ISCC.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 7\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 7\ISCC.exe"
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

if (-not $Candidates) {
    $Installer = Join-Path $RepoRoot 'dist\downloads\innosetup.exe'
    New-Item -ItemType Directory -Force (Split-Path $Installer) | Out-Null
    & curl.exe -L --fail --retry 3 --output $Installer 'https://jrsoftware.org/download.php/is.exe'
    if ($LASTEXITCODE -ne 0) { throw 'Could not download Inno Setup.' }
    $process = Start-Process -FilePath $Installer -Wait -PassThru -ArgumentList @(
        '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CURRENTUSER'
    )
    if ($process.ExitCode -ne 0) { throw 'Could not install Inno Setup.' }
    $Candidates = @(
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 7\ISCC.exe"
    ) | Where-Object { Test-Path -LiteralPath $_ }
}
if (-not $Candidates) { throw 'ISCC.exe was not found.' }
$Iscc = @($Candidates)[0]

$Output = Join-Path $RepoRoot 'dist\windows'
New-Item -ItemType Directory -Force $Output | Out-Null
& $Iscc "/DStageDir=$Stage" "/DOutputDir=$Output" (Join-Path $PSScriptRoot 'rtl-explorer.iss')
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compilation failed.' }
Write-Host "Installer generated at $(Join-Path $Output 'RTL-Explorer-Setup.exe')"
