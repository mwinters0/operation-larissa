<#
.SYNOPSIS
Operation Larissa on Windows, from a fresh clone to playing: asks for your copy of the game, checks it, installs every tool,
builds the legacy pack and starts the game.

.DESCRIPTION
Run it from anywhere; it works on the repository it is in. Every step is skipped when its result is already there, so a second
run only does what is missing.

  1. Your CD image: -Iso, else a file dialog. It is checked against the reference release (tools/import/source_files.py)
     before anything is installed, and remembered as the user variable NEP_ISO.
  2. mise (winget jdx.mise), then uv (mise install uv).
  3. FFmpeg (winget Gyan.FFmpeg: its builds have the libvorbis encoder).
  4. FluidSynth: the win10-x64 zip of its latest GitHub release, checked against the SHA-256 GitHub publishes for it,
     unpacked into %LOCALAPPDATA%\Programs\FluidSynth and put on your user PATH.
  5. Godot: mise's install of the pinned version; when mise cannot install it, the official Windows build of that version
     from GitHub (checked the same way) into %LOCALAPPDATA%\Programs\Godot, named by the user variable GODOT_BIN.
  6. mise run setup: the Python environment, the godot-sandbox extension and the General MIDI soundfont.
  7. mise run legacy:checktools, then mise run legacy:import (about 10 minutes, plus a 480 MB speech model the first time).
  8. mise run godot:play legacy, unless -NoPlay.

Windows PowerShell 5.1 and PowerShell 7 both run it. Windows keeps a downloaded script from running; start it with:

    powershell -ExecutionPolicy Bypass -File tools\setup_windows.ps1

docs/SETUP.md, "On Windows", says what each tool is for and what differs from Linux.

.PARAMETER Iso
The path of your CD image of Operation Neptune (the 1998 Windows CD-ROM release). Without it the script asks.

.PARAMETER NoPlay
Stop after building the legacy pack instead of starting the game.
#>
[CmdletBinding()]
param(
    [string]$Iso,
    [switch]$NoPlay
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"          # Invoke-WebRequest is many times slower while it draws its progress bar
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$Root = Split-Path -Parent $PSScriptRoot
$Programs = Join-Path $env:LOCALAPPDATA "Programs"
Set-Location $Root

function Write-Step([string]$text) { Write-Host ""; Write-Host "==> $text" -ForegroundColor Cyan }
function Write-Done([string]$text) { Write-Host "    $text" -ForegroundColor Green }
function Stop-Setup([string]$text) { Write-Host ""; Write-Host "SETUP STOPPED: $text" -ForegroundColor Red; exit 1 }

function Update-SessionPath {
    # A program winget or this script just installed is on the user PATH, which a running PowerShell does not re-read.
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ";"
}

function Add-UserPath([string]$folder) {
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    $parts = @()
    if ($user) { $parts = $user -split ";" | Where-Object { $_ } }
    if ($parts -notcontains $folder) {
        [Environment]::SetEnvironmentVariable("Path", (($parts + $folder) -join ";"), "User")
    }
    Update-SessionPath
}

function Set-UserVariable([string]$name, [string]$value) {
    [Environment]::SetEnvironmentVariable($name, $value, "User")
    Set-Item -Path "Env:$name" -Value $value
}

function Invoke-Native([string]$program, [string[]]$arguments) {
    # Runs a program on this console (not through PowerShell's pipeline, which would hide its progress and make Python buffer its
    # output) and returns its exit code.
    $exe = (Get-Command $program -ErrorAction Stop).Source
    $quoted = $arguments | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }
    $process = Start-Process -FilePath $exe -ArgumentList $quoted -NoNewWindow -Wait -PassThru
    return $process.ExitCode
}

function Invoke-Checked([string]$program, [string[]]$arguments) {
    $code = Invoke-Native $program $arguments
    if ($code -ne 0) { Stop-Setup "'$program $($arguments -join ' ')' failed (exit code $code)." }
}

function Invoke-Quiet([scriptblock]$command) {
    # A native command's output, with its failures tolerated: Windows PowerShell 5.1 turns a native program's stderr into errors,
    # which $ErrorActionPreference = "Stop" would make fatal.
    $saved = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { return (& $command 2>&1 | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | Select-Object -Last 1) }
    finally { $ErrorActionPreference = $saved }
}

function Install-Winget([string]$id) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Stop-Setup "winget is missing. Install 'App Installer' from the Microsoft Store, then run this script again."
    }
    $null = Invoke-Native "winget" @("install", "--id", $id, "-e", "--silent", "--accept-package-agreements", "--accept-source-agreements")
    # winget answers non-zero when the package is already installed; what matters is whether the program is there afterwards.
    Update-SessionPath
}

function Get-GitHubAsset([string]$repo, [string]$tag, [string]$pattern) {
    # One asset of a GitHub release ("latest" or a tag) whose name matches $pattern, with the SHA-256 GitHub publishes for it.
    $api = if ($tag -eq "latest") { "https://api.github.com/repos/$repo/releases/latest" } else { "https://api.github.com/repos/$repo/releases/tags/$tag" }
    $release = Invoke-RestMethod -Uri $api -Headers @{ "User-Agent" = "operation-larissa-setup" }
    $asset = $release.assets | Where-Object { $_.name -match $pattern } | Sort-Object { $_.name.Length } | Select-Object -First 1
    if (-not $asset) { Stop-Setup "the $repo release $($release.tag_name) has no file matching '$pattern'." }
    $sha = $null
    if ($asset.PSObject.Properties["digest"] -and $asset.digest -match "^sha256:([0-9a-fA-F]{64})$") { $sha = $Matches[1].ToLower() }
    return [pscustomobject]@{ Name = $asset.name; Url = $asset.browser_download_url; Sha256 = $sha; Tag = $release.tag_name }
}

function Save-Checked($asset, [string]$file) {
    Write-Host "    downloading $($asset.Url)"
    Invoke-WebRequest -Uri $asset.Url -OutFile $file -UseBasicParsing
    $got = (Get-FileHash -Algorithm SHA256 $file).Hash.ToLower()
    if ($asset.Sha256) {
        if ($got -ne $asset.Sha256) {
            Remove-Item $file -Force
            Stop-Setup "$($asset.Name) has SHA-256 $got, but GitHub publishes $($asset.Sha256): not using it."
        }
        Write-Done "SHA-256 matches GitHub's: $got"
    } else {
        Write-Host "    GitHub publishes no SHA-256 for $($asset.Name); downloaded over HTTPS, SHA-256 $got" -ForegroundColor Yellow
    }
}

function Expand-Into([string]$zip, [string]$dest) {
    # Unpack into a fresh folder; an archive with a single top folder is unwrapped so $dest holds its contents.
    $temp = Join-Path ([IO.Path]::GetTempPath()) ("larissa-" + [Guid]::NewGuid().ToString("N"))
    Expand-Archive -Path $zip -DestinationPath $temp -Force
    $top = @(Get-ChildItem $temp)
    $from = if ($top.Count -eq 1 -and $top[0].PSIsContainer) { $top[0].FullName } else { $temp }
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    New-Item -ItemType Directory -Force (Split-Path -Parent $dest) | Out-Null
    Move-Item $from $dest
    if (Test-Path $temp) { Remove-Item $temp -Recurse -Force }
}

if ($env:OS -ne "Windows_NT") { Stop-Setup "this script is for Windows. On Linux follow docs/SETUP.md." }
if (-not (Test-Path (Join-Path $Root "mise.toml"))) { Stop-Setup "run the copy of this script that is in the repository's tools folder." }

# ---- 1. Your copy of the game -------------------------------------------------------------------------------------------------
Write-Step "Your copy of Operation Neptune"
if (-not $Iso -and $env:NEP_ISO -and (Test-Path -LiteralPath $env:NEP_ISO -PathType Leaf)) {
    $answer = Read-Host "    Use $($env:NEP_ISO)? [Y/n]"
    if ($answer -notmatch "^[nN]") { $Iso = $env:NEP_ISO }
}
if (-not $Iso) {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = "Your CD image of Operation Neptune (1998 Windows CD-ROM)"
        $dialog.Filter = "CD images (*.iso)|*.iso|All files (*.*)|*.*"
        $owner = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true }     # keeps the dialog in front of the console
        if ($dialog.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) { $Iso = $dialog.FileName }
        $owner.Dispose()
    } catch {
        $Iso = Read-Host "    Path of your CD image (.iso)"
    }
}
if (-not $Iso) { Stop-Setup "no CD image chosen." }
$Iso = $Iso.Trim('"')
if (-not (Test-Path -LiteralPath $Iso -PathType Leaf)) { Stop-Setup "$Iso is not a file." }
$Iso = (Resolve-Path -LiteralPath $Iso).Path
Write-Done $Iso

# ---- 2. mise and uv -----------------------------------------------------------------------------------------------------------
Write-Step "mise (installs uv and Godot at the versions mise.toml pins)"
if (-not (Get-Command mise -ErrorAction SilentlyContinue)) {
    Install-Winget "jdx.mise"
    if (-not (Get-Command mise -ErrorAction SilentlyContinue)) {
        $found = Get-ChildItem (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages") -Recurse -Filter mise.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $found) { Stop-Setup "mise was installed but cannot be found. Open a new PowerShell window and run this script again." }
        Add-UserPath $found.DirectoryName
    }
}
Write-Done (& mise --version)
Invoke-Checked "mise" @("trust", (Join-Path $Root "mise.toml"))
Invoke-Checked "mise" @("install", "uv")

# ---- 1b. Check the copy before installing anything else -----------------------------------------------------------------------
Write-Step "Checking your copy against the reference release"
$env:NEP_ISO = $Iso
# Only uv (`mise exec uv`), in a throw-away environment with the one package the check reads the image with: nothing else is installed yet.
$code = Invoke-Native "mise" @("exec", "uv", "--", "uv", "run", "--no-project", "--with", "pycdlib>=1.22.0", "tools/import/source_files.py")
if ($code -ne 0) {
    Stop-Setup "$Iso is not the 1998 Windows CD-ROM release the importer is made for (the lines above name the files that differ)."
}
Set-UserVariable "NEP_ISO" $Iso
Write-Done "NEP_ISO = $Iso (kept for later runs)"

# ---- 3. FFmpeg ----------------------------------------------------------------------------------------------------------------
Write-Step "FFmpeg (encodes the music)"
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) { Install-Winget "Gyan.FFmpeg" }
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) { Stop-Setup "FFmpeg was installed but is not on the PATH. Open a new PowerShell window and run this script again." }
Write-Done (Get-Command ffmpeg).Source

# ---- 4. FluidSynth ------------------------------------------------------------------------------------------------------------
Write-Step "FluidSynth (renders the MIDI music)"
if (-not (Get-Command fluidsynth -ErrorAction SilentlyContinue)) {
    $asset = Get-GitHubAsset "FluidSynth/fluidsynth" "latest" "win10-x64.*\.zip$"
    $zip = Join-Path ([IO.Path]::GetTempPath()) $asset.Name
    Save-Checked $asset $zip
    $dest = Join-Path $Programs "FluidSynth"
    Expand-Into $zip $dest
    Remove-Item $zip -Force
    $exe = Get-ChildItem $dest -Recurse -Filter fluidsynth.exe | Select-Object -First 1
    if (-not $exe) { Stop-Setup "the FluidSynth zip $($asset.Name) holds no fluidsynth.exe." }
    Add-UserPath $exe.DirectoryName
    Write-Done "FluidSynth $($asset.Tag) in $($exe.DirectoryName) (on your user PATH)"
} else {
    Write-Done (Get-Command fluidsynth).Source
}

# ---- 5. Godot -----------------------------------------------------------------------------------------------------------------
Write-Step "Godot"
$pin = (Select-String -Path (Join-Path $Root "mise.toml") -Pattern '^godot\s*=\s*"([^"]+)"').Matches[0].Groups[1].Value   # 4.7.2-stable
if ($env:GODOT_BIN -and (Test-Path -LiteralPath $env:GODOT_BIN)) {
    Write-Done "GODOT_BIN = $($env:GODOT_BIN)"
} else {
    Write-Host "    installing Godot $pin through mise (about 100 MB)..."
    $godotDir = Invoke-Quiet { & mise install godot; if ($LASTEXITCODE -eq 0) { & mise where godot } }
    $godotExe = $null
    if ($godotDir -and (Test-Path $godotDir)) {
        $godotExe = Get-ChildItem $godotDir -Recurse -Filter "*.exe" | Where-Object { $_.Name -like "godot*" } | Select-Object -First 1
    }
    if ($godotExe) {
        Write-Done "mise's Godot $pin in $godotDir"
    } else {
        Write-Host "    mise cannot install Godot here; taking the official Windows build of $pin instead" -ForegroundColor Yellow
        $asset = Get-GitHubAsset "godotengine/godot-builds" $pin "_win64\.exe\.zip$"
        $zip = Join-Path ([IO.Path]::GetTempPath()) $asset.Name
        Save-Checked $asset $zip
        $dest = Join-Path $Programs "Godot\$pin"
        Expand-Into $zip $dest
        Remove-Item $zip -Force
        $console = Get-ChildItem $dest -Filter "*_console.exe" | Select-Object -First 1
        if (-not $console) { Stop-Setup "the Godot zip $($asset.Name) holds no _console.exe." }
        Set-UserVariable "GODOT_BIN" $console.FullName
        Set-UserVariable "MISE_DISABLE_TOOLS" "godot"     # so `mise run` does not try to install it again
        Write-Done "GODOT_BIN = $($console.FullName)"
    }
}

# ---- 6. The Python environment, the godot-sandbox extension, the soundfont ----------------------------------------------------
Write-Step "mise run setup (Python environment, godot-sandbox, General MIDI soundfont)"
Invoke-Checked "mise" @("run", "setup")

# ---- 7. Build the legacy pack -------------------------------------------------------------------------------------------------
Write-Step "Checking the importer's tools"
Invoke-Checked "mise" @("run", "legacy:checktools")
Write-Step "Building the legacy pack from your copy (about 10 minutes; the first run also downloads a 480 MB speech model)"
# The speech model is public: Hugging Face's hint to set a token (only for higher rate limits) is noise here.
$env:HF_HUB_VERBOSITY = "error"
Invoke-Checked "mise" @("run", "legacy:import")
Write-Done "the legacy pack is in godot\packs\legacy"

# ---- 8. Play ------------------------------------------------------------------------------------------------------------------
Write-Host ""
Write-Host "Done. To play later:  mise run godot:play legacy      (the editor: mise run godot:editor)" -ForegroundColor Green
if (-not $NoPlay) {
    Write-Step "Starting the game"
    $null = Invoke-Native "mise" @("run", "godot:play", "legacy")
}
