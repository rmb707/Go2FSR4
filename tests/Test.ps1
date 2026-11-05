#requires -Version 5.1
param([string]$OfficialPackage,[string]$ExistingCandidate)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src\Core.ps1')
. (Join-Path $root 'src\Lifecycle.ps1')
$script:checks=0
function Check([string]$Name,[scriptblock]$Test){& $Test; $script:checks++; Write-Output "PASS $Name"}
function Reject([scriptblock]$Action){$rejected=$false;try{& $Action | Out-Null}catch{$rejected=$true};if(!$rejected){throw 'Expected rejection did not occur.'}}
@(foreach($folder in @('src','tools','tests','vendor')){Get-ChildItem (Join-Path $root $folder) -Recurse -Filter *.ps1}) | ForEach-Object {
 $tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$errors)
 if($errors.Count){throw ($errors | Out-String)}
}
Check 'All PowerShell files parse' {}
Check 'Traversal and alternate data streams rejected' {
 foreach($relative in @('..\escape','C:\outside','safe.txt:stream','\\server\share')){Reject {Join-SafePath $env:TEMP $relative}}
}
Check 'Safe child path retained' {if((Join-SafePath $env:TEMP 'safe\file') -ne [IO.Path]::GetFullPath((Join-Path $env:TEMP 'safe\file'))){throw 'Child path mismatch'}}
Check 'Release configuration enables install while disabled or non-release builds are rejected' {
 $configured=$script:Release
 $script:Release=$configured.PSObject.Copy()
 try{
  $script:Release.liveInstallEnabled=$false; $script:Release.channel='release'
  Reject {Assert-LiveRelease}
  $script:Release.liveInstallEnabled=$true; $script:Release.channel='development'
  Reject {Assert-LiveRelease}
  $script:Release.channel='release'
  Assert-LiveRelease
 }finally{$script:Release=$configured}
 if($configured.channel -eq 'release' -and $configured.liveInstallEnabled){Assert-LiveRelease}
}
Check 'Unsupported baseline rejected' {Reject {Assert-InstallBaseline ([pscustomobject]@{Version='wrong';ProblemCode=0;SecureBootRegistry=1}) $script:Release.originalInfSha256}}
Check 'Secure Boot off rejected by baseline' {Reject {Assert-InstallBaseline ([pscustomobject]@{Version=$script:Release.originalDriverVersion;ProblemCode=0;SecureBootRegistry=0}) $script:Release.originalInfSha256}}
Check 'Kernel security requires successful reads, Secure Boot and enforcement without test signing' {
 $valid=[pscustomobject]@{SecureBootChecked=$true;SecureBootEnabled=$true;CodeIntegrityChecked=$true;CodeIntegrityEnforced=$true;TestSigningEnabled=$false}
 if(!(Test-KernelSecurityState $valid)){throw 'Valid kernel security rejected'}
 foreach($field in @('SecureBootChecked','SecureBootEnabled','CodeIntegrityChecked','CodeIntegrityEnforced','TestSigningEnabled')){
  $changed=$valid.PSObject.Copy(); $changed.$field=($field -eq 'TestSigningEnabled')
  if(Test-KernelSecurityState $changed){throw ('Invalid kernel security accepted: '+$field)}
  $changed.$field=$null
  if(Test-KernelSecurityState $changed){throw ('Unknown kernel security accepted: '+$field)}
 }
}
Check 'Unexpected baseline hash rejected' {Reject {Assert-InstallBaseline ([pscustomobject]@{Version=$script:Release.originalDriverVersion;ProblemCode=0;SecureBootRegistry=1}) ('A'*64)}}
Check 'Original restore requires exact identity, INF hash, health and Secure Boot' {
 $state=[pscustomobject]@{Before=[pscustomobject]@{InstanceId='test-device';Version=$script:Release.originalDriverVersion}}
 $device=[pscustomobject]@{InstanceId='test-device';Version=$script:Release.originalDriverVersion;ProblemCode=0;SecureBootRegistry=1}
 if(!(Test-OriginalDriverBinding $device $state $script:Release.originalInfSha256)){throw 'Valid original binding rejected'}
 if(Test-OriginalDriverBinding $device $state ('A'*64)){throw 'Replaced original INF accepted'}
 foreach($field in @('InstanceId','Version','ProblemCode','SecureBootRegistry')){
  $changed=$device.PSObject.Copy()
  if($field -eq 'ProblemCode'){$changed.$field=31}elseif($field -eq 'SecureBootRegistry'){$changed.$field=0}else{$changed.$field='different'}
  if(Test-OriginalDriverBinding $changed $state $script:Release.originalInfSha256){throw ('Invalid restore accepted: '+$field)}
 }
}
Check 'Install completion requires a later boot and verified candidate' {
 $state=[pscustomobject]@{Status='AwaitingInstallReboot';InstallBoot='boot-1';UninstallBoot=$null;Before=[pscustomobject]@{InstanceId='test-device'}}
 $device=[pscustomobject]@{InstanceId='test-device';BootId='boot-1'}
 if((Get-VerifiedLifecycleStatus $state $device $true $false) -ne 'AwaitingInstallReboot'){throw 'Same-boot install accepted'}
 $device.BootId='boot-2'
 if((Get-VerifiedLifecycleStatus $state $device $false $false) -ne 'AwaitingInstallReboot'){throw 'Unverified candidate accepted'}
 if((Get-VerifiedLifecycleStatus $state $device $true $false) -ne 'Installed'){throw 'Valid install not recognized'}
}
Check 'Restore completion requires a later boot and verified original' {
 $state=[pscustomobject]@{Status='AwaitingUninstallReboot';InstallBoot='boot-1';UninstallBoot='boot-2';Before=[pscustomobject]@{InstanceId='test-device'}}
 $device=[pscustomobject]@{InstanceId='test-device';BootId='boot-2'}
 if((Get-VerifiedLifecycleStatus $state $device $false $true) -ne 'AwaitingUninstallReboot'){throw 'Same-boot restore accepted'}
 $device.BootId='boot-3'
 if((Get-VerifiedLifecycleStatus $state $device $true $false) -ne 'AwaitingUninstallReboot'){throw 'Candidate mistaken for restored original'}
 if((Get-VerifiedLifecycleStatus $state $device $false $true) -ne 'Uninstalled'){throw 'Valid restore not recognized'}
}
Check 'Another device cannot complete an installation or restore' {
 foreach($status in @('AwaitingInstallReboot','AwaitingUninstallReboot')){
  $state=[pscustomobject]@{Status=$status;InstallBoot='boot-1';UninstallBoot='boot-1';Before=[pscustomobject]@{InstanceId='test-device'}}
  $device=[pscustomobject]@{InstanceId='different-device';BootId='boot-2'}
  if((Get-VerifiedLifecycleStatus $state $device $true $true) -ne $status){throw 'Unrelated device completed transaction'}
 }
}
Check 'Preexisting and unrelated packages excluded from uninstall ownership' {
 $before=@([pscustomobject]@{Driver='oem1.inf';InfHash='candidate'})
 $after=@($before)+@([pscustomobject]@{Driver='oem2.inf';InfHash='candidate'},[pscustomobject]@{Driver='oem3.inf';InfHash='unrelated'})
 $owned=@(Get-OwnedPackages $before $after @('candidate'))
 if($owned.Count -ne 1 -or $owned[0].Driver -ne 'oem2.inf'){throw 'Ownership filtering failed'}
}
Check 'Backup includes versioned AMD Windows companion and excludes unrelated families' {
 $inventory=@(
  [pscustomobject]@{Driver='oem1.inf';OriginalName='u0201776.inf'},
  [pscustomobject]@{Driver='oem2.inf';OriginalName='amdwin-u0201776.inf'},
  [pscustomobject]@{Driver='oem3.inf';OriginalName='amdocl.inf'},
  [pscustomobject]@{Driver='oem4.inf';OriginalName='unrelated-u0201776.inf'},
  [pscustomobject]@{Driver='oem5.inf';OriginalName='amdwin-u0205306.inf.backup'},
  [pscustomobject]@{Driver='oem6.inf';OriginalName='amdxe.inf'}
 )
 $selected=@(Get-BackupDriverPackages $inventory 'oem1.inf' @('u0205306.inf','amdwin-u0205306.inf','amdocl.inf'))
 if($selected.Count -ne 3 -or @($selected | Where-Object Driver -notin @('oem1.inf','oem2.inf','oem3.inf')).Count){throw 'Backup family selection incorrect'}
 if((Get-DriverFamily 'AMDWIN-U0201776.INF') -ne 'amdwin.inf'){throw 'Case-insensitive family selection failed'}
}
Check 'Original device bindings match by content even if published INF number changes' {
 $expected=@([pscustomobject]@{InstanceId='companion';Inf='oem2.inf';InfHash='original-companion';ProblemCode=0})
 $actual=@([pscustomobject]@{InstanceId='companion';Inf='oem80.inf';InfHash='original-companion';ProblemCode=0},[pscustomobject]@{InstanceId='unrelated';InfHash='other';ProblemCode=31})
 if(!(Test-DeviceDriverBindings $expected $actual)){throw 'Matching original package under a new INF number rejected'}
}
Check 'Missing, duplicate, changed or unhealthy original device bindings rejected' {
 $expected=@([pscustomobject]@{InstanceId='companion';InfHash='original-companion'})
 $good=[pscustomobject]@{InstanceId='companion';InfHash='original-companion';ProblemCode=0}
 if(Test-DeviceDriverBindings $expected @()){throw 'Missing original device accepted'}
 if(Test-DeviceDriverBindings $expected @($good,$good)){throw 'Duplicate original device accepted'}
 if(Test-DeviceDriverBindings $expected @([pscustomobject]@{InstanceId='companion';InfHash='candidate-companion';ProblemCode=0})){throw 'Wrong companion package accepted'}
 if(Test-DeviceDriverBindings $expected @([pscustomobject]@{InstanceId='companion';InfHash='original-companion';ProblemCode=31})){throw 'Unhealthy companion accepted'}
 if(Test-DeviceDriverBindings @() @($good)){throw 'Missing original binding record accepted'}
}
Check 'Restore verifier rejects stale kernel, companion or INF; success persists on recheck' {
 # Run the real verifier against synthetic system observations. No registry,
 # driver, certificate, or state-directory mutation is performed.
 $verificationState=[pscustomobject]@{
  Status='AwaitingUninstallReboot';InstallBoot='boot-1';UninstallBoot='boot-2'
  Before=[pscustomobject]@{InstanceId='test-device';Version=$script:Release.originalDriverVersion}
  CandidateHashes=@('candidate-inf')
  BindingsBefore=@([pscustomobject]@{InstanceId='companion';InfHash='original-companion';ProblemCode=0})
  BackupManifest=@([pscustomobject]@{Path='C:\synthetic-backup\amdkmdag.sys';Hash='original-kernel'})
 }
 $verificationDevice=[pscustomobject]@{InstanceId='test-device';Version=$script:Release.originalDriverVersion;ProblemCode=0;SecureBootRegistry=1;BootId='boot-3';Inf='test.inf'}
 $observedInf=$script:Release.originalInfSha256; $observedKernel=$script:Release.kernelSha256
 $observedBinding=[pscustomobject]@{InstanceId='companion';InfHash='original-companion';ProblemCode=0}
 $observedSecurity=[pscustomobject]@{SecureBootChecked=$true;SecureBootEnabled=$true;CodeIntegrityChecked=$true;CodeIntegrityEnforced=$true;TestSigningEnabled=$false}
 function Test-Administrator {return $true}
 function Assert-SecurePolicy {}
 function Initialize-StateDirectory {}
 function Get-State {return $verificationState}
 function Save-State([object]$State) {}
 function Save-Json([object]$Value,[string]$Path) {}
 function Get-DeviceSnapshot {return $verificationDevice}
 function Get-DeviceDriverBindings {return $observedBinding}
 function Get-KernelSecurityState {return $observedSecurity}
 function Get-CimInstance([string]$ClassName) {return [pscustomobject]@{Name='amduw-test';State='Running';PathName='C:\synthetic-kernel.sys'}}
 function Test-Path {return $true}
 function Get-FileHash([string]$Path,[string]$LiteralPath) {
  if($LiteralPath){return [pscustomobject]@{Hash=$observedInf}}
  return [pscustomobject]@{Hash=$observedKernel}
 }
 $report=Verify-Go2
 if($report.RestartVerified -or $report.RestoredDriverChecksPassed -or $verificationState.Status -ne 'AwaitingUninstallReboot'){throw 'Stale candidate kernel accepted as original'}
 $observedKernel='original-kernel'; $observedBinding.InfHash='candidate-companion'; $report=Verify-Go2
 if($report.RestartVerified -or $report.OriginalBindingsChecksPassed -or $verificationState.Status -ne 'AwaitingUninstallReboot'){throw 'Stale companion driver accepted as restored'}
 $observedBinding.InfHash='original-companion'; $report=Verify-Go2
 if(!$report.RestartVerified -or !$report.RestoredDriverChecksPassed -or $report.Managed -or $report.LifecycleStatus -ne 'Uninstalled'){throw 'Valid original kernel and binding not recognized'}
 $report=Verify-Go2
 if(!$report.RestartVerified -or !$report.RestoredDriverChecksPassed){throw 'Completed restore verification lost on recheck'}
 $observedInf='replaced-inf'; $report=Verify-Go2
 if($report.RestartVerified -or $report.RestoredDriverChecksPassed){throw 'Later INF replacement accepted as restored original'}
 $observedInf=$script:Release.originalInfSha256; $observedSecurity.SecureBootEnabled=$false; $report=Verify-Go2
 if($report.RestartVerified -or $report.RestoredDriverChecksPassed -or $report.KernelSecurityChecksPassed){throw 'Restore verified while current-boot Secure Boot is off'}
}
$fixture=Join-Path $env:TEMP ('Go2FSR4-test-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
Check 'AMD download sends publisher referer and still rejects unexpected content' {
 $cache=Join-Path $fixture 'download-cache'; New-Item -ItemType Directory -Path $cache | Out-Null
 $payload=[Text.Encoding]::UTF8.GetBytes('synthetic-publisher-payload')
 $sha=[Security.Cryptography.SHA256]::Create()
 try{$hash=[BitConverter]::ToString($sha.ComputeHash($payload)).Replace('-','')}finally{$sha.Dispose()}
 function Invoke-WebRequest([switch]$UseBasicParsing,[string]$Uri,[string]$OutFile,[hashtable]$Headers) {
  if($Uri -notlike 'https://drivers.amd.com/*' -or $Headers.Referer -ne 'https://www.amd.com/'){throw 'Publisher request headers incorrect'}
  [IO.File]::WriteAllBytes($OutFile,$payload)
 }
 $asset=[pscustomobject]@{name='test-amd.exe';url='https://drivers.amd.com/test.exe';sha256=$hash}
 $path=Get-Download $asset $cache
 if(!(Test-Path -LiteralPath $path)){throw 'Verified payload not promoted to cache'}
 $asset.name='unexpected.exe'; $asset.sha256='0'*64
 Reject {Get-Download $asset $cache}
 if(Test-Path -LiteralPath (Join-Path $cache $asset.name)){throw 'Unverified payload promoted to cache'}
 $asset.name='insecure.exe'; $asset.url='http://drivers.amd.com/test.exe'
 Reject {Get-Download $asset $cache}
}
Check 'Tampered file rejected' {
 $path=Join-Path $fixture 'hash.txt'; 'original' | Set-Content $path; $hash=(Get-FileHash $path).Hash
 Assert-Hash $path $hash; 'changed' | Set-Content $path; Reject {Assert-Hash $path $hash}
}
Check 'Atomic journal preserves previous revision' {
 $path=Join-Path $fixture 'state.json'; Save-Json @{phase='before'} $path; Save-Json @{phase='after'} $path
 if((Get-Content $path -Raw | ConvertFrom-Json).phase -ne 'after' -or (Get-Content ($path+'.previous') -Raw | ConvertFrom-Json).phase -ne 'before'){throw 'Journal atomic replacement failed'}
}
if($OfficialPackage){Check 'Every official package file matches pinned manifest' {Test-Package $OfficialPackage}}
if($ExistingCandidate){Check 'Existing working candidate preserves every other file' {Test-Package $ExistingCandidate -Patched}}
Write-Output "Completed $script:checks checks. No driver installation/uninstallation performed. Fixture: $fixture"

