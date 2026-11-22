<#
.SYNOPSIS
    Builds the CurseForge release zip: releases\<AddonName>-<version>.zip

.DESCRIPTION
    Reads the addon name from the .toc file name and the version from its "## Version:" line.
    The zip has one top-level <AddonName>/ folder with only what the game needs: the .toc,
    every file the .toc loads (whole folders for files under a subfolder such as Libs\),
    any of the addon's own media the code references (Interface\AddOns\<AddonName>\...),
    and LICENSE.

    Afterwards it prints this version's section of CHANGELOG.md and copies it to the
    clipboard, and lists the zip's contents.

.PARAMETER Install
    Also copy the addon into the game's AddOns folder (and remove .lua files the .toc no
    longer lists there).

.PARAMETER AddOnsPath
    The game's AddOns folder used by -Install.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\build.ps1
    powershell -ExecutionPolicy Bypass -File .\build.ps1 -Install
#>
param(
    [switch]$Install,
    [string]$AddOnsPath = (Join-Path ${env:ProgramFiles(x86)} 'World of Warcraft\_forever_\Interface\AddOns')
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

# --- Addon name and version from the .toc -----------------------------------------------------

$tocs = @(Get-ChildItem -Path $root -Filter '*.toc' -File)
if ($tocs.Count -ne 1) { throw "Expected exactly one .toc file in $root, found $($tocs.Count)." }
$toc = $tocs[0]
$name = $toc.BaseName
if ((Split-Path $root -Leaf) -ne $name) {
    Write-Warning "Folder name '$(Split-Path $root -Leaf)' doesn't match the .toc name '$name'."
}

$tocLines = Get-Content -Path $toc.FullName -Encoding UTF8
$versionLine = $tocLines | Where-Object { $_ -match '^##\s*Version:\s*(\S+)' } | Select-Object -First 1
if (-not $versionLine) { throw "No '## Version:' line in $($toc.Name)." }
$null = $versionLine -match '^##\s*Version:\s*(\S+)'
$version = $Matches[1]

# --- Files the game needs -----------------------------------------------------------------------

# Relative paths with forward slashes, in a stable order, no duplicates.
$files = New-Object 'System.Collections.Generic.List[string]'
function Add-File([string]$rel) {
    $rel = $rel.Replace('\', '/').TrimStart('/')
    if (-not $files.Contains($rel)) { $files.Add($rel) }
}
function Add-Path([string]$rel) {
    $full = Join-Path $root $rel
    if (Test-Path -LiteralPath $full -PathType Container) {
        Get-ChildItem -LiteralPath $full -Recurse -File | Sort-Object FullName | ForEach-Object {
            Add-File $_.FullName.Substring($root.Length + 1)
        }
    } elseif (Test-Path -LiteralPath $full -PathType Leaf) {
        Add-File $rel
    } else {
        throw "The .toc or code refers to '$rel', which doesn't exist."
    }
}

Add-File $toc.Name
$loaded = $tocLines | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }
foreach ($entry in $loaded) {
    $entry = $entry.Replace('/', '\')
    $top = $entry.Split('\')[0]
    if ($entry.Contains('\')) {
        Add-Path $top   # e.g. Libs\Foo\Foo.xml -> the whole Libs folder
    } else {
        Add-Path $entry
    }
}

# Media the code points at inside the addon folder, e.g. "Interface\AddOns\<name>\media\icon.tga".
$codeFiles = $files | Where-Object { $_ -match '\.(lua|xml)$' }
$mediaPattern = 'Interface[\\/]+AddOns[\\/]+' + [regex]::Escape($name) + '[\\/]+([^"'']+)'
foreach ($rel in $codeFiles) {
    $text = Get-Content -LiteralPath (Join-Path $root $rel) -Raw -Encoding UTF8
    foreach ($m in [regex]::Matches($text, $mediaPattern)) {
        $path = $m.Groups[1].Value -replace '\\\\', '\'
        $candidates = @($path, "$path.tga", "$path.blp", "$path.png")
        $found = $candidates | Where-Object { Test-Path -LiteralPath (Join-Path $root $_) } | Select-Object -First 1
        if ($found) { Add-Path $found } else { Write-Warning "$rel references missing media: $path" }
    }
}

if (Test-Path (Join-Path $root 'LICENSE')) { Add-File 'LICENSE' } else { Write-Warning 'No LICENSE file.' }

# A real line break inside a "..." string stops the game loading the file; catch it here.
foreach ($rel in $files | Where-Object { $_ -like '*.lua' }) {
    $n = 0
    foreach ($line in Get-Content -LiteralPath (Join-Path $root $rel) -Encoding UTF8) {
        $n++
        $code = ($line -split '--', 2)[0].Replace('\"', '')
        if ((($code.ToCharArray() | Where-Object { $_ -eq '"' }) | Measure-Object).Count % 2 -ne 0) {
            throw "${rel}:${n}: unbalanced quote (a string may run over a line break): $($line.Trim())"
        }
    }
}

# --- Zip ---------------------------------------------------------------------------------------

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$releases = Join-Path $root 'releases'
New-Item -ItemType Directory -Force -Path $releases | Out-Null
$zipPath = Join-Path $releases "$name-$version.zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($rel in $files) {
        $full = Join-Path $root ($rel.Replace('/', '\'))
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zip, $full, "$name/$rel", [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally {
    $zip.Dispose()
}
Write-Host "Built releases\$name-$version.zip ($($files.Count) files)" -ForegroundColor Green

# --- Contents ----------------------------------------------------------------------------------

$check = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $check.Entries | ForEach-Object { '  {0,8}  {1}' -f $_.Length, $_.FullName } | Write-Host
} finally {
    $check.Dispose()
}

# --- Changelog section -------------------------------------------------------------------------

$changelog = Join-Path $root 'CHANGELOG.md'
if (-not (Test-Path $changelog)) {
    Write-Warning 'No CHANGELOG.md.'
} else {
    $section = New-Object 'System.Collections.Generic.List[string]'
    $inSection = $false
    foreach ($line in Get-Content -LiteralPath $changelog -Encoding UTF8) {
        if ($line -match '^##\s+(\S+)') {
            if ($inSection) { break }
            $inSection = ($Matches[1] -eq $version)
        }
        if ($inSection) { $section.Add($line) }
    }
    if ($section.Count -eq 0) {
        Write-Warning "CHANGELOG.md has no '## $version' section."
    } else {
        $text = ($section -join "`r`n").Trim()
        Write-Host ''
        Write-Host $text
        Set-Clipboard -Value $text
        Write-Host ''
        Write-Host "Changelog for $version copied to the clipboard." -ForegroundColor Green
    }
}

# --- Optional install into the game -------------------------------------------------------------

if ($Install) {
    $dest = Join-Path $AddOnsPath $name
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    foreach ($rel in $files) {
        $target = Join-Path $dest ($rel.Replace('/', '\'))
        New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
        Copy-Item -LiteralPath (Join-Path $root ($rel.Replace('/', '\'))) -Destination $target -Force
    }
    # Remove top-level .lua files the .toc no longer loads (e.g. after a refactor).
    Get-ChildItem -LiteralPath $dest -Filter '*.lua' -File | Where-Object { -not $files.Contains($_.Name) } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName; Write-Host "Removed old $($_.Name)" }
    Write-Host "Installed to $dest" -ForegroundColor Green
}
