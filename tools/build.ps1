<#
.SYNOPSIS
    Compiles the AL app (bc-extension) and its test app (bc-extension-test) with the AL compiler and all four
    Microsoft code analyzers.

.DESCRIPTION
    Mirrors what VS Code does on build, without VS Code:
      1. Refreshes .alpackages from the local BC artifact cache and removes every non-Microsoft package, so a
         previous build of this app can never shadow the source.
      2. Compiles bc-extension/ with CodeCop, UICop, AppSourceCop and PerTenantExtensionCop and the project ruleset.
      3. Copies the freshly built app package into bc-extension-test/.alpackages and compiles the test app the same way.
    Exits non-zero when the compiler reports any error. The bar for this repo is zero errors and zero warnings.

    Only the AL part of the repo is built here; the Rust services build with cargo.

.PARAMETER ArtifactPath
    BC sandbox artifact folder that holds the matching platform and W1 application (see BcContainerHelper's
    artifact cache).

.PARAMETER AlExtensionPath
    Folder of the installed AL Language extension (its bin folder holds alc.dll and the analyzers).

.PARAMETER DotNetPath
    dotnet.exe of a .NET 10 runtime; the AL 18 compiler needs it.

.PARAMETER Project
    app, test, or all.
#>
[CmdletBinding()]
param(
    [string] $ArtifactPath = 'c:\bcartifacts.cache\sandbox\29.0.54011.55616',
    [string] $AlExtensionPath = (Get-ChildItem "$env:USERPROFILE\.vscode\extensions" -Directory -Filter 'ms-dynamics-smb.al-*' | Sort-Object Name -Descending | Select-Object -First 1).FullName,
    [string] $DotNetPath = (Get-ChildItem "$env:APPDATA\Code\User\globalStorage\ms-dotnettools.vscode-dotnet-runtime\.dotnet" -Directory -Filter '10.*' -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName 'dotnet.exe') } |
        Sort-Object { [version](($_.Name -split '~')[0]) } -Descending |
        Select-Object -First 1 | ForEach-Object { Join-Path $_.FullName 'dotnet.exe' }),
    [ValidateSet('app', 'test', 'all')]
    [string] $Project = 'all'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$appDir = Join-Path $repo 'bc-extension'
$testDir = Join-Path $repo 'bc-extension-test'
$bin = Join-Path $AlExtensionPath 'bin'
$alc = Join-Path $bin 'alc.dll'
$analyzers = 'CodeCop', 'UICop', 'AppSourceCop', 'PerTenantExtensionCop' |
    ForEach-Object { "/analyzer:$(Join-Path $bin "Microsoft.Dynamics.Nav.$_.dll")" }

if (-not $DotNetPath -or -not (Test-Path $DotNetPath)) { throw "No .NET 10 runtime found. Pass -DotNetPath." }
if (-not (Test-Path $alc)) { throw "alc.dll not found under $bin. Pass -AlExtensionPath." }

function Update-Symbols([string] $projectDir) {
    $cache = Join-Path $projectDir '.alpackages'
    New-Item -ItemType Directory -Force $cache | Out-Null
    Get-ChildItem $cache -Filter '*.app' | Where-Object { $_.Name -notlike 'Microsoft_*' -and $_.Name -ne 'System.app' } | Remove-Item -Force
    $major = ((Split-Path $ArtifactPath -Leaf) -split '\.')[0]
    $sources = @(Get-Item (Join-Path $ArtifactPath "platform\ModernDev\PFiles\Microsoft Dynamics NAV\${major}0\AL Development Environment\System.app")) +
        @(Get-ChildItem (Join-Path $ArtifactPath 'w1\Extensions') -Filter '*.app')
    foreach ($source in $sources) {
        $target = Join-Path $cache $source.Name
        if ((Test-Path $target) -and ((Get-Item $target).Length -eq $source.Length)) { continue }
        Copy-Item $source.FullName $target -Force
    }
}

function Invoke-Compile([string] $projectDir) {
    $manifest = Get-Content (Join-Path $projectDir 'app.json') -Raw | ConvertFrom-Json
    $out = Join-Path $projectDir ("{0}_{1}_{2}.app" -f $manifest.publisher, $manifest.name, $manifest.version)
    Write-Host "Compiling $($manifest.name) $($manifest.version)" -ForegroundColor Cyan
    $compilerArgs = @(
        $alc,
        "/project:$projectDir",
        "/packagecachepath:$(Join-Path $projectDir '.alpackages')",
        "/out:$out"
    )
    $ruleset = Join-Path $projectDir 'bif.ruleset.json'
    if (Test-Path $ruleset) { $compilerArgs += "/ruleset:$ruleset" }
    $compilerArgs += $analyzers
    & $DotNetPath @compilerArgs | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Compilation of $($manifest.name) failed." }
    return $out
}

if ($Project -in 'app', 'all') {
    Update-Symbols $appDir
    $appPackage = Invoke-Compile $appDir
}

if ($Project -in 'test', 'all') {
    Update-Symbols $testDir
    if (-not $appPackage) {
        $appPackage = Get-ChildItem $appDir -Filter '*.app' | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
        if (-not $appPackage) { throw "No app package in $appDir. Build the app first (-Project app)." }
    }
    Copy-Item $appPackage (Join-Path $testDir '.alpackages') -Force
    Invoke-Compile $testDir | Out-Null
}
