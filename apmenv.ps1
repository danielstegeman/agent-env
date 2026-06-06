#!/usr/bin/env pwsh
<#
.SYNOPSIS
    apmenv - Environment manager for APM (Agent Package Manager).
    Manages named profiles of agent/skill configurations and deploys them via apm.

.DESCRIPTION
    Think pyenv/nvm but for agent configurations. Each environment is a named
    apm.yml + .apm/ directory. Activating an environment deploys its packages
    to the current workspace (or globally) using apm install --root.
#>

param(
    [Parameter(Position = 0)]
    [string]$Command,

    [Parameter(Position = 1, ValueFromRemainingArguments)]
    [string[]]$Args
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Config ---
$script:EnvsRoot = Join-Path $env:USERPROFILE '.apm-envs'
$script:ConfigFile = Join-Path $script:EnvsRoot 'config.json'
$script:ActiveOutput = Join-Path $script:EnvsRoot '_active'

function Ensure-EnvsRoot {
    if (-not (Test-Path $script:EnvsRoot)) {
        New-Item -ItemType Directory -Path $script:EnvsRoot -Force | Out-Null
    }
}

function Read-Config {
    $cfg = New-Object PSObject
    $cfg | Add-Member -NotePropertyName 'active'    -NotePropertyValue $null
    $cfg | Add-Member -NotePropertyName 'outputDir' -NotePropertyValue $script:ActiveOutput
    $cfg | Add-Member -NotePropertyName 'targets'   -NotePropertyValue ([string[]]@())
    if (Test-Path $script:ConfigFile) {
        $saved = Get-Content $script:ConfigFile -Raw | ConvertFrom-Json
        $props = $saved.PSObject.Properties.Name
        if ('active'    -in $props -and $saved.active)    { $cfg.active    = $saved.active }
        if ('outputDir' -in $props -and $saved.outputDir) { $cfg.outputDir = $saved.outputDir }
        if ('targets'   -in $props -and $saved.targets)   { $cfg.targets   = [string[]]@($saved.targets) }
    }
    $cfg
}

function Write-Config {
    param([PSCustomObject]$Config)
    $Config | ConvertTo-Json -Depth 4 | Set-Content $script:ConfigFile -Encoding UTF8
}

function Get-EnvPath {
    param([string]$Name)
    Join-Path $script:EnvsRoot $Name
}

function Assert-EnvExists {
    param([string]$Name)
    $path = Get-EnvPath $Name
    if (-not (Test-Path $path)) {
        Write-Error "Environment '$Name' does not exist. Run: apmenv create $Name"
    }
    $path
}

function Assert-ActiveEnv {
    $config = Read-Config
    if (-not $config.active) {
        Write-Error "No active environment. Run: apmenv activate <name>"
    }
    $config.active
}

# --- Commands ---

function Invoke-Create {
    param([string[]]$CmdArgs)
    if (-not $CmdArgs -or $CmdArgs.Count -eq 0) {
        Write-Error "Usage: apmenv create <name> [--from <existing-env>]"
    }

    $name = $CmdArgs[0]
    $from = $null

    for ($i = 1; $i -lt $CmdArgs.Count; $i++) {
        if ($CmdArgs[$i] -eq '--from' -and ($i + 1) -lt $CmdArgs.Count) {
            $from = $CmdArgs[$i + 1]
            $i++
        }
    }

    Ensure-EnvsRoot
    $envPath = Get-EnvPath $name

    if (Test-Path $envPath) {
        Write-Error "Environment '$name' already exists."
    }

    if ($from) {
        $srcPath = Assert-EnvExists $from
        Copy-Item -Path $srcPath -Destination $envPath -Recurse
        Write-Host "Created environment '$name' (cloned from '$from')"
    } else {
        New-Item -ItemType Directory -Path $envPath -Force | Out-Null
        # Initialize a minimal apm.yml
        $manifest = @"
name: $name
version: 1.0.0
dependencies:
  apm: []
  mcp: []
"@
        Set-Content (Join-Path $envPath 'apm.yml') -Value $manifest -Encoding UTF8
        Write-Host "Created environment '$name' at $envPath"
    }
}

function Invoke-List {
    Ensure-EnvsRoot
    $config = Read-Config
    $envs = Get-ChildItem $script:EnvsRoot -Directory -ErrorAction SilentlyContinue

    if (-not $envs) {
        Write-Host "No environments. Run: apmenv create <name>"
        return
    }

    foreach ($env in $envs) {
        if ($env.Name -eq '_active') { continue }
        $marker = if ($config.active -eq $env.Name) { " *" } else { "" }
        $manifest = Join-Path $env.FullName 'apm.yml'
        $pkgCount = 0
        if (Test-Path $manifest) {
            $content = Get-Content $manifest -Raw
            $pkgCount = ([regex]::Matches($content, '^\s+-\s', 'Multiline')).Count
        }
        Write-Host "$($env.Name)$marker  ($pkgCount packages)"
    }
}

function Invoke-Setup {
    param([string[]]$CmdArgs)
    $config = Read-Config
    if (-not $CmdArgs) { $CmdArgs = @() }

    $outputDir = $null
    $targets = @()
    $showCurrent = $true

    for ($i = 0; $i -lt $CmdArgs.Count; $i++) {
        switch ($CmdArgs[$i]) {
            '--output'  { $outputDir = $CmdArgs[++$i]; $showCurrent = $false }
            '--targets' { $targets += ($CmdArgs[++$i] -split ','); $showCurrent = $false }
        }
    }

    if ($showCurrent) {
        Write-Host "Current configuration:"
        Write-Host "  Output directory: $($config.outputDir)"
        $t = if (@($config.targets).Count -gt 0) { $config.targets -join ', ' } else { '(auto-detect)' }
        Write-Host "  Default targets:  $t"
        Write-Host ""
        Write-Host "Usage: apmenv setup --output <dir> --targets copilot,claude,..."
        return
    }

    if ($outputDir) {
        $resolved = [System.IO.Path]::GetFullPath($outputDir)
        $config.outputDir = $resolved
        Write-Host "Output directory set to: $resolved"
    }

    if ($targets.Count -gt 0) {
        $config.targets = $targets
        Write-Host "Default targets set to: $($targets -join ', ')"
    }

    Write-Config $config
}

function Invoke-Activate {
    param([string[]]$CmdArgs)
    if (-not $CmdArgs -or $CmdArgs.Count -eq 0) {
        Write-Error "Usage: apmenv activate <name> [--target copilot,claude,...] [--root <dir>]"
    }

    $name = $CmdArgs[0]
    $envPath = Assert-EnvExists $name
    $targets = @()
    $root = $null

    for ($i = 1; $i -lt $CmdArgs.Count; $i++) {
        switch ($CmdArgs[$i]) {
            '--target' { $targets += $CmdArgs[++$i] }
            '--root'   { $root = $CmdArgs[++$i] }
        }
    }

    # Read persisted config for defaults
    $config = Read-Config
    $config.active = $name

    # Use config defaults if not overridden by flags
    $deployRoot = if ($root) { $root } else { $config.outputDir }
    if ($targets.Count -eq 0 -and @($config.targets).Count -gt 0) {
        $targets = $config.targets
    }

    Write-Config $config

    # Clear and re-populate the output folder
    if (Test-Path $deployRoot) {
        Remove-Item $deployRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $deployRoot -Force | Out-Null

    # Copy the environment's content to output
    Get-ChildItem $envPath | Copy-Item -Destination $deployRoot -Recurse -Force

    # Build apm install args
    $apmArgs = @('install', '--root', $deployRoot)
    if ($targets.Count -gt 0) {
        $apmArgs += '--target', ($targets -join ',')
    }

    Write-Host "Activating environment '$name'..."
    Write-Host "Output folder: $deployRoot"
    if ($targets.Count -gt 0) {
        Write-Host "Targets: $($targets -join ', ')"
    }
    Push-Location $envPath
    try {
        & apm @apmArgs
    } finally {
        Pop-Location
    }

    Write-Host "Environment '$name' is now active."
}

function Invoke-Deactivate {
    $config = Read-Config
    if (-not $config.active) {
        Write-Host "No environment is active."
        return
    }

    $prev = $config.active
    $config.active = $null
    Write-Config $config

    # Clear the output folder
    $outDir = $config.outputDir
    if (Test-Path $outDir) {
        Remove-Item $outDir -Recurse -Force
    }

    Write-Host "Deactivated environment '$prev'. Output folder cleared ($outDir)."
}

function Invoke-Remove {
    param([string[]]$CmdArgs)
    if (-not $CmdArgs -or $CmdArgs.Count -eq 0) {
        Write-Error "Usage: apmenv remove <name>"
    }

    $name = $CmdArgs[0]
    $envPath = Assert-EnvExists $name

    $config = Read-Config
    if ($config.active -eq $name) {
        $config.active = $null
        Write-Config $config
    }

    Remove-Item -Path $envPath -Recurse -Force
    Write-Host "Removed environment '$name'."
}

function Invoke-Install {
    param([string[]]$CmdArgs)
    $active = Assert-ActiveEnv
    $envPath = Get-EnvPath $active

    # PowerShell coerces a bare comma-list (copilot,claude) into an array, then
    # joins it with spaces when binding to [string[]]. Restore commas so apm
    # receives the correct '--target copilot,claude' format.
    $hasTarget = $false
    $apmArgsFinal = @()
    $i = 0
    while ($i -lt $CmdArgs.Count) {
        if ($CmdArgs[$i] -eq '--target' -or $CmdArgs[$i] -eq '-t') {
            $hasTarget = $true
            $apmArgsFinal += '--target'
            $i++
            if ($i -lt $CmdArgs.Count) {
                $apmArgsFinal += $CmdArgs[$i] -replace ' ', ','
                $i++
            }
        } else {
            # Resolve relative paths to absolute before we Push-Location into the env
            $arg = $CmdArgs[$i]
            if ($arg -notmatch '^-' -and (Test-Path $arg -ErrorAction SilentlyContinue)) {
                $arg = (Resolve-Path $arg).Path
            }
            $apmArgsFinal += $arg
            $i++
        }
    }

    if (-not $hasTarget) {
        $config = Read-Config
        if (@($config.targets).Count -gt 0) {
            $apmArgsFinal += '--target'
            $apmArgsFinal += ($config.targets -join ',')
        }
    }

    Write-Host "Installing into environment '$active'..."
    if ($apmArgsFinal -contains '--target') {
        $tIdx = [array]::IndexOf($apmArgsFinal, '--target')
        Write-Host "Targets: $($apmArgsFinal[$tIdx + 1])"
    }
    Push-Location $envPath
    try {
        & apm install @apmArgsFinal
    } finally {
        Pop-Location
    }

    # Auto-deploy to the output folder so changes are immediately visible
    Invoke-Deploy @()
}

function Invoke-Uninstall {
    param([string[]]$CmdArgs)
    $active = Assert-ActiveEnv
    $envPath = Get-EnvPath $active

    # Resolve any relative paths before changing directory
    $resolvedArgs = $CmdArgs | ForEach-Object {
        if ($_ -notmatch '^-' -and (Test-Path $_ -ErrorAction SilentlyContinue)) {
            (Resolve-Path $_).Path
        } else { $_ }
    }
    Push-Location $envPath
    try {
        & apm uninstall @resolvedArgs
    } finally {
        Pop-Location
    }
}

function Invoke-Packages {
    param([string[]]$CmdArgs)
    $active = Assert-ActiveEnv
    $envPath = Get-EnvPath $active

    Push-Location $envPath
    try {
        & apm list @CmdArgs
    } finally {
        Pop-Location
    }
}

function Invoke-Deploy {
    param([string[]]$CmdArgs)
    $active = Assert-ActiveEnv
    $envPath = Get-EnvPath $active

    $targets = @()
    $root = $null
    $CmdArgs = @($CmdArgs)  # ensure array even when called with no args

    for ($i = 0; $i -lt $CmdArgs.Count; $i++) {
        switch ($CmdArgs[$i]) {
            '--target' { $targets += $CmdArgs[++$i] }
            '--root'   { $root = $CmdArgs[++$i] }
        }
    }

    # Read persisted config for defaults
    $config = Read-Config
    $deployRoot = if ($root) { $root } else { $config.outputDir }
    if ($targets.Count -eq 0 -and @($config.targets).Count -gt 0) {
        $targets = $config.targets
    }

    $apmArgs = @('install', '--root', $deployRoot)
    if ($targets.Count -gt 0) {
        $apmArgs += '--target', ($targets -join ',')
    }

    Write-Host "Deploying environment '$active' to $deployRoot..."
    Push-Location $envPath
    try {
        & apm @apmArgs
    } finally {
        Pop-Location
    }
}

function Invoke-Current {
    $config = Read-Config
    if ($config.active) {
        Write-Host $config.active
    } else {
        Write-Host "(none)"
    }
}

function Show-Help {
    Write-Host @"
apmenv - Environment manager for APM

Usage: apmenv <command> [args]

Configuration:
  setup                            Show current config
  setup --output <dir>             Set the output directory
  setup --targets copilot,claude   Set default target platforms

Environment management:
  create <name> [--from <env>]     Create a new environment (optionally clone)
  list                             List all environments (* = active)
  activate <name> [--target ...]   Set active env and deploy via apm install
  deactivate                       Unset the active environment
  remove <name>                    Delete an environment
  current                          Print the active environment name

Package management (operates on active env):
  install <pkg> [apm flags]        apm install into the active environment
  uninstall <pkg>                  apm uninstall from the active environment
  packages                         apm list for the active environment

Deployment:
  deploy [--target ...] [--root .] Re-deploy active env to a workspace/target

Examples:
  apmenv setup --output C:\agent-ctx --targets copilot,claude
  apmenv create web-dev
  apmenv activate web-dev
  apmenv install microsoft/apm-sample-package
  apmenv deploy --target codex --root ./my-project
  apmenv create data-eng --from web-dev
"@
}

# --- Dispatch ---

switch ($Command) {
    'setup'      { Invoke-Setup $Args }
    'create'     { Invoke-Create $Args }
    'list'       { Invoke-List }
    'activate'   { Invoke-Activate $Args }
    'deactivate' { Invoke-Deactivate }
    'remove'     { Invoke-Remove $Args }
    'install'    { Invoke-Install $Args }
    'uninstall'  { Invoke-Uninstall $Args }
    'packages'   { Invoke-Packages $Args }
    'deploy'     { Invoke-Deploy $Args }
    'current'    { Invoke-Current }
    'help'       { Show-Help }
    ''           { Show-Help }
    default      { Write-Error "Unknown command: $Command. Run: apmenv help" }
}
