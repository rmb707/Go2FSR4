#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$OfficialInfPath,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [Parameter(Mandatory=$true)][string]$SelectedProfilePath
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$ExpectedOfficialHash='884C91EF4681D3E383B48DC760B4B2A95C95281E5796686A99A40B44FF65EE9D'
function Get-Sha256Bytes {
    param([Parameter(Mandatory)][byte[]]$Bytes)

    $Sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($Sha.ComputeHash($Bytes))).Replace('-','')
    }
    finally {
        $Sha.Dispose()
    }
}

function Get-Sha256File {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-ExactCount {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Value
    )

    $Count = 0
    $Offset = 0

    while ($true) {
        $Index = $Text.IndexOf($Value, $Offset, [StringComparison]::Ordinal)
        if ($Index -lt 0) {
            break
        }

        $Count++
        $Offset = $Index + $Value.Length
    }

    return $Count
}

function Require-Count {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][int]$Expected
    )

    $Actual = Get-ExactCount -Text $Text -Value $Value
    if ($Actual -ne $Expected) {
        throw "Exact source-count mismatch. Expected=$Expected Actual=$Actual Value=[$Value]"
    }
}

function Replace-Exact {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$OldValue,
        [Parameter(Mandatory)][AllowEmptyString()][string]$NewValue,
        [int]$ExpectedCount = 1
    )

    Require-Count -Text $Text -Value $OldValue -Expected $ExpectedCount
    return $Text.Replace($OldValue, $NewValue)
}

function Require-CrLfOnly {
    param([Parameter(Mandatory)][string]$Text)

    for ($i = 0; $i -lt $Text.Length; $i++) {
        if ($Text[$i] -eq "`n" -and ($i -eq 0 -or $Text[$i - 1] -ne "`r")) {
            throw "Official INF contains a non-CRLF line ending at character $i."
        }

        if ($Text[$i] -eq "`r" -and ($i + 1 -ge $Text.Length -or $Text[$i + 1] -ne "`n")) {
            throw "Official INF contains a non-CRLF line ending at character $i."
        }
    }
}

function Get-SectionBody {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$SectionName
    )

    $Header = "[$SectionName]"
    $Start = $Text.IndexOf($Header, [StringComparison]::Ordinal)

    if ($Start -lt 0) {
        throw "Section not found: $Header"
    }

    $Second = $Text.IndexOf($Header, $Start + $Header.Length, [StringComparison]::Ordinal)
    if ($Second -ge 0) {
        throw "Section appears more than once: $Header"
    }

    $BodyStart = $Start + $Header.Length
    if ($BodyStart + 1 -lt $Text.Length -and $Text.Substring($BodyStart, 2) -eq "`r`n") {
        $BodyStart += 2
    }

    $End = $Text.IndexOf("`r`n[", $BodyStart, [StringComparison]::Ordinal)
    if ($End -lt 0) {
        throw "Section end not found: $Header"
    }

    return $Text.Substring($BodyStart, $End - $BodyStart)
}

function Convert-ToUnicodeInfBytes {
    param([Parameter(Mandatory)][string]$Text)

    $Encoding = New-Object System.Text.UnicodeEncoding($false, $true, $true)
    [byte[]]$Body = $Encoding.GetBytes($Text)
    [byte[]]$Preamble = $Encoding.GetPreamble()
    [byte[]]$Output = New-Object byte[] ($Preamble.Length + $Body.Length)

    [Array]::Copy($Preamble, 0, $Output, 0, $Preamble.Length)
    [Array]::Copy($Body, 0, $Output, $Preamble.Length, $Body.Length)

    return ,$Output
}

function New-Profile {
    param(
        [string]$Name,
        [string]$TargetHardwareId,
        [string]$ModelAnchorLine,
        [string]$ModelToken,
        [string]$BaseInstallSection,
        [string]$DedicatedInstallSection,
        [string[]]$BannerLines,
        [object[]]$InstallBodyInsertions,
        [object[]]$CustomSections,
        [int]$ExpectedOemDirectiveCount
    )

    return [pscustomobject]@{
        Name = $Name
        TargetHardwareId = $TargetHardwareId
        ModelAnchorLine = $ModelAnchorLine
        ModelToken = $ModelToken
        BaseInstallSection = $BaseInstallSection
        DedicatedInstallSection = $DedicatedInstallSection
        BannerLines = $BannerLines
        InstallBodyInsertions = $InstallBodyInsertions
        CustomSections = $CustomSections
        ExpectedOemDirectiveCount = $ExpectedOemDirectiveCount
    }
}

function Build-ProfileInf {
    param(
        [Parameter(Mandatory)][byte[]]$OfficialSource,
        [Parameter(Mandatory)]$Profile
    )

    $Latin1 = [Text.Encoding]::GetEncoding(28591)
    $Text = $Latin1.GetString($OfficialSource)

    Require-CrLfOnly -Text $Text

    Require-Count -Text $Text -Value $Profile.TargetHardwareId -Expected 0
    Require-Count -Text $Text -Value ('CopyINF = .\amdcp\amdcp.inf'+"`r`n") -Expected 10
    Require-Count -Text $Text -Value ('CopyINF=amduw23e.inf'+"`r`n") -Expected 10
    Require-Count -Text $Text -Value 'HKR,"UMD\DXVA",ColorVibrance_ENABLE_DEF,%REG_SZ%,1' -Expected 1
    Require-Count -Text $Text -Value 'HKR,,ShowRSOverlay,%REG_SZ%,true' -Expected 4
    Require-Count -Text $Text -Value 'HKR,,ShowRSOverlay,%REG_SZ%,false' -Expected 2
    Require-Count -Text $Text -Value '[FDANSComponent]' -Expected 1
    Require-Count -Text $Text -Value $Profile.ModelAnchorLine -Expected 1

    $TargetModelLine =
        '"' + $Profile.ModelToken + '" = ' +
        $Profile.DedicatedInstallSection + ', ' +
        $Profile.TargetHardwareId

    $Text = Replace-Exact `
        -Text $Text `
        -OldValue $Profile.ModelAnchorLine `
        -NewValue ($Profile.ModelAnchorLine + "`r`n" + $TargetModelLine)

    $Text = Replace-Exact `
        -Text $Text `
        -OldValue ('CopyINF = .\amdcp\amdcp.inf'+"`r`n") `
        -NewValue '' `
        -ExpectedCount 10

    $Text = Replace-Exact `
        -Text $Text `
        -OldValue ('CopyINF=amduw23e.inf'+"`r`n") `
        -NewValue '' `
        -ExpectedCount 10

    $ComponentAnchor =
        '[' + $Profile.BaseInstallSection + '.Components]' + "`r`n" +
        'AddComponent = AMDCP,,AMDCPComponent'

    $ComponentReplacement =
        '[' + $Profile.BaseInstallSection + '.Components]' + "`r`n" +
        'AddComponent = AMDUWP,,AMDUWPComponent' + "`r`n" +
        'AddComponent = AMDCP,,AMDCPComponent'

    $Text = Replace-Exact `
        -Text $Text `
        -OldValue $ComponentAnchor `
        -NewValue $ComponentReplacement

    $Text = Replace-Exact `
        -Text $Text `
        -OldValue '[FDANSComponent]' `
        -NewValue ('[AMDUWPComponent]'+"`r`n"+
                   'ComponentIDs=VID1002&PID0001'+"`r`n`r`n"+
                   '[FDANSComponent]')

    $Body = Get-SectionBody -Text $Text -SectionName $Profile.BaseInstallSection

    foreach ($Insertion in $Profile.InstallBodyInsertions) {
        $Body = Replace-Exact `
            -Text $Body `
            -OldValue ([string]$Insertion.Anchor) `
            -NewValue (([string]$Insertion.Anchor) + "`r`n" + ([string]$Insertion.Line))
    }

    $Services = Get-SectionBody -Text $Text -SectionName ($Profile.BaseInstallSection + '.Services')
    $Hardware = Get-SectionBody -Text $Text -SectionName ($Profile.BaseInstallSection + '.HW')
    $Software = Get-SectionBody -Text $Text -SectionName ($Profile.BaseInstallSection + '.Software')
    $Components = Get-SectionBody -Text $Text -SectionName ($Profile.BaseInstallSection + '.Components')
    $General = Get-SectionBody -Text $Text -SectionName ($Profile.BaseInstallSection + '.GeneralConfigData')

    $FamilyLines = [System.Collections.Generic.List[string]]::new()

    foreach ($Line in $Profile.BannerLines) {
        [void]$FamilyLines.Add([string]$Line)
    }

    foreach ($Pair in @(
        [pscustomobject]@{ Name=$Profile.DedicatedInstallSection; Body=$Body },
        [pscustomobject]@{ Name=($Profile.DedicatedInstallSection + '.Services'); Body=$Services },
        [pscustomobject]@{ Name=($Profile.DedicatedInstallSection + '.HW'); Body=$Hardware },
        [pscustomobject]@{ Name=($Profile.DedicatedInstallSection + '.Software'); Body=$Software },
        [pscustomobject]@{ Name=($Profile.DedicatedInstallSection + '.Components'); Body=$Components },
        [pscustomobject]@{ Name=($Profile.DedicatedInstallSection + '.GeneralConfigData'); Body=$General }
    )) {
        [void]$FamilyLines.Add('[' + [string]$Pair.Name + ']')
        [void]$FamilyLines.Add([string]$Pair.Body)
        [void]$FamilyLines.Add('')
    }

    $DirectiveCount = 0

    foreach ($Section in $Profile.CustomSections) {
        [void]$FamilyLines.Add('[' + [string]$Section.Name + ']')

        foreach ($Line in $Section.Lines) {
            [void]$FamilyLines.Add([string]$Line)
            $DirectiveCount++
        }

        [void]$FamilyLines.Add('')
    }

    if ($DirectiveCount -ne $Profile.ExpectedOemDirectiveCount) {
        throw "$($Profile.Name): OEM directive-count mismatch. Expected=$($Profile.ExpectedOemDirectiveCount) Actual=$DirectiveCount"
    }

    $Family = [string]::Join("`r`n", $FamilyLines.ToArray())

    $Text = Replace-Exact `
        -Text $Text `
        -OldValue '[Strings]' `
        -NewValue ($Family + "`r`n[Strings]")

    Require-Count -Text $Text -Value $Profile.TargetHardwareId -Expected 1
    Require-Count -Text $Text -Value ("["+$Profile.DedicatedInstallSection+"]") -Expected 1
    Require-Count -Text $Text -Value ("["+$Profile.DedicatedInstallSection+".Services]") -Expected 1
    Require-Count -Text $Text -Value ("["+$Profile.DedicatedInstallSection+".HW]") -Expected 1
    Require-Count -Text $Text -Value ("["+$Profile.DedicatedInstallSection+".Software]") -Expected 1
    Require-Count -Text $Text -Value ("["+$Profile.DedicatedInstallSection+".Components]") -Expected 1
    Require-Count -Text $Text -Value ("["+$Profile.DedicatedInstallSection+".GeneralConfigData]") -Expected 1
    Require-Count -Text $Text -Value '[AMDUWPComponent]' -Expected 1
    Require-Count -Text $Text -Value ('CopyINF = .\amdcp\amdcp.inf'+"`r`n") -Expected 0
    Require-Count -Text $Text -Value ('CopyINF=amduw23e.inf'+"`r`n") -Expected 0

    foreach ($Section in $Profile.CustomSections) {
        Require-Count -Text $Text -Value ('[' + [string]$Section.Name + ']') -Expected 1
    }

    [byte[]]$Output = Convert-ToUnicodeInfBytes -Text $Text

    return [pscustomobject]@{
        Bytes = $Output
        Sha256 = Get-Sha256Bytes -Bytes $Output
        Length = $Output.Length
        OemDirectiveCount = $DirectiveCount
        TargetModelLine = $TargetModelLine
    }
}


$Go1 = New-Profile `
    -Name 'Legion Go 1 Z1 Extreme' `
    -TargetHardwareId 'PCI\VEN_1002&DEV_15BF&SUBSYS_381217AA&REV_04' `
    -ModelAnchorLine '"%AMD15BF.1%" = ati2mtag_Phoenix, PCI\VEN_1002&DEV_15BF&SUBSYS_16771025&REV_C1' `
    -ModelToken '%AMD15BF.1%' `
    -BaseInstallSection 'ati2mtag_Phoenix' `
    -DedicatedInstallSection 'ati2mtag_Phoenix_LegionGo' `
    -BannerLines @(
        '; ============================================================',
        '; Legion Go exact-HWID merged DDInstall family',
        '; AMD 26.10.1 / Public Beta v5.0 candidate',
        '; 26.10.1 Phoenix family cloned from exact official source',
        '; Lenovo-required compatibility semantics retained from the field-proven v4.5.1 profile',
        '; AMD ColorVibrance / RS overlay defaults intentionally preserved',
        '; ============================================================'
    ) `
    -InstallBodyInsertions @(
        [pscustomobject]@{
            Anchor='AddReg = ati2mtag_DSUMD_GFX10_3Plus'
            Line='AddReg = LegionGo_26_10_1_Lenovo_Delta'
        },
        [pscustomobject]@{
            Anchor='DelReg = ati2mtag_RemoveDeviceSettings'
            Line='AddReg = LegionGo_26_10_1_OEM_Settings'
        }
    ) `
    -CustomSections @(
        [pscustomobject]@{
            Name='LegionGo_26_10_1_Lenovo_Delta'
            Lines=@(
                'HKR,,DALNonStandardModesBCD5,%REG_BINARY%,07,20,12,80,00,00,00,00,08,00,12,80,00,00,00,00,09,00,16,00,00,00,00,00,10,00,16,00,00,00,00,00,10,80,19,20,00,00,00,00,12,00,19,20,00,00,00,00,14,40,25,60,00,00,00,00',
                'HKR,,DALRestrictedModesBCD5,%REG_BINARY%,16,00,12,00,00,00,00,00,12,80,10,24,00,00,00,00',
                'HKR,,HotkeysDisabled,%REG_DWORD%,0x1',
                'HKR,,dvr_ui_component_na,%REG_SZ%,true',
                'HKR,,DFPFreeSyncDefault,%REG_DWORD%,1',
                'HKR,,PP_WaitOnRegisterTimeout,%REG_DWORD%,0x2710',
                'HKR,,AllowWebContent,%REG_SZ%,false',
                'HKR,,LogoUrl,%REG_SZ%,hide',
                'HKR,,SystemTray,%REG_SZ%,false',
                'HKR,,DALRULE_ALLOWMONITORRANGELIMITMODESCRT,%REG_DWORD%,0',
                'HKR,,ToggleRsHotkey,%REG_SZ%,none',
                'HKR,,LCDFreeSyncDefault,%REG_DWORD%,0x7',
                'HKR,,PP_UserVariBrightLevel,%REG_DWORD%,2',
                'HKR,,Dal_UserVariBrightLevel,%REG_DWORD%,2'
            )
        },
        [pscustomobject]@{
            Name='LegionGo_26_10_1_OEM_Settings'
            Lines=@(
                'HKR,,DalFeatureEnablePsrSU,%REG_DWORD%,0',
                'HKR,,DalDisableZ10,%REG_DWORD%,1',
                'HKR,,EnableswGCFakeCGCG,%REG_DWORD%,1',
                'HKR,,DalEmbeddedIntegerScalingSupport,%REG_DWORD%,1',
                'HKR,,DalPSRFeatureEnable,%REG_DWORD%,0',
                'HKR,,DalWirelessDisplaySupport,%REG_DWORD%,1',
                'HKR,,DalDetectRequireHpdHigh,%REG_DWORD%,0',
                'HKR,,DisableFBCSupport,%REG_DWORD%,1',
                'HKR,,SmartDCDefMode,%REG_DWORD%,0',
                'HKR,,BDC7EDEA37E855EFFD36, %REG_BINARY%,59,79,07,9B',
                'HKR,,BDC7EDEA40E855EFFDFB, %REG_BINARY%,59,79,07,9B'
            )
        }
    ) `
    -ExpectedOemDirectiveCount 25

$GoS = New-Profile `
    -Name 'Legion Go S Z1 Extreme' `
    -TargetHardwareId 'PCI\VEN_1002&DEV_15BF&SUBSYS_380C17AA&REV_04' `
    -ModelAnchorLine '"%AMD15BF.1%" = ati2mtag_Phoenix, PCI\VEN_1002&DEV_15BF&SUBSYS_16771025&REV_C1' `
    -ModelToken '%AMD15BF.1%' `
    -BaseInstallSection 'ati2mtag_Phoenix' `
    -DedicatedInstallSection 'ati2mtag_Phoenix_LegionGoS' `
    -BannerLines @(
        '; ============================================================',
        '; Legion Go S Z1 Extreme exact-HWID merged DDInstall family',
        '; AMD 26.10.1 / Public Beta v5.0 candidate',
        '; 26.10.1 Phoenix family cloned from exact official source',
        '; Lenovo OEM compatibility semantics retained from the field-proven v4.5.1 profile',
        '; Lenovo AddReg remains after AMD DelReg',
        '; ============================================================'
    ) `
    -InstallBodyInsertions @(
        [pscustomobject]@{
            Anchor='DelReg = ati2mtag_RemoveDeviceSettings'
            Line='AddReg = LegionGoS_26_10_1_OEM_Phoenix'
        }
    ) `
    -CustomSections @(
        [pscustomobject]@{
            Name='LegionGoS_26_10_1_OEM_Phoenix'
            Lines=@(
                'HKR,,DALNonStandardModesBCD5,%REG_BINARY%,07,20,12,80,00,00,00,00,08,00,12,80,00,00,00,00,09,00,16,00,00,00,00,00,09,60,05,40,00,00,00,00,09,60,06,00,00,00,00,00,10,00,16,00,00,00,00,00,10,80,19,20,00,00,00,00,12,00,19,20,00,00,00,00,12,80,07,20,00,00,00,00,12,80,08,00,00,00,00,00,14,40,25,60,00,00,00,00,16,00,09,00,00,00,00,00,16,00,10,00,00,00,00,00,19,20,10,80,00,00,00,00',
                'HKR,,DalMinBrightnessMillinits,%REG_DWORD%,0x2710',
                'HKR,,DALRestrictedModesBCD5,%REG_BINARY%,08,00,06,00,00,00,00,00,10,24,07,68,00,00,00,00,12,80,10,24,00,00,00,00,16,00,12,00,00,00,00,00,16,80,10,50,00,00,00,00',
                'HKR,,DalEdgeDimmingLevelMapping,%REG_DWORD%,0x03000000',
                'HKR,,PP_WaitOnRegisterTimeout,%REG_DWORD%,0x2710',
                'HKR,,AllowWebContent,%REG_SZ%,false',
                'HKR,,LogoUrl,%REG_SZ%,hide',
                'HKR,,SystemTray,%REG_SZ%,false',
                'HKR,"UMD\DXVA",DynamicContrast_ENABLE_DEF,%REG_SZ%,0',
                'HKR,,DALRULE_ALLOWMONITORRANGELIMITMODESCRT,%REG_DWORD%,0',
                'HKR,"UMD\DXVA",DXVA_WMV,%REG_SZ%,0',
                'HKR,"UMD\DXVA",DXVA_WMV_DEF,%REG_SZ%,0',
                'HKR,,DXVA_WMV_NA,%REG_SZ%,1',
                'HKR,,DalSupportExternalPanelDrr,%REG_DWORD%,1',
                'HKR,,DalDisableZ10,%REG_DWORD%,1',
                'HKR,,DalEdgeDimmingLevelMapping,%REG_DWORD%,0x03000000',
                'HKR,,EnableswGCForceAtcL24KbWa,%REG_DWORD%,1',
                'HKR,,DalPSRFeatureEnable,%REG_DWORD%,1',
                'HKR,,DisableFBCSupport,%REG_DWORD%,0',
                'HKR,,SmartDCSupported,%REG_DWORD%,1',
                'HKR,,SmartDCDefMode,%REG_DWORD%,0',
                'HKR,,DalDisplayableSupport,%REG_DWORD%,0',
                'HKR,,Gmx_EnableHwFlipQueue,%REG_DWORD%,0',
                'HKR,,KmdEnableHwFlipQueue,%REG_DWORD%,0',
                'HKR,,BDC72DEA40E855EFFDFB, %REG_BINARY%,59,79,07,9B',
                'HKR,,BDC7EDEA37E855EFFD36, %REG_BINARY%,59,79,07,9B',
                'HKR,,BDC7EDEA40E855EFFDFB, %REG_BINARY%,59,79,07,9B',
                'HKR,,BDC7F3EA40E855EFFDFB, %REG_BINARY%,59,79,07,9B',
                'HKR,,PP_UserVariBrightLevel,%REG_DWORD%,2',
                'HKR,,Dal_UserVariBrightLevel,%REG_DWORD%,2'
            )
        }
    ) `
    -ExpectedOemDirectiveCount 30

$Go2 = New-Profile `
    -Name 'Legion Go 2 Z2 Extreme' `
    -TargetHardwareId 'PCI\VEN_1002&DEV_150E&SUBSYS_381C17AA&REV_C5' `
    -ModelAnchorLine '"%AMD150E.517%" = ati2mtag_Strix, PCI\VEN_1002&DEV_150E&SUBSYS_381C17AA&REV_E4' `
    -ModelToken '%AMD150E.517%' `
    -BaseInstallSection 'ati2mtag_Strix' `
    -DedicatedInstallSection 'ati2mtag_Strix_LegionGo2' `
    -BannerLines @(
        '; ============================================================',
        '; Legion Go 2 Z2 Extreme exact-HWID merged DDInstall family',
        '; AMD 26.10.1 / Public Beta v5.0 candidate',
        '; 26.10.1 Strix family cloned from exact official source',
        '; Exact Lenovo 381C17AA/C5 identity retained from OEM evidence',
        '; Lenovo OEM compatibility semantics retained from the field-proven v4.5.1 profile',
        '; ============================================================'
    ) `
    -InstallBodyInsertions @(
        [pscustomobject]@{
            Anchor='DelReg = ati2mtag_RemoveDeviceSettings'
            Line='AddReg = LegionGo2_26_10_1_OEM_Strix'
        }
    ) `
    -CustomSections @(
        [pscustomobject]@{
            Name='LegionGo2_26_10_1_OEM_Strix'
            Lines=@(
                'HKR,,DALNonStandardModesBCD5,%REG_BINARY%,07,20,12,80,00,00,00,00,08,00,12,80,00,00,00,00,09,00,16,00,00,00,00,00,10,00,16,00,00,00,00,00,10,80,19,20,00,00,00,00,12,00,19,20,00,00,00,00,14,40,25,60,00,00,00,00',
                'HKR,,ProblemReportUrl,%REG_SZ%,show',
                'HKR,,DALRestrictedModesBCD5,%REG_BINARY%,16,00,12,00,00,00,00,00,12,80,10,24,00,00,00,00',
                'HKR,,HotkeysDisabled,%REG_DWORD%,0x1',
                'HKR,,dvr_ui_component_na,%REG_SZ%,true',
                'HKR,,DFPFreeSyncDefault,%REG_DWORD%,1',
                'HKR,,PP_WaitOnRegisterTimeout,%REG_DWORD%,0x2710',
                'HKR,,mobile_runtime_component_NA,%REG_SZ%,true',
                'HKR,,AllowWebContent,%REG_SZ%,false',
                'HKR,,LogoUrl,%REG_SZ%,hide',
                'HKR,,SystemTray,%REG_SZ%,false',
                'HKR,,DalWFDEnable,%REG_DWORD%,1',
                'HKR,"UMD\DXVA",ColorVibrance_DEF,%REG_SZ%,40',
                'HKR,"UMD\DXVA",ColorVibrance_ENABLE_DEF,%REG_SZ%,0',
                'HKR,,DALRULE_ALLOWMONITORRANGELIMITMODESCRT,%REG_DWORD%,0',
                'HKR,,InitDelay,%REG_DWORD%,0x7FFFFFFF',
                'HKR,,ToggleRsHotkey,%REG_SZ%,none',
                'HKR,,LCDFreeSyncDefault,%REG_DWORD%,0x7',
                'HKR,,ShowRSOverlay,%REG_SZ%,false',
                'HKR,,DalMinBrightnessMillinits,%REG_DWORD%,0x1388',
                'HKR,,DalFeatureEnablePsrSU,%REG_DWORD%,0',
                'HKR,,DalDisableZ10,%REG_DWORD%,1',
                'HKR,,EnableswGCForceAtcL24KbWa,%REG_DWORD%,1',
                'HKR,,DalWirelessDisplaySupport,%REG_DWORD%,1',
                'HKR,,DalDetectRequireHpdHigh,%REG_DWORD%,0',
                'HKR,,BDC7E3EAF1E855EFFD3A, %REG_BINARY%,9B,16,09,9B',
                'HKR,,PP_UserVariBrightLevel,%REG_DWORD%,3',
                'HKR,,Dal_UserVariBrightLevel,%REG_DWORD%,3'
            )
        }
    ) `
    -ExpectedOemDirectiveCount 28

if(-not(Test-Path -LiteralPath $SelectedProfilePath -PathType Leaf)){throw "Selected profile is missing: $SelectedProfilePath"}
$Profile=Get-Content -LiteralPath $SelectedProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
if(-not [bool]$Profile.InstallCapable){throw "Selected profile is not install-capable: $([string]$Profile.Id)"}

$SelectedBuildProfile=$null
$ExpectedFinalHash=''
$ExpectedFinalLength=0
$ExpectedDirectiveCount=0

switch([string]$Profile.Id){
    'LegionGo1' {
        $SelectedBuildProfile=$Go1
        $ExpectedFinalHash='AE9D42FEA2FCBD6739CF1E4F540EA4A7F21EF5DA099C66F603130843462E747D'
        $ExpectedFinalLength=2246098
        $ExpectedDirectiveCount=25
    }
    'LegionGoS-Z1Extreme' {
        $SelectedBuildProfile=$GoS
        $ExpectedFinalHash='6108B18E339E221506CB153B2F77B9521D1C7DF9B23429BA61381979A5BFE42E'
        $ExpectedFinalLength=2246940
        $ExpectedDirectiveCount=30
    }
    'LegionGo2-Z2Extreme' {
        $SelectedBuildProfile=$Go2
        $ExpectedFinalHash='7201A6EC902929B2292BA4AA014645CA98A0B7B65777F15EA77D0BAB8D1B8DDB'
        $ExpectedFinalLength=2246038
        $ExpectedDirectiveCount=28
    }
    default { throw "Unsupported selected profile for INF build: $([string]$Profile.Id)" }
}

if(([string]$Profile.Hardware.ExactHardwareId) -cne [string]$SelectedBuildProfile.TargetHardwareId){throw 'Profile/build HWID mismatch.'}
if(([string]$Profile.Amd.BaseInstallSection) -cne [string]$SelectedBuildProfile.BaseInstallSection){throw 'Profile/build base DDInstall mismatch.'}
if(([string]$Profile.Amd.DedicatedInstallSection) -cne [string]$SelectedBuildProfile.DedicatedInstallSection){throw 'Profile/build dedicated DDInstall mismatch.'}
if(([string]$Profile.Final.ExpectedInfSHA256).ToUpperInvariant() -cne $ExpectedFinalHash){throw 'Profile final INF hash changed.'}
if((Get-Sha256File $OfficialInfPath) -cne $ExpectedOfficialHash){throw 'Official 26.10.1 INF hash mismatch.'}

[byte[]]$Official=[IO.File]::ReadAllBytes($OfficialInfPath)
$Built=Build-ProfileInf -OfficialSource $Official -Profile $SelectedBuildProfile
if($Built.Sha256 -cne $ExpectedFinalHash){throw "Final INF hash mismatch. Expected=$ExpectedFinalHash Actual=$($Built.Sha256)"}
if($Built.Length -ne $ExpectedFinalLength){throw "Final INF length mismatch. Expected=$ExpectedFinalLength Actual=$($Built.Length)"}
if($Built.OemDirectiveCount -ne $ExpectedDirectiveCount){throw "Final INF OEM directive mismatch. Expected=$ExpectedDirectiveCount Actual=$($Built.OemDirectiveCount)"}

$Parent=Split-Path -Parent $OutputPath
if(-not(Test-Path -LiteralPath $Parent -PathType Container)){New-Item -ItemType Directory -Path $Parent -Force|Out-Null}
[IO.File]::WriteAllBytes($OutputPath,[byte[]]$Built.Bytes)
if((Get-Sha256File $OutputPath) -cne $ExpectedFinalHash){throw 'Written final INF hash changed.'}
Write-Host ("[PASS] Deterministic {0} AMD 26.10.1 INF: {1}" -f [string]$Profile.Id,$ExpectedFinalHash)
