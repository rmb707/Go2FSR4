function Install-Go2 {
 Assert-LiveRelease; Initialize-StateDirectory; Assert-SecurePolicy
 $previous=Get-State; if($previous -and $previous.Status -ne 'Uninstalled'){throw 'Existing transaction: use Verify or Uninstall. Recovery records will not be overwritten.'}
 $device=Get-DeviceSnapshot
 $infHash=(Get-FileHash (Join-Path $env:WINDIR ('INF\'+$device.Inf))).Hash
 Assert-InstallBaseline $device $infHash
 $drive=Get-PSDrive -Name ([IO.Path]::GetPathRoot($script:DataRoot).Substring(0,1))
 if($drive.Free -lt ($script:Release.minimumFreeGB*1GB)){throw 'At least 12 GB free space required.'}
 $native=@(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object {$_.PSObject.Properties['DisplayName'] -and $_.DisplayName -match '^AMD (Settings|DVR|Software)'})
 if($native.Count){throw 'Existing native AMD Software requires a supported migration plan; stopped before changes.'}
 if($previous){
  $archive=Join-SafePath $script:DataRoot ('sessions\completed-'+[Guid]::NewGuid().ToString('N')+'.json')
  $statePath=Join-Path $script:DataRoot 'state.json'
  Copy-Item -LiteralPath $statePath -Destination $archive
  Assert-Hash $archive (Get-FileHash -LiteralPath $statePath).Hash
  Remove-Item -LiteralPath $statePath
  New-PreparedPackage
 }elseif(!(Test-Path (Join-Path $script:DataRoot 'prepared.json'))){New-PreparedPackage}
 $prepared=Get-Content (Join-Path $script:DataRoot 'prepared.json') -Raw | ConvertFrom-Json
 Assert-NoReparse $prepared.Work
 if(!$prepared.Work.StartsWith($script:DataRoot+'\sessions\',[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid prepared-session path.'}
 Test-Package $prepared.Driver -Patched
 $before=Get-DriverInventory
 $candidateInfs=@(Get-ChildItem $prepared.Driver -Recurse -Filter *.inf)
 $candidateHashes=@($candidateInfs | ForEach-Object {(Get-FileHash $_.FullName).Hash})
 $backup=Join-Path $prepared.Work 'backup'; New-Item -ItemType Directory -Path $backup | Out-Null
 $names=@($candidateInfs.Name)
 $backupPackages=@(Get-BackupDriverPackages $before $device.Inf $names)
 $bindingsBefore=@(Get-DeviceDriverBindings -PackageNames @($backupPackages.Driver))
 if(@($bindingsBefore | Where-Object {$_.InstanceId -eq $device.InstanceId -and $_.InfHash -eq $infHash}).Count -ne 1){throw 'Original display binding was not captured for recovery.'}
 if(@($bindingsBefore | Where-Object ProblemCode -ne 0).Count){throw 'An affected device is unhealthy before installation.'}
 foreach($package in $backupPackages){
  $null=Invoke-Checked pnputil.exe @('/export-driver',$package.Driver,$backup)
 }
 $original=@(Get-ChildItem $backup -Recurse -Filter *.inf | Where-Object {(Get-FileHash $_.FullName).Hash -eq $infHash})
 if($original.Count -ne 1){throw 'Original display backup could not be verified.'}
 $backupManifest=@(Get-ChildItem $backup -Recurse -File | ForEach-Object {[pscustomobject]@{Path=$_.FullName;Hash=(Get-FileHash $_.FullName).Hash}})
 $backupInfHashes=@($backupManifest | Where-Object {$_.Path -like '*.inf'} | ForEach-Object {$_.Hash})
 foreach($binding in $bindingsBefore){if($binding.InfHash -notin $backupInfHashes){throw ('Original device package missing from verified backup: '+$binding.Name)}}
 $state=[pscustomobject]@{Schema=2;Status='Installing';Before=$device;BindingsBefore=$bindingsBefore;Prepared=$prepared;InventoryBefore=$before;CandidateHashes=$candidateHashes;OwnedPackages=@();OriginalInf=$original[0].FullName;BackupManifest=$backupManifest;Certificate=$null;CatalogRegistered=$false;SoftwareAttempted=@();Error=$null;InstallBoot=$device.BootId;UninstallBoot=$null}
 Save-State $state
 try {
  $cert=New-SelfSignedCertificate -Type CodeSigningCert -Subject ('CN=Go2FSR4 Package '+$prepared.Id) -CertStoreLocation Cert:\LocalMachine\My -KeyLength 3072 -HashAlgorithm SHA256 -KeyExportPolicy NonExportable -NotAfter (Get-Date).AddYears(5)
  $state.Certificate=$cert.Thumbprint; Save-State $state
  $cat=Join-Path $prepared.Driver 'u0205306.cat'
  $null=Invoke-Checked $prepared.SignTool @('sign','/sm','/s','My','/sha1',$cert.Thumbprint,'/fd','SHA256',$cat)
  $cer=Join-Path $prepared.Work 'package.cer'; Export-Certificate -Cert $cert -FilePath $cer | Out-Null
  foreach($store in @('Root','TrustedPublisher')){Import-Certificate -FilePath $cer -CertStoreLocation ('Cert:\LocalMachine\'+$store) | Out-Null}
  Remove-Item -LiteralPath ('Cert:\LocalMachine\My\'+$cert.Thumbprint) -DeleteKey
  $null=Invoke-Checked $prepared.SignTool @('verify','/pa','/c',$cat,(Join-Path $prepared.Driver 'u0205306.inf'))
  $null=Invoke-Checked $prepared.SignTool @('verify','/kp','/c',$prepared.OriginalCatalog,(Join-Path $prepared.Driver 'B026676\amdkmdag.sys'))
  $managedCat=Join-Path $prepared.Work ('Go2FSR4-'+$prepared.Id+'.cat'); Copy-Item $prepared.OriginalCatalog $managedCat
  $state.CatalogRegistered=$true; Save-State $state
  $null=Invoke-Checked $prepared.SignTool @('catdb','/g','{F750E6C3-38EE-11D1-85E5-00C04FC295EE}',$managedCat)
  try {$null=Invoke-Checked pnputil.exe @('/add-driver',(Join-Path $prepared.Driver 'u0205306.inf'),'/install') @(0,3010)}
  finally {$state.OwnedPackages=@(Get-OwnedPackages $before (Get-DriverInventory) $candidateHashes); Save-State $state}
  foreach($msi in (Get-MsiSpecs $prepared.Software)){
   $sig=Get-AuthenticodeSignature $msi.Path
   if($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Advanced Micro Devices'){throw 'MSI publisher verification failed.'}
   $state.SoftwareAttempted+=@($msi); Save-State $state
   Invoke-Msi $msi install (Join-Path $script:DataRoot ('logs\'+$msi.Product+'-install.log'))
  }
  # Keep OEM Store registration intact for rollback. Close only stale AMD UI processes.
  Get-Process RadeonSoftware,cncmd -ErrorAction SilentlyContinue | Where-Object {$_.Path -like '*\WindowsApps\AdvancedMicroDevicesInc-*'} | Stop-Process
  $after=Get-DeviceSnapshot
  if($after.Version -ne $script:Release.driverVersion -or $after.ProblemCode -ne 0){throw 'New driver did not bind cleanly.'}
  Assert-SecurePolicy; $state.Status='AwaitingInstallReboot'; Save-State $state
  Write-Status 'Installed. Restart Windows, then click Verify in this same installer. No automatic restart.'
 }catch{
  $state.Error=$_.Exception.Message; $state.Status='RecoveryRequired'
  $state.OwnedPackages=@(Get-OwnedPackages $before (Get-DriverInventory) $candidateHashes); Save-State $state
  throw ('Install incomplete. Use Uninstall to restore the verified backup. '+$state.Error)
 }finally{
  if($state.Certificate -and (Test-Path -LiteralPath ('Cert:\LocalMachine\My\'+$state.Certificate))){Remove-Item -LiteralPath ('Cert:\LocalMachine\My\'+$state.Certificate) -DeleteKey}
 }
}
function Verify-Go2 {
 $device=Get-DeviceSnapshot; $admin=Test-Administrator
 if($admin){Assert-SecurePolicy}
 $kernelSecurity=Get-KernelSecurityState
 $securityPassed=Test-KernelSecurityState $kernelSecurity
 $services=@(Get-CimInstance Win32_SystemDriver | Where-Object {$_.Name -like 'amduw*' -and $_.State -eq 'Running'})
 $kernels=@(foreach($svc in $services){
  $path=$svc.PathName.Trim('"') -replace '^\\SystemRoot',$env:WINDIR
  $hash=if(Test-Path -LiteralPath $path){(Get-FileHash $path).Hash}else{$null}
  [pscustomobject]@{Name=$svc.Name;Hash=$hash;MatchesPinnedKernel=($hash -eq $script:Release.kernelSha256)}
 })
 $passed=$device.Version -eq $script:Release.driverVersion -and $device.ProblemCode -eq 0 -and $device.SecureBootRegistry -eq 1 -and $securityPassed -and @($kernels | Where-Object MatchesPinnedKernel).Count -eq 1
 $report=[pscustomobject]@{Timestamp=(Get-Date -Format o);Device=$device;RunningKernels=$kernels;KernelSecurity=$kernelSecurity;KernelSecurityChecksPassed=$securityPassed;DriverChecksPassed=$passed;RestoredDriverChecksPassed=$false;OriginalBindingsChecksPassed=$false;LifecycleStatus='Unmanaged';FirmwareAndCodeIntegrityChecked=$admin;FsrRuntime='Not checked by hardware verification';GamePerformance='Not checked';Managed=$false;RestartVerified=$false}
 if($admin){
  Initialize-StateDirectory; $state=Get-State
  if($state){
   $activeHash=(Get-FileHash -LiteralPath (Join-Path $env:WINDIR ('INF\'+$device.Inf))).Hash
   $originalPassed=Test-OriginalDriverBinding $device $state $activeHash
   $originalKernelHashes=@($state.BackupManifest | Where-Object {[IO.Path]::GetFileName($_.Path) -ieq 'amdkmdag.sys'} | ForEach-Object {$_.Hash} | Select-Object -Unique)
   $originalKernelPassed=$originalKernelHashes.Count -eq 1 -and @($kernels | Where-Object {$_.Hash -in $originalKernelHashes}).Count -eq 1
   $bindingsPassed=$false
   if($state.PSObject.Properties['BindingsBefore']){
    $currentBindings=@(Get-DeviceDriverBindings -InstanceIds @($state.BindingsBefore.InstanceId))
    $bindingsPassed=Test-DeviceDriverBindings @($state.BindingsBefore) $currentBindings
   }
   $restorePassed=$originalPassed -and $originalKernelPassed -and $bindingsPassed -and $securityPassed
   $candidatePassed=$passed -and $activeHash -in @($state.CandidateHashes) -and $device.InstanceId -eq $state.Before.InstanceId
   $status=Get-VerifiedLifecycleStatus $state $device $candidatePassed $restorePassed
   if($status -ne $state.Status){$state.Status=$status; Save-State $state}
   $report.LifecycleStatus=$state.Status
   $report.Managed=$state.Status -ne 'Uninstalled' -and ($originalPassed -or $candidatePassed)
   $report.RestoredDriverChecksPassed=$restorePassed
   $report.OriginalBindingsChecksPassed=$bindingsPassed
   if($state.Status -eq 'Installed' -and $device.BootId -ne $state.InstallBoot -and $candidatePassed){$report.RestartVerified=$true}
   if($state.Status -eq 'Uninstalled' -and $device.BootId -ne $state.UninstallBoot -and $restorePassed){$report.RestartVerified=$true}
  }; Save-Json $report (Join-Path $script:DataRoot 'verification.json')
 }; $report
}
function Uninstall-Go2 {
 # Recovery remains available even if a later release disables installation.
 Initialize-StateDirectory; Assert-SecurePolicy; $state=Get-State
 if(!$state){throw 'No owned installation journal. Unmanaged drivers will not be removed.'}
 if($state.Status -eq 'Uninstalled'){Write-Status 'Already uninstalled. Recovery records retained.'; return}
 if(!$state.PSObject.Properties['BindingsBefore'] -or !@($state.BindingsBefore).Count){throw 'Journal lacks original device bindings; manual recovery review required.'}
 foreach($row in $state.BackupManifest){Assert-Hash $row.Path $row.Hash}
 $device=Get-DeviceSnapshot
 if($device.InstanceId -ne $state.Before.InstanceId){throw 'Hardware no longer matches recovery journal.'}
 if($device.Version -notin @($state.Before.Version,$script:Release.driverVersion)){throw 'A different driver was installed later; automatic rollback stopped.'}
 $activeHash=(Get-FileHash -LiteralPath (Join-Path $env:WINDIR ('INF\'+$device.Inf))).Hash
 if($activeHash -notin (@($state.CandidateHashes)+@($script:Release.originalInfSha256))){throw 'Active INF was replaced outside this transaction; automatic rollback stopped.'}
 if(!('Go2Restore' -as [type])){Add-Type 'using System; using System.Runtime.InteropServices; public static class Go2Restore { [DllImport("newdev.dll",CharSet=CharSet.Unicode,SetLastError=true)] public static extern bool UpdateDriverForPlugAndPlayDevices(IntPtr h,string id,string inf,uint flags,out bool reboot); }'}
 $state.Status='Uninstalling'; Save-State $state
 try{
  $reboot=$false
  $ok=[Go2Restore]::UpdateDriverForPlugAndPlayDevices([IntPtr]::Zero,$script:Profile.Hardware.ExactHardwareId,$state.OriginalInf,1,[ref]$reboot)
  if(!$ok){throw ('Original driver restore failed, Win32 '+[Runtime.InteropServices.Marshal]::GetLastWin32Error())}
  $after=Get-DeviceSnapshot
  $restoredHash=(Get-FileHash -LiteralPath (Join-Path $env:WINDIR ('INF\'+$after.Inf))).Hash
  if(!(Test-OriginalDriverBinding $after $state $restoredHash)){throw 'Original driver identity, INF hash, health, or Secure Boot not verified; keeping all recovery material.'}
  $owned=@(Get-OwnedPackages @($state.InventoryBefore) (Get-DriverInventory) @($state.CandidateHashes))
  foreach($package in $owned){$null=Invoke-Checked pnputil.exe @('/delete-driver',$package.Driver,'/uninstall') @(0,3010)}
  $remaining=@(Get-OwnedPackages @($state.InventoryBefore) (Get-DriverInventory) @($state.CandidateHashes))
  if($remaining.Count){throw 'Owned packages remain in use. Restart and retry Uninstall; certificate trust retained.'}
  foreach($old in @($state.BackupManifest | Where-Object {$_.Path -like '*.inf'})){$null=Invoke-Checked pnputil.exe @('/add-driver',$old.Path,'/install') @(0,3010)}
  foreach($msi in @($state.SoftwareAttempted)){Invoke-Msi $msi uninstall (Join-Path $script:DataRoot ('logs\'+$msi.Product+'-uninstall.log'))}
  $after=Get-DeviceSnapshot
  $restoredHash=(Get-FileHash -LiteralPath (Join-Path $env:WINDIR ('INF\'+$after.Inf))).Hash
  if(!(Test-OriginalDriverBinding $after $state $restoredHash)){throw 'Original binding changed during cleanup; certificate trust retained.'}
  $currentBindings=@(Get-DeviceDriverBindings -InstanceIds @($state.BindingsBefore.InstanceId))
  if(!(Test-DeviceDriverBindings @($state.BindingsBefore) $currentBindings)){throw 'Original companion device bindings are not restored. Restart and retry Uninstall; certificate trust retained.'}
  if($state.CatalogRegistered){
   $null=Invoke-Checked $state.Prepared.SignTool @('catdb','/g','{F750E6C3-38EE-11D1-85E5-00C04FC295EE}','/r',('Go2FSR4-'+$state.Prepared.Id+'.cat'))
   $state.CatalogRegistered=$false; Save-State $state
  }
  if($state.Certificate){foreach($store in @('Root','TrustedPublisher','My')){
   $certPath='Cert:\LocalMachine\'+$store+'\'+$state.Certificate
   if(Test-Path -LiteralPath $certPath){if($store -eq 'My'){Remove-Item -LiteralPath $certPath -DeleteKey}else{Remove-Item -LiteralPath $certPath}}
  }}
  Assert-SecurePolicy
  $state.Status='AwaitingUninstallReboot'; $state.UninstallBoot=(Get-DeviceSnapshot).BootId; $state.Error=$null; Save-State $state
  Write-Status 'Original driver restored; owned packages/software/trust removed. Restart, then Verify. Backup/logs retained.'
 }catch{$state.Status='RecoveryRequired'; $state.Error=$_.Exception.Message; Save-State $state; throw}
}

