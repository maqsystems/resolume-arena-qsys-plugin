param(
  [ValidateSet("none", "development", "fix", "minor", "major")]
  [string]$Increment = "development",
  [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"
$pluginName = "ResolumeArena"
$projectRoot = Split-Path -Parent $PSScriptRoot
$infoPath = Join-Path $projectRoot "info.lua"
$sourcePath = Join-Path $projectRoot "plugin.lua"
$compilerPath = Join-Path $PSScriptRoot "PLUGCC.exe"
$outputPath = Join-Path $projectRoot "$pluginName.qplug"

if (-not (Test-Path -LiteralPath $compilerPath)) {
  throw "Compiler not found: $compilerPath"
}


$info = [IO.File]::ReadAllText($infoPath)
$match = [regex]::Match($info, 'Version\s*=\s*"(\d+)\.(\d+)\.(\d+)\.(\d+)"')
if (-not $match.Success) {
  throw "Version was not found in info.lua"
}

$parts = @(
  [int]$match.Groups[1].Value,
  [int]$match.Groups[2].Value,
  [int]$match.Groups[3].Value,
  [int]$match.Groups[4].Value
)

switch ($Increment) {
  "major"       { $parts = @($parts[0] + 1, 0, 0, 0) }
  "minor"       { $parts = @($parts[0], $parts[1] + 1, 0, 0) }
  "fix"         { $parts = @($parts[0], $parts[1], $parts[2] + 1, 0) }
  "development" { $parts[3]++ }
  "none"        { }
}

$buildVersion = $parts -join "."
if ($Increment -ne "none") {
  $updatedInfo = [regex]::Replace(
    $info,
    'Version\s*=\s*"\d+\.\d+\.\d+\.\d+"',
    "Version = `"$buildVersion`"",
    1
  )
  [IO.File]::WriteAllText($infoPath, $updatedInfo, [Text.UTF8Encoding]::new($false))
}

Push-Location $projectRoot
try {
  & $compilerPath $pluginName $sourcePath
  if ($LASTEXITCODE -ne 0) {
    throw "PLUGCC failed with exit code $LASTEXITCODE"
  }
}
finally {
  Pop-Location
}

if (-not (Test-Path -LiteralPath $outputPath)) {
  throw "Expected output was not generated: $outputPath"
}

if (-not $SkipInstall) {
  $documents = [Environment]::GetFolderPath("MyDocuments")
  $installDirectory = Join-Path $documents "QSC\Q-Sys Designer\Plugins\ResolumeArena"
  $installedPlugin = Join-Path $installDirectory "$pluginName.qplug"
  $temporaryPlugin = "$installedPlugin.tmp"

  [void](New-Item -ItemType Directory -Force -Path $installDirectory)
  Copy-Item -LiteralPath $outputPath -Destination $temporaryPlugin -Force
  Move-Item -LiteralPath $temporaryPlugin -Destination $installedPlugin -Force
  Write-Output "Installed: $installedPlugin"
}

Write-Output "Built $pluginName.qplug (Version $buildVersion)"
