# Downloads the pinned Windows Godot editor into .cache/godot/ (for make test / run_checks).
# Run from repo root: powershell -ExecutionPolicy Bypass -File tools/setup_godot_windows.ps1

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$VersionsFile = Join-Path $Root "tools\versions.env"
$CacheDir = Join-Path $Root ".cache\godot"

function Read-VersionEnv([string]$Key) {
	foreach ($line in Get-Content $VersionsFile) {
		$trimmed = $line.Trim()
		if ($trimmed -eq "" -or $trimmed.StartsWith("#") -or -not $trimmed.Contains("=")) { continue }
		$parts = $trimmed.Split("=", 2)
		if ($parts[0].Trim() -eq $Key) { return $parts[1].Trim() }
	}
	return ""
}

$GodotVersion = Read-VersionEnv "GODOT_VERSION"
if ($GodotVersion -eq "") {
	Write-Error "GODOT_VERSION missing from tools/versions.env"
}

$ZipName = "Godot_v$GodotVersion-stable_win64.exe.zip"
$ExeName = "Godot_v$GodotVersion-stable_win64.exe"
$Url = "https://github.com/godotengine/godot-builds/releases/download/$GodotVersion-stable/$ZipName"
$ZipPath = Join-Path $CacheDir $ZipName
$ExePath = Join-Path $CacheDir $ExeName

New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null

if (Test-Path $ExePath) {
	Write-Host "Using cached Godot binary: $ExePath"
	exit 0
}

if (-not (Test-Path $ZipPath)) {
	Write-Host "Downloading Godot $GodotVersion from $Url ..."
	Invoke-WebRequest -Uri $Url -OutFile $ZipPath -UseBasicParsing
} else {
	Write-Host "Using cached zip: $ZipPath"
}

$TempExtract = Join-Path $CacheDir "extract-tmp"
if (Test-Path $TempExtract) {
	Remove-Item -Recurse -Force $TempExtract
}
New-Item -ItemType Directory -Force -Path $TempExtract | Out-Null
Expand-Archive -Path $ZipPath -DestinationPath $TempExtract -Force

$Extracted = Get-ChildItem -Path $TempExtract -Filter $ExeName -File -Recurse | Select-Object -First 1
if ($null -eq $Extracted) {
	Write-Error "$ExeName not found inside $ZipName"
}

Copy-Item -Path $Extracted.FullName -Destination $ExePath -Force
$ConsoleName = $ExeName -replace "\.exe$", "_console.exe"
$ConsoleExtracted = Get-ChildItem -Path $TempExtract -Filter $ConsoleName -File -Recurse | Select-Object -First 1
if ($null -ne $ConsoleExtracted) {
	Copy-Item -Path $ConsoleExtracted.FullName -Destination (Join-Path $CacheDir $ConsoleName) -Force
}

Remove-Item -Recurse -Force $TempExtract
Write-Host "Installed Godot to $ExePath"
