param(
    [string]$FlutterBin = "C:\src\flutter\bin\flutter.bat",
    [switch]$Windows = $true,
    [switch]$Android = $true,
    [string]$ReleaseTag = ""
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

if (-not (Test-Path $FlutterBin)) {
    $cmd = Get-Command flutter -ErrorAction SilentlyContinue
    if ($cmd) {
        $FlutterBin = $cmd.Source
    } else {
        throw "Flutter SDK не найден. Установите Flutter в C:\src\flutter или передайте -FlutterBin."
    }
}

$DistDir = Join-Path $RootDir "dist"
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

Write-Host ">> Установка зависимостей и проверка кода..." -ForegroundColor Cyan
& $FlutterBin pub get
& $FlutterBin analyze
& $FlutterBin test

if ($Windows) {
    Write-Host ">> Сборка Windows x64 Release..." -ForegroundColor Cyan
    & $FlutterBin build windows --release
    Write-Host ">> Сборка однофайлового лаунчера..." -ForegroundColor Cyan
    & cmake -S windows/onefile -B build/onefile -A x64
    & cmake --build build/onefile --config Release
    $WinExe = Join-Path $DistDir "Taler-Windows-x64.exe"
    & (Join-Path $PSScriptRoot "pack_onefile.ps1") -SourceDir (Join-Path $RootDir "build\windows\x64\runner\Release") -Launcher (Join-Path $RootDir "build\onefile\Release\launcher.exe") -Output $WinExe
    Write-Host ">> Готово: $WinExe" -ForegroundColor Green
}

if ($Android) {
    Write-Host ">> Сборка Android APK (split-per-abi)..." -ForegroundColor Cyan
    & $FlutterBin build apk --release --split-per-abi
    $ApkDir = Join-Path $RootDir "build\app\outputs\flutter-apk"
    $Arm64 = Join-Path $ApkDir "app-arm64-v8a-release.apk"
    $Arm32 = Join-Path $ApkDir "app-armeabi-v7a-release.apk"
    if (Test-Path $Arm64) {
        Copy-Item $Arm64 (Join-Path $DistDir "Taler-Android-arm64-v8a.apk") -Force
    }
    if (Test-Path $Arm32) {
        Copy-Item $Arm32 (Join-Path $DistDir "Taler-Android-armeabi-v7a.apk") -Force
    }
    Write-Host ">> Готовы APK в $DistDir" -ForegroundColor Green
}

if ($ReleaseTag -ne "") {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "GitHub CLI (gh) не найден для публикации релиза."
    }
    $files = Get-ChildItem -Path $DistDir -File | Select-Object -ExpandProperty FullName
    if ($files.Count -eq 0) {
        throw "В папке $DistDir нет собранных файлов."
    }
    Write-Host ">> Публикация релиза $ReleaseTag в grentu/Taler..." -ForegroundColor Cyan
    & gh release create $ReleaseTag @files --repo grentu/Taler --title "Taler $ReleaseTag" --generate-notes
}
