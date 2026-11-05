#requires -Version 5.1
param([string]$CacheDirectory=(Join-Path $env:TEMP ('Go2-downloads-'+[Guid]::NewGuid().ToString('N').Substring(0,8))))
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Core.ps1')
if(Test-Path -LiteralPath $CacheDirectory){throw 'Fresh download test requires a new cache directory.'}
Assert-NoReparse $CacheDirectory
New-Item -ItemType Directory -Path $CacheDirectory | Out-Null
Write-Output ('Fresh cache: '+$CacheDirectory)
foreach($asset in $script:Release.downloads){
 $path=Get-Download $asset $CacheDirectory
 Write-Output ('Verified fresh publisher download: '+$asset.name+'; bytes='+(Get-Item -LiteralPath $path).Length)
}
Write-Output 'FRESH PUBLISHER DOWNLOAD VERIFICATION PASSED'
