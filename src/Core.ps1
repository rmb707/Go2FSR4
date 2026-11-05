#requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:AppRoot=Split-Path -Parent $PSScriptRoot
$script:Release=Get-Content (Join-Path $script:AppRoot 'config\release.json') -Raw | ConvertFrom-Json
$script:Profile=Get-Content (Join-Path $script:AppRoot 'config\device.json') -Raw | ConvertFrom-Json
$script:DataRoot=Join-Path $env:ProgramData 'Go2FSR4'
$script:LogSink=$null
function Write-Status([string]$Message) { Write-Host $Message; if($script:LogSink){& $script:LogSink $Message} }
function Assert-Hash([string]$Path,[string]$Expected) {
 if(!(Test-Path -LiteralPath $Path -PathType Leaf)){throw "Missing file: $Path"}
 if((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -cne $Expected.ToUpperInvariant()){throw "SHA-256 mismatch: $Path"}
}
function Join-SafePath([string]$Root,[string]$Relative) {
 if([IO.Path]::IsPathRooted($Relative) -or $Relative -match ':'){throw 'Absolute/stream path rejected.'}
 $base=[IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'
 $path=[IO.Path]::GetFullPath((Join-Path $base $Relative))
 if(!$path.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){throw 'Path escapes its root.'}
 return $path
}
function Assert-NoReparse([string]$Path) {
 $cursor=[IO.Path]::GetFullPath($Path)
 while($cursor){
  if(Test-Path -LiteralPath $cursor){if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Reparse point rejected: $cursor"}}
  $parent=Split-Path -Parent $cursor; if($parent -eq $cursor){break}; $cursor=$parent
 }
}
function Test-Administrator { ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator) }
function Assert-Administrator { if(!(Test-Administrator)){throw 'Administrator rights required.'} }
function Initialize-StateDirectory {
 Assert-Administrator; Assert-NoReparse $script:DataRoot
 if(Test-Path -LiteralPath $script:DataRoot){
  $acl=Get-Acl -LiteralPath $script:DataRoot
  if($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin @('S-1-5-18','S-1-5-32-544')){throw 'Untrusted state directory owner.'}
  foreach($rule in $acl.Access){
   $sid=$rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
   $writes=[Security.AccessControl.FileSystemRights]'Write,Modify,FullControl,ChangePermissions,TakeOwnership'
   if($rule.AccessControlType -eq 'Allow' -and ($rule.FileSystemRights -band $writes) -and $sid -notin @('S-1-5-18','S-1-5-32-544')){throw 'State directory has untrusted write access.'}
  }
 }else{
  New-Item -ItemType Directory -Path $script:DataRoot | Out-Null
  $acl=New-Object Security.AccessControl.DirectorySecurity
  $admins=New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
  $acl.SetOwner($admins); $acl.SetAccessRuleProtection($true,$false)
  foreach($sid in @('S-1-5-18','S-1-5-32-544')){
   $identity=New-Object Security.Principal.SecurityIdentifier($sid)
   $rule=New-Object Security.AccessControl.FileSystemAccessRule($identity,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
   $acl.AddAccessRule($rule)
  }; Set-Acl -LiteralPath $script:DataRoot -AclObject $acl
 }
 foreach($name in @('logs','cache','sessions')){New-Item -ItemType Directory -Path (Join-SafePath $script:DataRoot $name) -Force | Out-Null}
}
function Save-Json([object]$Value,[string]$Path) {
 Assert-NoReparse $Path
 $temp=$Path+'.new'; $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $temp -Encoding UTF8
 if(Test-Path -LiteralPath $Path){[IO.File]::Replace($temp,$Path,$Path+'.previous')}else{[IO.File]::Move($temp,$Path)}
}
function Invoke-Checked([string]$Exe,[string[]]$Arguments,[int[]]$Allowed=@(0)) {
 Write-Status ('Running '+[IO.Path]::GetFileName($Exe))
 $text=& $Exe @Arguments 2>&1 | Out-String; $code=$LASTEXITCODE
 if($script:LogSink){& $script:LogSink $text}
 if($code -notin $Allowed){throw "Command failed ($code): $Exe`n$text"}; return $text
}
function Get-DeviceSnapshot {
 $exact=$script:Profile.Hardware.ExactHardwareId
 $devices=@(Get-PnpDevice -Class Display -PresentOnly | Where-Object {$_.InstanceId.StartsWith($exact+'\',[StringComparison]::OrdinalIgnoreCase)})
 if($devices.Count -ne 1){throw 'Supported Legion Go 2 Z2 Extreme C5 display device was not uniquely found.'}
 $id=$devices[0].InstanceId
 [pscustomobject]@{
  InstanceId=$id
  Version=(Get-PnpDeviceProperty -InstanceId $id -KeyName DEVPKEY_Device_DriverVersion).Data
  Inf=(Get-PnpDeviceProperty -InstanceId $id -KeyName DEVPKEY_Device_DriverInfPath).Data
  ProblemCode=(Get-PnpDeviceProperty -InstanceId $id -KeyName DEVPKEY_Device_ProblemCode).Data
  BootId=(Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('o')
  SecureBootRegistry=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State').UEFISecureBootEnabled
 }
}
function Assert-InstallBaseline([object]$Device,[string]$InfHash) {
 if($Device.Version -ne $script:Release.originalDriverVersion -or $Device.ProblemCode -ne 0 -or $Device.SecureBootRegistry -ne 1){throw 'Requires the validated working Lenovo driver with Secure Boot enabled.'}
 if($InfHash -ne $script:Release.originalInfSha256){throw 'Original INF is not the validated Lenovo package.'}
}
function Test-OriginalDriverBinding([object]$Device,[object]$State,[string]$InfHash) {
 return ($Device.InstanceId -eq $State.Before.InstanceId -and
  $Device.Version -eq $State.Before.Version -and $Device.ProblemCode -eq 0 -and
  $Device.SecureBootRegistry -eq 1 -and $InfHash -eq $script:Release.originalInfSha256)
}
function Get-VerifiedLifecycleStatus([object]$State,[object]$Device,[bool]$CandidatePassed,[bool]$OriginalPassed) {
 if($Device.InstanceId -ne $State.Before.InstanceId){return $State.Status}
 if($State.Status -eq 'AwaitingInstallReboot' -and $Device.BootId -ne $State.InstallBoot -and $CandidatePassed){return 'Installed'}
 if($State.Status -eq 'AwaitingUninstallReboot' -and $Device.BootId -ne $State.UninstallBoot -and $OriginalPassed){return 'Uninstalled'}
 return $State.Status
}
function Assert-SecurePolicy {
 Assert-Administrator
 if(!(Confirm-SecureBootUEFI)){throw 'UEFI Secure Boot must be enabled.'}
 if(!(Test-KernelSecurityState (Get-KernelSecurityState))){throw 'Current-boot Secure Boot and normal Code Integrity enforcement required; test signing unsupported.'}
}
function Get-KernelSecurityState {
 if(!('Go2KernelSecurity' -as [type])){
  Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class Go2KernelSecurity {
 [StructLayout(LayoutKind.Sequential,Pack=1)] public struct BootInfo { public byte Enabled,Capable; }
 [StructLayout(LayoutKind.Sequential)] public struct IntegrityInfo { public uint Length,Options; }
 [DllImport("ntdll.dll",EntryPoint="NtQuerySystemInformation")]
 static extern int QueryBoot(int cls,ref BootInfo info,int length,out int returned);
 [DllImport("ntdll.dll",EntryPoint="NtQuerySystemInformation")]
 static extern int QueryIntegrity(int cls,ref IntegrityInfo info,int length,out int returned);
 public static object[] Read() {
  BootInfo boot=new BootInfo(); int bootBytes;
  int bootStatus=QueryBoot(145,ref boot,Marshal.SizeOf(typeof(BootInfo)),out bootBytes);
  IntegrityInfo integrity=new IntegrityInfo(); integrity.Length=(uint)Marshal.SizeOf(typeof(IntegrityInfo)); int integrityBytes;
  int integrityStatus=QueryIntegrity(103,ref integrity,(int)integrity.Length,out integrityBytes);
  return new object[]{bootStatus,bootBytes,boot.Enabled,boot.Capable,integrityStatus,integrityBytes,integrity.Options};
 }
}
'@
 }
 $result=[Go2KernelSecurity]::Read()
 $bootChecked=[int]$result[0] -eq 0 -and [int]$result[1] -ge 2
 $integrityChecked=[int]$result[4] -eq 0 -and [int]$result[5] -ge 8
 [pscustomobject]@{
  Source='NtQuerySystemInformation: SystemSecureBootInformation (145), SystemCodeIntegrityInformation (103)'
  SecureBootQueryStatus=('0x{0:X8}' -f [int]$result[0]); SecureBootChecked=$bootChecked
  SecureBootEnabled=if($bootChecked){[int]$result[2] -eq 1}else{$null}
  SecureBootCapable=if($bootChecked){[int]$result[3] -eq 1}else{$null}
  CodeIntegrityQueryStatus=('0x{0:X8}' -f [int]$result[4]); CodeIntegrityChecked=$integrityChecked
  CodeIntegrityFlags=('0x{0:X8}' -f [uint32]$result[6])
  CodeIntegrityEnforced=if($integrityChecked){([uint32]$result[6] -band 1) -ne 0}else{$null}
  TestSigningEnabled=if($integrityChecked){([uint32]$result[6] -band 2) -ne 0}else{$null}
 }
}
function Test-KernelSecurityState([object]$Security) {
 return ($Security.SecureBootChecked -eq $true -and $Security.SecureBootEnabled -eq $true -and
  $Security.CodeIntegrityChecked -eq $true -and $Security.CodeIntegrityEnforced -eq $true -and
  $Security.TestSigningEnabled -eq $false)
}
function Assert-LiveRelease { if(!$script:Release.liveInstallEnabled -or $script:Release.channel -ne 'release'){throw $script:Release.releaseGate} }
function Test-Package([string]$Root,[switch]$Patched) {
 Assert-NoReparse $Root
 $rows=Get-Content (Join-Path $script:AppRoot 'config\official-files.json') -Raw | ConvertFrom-Json
 $expectedNames=@($rows | ForEach-Object {$_.path.ToLowerInvariant()})
 $actual=@(Get-ChildItem -LiteralPath $Root -Recurse -File | ForEach-Object {$_.FullName.Substring($Root.TrimEnd('\').Length+1).ToLowerInvariant()})
 if(@(Compare-Object $expectedNames $actual).Count -ne 0){throw 'Package file set differs from the pinned source.'}
 foreach($row in $rows){
  $hash=$row.sha256
  if($Patched){
   if($row.path -eq 'u0205306.cat'){continue}
   if($row.path -eq 'u0205306.inf'){$hash=$script:Profile.Final.ExpectedInfSHA256}
   if($row.path -eq 'B026676\amdgcf.dat'){$hash=$script:Profile.Final.ExpectedDatSHA256}
  }; Assert-Hash (Join-SafePath $Root $row.path) $hash
 }; Write-Status 'Full package file set and SHA-256 checks passed.'
}
function Get-OwnedPackages([object[]]$Before,[object[]]$After,[string[]]$CandidateHashes) {
 $prior=@($Before | ForEach-Object {$_.Driver})
 @($After | Where-Object {$_.Driver -notin $prior -and $_.InfHash -in $CandidateHashes})
}
function Get-DriverFamily([string]$OriginalName) {
 $name=[IO.Path]::GetFileName($OriginalName).ToLowerInvariant()
 if($name -match '^amdwin-u[0-9]+\.inf$'){return 'amdwin.inf'}
 return $name
}
function Get-BackupDriverPackages([object[]]$Inventory,[string]$DisplayInf,[string[]]$CandidateNames) {
 $families=@($CandidateNames | ForEach-Object {Get-DriverFamily $_})
 @($Inventory | Where-Object {$_.Driver -eq $DisplayInf -or (Get-DriverFamily $_.OriginalName) -in $families})
}
function Get-DriverInventory {
 @(Get-WindowsDriver -Online | ForEach-Object {
  [pscustomobject]@{Driver=$_.Driver;OriginalName=[IO.Path]::GetFileName($_.OriginalFileName);Version=$_.Version.ToString();InfHash=(Get-FileHash -LiteralPath (Join-Path $env:WINDIR ('INF\'+$_.Driver))).Hash}
 })
}
function Get-DeviceDriverBindings([string[]]$PackageNames=@(),[string[]]$InstanceIds=@()) {
 $devices=@(Get-PnpDevice -PresentOnly)
 if($InstanceIds.Count){$devices=@($devices | Where-Object InstanceId -in $InstanceIds)}
 if(!$devices.Count){return @()}
 $properties=@(Get-PnpDeviceProperty -InstanceId @($devices.InstanceId) -KeyName DEVPKEY_Device_DriverInfPath -ErrorAction SilentlyContinue)
 foreach($property in $properties){
  if(!$property.PSObject.Properties['Data'] -or !$property.PSObject.Properties['InstanceId']){continue}
  if($PackageNames.Count -and $property.Data -notin $PackageNames){continue}
  $inf=[string]$property.Data
  if($inf -notmatch '^[A-Za-z0-9_.-]+\.inf$'){continue}
  $device=@($devices | Where-Object InstanceId -eq $property.InstanceId)
  if($device.Count -ne 1){throw 'Device binding snapshot was not unique.'}
  [pscustomobject]@{
   InstanceId=$property.InstanceId
   Name=$device[0].FriendlyName
   Inf=$inf
   InfHash=(Get-FileHash -LiteralPath (Join-Path $env:WINDIR ('INF\'+$inf))).Hash
   ProblemCode=(Get-PnpDeviceProperty -InstanceId $property.InstanceId -KeyName DEVPKEY_Device_ProblemCode -ErrorAction Stop).Data
  }
 }
}
function Test-DeviceDriverBindings([object[]]$Expected,[object[]]$Actual) {
 if(!@($Expected).Count){return $false}
 foreach($before in $Expected){
  $current=@($Actual | Where-Object InstanceId -eq $before.InstanceId)
  if($current.Count -ne 1){return $false}
  if($current[0].InfHash -ne $before.InfHash -or $current[0].ProblemCode -ne 0){return $false}
 }
 return $true
}
function Get-Download([object]$Asset,[string]$Cache) {
 $target=Join-SafePath $Cache $Asset.name
 if(!(Test-Path -LiteralPath $target)){
  if(([Uri]$Asset.url).Scheme -ne 'https'){throw 'HTTPS required.'}
  Write-Status ('Downloading '+$Asset.name+' from publisher; this can take several minutes.')
  $partial=$target+'.partial'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
  $headers=@{}
  # AMD's download endpoint otherwise returns a successful HTML error page.
  if(([Uri]$Asset.url).DnsSafeHost -eq 'drivers.amd.com'){$headers.Referer='https://www.amd.com/'}
  Invoke-WebRequest -UseBasicParsing -Uri $Asset.url -OutFile $partial -Headers $headers
  Assert-Hash $partial $Asset.sha256; Move-Item -LiteralPath $partial -Destination $target
 }; Assert-Hash $target $Asset.sha256; $target
}
function New-PreparedPackage {
 Initialize-StateDirectory
 $id=[Guid]::NewGuid().ToString('N'); $work=Join-SafePath $script:DataRoot ('sessions\'+$id)
 New-Item -ItemType Directory -Path $work | Out-Null
 $cache=Join-Path $script:DataRoot 'cache'
 foreach($asset in $script:Release.downloads){$null=Get-Download $asset $cache}
 $seven=Join-Path $work '7zip'
 $null=Invoke-Checked (Join-Path $cache '7zr.exe') @('x',(Join-Path $cache '7zip.exe'),('-o'+$seven),'-y')
 $sevenExe=Join-Path $seven '7z.exe'; $official=Join-Path $work 'official'
 $null=Invoke-Checked $sevenExe @('x',(Join-Path $cache 'AMD.exe'),('-o'+$official),'-y')
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 [IO.Compression.ZipFile]::ExtractToDirectory((Join-Path $cache 'SDK.zip'),(Join-Path $work 'sdk'))
 [IO.Compression.ZipFile]::ExtractToDirectory((Join-Path $cache 'WDK.zip'),(Join-Path $work 'wdk'))
 $source=Join-Path $official 'Packages\Drivers\Display\WT6A_INF'; Test-Package $source
 $driver=Join-Path $work 'driver'; Copy-Item -LiteralPath $source -Destination $driver -Recurse
 $deviceProfile=Join-Path $script:AppRoot 'config\device.json'
 & (Join-Path $script:AppRoot 'vendor\Build-V4-Inf.ps1') -OfficialInfPath (Join-Path $source 'u0205306.inf') -OutputPath (Join-Path $driver 'u0205306.inf') -SelectedProfilePath $deviceProfile
 & (Join-Path $script:AppRoot 'vendor\Build-V4-AmdGcfDat.ps1') -OfficialDatPath (Join-Path $source 'B026676\amdgcf.dat') -OutputPath (Join-Path $driver 'B026676\amdgcf.dat') -SelectedProfilePath $deviceProfile
 $sign=Join-Path $work 'sdk\bin\10.0.28000.0\x64\signtool.exe'; $inf2cat=Join-Path $work 'wdk\c\bin\10.0.28000.0\x86\Inf2Cat.exe'
 $originalCat=Join-Path $work 'original.cat'; Copy-Item -LiteralPath (Join-Path $source 'u0205306.cat') -Destination $originalCat
 $null=Invoke-Checked $sign @('verify','/kp','/c',$originalCat,(Join-Path $driver 'B026676\amdkmdag.sys'))
 $null=Invoke-Checked $inf2cat @(('/driver:'+ $driver),'/os:10_X64','/verbose')
 Get-ChildItem -LiteralPath $source -Recurse -Filter *.cat | Where-Object Name -ne 'u0205306.cat' | ForEach-Object {
  Copy-Item -LiteralPath $_.FullName -Destination (Join-SafePath $driver $_.FullName.Substring($source.Length+1)) -Force
 }
 Test-Package $driver -Patched
 $software=Join-Path $work 'software'
 $null=Invoke-Checked $sevenExe @('x',(Join-Path $source 'B026676\ccc2_install.exe'),('-o'+$software),'-y')
 Save-Json ([ordered]@{Id=$id;Work=$work;Driver=$driver;SignTool=$sign;OriginalCatalog=$originalCat;Software=$software;Prepared=(Get-Date -Format o)}) (Join-Path $script:DataRoot 'prepared.json')
 Write-Status 'Prepared and verified. No drivers, certificates, or boot settings installed.'
}
function Get-MsiSpecs([string]$Software) {
 @(
  [pscustomobject]@{Name='AMD Settings';Product='{A8E5B545-3B0F-4A84-B766-EF079C00EAF9}';Path=(Join-Path $Software 'CN\cnext\cnext64\ccc-next64.msi');Extra=''},
  [pscustomobject]@{Name='AMD DVR';Product='{118A830B-33E5-481F-A0EA-FDC28C06584E}';Path=(Join-Path $Software 'CN\amddvr\amddvr64\amddvr64.msi');Extra='LAUNCHED_FROM_CIM=1'}
 )
}
function Invoke-Msi([object]$Spec,[string]$Action,[string]$Log) {
 if($Action -eq 'install'){$arguments='/i "'+$Spec.Path+'" /qn /norestart REBOOT=ReallySuppress '+$Spec.Extra}else{$arguments='/x '+$Spec.Product+' /qn /norestart REBOOT=ReallySuppress'}
 $arguments+=' /l*v "'+$Log+'"'; $proc=Start-Process msiexec.exe -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
 $allowed=@(0,3010); if($Action -ne 'install'){$allowed+=1605}
 if($proc.ExitCode -notin $allowed){throw "MSI $Action failed: $($Spec.Name), code $($proc.ExitCode). See $Log"}
}
function Get-State { $path=Join-Path $script:DataRoot 'state.json'; if(Test-Path -LiteralPath $path){Get-Content -LiteralPath $path -Raw | ConvertFrom-Json}else{$null} }
function Save-State([object]$State) { Save-Json $State (Join-Path $script:DataRoot 'state.json') }
function Test-FsrRuntime([string]$LibraryDirectory,[string]$OutputDirectory) {
 $source=(Resolve-Path -LiteralPath $LibraryDirectory).Path.TrimEnd('\')
 $target=[IO.Path]::GetFullPath($OutputDirectory)
 if($target -eq $source -or $target.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Probe output must be outside the game directory.'}
 if(Test-Path -LiteralPath $target){throw 'Probe output directory must be new.'}
 Assert-NoReparse $target
 $names=@('amd_fidelityfx_loader_dx12.dll','amd_fidelityfx_upscaler_dx12.dll')
 foreach($name in $names){
  $sig=Get-AuthenticodeSignature (Join-Path $source $name)
  if($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Advanced Micro Devices'){throw "Valid AMD signature required: $name"}
 }
 if((Get-DeviceSnapshot).SecureBootRegistry -ne 1){throw 'Secure Boot must remain enabled.'}
 New-Item -ItemType Directory -Path $target | Out-Null
 foreach($name in $names){Copy-Item -LiteralPath (Join-Path $source $name) -Destination (Join-Path $target $name)}
 $compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
 $exe=Join-Path $target 'Probe.exe'
 $null=Invoke-Checked $compiler @('/nologo','/platform:x64',('/out:'+ $exe),(Join-Path $PSScriptRoot 'Probe.cs'))
 $text=Invoke-Checked $exe @()
 $text | Set-Content (Join-Path $target 'result.txt')
 Write-Status $text
 Write-Status 'FSR 4.1.2 context created. This verifies API availability, not game rendering or performance.'
}

