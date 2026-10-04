<#
.SYNOPSIS
    Publishes the freshly built app and test packages to the dev container and runs every test.

.DESCRIPTION
    Removes any doubt about which build is running:
      1. Publishes the bc-extension and bc-extension-test packages produced by tools\build.ps1 through the dev
         endpoint, so a package with an unchanged version replaces the one already in the container.
      2. Runs all test codeunits of the test app with the AL test runner.
      3. Writes the results to .output\TestResults.xml (full error messages and call stacks) and prints the failures.
    Needs BcContainerHelper and an elevated PowerShell (Docker). Build first with tools\build.ps1.

.PARAMETER ContainerName
    The BC container.

.PARAMETER Credential
    NavUserPassword credential of the container user; prompted when omitted.

.PARAMETER SkipPublish
    Runs the tests against what is already published.
#>
[CmdletBinding()]
param(
    [string] $ContainerName = 'bc29loc',
    [pscredential] $Credential = (Get-Credential -Message "User for $ContainerName"),
    [switch] $SkipPublish
)

$ErrorActionPreference = 'Stop'
Import-Module BcContainerHelper -DisableNameChecking
$repo = Split-Path $PSScriptRoot -Parent

function Get-Package([string] $projectDir) {
    $manifest = Get-Content (Join-Path $projectDir 'app.json') -Raw | ConvertFrom-Json
    $package = Join-Path $projectDir ("{0}_{1}_{2}.app" -f $manifest.publisher, $manifest.name, $manifest.version)
    if (-not (Test-Path $package)) { throw "$package not found. Run tools\build.ps1 first." }
    Write-Host ("{0} built {1}" -f (Split-Path $package -Leaf), (Get-Item $package).LastWriteTime) -ForegroundColor Cyan
    return @{ Path = $package; Id = $manifest.id }
}

$app = Get-Package (Join-Path $repo 'bc-extension')
$test = Get-Package (Join-Path $repo 'bc-extension-test')

if (-not $SkipPublish) {
    foreach ($package in $app, $test) {
        try {
            Publish-BcContainerApp -containerName $ContainerName -credential $Credential -appFile $package.Path -useDevEndpoint -skipVerification
        }
        catch {
            # every compile gets a new package ID, so the same ID means this exact build is already published
            # (for example from VS Code); anything else is a real failure
            if ("$_" -notmatch 'duplicate package ID') { throw }
            Write-Host ("{0} is already published in {1}." -f (Split-Path $package.Path -Leaf), $ContainerName) -ForegroundColor Yellow
        }
    }
}

# the result file must be in a folder shared with the container
$sharedResults = Join-Path $bcContainerHelperConfig.hostHelperFolder "Extensions\$ContainerName\BifTestResults.xml"
Remove-Item $sharedResults -Force -ErrorAction SilentlyContinue
Run-TestsInBcContainer -containerName $ContainerName -credential $Credential -extensionId $test.Id `
    -XUnitResultFileName $sharedResults -detailed | Out-Null

$output = Join-Path $repo '.output'
New-Item -ItemType Directory -Force $output | Out-Null
$results = Join-Path $output 'TestResults.xml'
Copy-Item $sharedResults $results -Force

[xml] $xml = Get-Content $results -Raw
$all = $xml.SelectNodes('//test')
$failed = $xml.SelectNodes("//test[@result='Fail']")
foreach ($node in $failed) {
    Write-Host "`nFAIL $($node.name)" -ForegroundColor Red
    Write-Host $node.failure.message
    Write-Host $node.failure.'stack-trace'
}
Write-Host ("`n{0} tests, {1} failed. Full results: {2}" -f $all.Count, $failed.Count, $results) -ForegroundColor $(if ($failed.Count) { 'Red' } else { 'Green' })
if ($failed.Count) { exit 1 }
