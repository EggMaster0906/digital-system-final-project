[CmdletBinding()]
param(
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

    $quartusCommand = Get-Command quartus_sh.exe -ErrorAction SilentlyContinue
    if ($quartusCommand) {
        $candidates += Split-Path -Parent $quartusCommand.Source
    }

    $candidates += @(
        'C:\altera\13.1\quartus\bin64',
        'C:\altera\13.1\quartus\bin',
        'C:\intelFPGA\13.1\quartus\bin64',
        'C:\intelFPGA_lite\13.1\quartus\bin64'
    )

    foreach ($candidate in $candidates) {
        $quartusSh = Join-Path $candidate 'quartus_sh.exe'
        if ($candidate -and (Test-Path -LiteralPath $quartusSh)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw 'Quartus II 13.1 was not found. Pass its bin directory with -QuartusBin.'
}

$resolvedQuartusBin = Find-QuartusBin -RequestedPath $QuartusBin
$quartusSh = Join-Path $resolvedQuartusBin 'quartus_sh.exe'
$projectName = 'digital_system_final_project'
$sofPath = Join-Path $PSScriptRoot "output_files\$projectName.sof"

Push-Location $PSScriptRoot
try {
    Write-Host "=== Build $projectName ==="
    Write-Host "Quartus tools: $resolvedQuartusBin"

    & $quartusSh --flow compile $projectName
    if ($LASTEXITCODE -ne 0) {
        throw "Quartus compilation failed with exit code $LASTEXITCODE."
    }

    if (-not (Test-Path -LiteralPath $sofPath)) {
        throw "Compilation completed without producing $sofPath"
    }

    $sofInfo = Get-Item -LiteralPath $sofPath
    Write-Host "Build completed: $($sofInfo.FullName) ($($sofInfo.Length) bytes)"
} finally {
    Pop-Location
}
