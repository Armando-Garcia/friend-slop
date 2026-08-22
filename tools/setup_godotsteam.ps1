# Installs GodotSteam GDExtension for FriendSlop (Godot 4.6.x).
# Run from repo root: powershell -ExecutionPolicy Bypass -File tools/setup_godotsteam.ps1

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$VersionsFile = Join-Path $Root "tools\versions.env"
$Cache = Join-Path $Root ".cache\steam-setup"
$AddonsDir = Join-Path $Root "addons\godotsteam"
$Gde = Join-Path $AddonsDir "godotsteam.gdextension"
$GdeDisabled = Join-Path $AddonsDir "godotsteam.gdextension.disabled"
$EditorPanel = Join-Path $AddonsDir "editor\steamworks_panel.tscn"

function Test-GodotSteamComplete {
	$hasManifest = (Test-Path $Gde) -or (Test-Path $GdeDisabled)
	$hasPanel = Test-Path $EditorPanel
	$hasWin = Test-Path (Join-Path $AddonsDir "win64\libgodotsteam.windows.template_debug.x86_64.dll")
	$hasLinux = Test-Path (Join-Path $AddonsDir "linux64\libgodotsteam.linux.template_debug.x86_64.so")
	return ($hasManifest -and $hasPanel -and $hasWin -and $hasLinux)
}

function Read-VersionEnv([string]$Key) {
	foreach ($line in Get-Content $VersionsFile) {
		$trimmed = $line.Trim()
		if ($trimmed -eq "" -or $trimmed.StartsWith("#") -or -not $trimmed.Contains("=")) { continue }
		$parts = $trimmed.Split("=", 2)
		if ($parts[0].Trim() -eq $Key) { return $parts[1].Trim() }
	}
	return ""
}

$ReleaseTag = Read-VersionEnv "GODOTSTEAM_GDE_RELEASE_TAG"
$ZipName = Read-VersionEnv "GODOTSTEAM_GDE_ZIP"
$Version = Read-VersionEnv "GODOTSTEAM_VERSION"
if ($ReleaseTag -eq "" -or $ZipName -eq "") {
	Write-Error "GODOTSTEAM_GDE_RELEASE_TAG or GODOTSTEAM_GDE_ZIP missing from tools/versions.env"
}

$Url = "https://codeberg.org/godotsteam/godotsteam/releases/download/$ReleaseTag/$ZipName"
New-Item -ItemType Directory -Force -Path $Cache, (Split-Path $AddonsDir) | Out-Null

if (Test-GodotSteamComplete) {
	Write-Host "GodotSteam already installed at $AddonsDir"
} else {
	if (Test-Path $AddonsDir) {
		Write-Host "GodotSteam install incomplete (missing editor panel or libs); reinstalling ..."
	}
	$ZipPath = Join-Path $Cache $ZipName
	if (-not (Test-Path $ZipPath)) {
		Write-Host "Downloading $Url ..."
		Invoke-WebRequest -Uri $Url -OutFile $ZipPath -UseBasicParsing
	} else {
		Write-Host "Using cached $ZipName"
	}

	$TempExtract = Join-Path $env:TEMP ("godotsteam-extract-" + [guid]::NewGuid().ToString())
	New-Item -ItemType Directory -Force -Path $TempExtract | Out-Null
	try {
		Expand-Archive -Force -Path $ZipPath -DestinationPath $TempExtract
		$Source = Join-Path $TempExtract "addons\godotsteam"
		if (-not (Test-Path $Source)) {
			if (Test-Path (Join-Path $TempExtract "godotsteam.gdextension")) {
				$Source = $TempExtract
			} else {
				Write-Error "Could not find godotsteam.gdextension in $ZipName"
			}
		}
		if (Test-Path $AddonsDir) { Remove-Item -Recurse -Force $AddonsDir }
		Copy-Item -Recurse -Force $Source $AddonsDir
		Write-Host "GodotSteam installed to $AddonsDir"
	} finally {
		Remove-Item -Recurse -Force $TempExtract -ErrorAction SilentlyContinue
	}
}

$LinuxLib = Join-Path $AddonsDir "linux64\libgodotsteam.linux.template_debug.x86_64.so"
$WindowsLib = Join-Path $AddonsDir "win64\libgodotsteam.windows.template_debug.x86_64.dll"
$AppId = Join-Path $Root "steam_appid.txt"

if (-not (Test-Path $LinuxLib)) {
	Write-Error "GodotSteam Linux x86_64 libraries missing at $LinuxLib"
}
if (-not (Test-Path $WindowsLib)) {
	Write-Error "GodotSteam Windows x86_64 libraries missing at $WindowsLib"
}
if (-not (Test-Path $AppId)) {
	Write-Error "steam_appid.txt missing at repo root"
}

Write-Host ""
Write-Host "Done. GodotSteam $Version ready (GDExtension $ReleaseTag)."
Write-Host "Fully quit Godot, reopen the project, then host/join from the menu lobby."
