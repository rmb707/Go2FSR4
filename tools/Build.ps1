#requires -Version 5.1
param([string]$OutputDirectory)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$build=Join-Path $root 'build'
$dist=if($OutputDirectory){[IO.Path]::GetFullPath($OutputDirectory)}else{Join-Path $root 'dist'}
New-Item -ItemType Directory -Path $build,$dist -Force | Out-Null
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$zip=Join-Path $build 'bundle.zip'
if(Test-Path -LiteralPath $zip){Remove-Item -LiteralPath $zip}
$stream=[IO.File]::Open($zip,[IO.FileMode]::CreateNew)
$archive=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create)
try {
 $files=@(foreach($folder in @('src','config','vendor','docs')){Get-ChildItem (Join-Path $root $folder) -File -Recurse | Where-Object Name -ne 'Launcher.cs'})
 $files=@($files | Where-Object {
  $_.Name -notmatch '^(AGENTS|CLAUDE|GEMINI)\.md$|handoff' -and
  $_.FullName.Substring($root.Length) -notmatch '[\\/](\.codex|\.claude|\.t3)[\\/]'
 })
 $files+=@(foreach($name in @('README.md','LICENSE','THIRD_PARTY_NOTICES.md')){Get-Item (Join-Path $root $name)})
 foreach($file in ($files | Sort-Object FullName)){
  $relative=$file.FullName.Substring($root.Length+1).Replace('\','/')
  $entry=$archive.CreateEntry($relative,[IO.Compression.CompressionLevel]::Optimal)
  $entry.LastWriteTime=[DateTimeOffset]::Parse('2026-01-01T00:00:00Z')
  $input=[IO.File]::OpenRead($file.FullName); $output=$entry.Open()
  try{$input.CopyTo($output)}finally{$input.Dispose();$output.Dispose()}
 }
} finally {$archive.Dispose();$stream.Dispose()}
$hash=(Get-FileHash $zip).Hash
(Get-Content (Join-Path $root 'src\Launcher.cs') -Raw).Replace('BUNDLE_HASH',$hash) | Set-Content (Join-Path $build 'Launcher.cs')
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$exe=Join-Path $dist 'Go2FSR4.exe'
& $compiler /nologo /target:winexe /platform:x64 /optimize+ /reference:System.Windows.Forms.dll /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll ('/resource:'+ $zip+',bundle.zip') ('/out:'+ $exe) (Join-Path $build 'Launcher.cs')
if($LASTEXITCODE -ne 0){throw 'Launcher compilation failed.'}
$test=Start-Process -FilePath $exe -ArgumentList '--self-test' -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $build 'launcher-selftest.txt') -RedirectStandardError (Join-Path $build 'launcher-selftest-errors.txt')
if($test.ExitCode -ne 0){throw 'Embedded launcher self-test failed.'}
(Get-FileHash $exe).Hash+'  Go2FSR4.exe' | Set-Content (Join-Path $dist 'SHA256SUMS.txt')
Write-Output "Built $exe"
Get-Content (Join-Path $build 'launcher-selftest.txt')


