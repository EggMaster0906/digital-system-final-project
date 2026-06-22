[CmdletBinding()]
param(
    [string]$Cable,
    [string]$QuartusBin
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Find-QuartusBin {
    param([string]$RequestedPath)

    $candidates = @()
    if ($RequestedPath) {
        $candidates += $RequestedPath
    }

    $programmerCommand = Get-Command quartus_pgm.exe -ErrorAction SilentlyContinue
    if ($programmerCommand) {
        $candidates += Split-Path -Parent $programmerCommand.Source
    }

    $candidates += @(
        'C:\altera\13.1\quartus\bin64',
        'C:\altera\13.1\quartus\bin',
        'C:\intelFPGA\13.1\quartus\bin64',
        'C:\intelFPGA_lite\13.1\quartus\bin64'
    )

    foreach ($candidate in $candidates) {
        $quartusPgm = Join-Path $candidate 'quartus_pgm.exe'
        $jtagConfig = Join-Path $candidate 'jtagconfig.exe'
        if ($candidate -and
            (Test-Path -LiteralPath $quartusPgm) -and
            (Test-Path -LiteralPath $jtagConfig)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw 'Quartus Programmer was not found. Pass its bin directory with -QuartusBin.'
}

$resolvedQuartusBin = Find-QuartusBin -RequestedPath $QuartusBin
$quartusPgm = Join-Path $resolvedQuartusBin 'quartus_pgm.exe'
$jtagConfig = Join-Path $resolvedQuartusBin 'jtagconfig.exe'
$projectName = 'digital_system_final_project'
$sofRelativePath = "output_files\$projectName.sof"
$sofPath = Join-Path $PSScriptRoot $sofRelativePath

if (-not (Test-Path -LiteralPath $sofPath)) {
    throw "Programming file not found: $sofPath. Run build.ps1 first."
}

Push-Location $PSScriptRoot
try {
    Write-Host "=== Download $projectName.sof ==="
    Write-Host "Quartus tools: $resolvedQuartusBin"

    # Quartus 13.1 writes connection progress to stderr even when the command
    # succeeds. Temporarily allow native stderr so PowerShell does not turn
    # that informational output into a terminating NativeCommandError.
    $savedErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $jtagOutput = & $jtagConfig 2>&1
        $jtagExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }

    if ($jtagExitCode -ne 0) {
        $jtagOutput | ForEach-Object { Write-Host $_ }
        throw "jtagconfig failed with exit code $jtagExitCode."
    }
    $jtagOutput | ForEach-Object { Write-Host $_ }

    if (($jtagOutput -join "`n") -notmatch 'EP4CE115') {
        throw 'The expected EP4CE115 device was not found in the JTAG chain.'
    }

    if (-not $Cable) {
        $cableNames = @(
            $jtagOutput |
                ForEach-Object {
                    $match = [regex]::Match([string]$_, '^\s*\d+\)\s+(.+)$')
                    if ($match.Success) { $match.Groups[1].Value }
                } |
                Where-Object { $_ -like 'USB-Blaster*' }
        )

        if ($cableNames.Count -eq 0) {
            throw 'No USB-Blaster cable was found.'
        }
        if ($cableNames.Count -gt 1) {
            throw 'Multiple USB-Blaster cables were found. Select one with -Cable.'
        }

        $Cable = $cableNames[0]
    }

    Write-Host "Programming through: $Cable"
    try {
        $ErrorActionPreference = 'Continue'
        & $quartusPgm -c $Cable -m JTAG -o "p;$sofRelativePath@1"
        $programExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }

    if ($programExitCode -ne 0) {
        throw "FPGA programming failed with exit code $programExitCode."
    }

    Write-Host 'Download completed successfully.'
} finally {
    Pop-Location
}
