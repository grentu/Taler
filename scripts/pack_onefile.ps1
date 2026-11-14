<#
  Собирает Taler-Windows-x64.exe: лаунчер (windows/onefile) и релизная папка
  Flutter в одном файле. При первом запуске лаунчер распаковывает приложение в
  %LOCALAPPDATA%\Taler\app-<build id> и запускает taler.exe.
#>
param(
    [string]$SourceDir = "build\windows\x64\runner\Release",
    [string]$Launcher = "build\onefile\Release\launcher.exe",
    [string]$Output = "dist\Taler-Windows-x64.exe"
)

$ErrorActionPreference = "Stop"

$src = (Resolve-Path $SourceDir).Path.TrimEnd('\')
if (-not (Test-Path (Join-Path $src "taler.exe"))) {
    throw "taler.exe not found in $src. Run: flutter build windows --release"
}
if (-not (Test-Path $Launcher)) {
    throw "Launcher not found at $Launcher. Build it with cmake."
}

$outDir = Split-Path -Parent $Output
if ($outDir) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
Copy-Item $Launcher $Output -Force
$outPath = (Resolve-Path $Output).Path

$files = @(Get-ChildItem -Path $src -Recurse -File | Sort-Object FullName)
$utf8 = New-Object System.Text.UTF8Encoding($false)

# Build id меняется вместе с любым файлом, поэтому новая сборка распакуется в новую папку.
$idSource = New-Object System.Text.StringBuilder
foreach ($f in $files) {
    $rel = $f.FullName.Substring($src.Length + 1).Replace('\', '/')
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash
    [void]$idSource.Append("$rel=$hash;")
}
$sha = [System.Security.Cryptography.SHA256]::Create()
$idBytes = $sha.ComputeHash($utf8.GetBytes($idSource.ToString()))
$buildId = [System.BitConverter]::ToUInt64($idBytes, 0)

$stream = [System.IO.File]::Open($outPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write)
try {
    $writer = New-Object System.IO.BinaryWriter($stream)
    $archiveOffset = [uint64]$stream.Position
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($src.Length + 1).Replace('\', '/')
        $pathBytes = $utf8.GetBytes($rel)
        $writer.Write([uint32]$pathBytes.Length)
        $writer.Write([byte[]]$pathBytes)
        $writer.Write([uint64]$f.Length)
        $writer.Flush()
        $in = [System.IO.File]::OpenRead($f.FullName)
        try { $in.CopyTo($stream) } finally { $in.Dispose() }
    }
    $writer.Write([byte[]][System.Text.Encoding]::ASCII.GetBytes("TALERPK1"))
    $writer.Write([uint64]$archiveOffset)
    $writer.Write([uint64]$files.Count)
    $writer.Write([uint64]$buildId)
    $writer.Flush()
} finally {
    $stream.Dispose()
}

$sizeMb = [math]::Round((Get-Item $outPath).Length / 1MB, 1)
Write-Host (">> {0} ({1} MB, files: {2}, build {3:x16})" -f $outPath, $sizeMb, $files.Count, $buildId)
