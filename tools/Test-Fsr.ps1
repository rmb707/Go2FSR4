param([Parameter(Mandatory=$true)][string]$LibraryDirectory)
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Core.ps1')
$target=Join-Path $env:TEMP ('Go2FSR4-probe-'+[Guid]::NewGuid().ToString('N'))
Test-FsrRuntime -LibraryDirectory $LibraryDirectory -OutputDirectory $target
Write-Output ('Probe evidence: '+$target)
