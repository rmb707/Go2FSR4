param([ValidateSet('Gui','Verify','Prepare','Install','Uninstall')][string]$Action='Gui')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Core.ps1')
. (Join-Path $PSScriptRoot 'Lifecycle.ps1')
$mutex=New-Object Threading.Mutex($false,'Global\Go2FSR4-Operation')
$held=$false
try {
 try{$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}
 if(!$held){throw 'Another Go2FSR4 operation is already running.'}
 if($Action -ne 'Gui'){
  switch($Action){
   Verify {Verify-Go2 | ConvertTo-Json -Depth 8}
   Prepare {New-PreparedPackage}
   Install {Install-Go2}
   Uninstall {Uninstall-Go2}
  }; exit 0
 }
 Add-Type -AssemblyName System.Windows.Forms,System.Drawing
 [Windows.Forms.Application]::EnableVisualStyles()
 $form=New-Object Windows.Forms.Form
 $form.Text='Go2FSR4'; $form.Size=New-Object Drawing.Size(820,640); $form.MinimumSize=$form.Size
 $form.StartPosition='CenterScreen'; $form.Font=New-Object Drawing.Font('Segoe UI',10)
 $heading=New-Object Windows.Forms.Label
 $heading.Text='Go2FSR4'; $heading.Font=New-Object Drawing.Font('Segoe UI',25,[Drawing.FontStyle]::Bold)
 $heading.SetBounds(22,16,740,50); $form.Controls.Add($heading)
 $intro=New-Object Windows.Forms.Label
 $intro.Text="FSR 4.1.2 / Adrenalin 26.10.1 for Legion Go 2 Z2 Extreme`r`nSecure Boot stays enabled. Install, verify, and restore from the same app."
 $intro.SetBounds(24,70,750,52); $form.Controls.Add($intro)
 $notice=New-Object Windows.Forms.Label
 $notice.Text=if($script:Release.liveInstallEnabled){'Experimental community release. Read the README and recovery instructions first.'}else{'DEVELOPMENT BUILD: installation disabled until lifecycle and recovery testing passes.'}
 $notice.ForeColor=[Drawing.Color]::DarkRed; $notice.SetBounds(24,130,750,44); $form.Controls.Add($notice)
 $output=New-Object Windows.Forms.TextBox
 $output.Multiline=$true; $output.ReadOnly=$true; $output.ScrollBars='Both'; $output.WordWrap=$false
 $output.Font=New-Object Drawing.Font('Consolas',9); $output.SetBounds(24,238,750,320)
 $output.Anchor='Top,Bottom,Left,Right'; $form.Controls.Add($output)
 $script:busy=$false; $script:buttons=@()
 $script:LogSink={param($text) $output.AppendText($text+"`r`n"); [Windows.Forms.Application]::DoEvents()}
 $actions=@('Verify','Prepare','Install','Uninstall','Check FSR')
 for($i=0;$i -lt $actions.Count;$i++){
  $button=New-Object Windows.Forms.Button; $button.Text=$actions[$i]; $button.Tag=$actions[$i]
  $button.SetBounds((24+($i*151)),184,140,38); $form.Controls.Add($button); $script:buttons+=@($button)
  $button.Add_Click({
   param($sender,$eventArgs)
   if($script:busy){return}; $script:busy=$true
   foreach($item in $script:buttons){$item.Enabled=$false}
   try{
    switch([string]$sender.Tag){
     Verify {
      $report=Verify-Go2
      Write-Status ('Driver: '+$report.Device.Version+' | Device error code: '+$report.Device.ProblemCode)
      Write-Status ('Secure Boot reported enabled: '+($report.Device.SecureBootRegistry -eq 1))
      Write-Status ('Current boot Secure Boot and Code Integrity verified: '+$report.KernelSecurityChecksPassed)
      Write-Status ('FSR driver and running kernel verified: '+$report.DriverChecksPassed)
      Write-Status ('Original Lenovo driver and companion devices restored: '+$report.RestoredDriverChecksPassed)
      Write-Status ('Installation status: '+$report.LifecycleStatus)
      Write-Status ('UEFI and Code Integrity checked directly: '+$report.FirmwareAndCodeIntegrityChecked)
      Write-Status ('Managed by this installer: '+$report.Managed+' | Managed restart verified: '+$report.RestartVerified)
      Write-Status 'FSR runtime: use Check FSR. Actual game rendering/performance require a game test.'
     }
     Prepare {New-PreparedPackage}
     Install {
      Assert-LiveRelease
      $choice=[Windows.Forms.MessageBox]::Show('This installs a locally modified AMD driver package and a machine-local package certificate. Secure Boot remains on. The screen may blink. A verified driver backup will be created first. Continue?','Go2FSR4 install','YesNo','Warning')
      if($choice -eq 'Yes'){Install-Go2}
     }
     Uninstall {
      $choice=[Windows.Forms.MessageBox]::Show('Restore the backed-up Lenovo driver and remove only changes recorded by this installer? Backups and logs will be kept.','Go2FSR4 restore','YesNo','Question')
      if($choice -eq 'Yes'){Uninstall-Go2}
     }
     'Check FSR' {
      $folder=New-Object Windows.Forms.FolderBrowserDialog
      $folder.Description='Select a game or SDK folder containing AMD-signed FidelityFX loader and upscaler DLLs. The originals will not be modified.'
      if($folder.ShowDialog() -eq 'OK'){
       Initialize-StateDirectory
       Test-FsrRuntime $folder.SelectedPath (Join-Path $script:DataRoot ('sessions\probe-'+[Guid]::NewGuid().ToString('N')))
      }; $folder.Dispose()
     }
    }
   }catch{Write-Status ('STOPPED: '+$_.Exception.Message)}finally{
    $script:busy=$false; foreach($item in $script:buttons){$item.Enabled=$true}
    if(!$script:Release.liveInstallEnabled){($script:buttons | Where-Object Text -eq 'Install').Enabled=$false}
   }
  })
 }
 if(!$script:Release.liveInstallEnabled){($script:buttons | Where-Object Text -eq 'Install').Enabled=$false}
 $footer=New-Object Windows.Forms.Label
 $footer.Text='No automatic restart. Verification distinguishes driver checks, FSR context creation, and actual game testing.'
 $footer.SetBounds(24,566,750,30); $footer.Anchor='Bottom,Left,Right'; $form.Controls.Add($footer)
 $form.Add_FormClosing({param($s,$e) if($script:busy){$e.Cancel=$true}})
 Write-Status ('Version '+$script:Release.version+' / '+$script:Release.channel)
 try{$device=Get-DeviceSnapshot; Write-Status ('Detected Legion Go 2 Z2 Extreme / Radeon 890M'); Write-Status ('Driver '+$device.Version+' | Secure Boot enabled: '+($device.SecureBootRegistry -eq 1))}catch{Write-Status $_.Exception.Message}
 [void]$form.ShowDialog(); $form.Dispose()
} finally {if($held){$mutex.ReleaseMutex()}; $mutex.Dispose()}

