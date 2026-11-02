#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
foreach ($directory in @($root, (Join-Path $root 'api2026gateway'))) {
    foreach ($command in @(
        @('init', '-backend=false', '-input=false', '-lockfile=readonly'),
        @('validate')
    )) {
        & terraform "-chdir=$directory" @command
        if ($LASTEXITCODE -ne 0) { throw "Terraform $($command[0]) failed in $directory." }
    }
}
& terraform "-chdir=$root" fmt -check -recursive
if ($LASTEXITCODE -ne 0) { throw 'Terraform formatting check failed.' }
foreach ($directory in @($root, (Join-Path $root 'api2026gateway'))) {
    & terraform "-chdir=$directory" test
    if ($LASTEXITCODE -ne 0) { throw "Terraform mocked regression tests failed in $directory." }
}
& python -B -m unittest discover -s (Join-Path $root 'tests') -p 'test_*.py'
if ($LASTEXITCODE -ne 0) { throw 'Python regression tests failed.' }
foreach ($path in Get-ChildItem -LiteralPath $root -Filter '*.ps1' -Recurse -File) {
    $tokens = $null
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($path.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "PowerShell parse failure: $($path.Name)" }
}
& (Join-Path $root 'tests\Test-ModelScripts.ps1')
& (Join-Path $root 'tests\Test-CustomerAcceptance.ps1')
& (Join-Path $root 'tests\Test-PortalAcceptance.ps1')
Write-Host 'Offline checks passed. This does not certify Azure deployment, model runtime or portal behavior.'
