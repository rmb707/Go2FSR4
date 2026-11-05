param()
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$root=Split-Path -Parent $PSScriptRoot
$data=Get-Content (Join-Path $root 'docs\benchmark-summary.json') -Raw | ConvertFrom-Json
$img=New-Object Drawing.Bitmap(1440,940)
$g=[Drawing.Graphics]::FromImage($img); $g.SmoothingMode='AntiAlias'; $g.TextRenderingHint='AntiAliasGridFit'
$bg=[Drawing.ColorTranslator]::FromHtml('#101820'); $g.Clear($bg)
$white=New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#F3F6F8'))
$muted=New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#BAC8D0'))
$green=New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#5FE0AF'))
$blue=New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#68ACFF'))
$track=New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#263541'))
$title=New-Object Drawing.Font('Segoe UI',38,[Drawing.FontStyle]::Bold)
$large=New-Object Drawing.Font('Segoe UI',28,[Drawing.FontStyle]::Bold)
$body=New-Object Drawing.Font('Segoe UI',21)
$small=New-Object Drawing.Font('Segoe UI',17)
try{
 $g.DrawString('Go2FSR4',$title,$white,55,35)
 $g.DrawString('COD benchmark | Legion Go 2 Z2 Extreme',$body,$muted,57,105)
 $g.DrawString('Adrenalin 26.10.1 | Secure Boot enabled on the tested device',$small,$muted,57,150)
 $g.DrawString('Output / internal resolution',$small,$muted,57,216)
 $g.DrawString('AVERAGE FPS',$small,$muted,495,216)
 for($i=0;$i -lt 2;$i++){
  $run=$data.runs[$i]; $y=280+($i*220)
  $g.DrawString($run.output,$large,$white,57,$y)
  $g.DrawString(('Internal: '+$run.render),$small,$muted,60,($y+52))
  $g.FillRectangle($track,495,$y,700,38)
  $g.FillRectangle($blue,495,$y,([single](700*$run.baseAverage/120)),38)
  $g.DrawString(($run.baseAverage.ToString()+' base'),$body,$white,1210,($y-1))
  $g.FillRectangle($track,495,($y+60),700,38)
  $g.FillRectangle($green,495,($y+60),([single](700*$run.generatedAverage/120)),38)
  $g.DrawString(($run.generatedAverage.ToString()+' with FG'),$body,$white,1210,($y+59))
  $g.DrawString(('Base 1% low: '+$run.baseLow1+' FPS   |   Reported input latency: '+$run.latencyMs+' ms'),$small,$muted,495,($y+112))
 }
 $g.DrawString(('Native FSR 4 | '+$data.upscalingMode+' | AMD frame generation'),$small,$white,57,738)
 $g.DrawString('Different output and internal resolutions. Same driver. Not a driver-only A/B.',$small,$muted,57,782)
 $g.DrawString('Single runs on one device. Generated-frame 1% low: 50 FPS in both runs.',$small,$muted,57,822)
 $g.DrawString('Measured Nov 4, 2026 | See README and methodology for limits.',$small,$muted,57,862)
 $img.Save((Join-Path $root 'docs\images\cod-results.png'),[Drawing.Imaging.ImageFormat]::Png)
}finally{
 $g.Dispose();$img.Dispose();foreach($obj in @($white,$muted,$green,$blue,$track,$title,$large,$body,$small)){$obj.Dispose()}
}
