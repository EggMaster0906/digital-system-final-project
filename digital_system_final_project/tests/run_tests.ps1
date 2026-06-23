[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$sources = @(
    (Join-Path $projectRoot 'digital_system_final_project.v'),
    (Join-Path $projectRoot 'clock_divider.v'),
    (Join-Path $projectRoot 'button_conditioner.v'),
    (Join-Path $projectRoot 'configuration_controller.v'),
    (Join-Path $projectRoot 'traffic_controller.v'),
    (Join-Path $projectRoot 'countdown_display.v'),
    (Join-Path $projectRoot 'seven_seg_decoder.v'),
    (Join-Path $projectRoot 'lcd_controller.v')
)

$tests = @(
    @{ Top = 'traffic_controller_tb'; File = 'traffic_controller_tb.v' },
    @{ Top = 'night_mode_tb'; File = 'night_mode_tb.v' },
    @{ Top = 'fault_mode_tb'; File = 'fault_mode_tb.v' },
    @{ Top = 'configuration_controller_tb'; File = 'configuration_controller_tb.v' },
    @{ Top = 'system_settings_mode_tb'; File = 'system_settings_mode_tb.v' },
    @{ Top = 'countdown_display_tb'; File = 'countdown_display_tb.v' },
    @{ Top = 'lcd_controller_tb'; File = 'lcd_controller_tb.v' }
)

foreach ($test in $tests) {
    $output = Join-Path $env:TEMP ($test.Top + '.vvp')
    try {
        Write-Host "=== Test $($test.Top) ==="
        & iverilog -g2012 -Wall -s $test.Top -o $output @sources (Join-Path $PSScriptRoot $test.File)
        if ($LASTEXITCODE -ne 0) {
            throw "iVerilog compilation failed with exit code $LASTEXITCODE."
        }

        $simulationOutput = & vvp $output
        $simulationOutput | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) {
            throw "Simulation failed with exit code $LASTEXITCODE."
        }
        if (($simulationOutput -join "`n") -notmatch '(?m)^PASS:') {
            throw 'Simulation completed without a PASS result.'
        }
        if (($simulationOutput -join "`n") -match '(?m)^FAIL:') {
            throw 'Simulation reported one or more failures.'
        }
    } finally {
        Remove-Item -LiteralPath $output -Force -ErrorAction SilentlyContinue
    }
}

Write-Host 'All tests passed.'
