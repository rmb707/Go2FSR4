param([Parameter(Mandatory=$true)][string]$SeedDirectory)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src\Core.ps1')
$script:DataRoot=Join-Path $env:TEMP ('Go2-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
# Preparation-only test sandbox. No Lifecycle.ps1 import or machine installation.
function Initialize-StateDirectory {
 if(!$script:DataRoot.StartsWith((Join-Path $env:TEMP 'Go2-'),[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid preparation test sandbox'}
 Assert-NoReparse $script:DataRoot
 foreach($name in @('logs','cache','sessions')){New-Item -ItemType Directory -Path (Join-SafePath $script:DataRoot $name) -Force | Out-Null}
}
Initialize-StateDirectory
$seedMap=@{
 'AMD.exe'='whql-amd-software-adrenalin-edition-26.10.1-win11-c.exe'
 '7zr.exe'='7zr.exe'
 '7zip.exe'='7z2605-x64.exe'
 'SDK.zip'='Microsoft.Windows.SDK.BuildTools.10.0.28000.2526.zip'
 'WDK.zip'='Microsoft.Windows.WDK.x64.10.0.28000.2526.zip'
}
foreach($asset in $script:Release.downloads){
 $source=Join-Path $SeedDirectory $seedMap[$asset.name]
 if(!(Test-Path -LiteralPath $source)){$source=Join-Path $SeedDirectory $asset.name}
 Assert-Hash $source $asset.sha256
 # Read-only use of hardlinked publisher archives avoids duplicating multi-GB inputs.
 New-Item -ItemType HardLink -Path (Join-Path $script:DataRoot ('cache\'+$asset.name)) -Target $source | Out-Null
}
New-PreparedPackage
Write-Output ('PREPARATION TEST OUTPUT: '+$script:DataRoot)

