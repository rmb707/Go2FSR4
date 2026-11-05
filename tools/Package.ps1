#requires -Version 5.1
param([string]$OutputDirectory)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$release=Get-Content (Join-Path $root 'config\release.json') -Raw | ConvertFrom-Json
if($release.version -notmatch '^[0-9A-Za-z][0-9A-Za-z.-]*$'){throw 'Invalid release version.'}
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$dist=if($OutputDirectory){[IO.Path]::GetFullPath($OutputDirectory)}else{Join-Path $root 'dist'}
$exe=Join-Path $dist 'Go2FSR4.exe'
if(!(Test-Path -LiteralPath $exe)){throw 'Run tools/Build.ps1 first.'}
# Explicit public file list: new files require review before they can ship.
$paths=@(
 '.gitignore','.github/workflows/build.yml','.github/FUNDING.yml','LICENSE','README.md','THIRD_PARTY_NOTICES.md',
 'config/device.json','config/official-files.json','config/release.json',
 'src/App.ps1','src/Core.ps1','src/Launcher.cs','src/Lifecycle.ps1','src/Probe.cs',
 'tests/Test.ps1','tools/Build.ps1','tools/Package.ps1','tools/Render-Benchmarks.ps1',
 'tools/Test-Fsr.ps1','tools/Test-Preparation.ps1','tools/Test-Downloads.ps1',
 'vendor/Build-V4-AmdGcfDat.ps1','vendor/Build-V4-Inf.ps1',
 'vendor/LICENSE-LeGo2.txt','vendor/license-source.json',
 'docs/BENCHMARKS.md','docs/benchmark-summary.json','docs/DEVELOPMENT.md',
 'docs/RELEASE-CHECKLIST.md','docs/RELEASE-NOTES.md','docs/SECURITY-AND-RECOVERY.md',
 'docs/VALIDATION.md','docs/images/cod-native-fsr4.png','docs/images/cod-results.png'
)
foreach($relative in $paths){
 $path=Join-Path $root $relative
 $item=Get-Item -LiteralPath $path
 if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Reparse point in public files: $relative"}
 if($relative -match '\.(md|json|ps1|cs|yml)$'){
  $body=[IO.File]::ReadAllText($path)
  $privateMarkers='(?i)C:[/\\]Users[/\\]|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|'+('-----'+'BEGIN '+'[^\r\n]*PRIVATE KEY-----')+'|'+('t3-'+'thread://')+'|'+('Development '+'handoff')
  if($body -match $privateMarkers){
   throw "Private content marker in public file: $relative"
  }
 }
}
$name='Go2FSR4-source-'+$release.version+'.zip'
$destination=Join-Path $dist $name
$temporary=Join-Path $dist ([Guid]::NewGuid().ToString('N')+'.tmp')
$stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew)
$archive=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create)
try {
 foreach($relative in ($paths | Sort-Object)){
  $entry=$archive.CreateEntry('Go2FSR4/'+$relative,[IO.Compression.CompressionLevel]::Optimal)
  $entry.LastWriteTime=[DateTimeOffset]::Parse('2026-01-01T00:00:00Z')
  $input=[IO.File]::OpenRead((Join-Path $root $relative)); $output=$entry.Open()
  try{$input.CopyTo($output)}finally{$input.Dispose();$output.Dispose()}
 }
} finally {$archive.Dispose();$stream.Dispose()}
Move-Item -LiteralPath $temporary -Destination $destination -Force
$readback=[IO.Compression.ZipFile]::OpenRead($destination)
try {
 if($readback.Entries.Count -ne $paths.Count){throw 'Public source archive entry count mismatch.'}
 foreach($entry in $readback.Entries){
  if($entry.FullName -match '(?i)(^|/)(\.codex|\.claude|\.t3|\.local|build|dist)/|\.(pfx|p12|cer|log|dmp|csv)$|(^|/)(AGENTS|CLAUDE|GEMINI)\.md$|handoff'){
   throw ('Unexpected private entry: '+$entry.FullName)
  }
 }
} finally {$readback.Dispose()}
$sums=@(foreach($file in @($exe,$destination)){(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash+'  '+[IO.Path]::GetFileName($file)})
[IO.File]::WriteAllLines((Join-Path $dist 'SHA256SUMS.txt'),$sums,(New-Object Text.UTF8Encoding($false)))
Write-Output ('Public source archive: '+$destination)
Write-Output ('Reviewed entries: '+$paths.Count)
Write-Output ('Channel: '+$release.channel+'; live installation enabled: '+$release.liveInstallEnabled)
