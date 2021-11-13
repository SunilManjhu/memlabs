########################
### Config Functions ###
########################

function Get-UserConfiguration {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Configuration Name/File")]
        [string]$Configuration
    )

    $return = [PSCustomObject]@{
        Loaded  = $false
        Config  = $null
        Message = $null
    }

    # Add extension
    if (-not $Configuration.EndsWith(".json")) {
        $Configuration = "$Configuration.json"
    }

    # Get deployment configuration
    $configPath = Join-Path $Common.ConfigPath $Configuration
    if (-not (Test-Path $configPath)) {
        $sampleConfigPath = Join-Path $Common.ConfigPath "samples\$Configuration"
        if (-not (Test-Path $sampleConfigPath)) {
            $return.Message = "Get-UserConfiguration: $Configuration not found in $configPath or $sampleConfigPath. Please create the config manually or use genconfig.ps1, and try again."
            return $return
        }
        $configPath = $sampleConfigPath
    }

    try {
        Write-Log "Get-UserConfiguration: Loading $configPath." -LogOnly
        $config = Get-Content $configPath -Force | ConvertFrom-Json
        $return.Loaded = $true
        $return.Config = $config
        return $return
    }
    catch {
        $return.Message = "Get-UserConfiguration: Failed to load $configPath. $_"
        return $return
    }

}

# function Get-Files {

#     param (
#         [Parameter(Mandatory = $false, ParameterSetName = "ConfigFile", HelpMessage = "Configuration Name for which to download the files.")]
#         [string]$Configuration,
#         [Parameter(Mandatory = $false, ParameterSetName = "GetAll", HelpMessage = "Get all files.")]
#         [switch]$DownloadAll,
#         [Parameter(Mandatory = $false, HelpMessage = "Force redownloading the image, if it exists.")]
#         [switch]$Force,
#         [Parameter(Mandatory = $false, HelpMessage = "Dry Run.")]
#         [switch]$WhatIf
#     )

#     # Validate token exists
#     if ($Common.FatalError) {
#         Write-Log "Main: Critical Failure! $($Common.FatalError)" -Failure
#         return
#     }

#     Write-Host

#     if ($Configuration) {
#         $success = Get-FilesForConfiguration -Configuration $Configuration -Force:$Force -WhatIf:$WhatIf
#     }

#     if ($DownloadAll) {
#         $success = Get-FilesForConfiguration -DownloadAll -Force:$Force -WhatIf:$WhatIf
#     }

#     return $success
# }

function Get-FilesForConfiguration {
    param (
        [Parameter(Mandatory = $false, ParameterSetName = "ConfigFile", HelpMessage = "Configuration Name for which to download the files.")]
        [string]$Configuration,
        [Parameter(Mandatory = $false, ParameterSetName = "ConfigObject", HelpMessage = "Configuration Object for which to download the files.")]
        [object]$InputObject,
        [Parameter(Mandatory = $false, ParameterSetName = "All", HelpMessage = "Get all files.")]
        [switch]$DownloadAll,
        [Parameter(Mandatory = $false, HelpMessage = "Skip Hash Testing of downloaded files.")]
        [switch]$IgnoreHashFailure,
        [Parameter(Mandatory = $false, HelpMessage = "Force redownloading the image, if it exists.")]
        [switch]$ForceDownloadFiles,
        [Parameter(Mandatory = $false)]
        [switch]$UseCDN,
        [Parameter(Mandatory = $false, HelpMessage = "Dry Run.")]
        [switch]$WhatIf
    )

    # Load config file
    if ($Configuration -and -not $DownloadAll) {
        $result = Get-UserConfiguration -Configuration $Configuration
        if ($result.Loaded) {
            $config = $result.Config
        }
    }

    # Config object
    if ($InputObject) {
        $config = $InputObject
    }

    # Get unique items from config
    if ($config) {
        $operatingSystemsToGet = $config.virtualMachines.operatingSystem | Select-Object -Unique
        $sqlVersionsToGet = $config.virtualMachines.sqlVersion | Select-Object -Unique
    }

    Write-Log "Get-FilesForConfiguration: Downloading/Verifying Files required by specified config..." -Activity

    $allSuccess = $true

    foreach ($file in $Common.AzureFileList.OS) {

        if ($file.id -eq "vmbuildadmin") { continue }
        if (-not $DownloadAll -and $operatingSystemsToGet -notcontains $file.id) { continue }
        $worked = Get-FileFromStorage -File $file -ForceDownloadFiles:$ForceDownloadFiles -WhatIf:$WhatIf -UseCDN:$UseCDN -IgnoreHashFailure:$IgnoreHashFailure
        if (-not $worked) {
            $allSuccess = $false
        }
    }

    foreach ($file in $Common.AzureFileList.ISO) {
        if (-not $DownloadAll -and $sqlVersionsToGet -notcontains $file.id) { continue }
        $worked = Get-FileFromStorage -File $file -ForceDownloadFiles:$ForceDownloadFiles -WhatIf:$WhatIf -UseCDN:$UseCDN -IgnoreHashFailure:$IgnoreHashFailure
        if (-not $worked) {
            $allSuccess = $false
        }
    }

    return $allSuccess
}

function Add-ValidationMessage {
    param (
        [string]$Message,
        [object]$ReturnObject,
        [switch]$Failure,
        [switch]$Warning
    )

    $ReturnObject.Problems += 1
    [void]$ReturnObject.Message.AppendLine($Message)

    if ($Failure.IsPresent) {
        $ReturnObject.Failures += 1
    }

    if ($Warning.IsPresent) {
        $ReturnObject.Warnings += 1
    }
}

function Test-ValidVmOptions {
    param (
        [object] $ConfigObject,
        [object] $ReturnObject
    )

    # prefix
    if (-not $ConfigObject.vmOptions.prefix) {
        Add-ValidationMessage -Message "VM Options Validation: vmOptions.prefix not present in vmOptions. You must specify the prefix that will be added to name of Virtual Machine(s)." -ReturnObject $ReturnObject -Failure
    }

    # basePath
    if (-not $ConfigObject.vmOptions.basePath) {
        Add-ValidationMessage -Message "VM Options Validation: vmOptions.basePath not present in vmOptions. You must specify the base path where the Virtual Machines will be created." -ReturnObject $ReturnObject -Failure
    }
    else {
        if (-not $ConfigObject.vmOptions.basepath.Contains(":\")) {
            Add-ValidationMessage -Message "VM Options Validation: vmOptions.basePath value [$($ConfigObject.vmOptions.basePath)] is invalid. You must specify the full path. For example: E:\VirtualMachines" -ReturnObject $ReturnObject -Failure
        }
        else {
            $driveLetter = $ConfigObject.vmOptions.basepath.Substring(0, 1)
            if (-not (Test-Path "$driveLetter`:\")) {
                Add-ValidationMessage -Message "VM Options Validation: vmOptions.basePath value [$($ConfigObject.vmOptions.basePath)] is invalid. You must specify a valid path. For example: E:\VirtualMachines" -ReturnObject $ReturnObject -Failure
            }

            if ($driveLetter -in "C", "D", "Z") {
                Add-ValidationMessage -Message "VM Options Validation: vmOptions.basePath value [$($ConfigObject.vmOptions.basePath)] is invalid. You must specify a drive letter other than C/D/Z. For example: E:\VirtualMachines" -ReturnObject $ReturnObject -Failure
            }
        }
    }

    # domainName
    if (-not $ConfigObject.vmOptions.domainName) {
        Add-ValidationMessage -Message "VM Options Validation: vmOptions.domainName not present in vmOptions. You must specify the Domain name." -ReturnObject $ReturnObject -Failure
    }
    else {

        # contains .
        if (-not $ConfigObject.vmOptions.domainName.Contains(".")) {
            Add-ValidationMessage -Message "VM Options Validation: vmOptions.domainName value [$($ConfigObject.vmOptions.domainName)] is invalid. You must specify the Full Domain name. For example: contoso.com" -ReturnObject $ReturnObject -Failure
        }

        # valid domain name
        $pattern = "^((?!-)[A-Za-z0-9-]{1,63}(?<!-)\.)+[A-Za-z]{2,6}$"
        if (-not ($ConfigObject.vmOptions.domainName -match $pattern)) {
            Add-ValidationMessage -Message "VM Options Validation: vmOptions.domainName value [$($ConfigObject.vmOptions.domainName)] contains invalid characters, is too long, or too short. You must specify a valid Domain name. For example: contoso.com." -ReturnObject $ReturnObject -Failure
        }

        $netBiosDomain = $ConfigObject.vmOptions.domainName.Split(".")[0]
        if ($netBiosDomain.Length -gt 15) {
            Add-ValidationMessage -Message "VM Options Validation: vmOptions.domainName [$($ConfigObject.vmOptions.domainName)] is too long. Netbios domain name [$netBiosDomain] must be less than 15 chars." -ReturnObject $ReturnObject -Failure
        }

        if ($netBiosDomain.Length -lt 1) {
            Add-ValidationMessage -Message "VM Options Validation: vmOptions.domainName  [$($ConfigObject.vmOptions.domainName)] is too short. Must be at least 1 chars." -ReturnObject $ReturnObject -Failure
        }
    }

    # adminName
    if (-not $ConfigObject.vmOptions.adminName) {
        Add-ValidationMessage -Message "VM Options Validation: vmOptions.adminName not present in vmOptions. You must specify the Domain Admin user name that will be created." -ReturnObject $ReturnObject -Failure
    }
    else {

        $pattern = "[$([Regex]::Escape('/\[:;|=,@+*?<>') + '\]' + '\"'+'\s')]"
        if ($ConfigObject.vmOptions.adminName -match $pattern) {
            Add-ValidationMessage -Message "VM Options Validation: vmOptions.adminName [$($ConfigObject.vmoptions.adminName)] contains invalid characters. You must specify a valid domain username. For example: bob" -ReturnObject $ReturnObject -Failure
        }

        if ($ConfigObject.vmOptions.adminName.Length -gt 64) {
            Add-ValidationMessage -Message "VM Options Validation: vmOptions.adminName [$($ConfigObject.vmoptions.adminName)] is too long. Must be less than 64 chars" -ReturnObject $ReturnObject -Failure
        }

        if ($ConfigObject.vmOptions.adminName.Length -lt 3) {
            Add-ValidationMessage -Message "VM Options Validation: vmOptions.adminName [$($ConfigObject.vmoptions.adminName)] is too short. Must be at least 3 chars" -ReturnObject $ReturnObject -Failure
        }
    }

    # network
    if (-not $ConfigObject.vmOptions.network) {
        Add-ValidationMessage -Message "VM Options Validation: vmOptions.network not present in vmOptions. You must specify the Network subnet for the environment." -ReturnObject $ReturnObject -Failure
    }
    else {
        $pattern1 = "^(192.168)(.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5]).0)$"
        $pattern2 = "^(10)(.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])){2,2}.0$"
        $pattern3 = "^(172).(1[6-9]|2[0-9]|3[0-1])(.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])).0$"

        if ($ConfigObject.vmOptions.network -eq "10.250.250.0") {
            Add-ValidationMessage -Message "VM Options Validation: vmOptions.network [$($ConfigObject.vmoptions.network)] value is reserved for 'Cluster'. Please use a different subnet." -ReturnObject $ReturnObject -Warning
        }

        if ($ConfigObject.vmOptions.network -eq "172.31.250.0") {
            Add-ValidationMessage -Message "VM Options Validation: vmOptions.network [$($ConfigObject.vmoptions.network)] value is reserved for 'Internet' clients. Please use a different subnet." -ReturnObject $ReturnObject -Warning
        }
        elseif (-not ($ConfigObject.vmOptions.network -match $pattern1 -or $ConfigObject.vmOptions.network -match $pattern2 -or $ConfigObject.vmOptions.network -match $pattern3)) {
            Add-ValidationMessage -Message "VM Options Validation: vmOptions.network [$($ConfigObject.vmoptions.network)] value is invalid. You must specify a valid Class C Subnet. For example: 192.168.1.0" -ReturnObject $ReturnObject -Failure
        }

        $existingSubnet = Get-List -Type Subnet | Where-Object { $_.Subnet -eq $($ConfigObject.vmoptions.network) | Select-Object -First 1 }
        if ($existingSubnet) {
            if ($($ConfigObject.vmoptions.domainName) -ne $($existingSubnet.Domain)) {
                Add-ValidationMessage -Message "VM Options Validation: vmOptions.network [$($ConfigObject.vmoptions.network)] with vmOptions.domainName [$($ConfigObject.vmoptions.domainName)] is in use by existing Domain [$($existingSubnet.Domain)]. You must specify a different network" -ReturnObject $ReturnObject -Warning
            }
            $CASorPRI = ($ConfigObject.virtualMachines.role -contains "CAS") -or (($ConfigObject.virtualMachines.role -contains "Primary"))
            if ($CASorPRI) {
                $existingCASorPRI = @()
                $existingCASorPRI += Get-List -Type VM | Where-Object { $_.Subnet -eq $($ConfigObject.vmoptions.network) } | Where-Object { ($_.Role -eq "CAS") -or ($_.Role -eq "Primary") }
                if ($existingCASorPRI.Count -gt 0) {
                    Add-ValidationMessage -Message "VM Options Validation: vmOptions.network [$($ConfigObject.vmoptions.network)] is in use by an existing SiteServer in [$($existingSubnet.Domain)]. You must specify a different network" -ReturnObject $ReturnObject -Warning
                }

            }
        }

    }
}

function Test-ValidCmOptions {
    param (
        [object] $ConfigObject,
        [object] $ReturnObject
    )

    # version
    if ($Common.Supported.CMVersions -notcontains $ConfigObject.cmOptions.version) {
        Add-ValidationMessage -Message "CM Options Validation: cmOptions contains invalid CM Version [$($ConfigObject.cmOptions.version)]. Must be either 'current-branch' or 'tech-preview'." -ReturnObject $ReturnObject -Failure
    }

    # install
    if ($ConfigObject.cmOptions.install -isnot [bool]) {
        Add-ValidationMessage -Message "CM Options Validation: cmOptions.install has an invalid value [$($ConfigObject.cmOptions.install)]. Value must be either 'true' or 'false' without any quotes." -ReturnObject $ReturnObject -Failure
    }

    # updateToLatest
    if ($ConfigObject.cmOptions.updateToLatest -isnot [bool]) {
        Add-ValidationMessage -Message "CM Options Validation: cmOptions.updateToLatest has an invalid value [$($ConfigObject.cmOptions.updateToLatest)]. Value must be either 'true' or 'false' without any quotes." -ReturnObject $ReturnObject -Failure
    }

    # installDPMPRoles
    if ($ConfigObject.cmOptions.installDPMPRoles -isnot [bool]) {
        Add-ValidationMessage -Message "CM Options Validation: cmOptions.installDPMPRoles has an invalid value [$($ConfigObject.cmOptions.installDPMPRoles)]. Value must be either 'true' or 'false' without any quotes." -ReturnObject $ReturnObject -Failure
    }

    # pushClientToDomainMembers
    if ($ConfigObject.cmOptions.pushClientToDomainMembers -isnot [bool]) {
        Add-ValidationMessage -Message "CM Options Validation: cmOptions.pushClientToDomainMembers has an invalid value [$($ConfigObject.cmOptions.pushClientToDomainMembers)]. Value must be either 'true' or 'false' without any quotes." -ReturnObject $ReturnObject -Failure
    }

}

function Test-ValidVmSupported {
    param (
        [object] $VM,
        [object] $ConfigObject,
        [object] $ReturnObject
    )

    if (-not $VM) {
        throw
    }

    $vmName = $VM.vmName

    # vmName characters
    if ($vm.vmName.Length -gt 15) {
        Add-ValidationMessage -Message "VM Validation: [$vmName] has invalid name. Windows computer name cannot be more than 15 characters long." -ReturnObject $ReturnObject -Warning
    }

    #prefix + vmName combined name validation
    $pattern = "[$([Regex]::Escape('/\[:;|=,@+*?<>') + '\]' + '\"'+'\s')]"
    if ($($ConfigObject.vmOptions.prefix + $vm.vmName) -match $pattern) {
        Add-ValidationMessage -Message "VM Validation: [$vmName] contains invalid characters." -ReturnObject $ReturnObject -Failure
    }

    # Supported OS
    if ($VM.role -ne "OSDClient") {
        if ($Common.Supported.OperatingSystems -notcontains $vm.operatingSystem) {
            Add-ValidationMessage -Message "VM Validation: [$vmName] does not contain a supported operatingSystem [$($vm.operatingSystem)]." -ReturnObject $ReturnObject -Failure
        }
    }

    # Supported DSC Roles for Existing scenario
    if ($configObject.parameters.ExistingDCName) {
        # Supported DSC Roles for Existing Scenario
        if ($Common.Supported.RolesForExisting -notcontains $vm.role) {
            $supportedRoles = $Common.Supported.RolesForExisting -join ", "
            Add-ValidationMessage -Message "VM Validation: [$vmName] contains an unsupported role [$($vm.role)]. Supported values are: $supportedRoles" -ReturnObject $ReturnObject -Failure
        }
    }
    else {
        # Supported DSC Roles
        if ($Common.Supported.Roles -notcontains $vm.role) {
            $supportedRoles = $Common.Supported.Roles -join ", "
            Add-ValidationMessage -Message "VM Validation: [$vmName] contains an unsupported role [$($vm.role)]. Supported values are: $supportedRoles" -ReturnObject $ReturnObject -Failure
        }
    }

}

function Test-ValidVmMemory {
    param (
        [object] $VM,
        [object] $ReturnObject
    )

    if (-not $VM) {
        throw
    }

    $vmName = $VM.vmName
    $vmRole = $VM.role

    # Memory
    if (-not $VM.memory) {
        Add-ValidationMessage -Message "$vmRole Validation: [$vmName] does not contain memory value []. Specify desired memory; For example: 4GB" -ReturnObject $ReturnObject -Failure
    }
    else {

        $vmMemory = $VM.memory

        # not string
        if ($vmMemory -isnot [string]) {
            Add-ValidationMessage -Message "$vmRole Validation: [$vmName] memory value [$vmMemory] is invalid. Specify desired memory; For example: 4GB" -ReturnObject $ReturnObject -Failure
        }

        # memory doesn't contain MB/GB
        if ($vmMemory -is [string] -and -not ($vmMemory.ToUpperInvariant().EndsWith("MB") -or $vmMemory.ToUpperInvariant().EndsWith("GB"))) {
            Add-ValidationMessage -Message "$vmRole Validation: [$vmName] memory value [$vmMemory] is invalid. Specify desired memory with MB/GB; For example: 4GB" -ReturnObject $ReturnObject -Failure
        }

        # memory less than 512MB
        if ($vmMemory.ToUpperInvariant().EndsWith("MB") -and $([int]$vmMemory.ToUpperInvariant().Replace("MB", "")) -lt 512 ) {
            Add-ValidationMessage -Message "$vmRole Validation: [$vmName] memory value [$vmMemory] is invalid. Should be more than 512MB" -ReturnObject $ReturnObject -Failure
        }

        # memory greater than 64GB
        if ($vmMemory.ToUpperInvariant().EndsWith("GB") -and $([int]$vmMemory.ToUpperInvariant().Replace("GB", "")) -gt 64 ) {
            Add-ValidationMessage -Message "$vmRole Validation: [$vmName] memory value [$vmMemory] is invalid. Should be less than 64GB" -ReturnObject $ReturnObject -Failure
        }
    }

}

function Test-ValidVmDisks {
    param (
        [object] $VM,
        [object] $ReturnObject
    )

    if (-not $VM) {
        throw
    }

    $vmName = $VM.vmName
    $vmRole = $VM.role

    # Additional Disks
    if ($VM.additionalDisks) {
        $validLetters = 69..89 | ForEach-Object { [char]$_ }    # Letters E-Y
        $disks = $VM.additionalDisks
        $disks | Get-Member -MemberType NoteProperty | ForEach-Object {

            # valid drive letter
            if ($_.Name.Length -ne 1 -or $validLetters -notcontains $_.Name) {
                Add-ValidationMessage -Message "$vmRole Validation: [$vmName] contains invalid additional disks [$disks]; Disks must have a single drive letter between E and Y." -ReturnObject $ReturnObject -Failure
            }

            $size = $($vm.additionalDisks."$($_.Name)")

            if (-not $size.ToUpperInvariant().EndsWith("GB")) {
                Add-ValidationMessage -Message "$vmRole Validation: [$vmName] contains invalid additional disks [$disks]; Specify desired size in GB; For example: 200GB" -ReturnObject $ReturnObject -Failure
            }

            if ($size.ToUpperInvariant().EndsWith("GB") -and $([int]$size.ToUpperInvariant().Replace("GB", "")) -lt 10 ) {
                Add-ValidationMessage -Message "$vmRole Validation: [$vmName] contains invalid additional disks [$disks]; Disks must be larger than 10GB" -ReturnObject $ReturnObject -Failure
            }

            if ($size.ToUpperInvariant().EndsWith("GB") -and $([int]$size.ToUpperInvariant().Replace("GB", "")) -gt 1000 ) {
                Add-ValidationMessage -Message "$vmRole Validation: [$vmName] contains invalid additional disks [$disks]; Disks must be less than 1000GB" -ReturnObject $ReturnObject -Failure
            }
        }
    }

}

function Test-ValidVmProcs {
    param (
        [object] $VM,
        [object] $ReturnObject
    )

    if (-not $VM) {
        throw
    }

    $vmName = $VM.vmName
    $vmRole = $VM.role

    if (-not $VM.virtualProcs -or -not $VM.virtualProcs -is [int]) {
        Add-ValidationMessage -Message "$vmRole Validation: [$vmName] contains invalid virtualProcs [$($vm.virtualProcs)]. Specify desired virtualProcs; For example: 2" -ReturnObject $ReturnObject -Failure
    }
    else {
        $virtualProcs = $VM.virtualProcs
        if ($virtualProcs -gt 16 -or $virtualProcs -lt 1) {
            Add-ValidationMessage -Message "$vmRole Validation: [$vmName] virtualProcs value [$virtualProcs] is invalid. Specify a value from 1-16." -ReturnObject $ReturnObject -Failure
        }
    }

}

function Test-ValidVmServerOS {
    param (
        [object] $VM,
        [object] $ReturnObject
    )

    if (-not $VM) {
        throw
    }

    $vmName = $VM.vmName
    $vmRole = $VM.role

    if ($VM.operatingSystem -notlike "*Server*") {
        Add-ValidationMessage -Message "$vmRole Validation: [$vmName] contains invalid OS [$($VM.operatingSystem)]. OS must be a Server OS for Primary/CAS/DPMP roles, or when SQL is selected." -ReturnObject $ReturnObject -Warning
    }

}

function Test-ValidVmPath {
    param (
        [object] $VM,
        [string] $PathProperty,
        [string] $ValidPathExample,
        [object] $ReturnObject
    )

    if (-not $VM) {
        throw
    }

    if (-not $VM.$PathProperty) {
        return
    }

    $vmName = $VM.vmName
    $vmRole = $VM.role

    # path
    if (-not $VM.$PathProperty.Contains(":\") -or $VM.$PathProperty.EndsWith(":") -or $VM.$PathProperty.EndsWith("\")) {
        Add-ValidationMessage -Message "$vmRole Validation: VM [$vmName] contains invalid $PathProperty [$($VM.$PathProperty)]. Value must be a valid path; For example: ""$ValidPathExample""." -ReturnObject $ReturnObject -Failure
    }
    else {

        # valid drive
        $installDrive = $VM.$PathProperty.Substring(0, 1)

        if ($installDrive -in "A", "B", "D", "Z") {
            Add-ValidationMessage -Message "$vmRole Validation: VM [$vmName] contains invalid $PathProperty [$($VM.$PathProperty)]. A/B/D/Z drive letters are not allowed." -ReturnObject $ReturnObject -Failure
        }

        if ($installDrive -ne "C" -and -not $VM.additionalDisks) {
            Add-ValidationMessage -Message "$vmRole Validation: VM [$vmName] contains invalid $PathProperty [$($VM.$PathProperty)]. When using a drive other than C, additionalDisks must be defined." -ReturnObject $ReturnObject -Warning
        }

        if ($installDrive -ne "C" -and $VM.additionalDisks) {
            $defined = $VM.additionalDisks | Get-Member -Name $installDrive
            if (-not $defined) {
                Add-ValidationMessage -Message "$vmRole Validation: VM [$vmName] contains invalid $PathProperty [$($VM.$PathProperty)]. When using a drive other than C, additionalDisks must contain the desired drive letter." -ReturnObject $ReturnObject -Warning
            }
        }

    }
}

function Test-ValidRoleDC {
    param (
        [object] $ConfigObject,
        [object] $ReturnObject
    )

    $DCVM = $configObject.virtualMachines | Where-Object { $_.role -eq "DC" }
    $vmRole = "DC"

    $containsDC = $configObject.virtualMachines.role -contains "DC"
    $existingDC = $configObject.parameters.ExistingDCName
    $domain = $ConfigObject.vmOptions.domainName

    if ($containsDC) {

        if ($existingDC) {
            Add-ValidationMessage -Message "$vmRole Validation: DC Role specified in configuration and existing DC [$existingDC] found in this domain [$domain]. Adding a DC to existing environment is not supported." -ReturnObject $ReturnObject -Warning
        }

        # $MyInvocation.BoundParameters.ConfigObject.VirtualMachines | Out-Host
        if (Test-SingleRole -VM $DCVM -ReturnObject $ReturnObject) {

            # Server OS
            Test-ValidVmServerOS -VM $DCVM -ReturnObject $ReturnObject

            # No SQL on DC
            if ($DCVM.sqlVersion) {
                Add-ValidationMessage -Message "$vmRole Validation: Adding SQL on Domain Controller is not supported." -ReturnObject $ReturnObject -Warning
            }

        }
    }
    else {

        # Existing Scenario, without existing DC Name
        if (-not $existingDC) {
            Add-ValidationMessage -Message "$vmRole Validation: DC role not specified in the configuration file and existing DC not found." -ReturnObject $ReturnObject -Warning
        }

        if ($existingDC) {

            # Check VM exists in Hyper-V
            #$vm = Get-VM -Name $existingDC -ErrorAction SilentlyContinue
            $vm = Get-List -type VM | Where-Object { $_.vmName -eq $existingDC }
            if (-not $vm) {
                Add-ValidationMessage -Message "$vmRole Validation: Existing DC found [$existingDC] but VM with the same name was not found in Hyper-V." -ReturnObject $ReturnObject -Warning
            }
            else {
                if ($vm.State -eq "Running") {
                    # Check network in Hyper-V
                    # $vmnet = Get-VM -Name $existingDC -ErrorAction SilentlyContinue | Get-VMNetworkAdapter
                    # if ($vmnet.SwitchName -ne $configObject.vmOptions.network) {
                    #     Add-ValidationMessage -Message "$vmRole Validation: Existing DC [$existingDC] found but VM Switch [$($vmnet.SwitchName)] doesn't match specified network [$($configObject.vmOptions.network)]." -ReturnObject $ReturnObject -Warning
                    # }
                }
                else {
                    # VM Not running, cannot validate network
                    Add-ValidationMessage -Message "$vmRole Validation: Existing DC [$existingDC] found but VM is not Running." -ReturnObject $ReturnObject -Warning
                }

                # Account validation
                $vmProps = Get-List -Type VM -DomainName $($ConfigObject.vmOptions.DomainName) | Where-Object { $_.role -eq "DC" }
                if ($vmProps.AdminName -ne $ConfigObject.vmOptions.adminName) {
                    Add-ValidationMessage -Message "Account Validation: Existing DC [$existingDC] is using a different admin name [$($ConfigObject.vmOptions.adminName)] for deployment. You must use the existing admin user [$($vmProps.AdminName)]." -ReturnObject $ReturnObject -Warning
                    Get-List -FlushCache | Out-Null
                }
            }
        }
    }
}

function Test-ValidRoleCSPS {
    param (
        [object] $VM,
        [object] $ConfigObject,
        [object] $ReturnObject
    )

    if (-not $VM) {
        throw
    }

    $vmName = $VM.vmName
    $vmRole = $VM.role

    # Primary/CAS must contain SQL
    if (-not $VM.sqlVersion -and -not $VM.remoteSQLVM) {
        Add-ValidationMessage -Message "$vmRole Validation: VM [$vmName] does not contain sqlVersion; When deploying $vmRole Role, you must specify the SQL Version." -ReturnObject $ReturnObject -Warning
    }

    # Remote SQL
    if ($VM.remoteSQLVM) {
        $sqlServerName = $VM.remoteSQLVM
        $SQLVM = $ConfigObject.virtualMachines | Where-Object { $_.vmName -eq $sqlServerName }

        # Remote SQL must contain sqlVersion
        if ($SQLVM) {
            if (-not $SQLVM.sqlVersion) {
                Add-ValidationMessage -Message "$vmRole Validation: VM [$sqlServerName] does not contain sqlVersion; When deploying $vmRole Role with remote SQL, you must specify the SQL Version for SQL VM." -ReturnObject $ReturnObject -Warning
            }
        }
        else {
            Add-ValidationMessage -Message "$vmRole Validation: VM [$sqlServerName] does not exist; When deploying $vmRole Role with remote SQL, you must include the remote SQL VM." -ReturnObject $ReturnObject -Warning
            Write-Verbose "VMs are $($ConfigObject.virtualMachines.vmName)"
        }

        # Minimum Memory
        if ($VM.memory / 1 -lt 3GB) {
            Add-ValidationMessage -Message "$vmRole Validation: VM [$vmName] must contain a minimum of 3GB memory when using remote SQL." -ReturnObject $ReturnObject -Failure
        }

    }
    else {
        # Local SQL

        # Minimum Memory
        if ($VM.memory / 1 -lt 6GB) {
            Add-ValidationMessage -Message "$vmRole Validation: VM [$vmName] must contain a minimum of 6GB memory when using local SQL." -ReturnObject $ReturnObject -Failure
        }
    }

    # Site Code
    if ($VM.siteCode.Length -ne 3) {
        Add-ValidationMessage -Message "$vmRole Validation: VM [$vmName] contains invalid Site Code [$($VM.siteCode)] Must be exactly 3 chars." -ReturnObject $ReturnObject -Failure
    }

    # Parent Site Code
    if ($VM.parentSiteCode -and $VM.parentSiteCode.Length -ne 3) {
        Add-ValidationMessage -Message "$vmRole Validation: VM [$vmName] contains invalid Site Code [$($VM.parentSiteCode)] Must be exactly 3 chars." -ReturnObject $ReturnObject -Failure
    }

    # invalid site codes
    $pattern = "^[a-zA-Z0-9]+$"
    if (-not ($VM.siteCode -match $pattern)) {
        Add-ValidationMessage -Message "$vmRole Validation: VM [$vmName] contains invalid Site Code (Must be AlphaNumeric) [$($VM.siteCode)]." -ReturnObject $ReturnObject -Failure
    }

    # reserved site codes
    if ($VM.siteCode.ToUpperInvariant() -in "AUX", "CON", "NUL", "PRN", "SMS", "ENV") {
        Add-ValidationMessage -Message "$vmRole Validation: VM [$vmName] contains Site Code [$($VM.siteCode)] reserved for Configuration Manager and Windows." -ReturnObject $ReturnObject -Failure
    }

    $otherVMs = $ConfigObject.VirtualMachines | Where-Object { $_.vmName -ne $VM.vmName } | Where-Object { $null -ne $_.Sitecode }
    foreach ($vmWithSiteCode in $otherVMs) {
        if ($VM.siteCode.ToUpperInvariant() -eq $vmWithSiteCode.siteCode.ToUpperInvariant() -and ($vmWithSiteCode.role -in "CAS", "Primary")) {
            Add-ValidationMessage -Message "$vmRole Validation: VM contains Site Code [$($VM.siteCode)] that is already used by another siteserver [$($vmWithSiteCode.vmName)]." -ReturnObject $ReturnObject -Failure
        }
    }

    $otherVMs = Get-List -type VM -DomainName $($ConfigObject.vmOptions.DomainName) | Where-Object { $null -ne $_.siteCode }
    foreach ($vmWithSiteCode in $otherVMs) {
        if ($VM.siteCode.ToUpperInvariant() -eq $vmWithSiteCode.siteCode.ToUpperInvariant() -and ($vmWithSiteCode.role -in "CAS", "Primary")) {
            Add-ValidationMessage -Message "$vmRole Validation: VM contains Site Code [$($VM.siteCode)] that is already used by another siteserver [$($vmWithSiteCode.vmName)]." -ReturnObject $ReturnObject -Failure
        }
    }

    # Server OS
    Test-ValidVmServerOS -VM $VM -ReturnObject $ReturnObject

    # install dir
    Test-ValidVmPath -VM $VM -PathProperty "cmInstallDir" -ValidPathExample "E:\ConfigMgr" -ReturnObject $ReturnObject

}

function Test-ValidRolePassiveSite {
    param (
        [object] $VM,
        [object] $ConfigObject,
        [object] $ReturnObject
    )

    if (-not $VM) {
        throw
    }

    $vmName = $VM.vmName
    $vmRole = $VM.role

    # Server OS
    Test-ValidVmServerOS -VM $VM -ReturnObject $ReturnObject

    # install dir
    Test-ValidVmPath -VM $VM -PathProperty "cmInstallDir" -ValidPathExample "E:\ConfigMgr" -ReturnObject $ReturnObject

    if (-not $VM.remoteContentLibVM) {
        Add-ValidationMessage -Message "$vmRole Validation: VM [$vmName] does not contain remoteContentLibVM; When deploying $vmRole Role, you must specify the FileServer where Content Library will be hosted." -ReturnObject $ReturnObject -Warning
    }

    if ($VM.remoteContentLibVM) {
        $fsInConfig = $ConfigObject.virtualMachines | Where-Object { $_.vmName -eq $VM.remoteContentLibVM }
        if (-not $fsInConfig) {
            $fsVM = Get-List -type VM -DomainName $($ConfigObject.vmOptions.DomainName) | Where-Object { $_.vmName -eq $VM.remoteContentLibVM }
        }
        else {
            $fsVM = $fsInConfig
        }

        if (-not $fsVM) {
            Add-ValidationMessage -Message "$vmRole Validation: VM [$vmName] configuration contains remoteContentLibVM [$($VM.remoteContentLibVM)] which does not exist in Configuration or Hyper-V." -ReturnObject $ReturnObject -Warning
        }

        if ($fsVM -and $fsVM.role -ne "FileServer") {
            Add-ValidationMessage -Message "$vmRole Validation: VM [$vmName] configuration contains remoteContentLibVM [$($VM.remoteContentLibVM)] which currently has role [$($fsVM.role)]. remoteContentLibVM role must be FileServer." -ReturnObject $ReturnObject -Warning
        }
    }

    if (-not $VM.siteCode) {
        Add-ValidationMessage -Message "$vmRole Validation: VM [$vmName] does not contain siteCode; When deploying $vmRole Role, you must specify the siteCode of an Active Site Server." -ReturnObject $ReturnObject -Warning
    }
    else {
        $assInConfig = $ConfigObject.virtualMachines | Where-Object { $_.sitecode -eq $VM.siteCode -and ($_.role -eq "CAS" -or $_.role -eq "Primary") }
        if (-not $assInConfig) {
            $assVM = Get-ExistingSiteServer -DomainName $ConfigObject.vmOptions.DomainName -SiteCode $VM.siteCode

            if (($assVM | Measure-Object).Count -eq 0) {
                Add-ValidationMessage -Message "$vmRole Validation: VM [$vmName] contains a siteCode [$($VM.siteCode)] which doesn't belong to an existing Site Server." -ReturnObject $ReturnObject -Warning
            }

            if (($assVM | Measure-Object).Count -gt 1) {
                Add-ValidationMessage -Message "$vmRole Validation: VM [$vmName] contains a siteCode [$($VM.siteCode)] which already contains a passive site server." -ReturnObject $ReturnObject -Warning
            }
        }
        else {
            $assVM = Get-ExistingSiteServer -DomainName $ConfigObject.vmOptions.DomainName -SiteCode $VM.siteCode
            if (($assVM | Measure-Object).Count -ne 0) {
                Add-ValidationMessage -Message "$vmRole Validation: VM [$vmName] contains a siteCode [$($VM.siteCode)] which already exists in Hyper-V for VM [$($assVM.vmName)]." -ReturnObject $ReturnObject -Warning
            }
        }
    }
}

function Test-ValidRoleFileServer {
    param (
        [object] $VM,
        [object] $ReturnObject
    )

    if (-not $VM) {
        throw
    }

    $vmName = $VM.vmName
    $vmRole = $VM.role

    # Server OS
    Test-ValidVmServerOS -VM $VM -ReturnObject $ReturnObject

    if (-not $VM.additionalDisks) {
        Add-ValidationMessage -Message "$vmRole Validation: VM [$vmName] does not contain additionalDisks. FileServer must contain E and F drives." -ReturnObject $ReturnObject -Warning
    }
    else {
        $edrive = $VM.additionalDisks | Get-Member -Name "E"
        $fdrive = $VM.additionalDisks | Get-Member -Name "F"

        if (-not $edrive) {
            Add-ValidationMessage -Message "$vmRole Validation: VM [$vmName] does not contain E drive. FileServer must contain E and F drives." -ReturnObject $ReturnObject -Warning
        }

        if (-not $fdrive) {
            Add-ValidationMessage -Message "$vmRole Validation: VM [$vmName] does not contain F drive. FileServer must contain E and F drives." -ReturnObject $ReturnObject -Warning
        }
    }

}

function Test-SingleRole {
    param (
        [object] $VM,
        [object] $ReturnObject
    )

    if (-not $VM) {
        # $MyInvocation | Out-Host
        throw
    }

    $vmRole = $VM.role

    # Single Role
    if ($VM -is [object[]] -and $VM.Count -ne 1) {
        $vmRole = $VM.role | Select-Object -Unique
        if ($vmRole -eq "DC") {
            Add-ValidationMessage -Message "$vmRole Validation: Multiple virtual Machines with $vmRole Role specified in configuration. Only single $vmRole role is supported." -ReturnObject $ReturnObject -Warning
        }
        else {
            Add-ValidationMessage -Message "$vmRole Validation: Multiple machines with $vmRole role can not be deployed at the same time. You can add more $vmRole machines to your domain after it is deployed." -ReturnObject $ReturnObject -Warning
        }
        return $false
    }

    return $true
}

function Test-Configuration {
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "ConfigFile", HelpMessage = "Configuration File")]
        [string]$FilePath,
        [Parameter(Mandatory = $true, ParameterSetName = "ConfigObject", HelpMessage = "Configuration File")]
        [object]$InputObject
        #[Parameter(Mandatory = $false, ParameterSetName = "ConfigObject", HelpMessage = "Should we flush the cache to get accurate results?")]
        #[bool] $fast = $false
    )

    $return = [PSCustomObject]@{
        Valid        = $false
        DeployConfig = $null
        Message      = [System.Text.StringBuilder]::new()
        Failures     = 0
        Warnings     = 0
        Problems     = 0
    }

    if ($FilePath) {
        try {
            $configObject = Get-Content $FilePath -Force | ConvertFrom-Json
        }
        catch {
            $return.Message = "Failed to load $FilePath as JSON. Please check if the config is valid or create a new one using genconfig.ps1"
            $return.Problems += 1
            $return.Failures += 1
            return $return
        }
    }

    if ($InputObject) {
        # Convert to Json and back to make a copy of the object, so the original is not modified
        $configObject = $InputObject | ConvertTo-Json -Depth 3 | ConvertFrom-Json
    }

    # InputObject could be blank
    # if (-not $InputObject -and -not $FilePath) {
    #     if ($InputObject -isnot [System.Management.Automation.PSCustomObject]) {
    #         $return.Message = "InputObject is invalid. Please check if the config is valid or create a new one using genconfig.ps1"
    #         $return.Problems += 1
    #         $return.Failures += 1
    #         return $return
    #     }
    # }

    $deployConfig = New-DeployConfig -configObject $configObject
    $return.DeployConfig = $deployConfig


    if ($deployConfig.virtualMachines.Count -eq 0) {
        $return.Message = "Configuration contains no Virtual Machines. Nothing to deploy."
        $return.Problems += 1
        #$return.Failures += 1
        return $return
    }

    # Contains roles
    if ($deployConfig.virtualMachines) {
        $containsCS = $deployConfig.virtualMachines.role -contains "CAS"
        $containsPS = $deployConfig.virtualMachines.role -contains "Primary"
        $containsDPMP = $deployConfig.virtualMachines.role -contains "DPMP"
        $containsPassive = $deployConfig.virtualMachines.role -contains "PassiveSite"
    }
    else {
        $containsCS = $containsPS = $containsDPMP = $containsPassive = $false
    }

    $needCMOptions = $containsCS -or $containsPS

    # VM Options
    # ===========
    Test-ValidVmOptions -ConfigObject $deployConfig -ReturnObject $return

    # CM Options
    # ===========

    # CM Version
    if ($needCMOptions) {
        Test-ValidCmOptions -ConfigObject $deployConfig -ReturnObject $return
    }

    # VM Validations
    # ==============
    foreach ($vm in $deployConfig.virtualMachines) {

        # Supported values
        Test-ValidVmSupported -VM $vm -ConfigObject $deployConfig -ReturnObject $return

        # Valid Memory
        Test-ValidVmMemory -VM $vm -ReturnObject $return

        # virtualProcs
        Test-ValidVmProcs -VM $vm -ReturnObject $return

        # Valid additionalDisks
        Test-ValidVmDisks -VM $vm -ReturnObject $return

        if ($vm.sqlVersion) {

            # Supported SQL
            if ($Common.Supported.SqlVersions -notcontains $vm.sqlVersion) {
                Add-ValidationMessage -Message "VM Validation: [$($vm.vmName)] does not contain a supported sqlVersion [$($vm.sqlVersion)]." -ReturnObject $return -Failure
            }

            # Server OS
            Test-ValidVmServerOS -VM $vm -ReturnObject $return

            # sqlInstance dir
            Test-ValidVmPath -VM $vm -PathProperty "sqlInstanceDir" -ValidPathExample "F:\SQL" -ReturnObject $return

            # sqlInstanceName
            if (-not $vm.sqlInstanceName) {
                Add-ValidationMessage -Message "VM Validation: [$($vm.vmName)] does not contain sqlInstanceName." -ReturnObject $return -Warning
            }

            # Minimum SQL Memory
            if ($VM.memory / 1 -lt 4GB) {
                Add-ValidationMessage -Message "$vmRole Validation: VM [$vmName] must contain a minimum of 4GB memory when using SQL." -ReturnObject $return -Failure
            }
        }

    }

    # DC Validation
    # ==============
    Test-ValidRoleDC -ConfigObject $deployConfig -ReturnObject $return

    # CAS Validations
    # ==============
    if ($containsCS) {

        $CSVM = $deployConfig.virtualMachines | Where-Object { $_.role -eq "CAS" }
        $vmName = $CSVM.vmName
        $vmRole = $CSVM.role

        # Single CAS
        if (Test-SingleRole -VM $CSVM -ReturnObject $return) {

            # CAS without Primary
            if (-not $containsPS) {
                Add-ValidationMessage -Message "$vmRole Validation: VM [$vmName] specified without Primary Site; When deploying CAS Role, you must add a Primary Role as well." -ReturnObject $return -Warning
            }

            # Validate CAS role
            Test-ValidRoleCSPS -VM $CSVM -ConfigObject $deployConfig -ReturnObject $return

        }

    }

    # Primary Validations
    # ==============
    if ($containsPS) {

        # Validate Primary role
        $PSVM = $deployConfig.virtualMachines | Where-Object { $_.role -eq "Primary" }
        $vmName = $PSVM.vmName
        $vmRole = $PSVM.role
        $psParentSiteCode = $PSVM.parentSiteCode

        if (Test-SingleRole -VM $PSVM -ReturnObject $return) {

            Test-ValidRoleCSPS -VM $PSVM -ConfigObject $deployConfig -ReturnObject $return

            # Valid parent Site Code
            if ($psParentSiteCode) {
                $casSiteCodes = Get-ValidCASSiteCodes -Config $deployConfig
                $parentCodes = $casSiteCodes -join ","
                if ($psParentSiteCode -notin $casSiteCodes) {
                    Add-ValidationMessage -Message "$vmRole Validation: Primary [$vmName] contains parentSiteCode [$psParentSiteCode] which is invalid. Valid Parent Site Codes: $parentCodes" -ReturnObject $return -Warning
                }
            }

            # Other Site servers must be running
            if ($psParentSiteCode -and $deployConfig.parameters.ExistingCASName -and $deployConfig.cmOptions.updateToLatest) {
                $notRunning = Get-ExistingSiteServer -DomainName $deployConfig.vmOptions.domainName | Where-Object { $_.State -ne "Running" }
                $notRunningNames = $notRunning.vmName -join ","
                if ($notRunning.Count -gt 0) {
                    Add-ValidationMessage -Message "$vmRole Validation: Primary [$vmName] requires other site servers [$notRunningNames] to be running." -ReturnObject $return -Warning
                    Get-List -FlushCache | Out-Null
                }
            }

            # CAS with Primary, without parentSiteCode
            if ($containsCS) {
                if ($psParentSiteCode -ne $CSVM.siteCode) {
                    Add-ValidationMessage -Message "$vmRole Validation: VM [$vmName] specified with CAS, but parentSiteCode [$psParentSiteCode] does not match CAS Site Code [$($CSVM.siteCode)]." -ReturnObject $return -Warning
                }
            }

        }
    }

    # Passive Validations
    # ===================
    if ($containsPassive) {
        $passiveVM = $deployConfig.virtualMachines | Where-Object { $_.role -eq "PassiveSite" }

        # PassiveSite VM count -eq 1
        if (Test-SingleRole -VM $passiveVM -ReturnObject $return) {
            Test-ValidRolePassiveSite -VM $passiveVM -ConfigObject $deployConfig -ReturnObject $return
        }
    }

    # FileServer Validations
    # ======================
    $FSVMs = $deployConfig.virtualMachines | Where-Object { $_.role -eq "FileServer" }
    foreach ($FSVM in $FSVMs) {
        Test-ValidRoleFileServer -VM $FSVM -ReturnObject $return
    }

    # DPMP Validations
    # =================
    if ($containsDPMP) {

        $DPMPVM = $deployConfig.virtualMachines | Where-Object { $_.role -eq "DPMP" }

        # Server OS
        Test-ValidVmServerOS -VM $DPMPVM -ReturnObject $return

        if (-not $containsPS -and -not $deployConfig.parameters.ExistingPSName) {
            Add-ValidationMessage -Message "Role Conflict: DPMP Role specified without Primary site and an existing Primary with same siteCode/subnet was not found." -ReturnObject $return -Warning
        }

    }

    # Role Conflicts
    # ==============

    # CAS/Primary must include DC
    if (($containsCS -or $containsPS) -and -not $deployConfig.parameters.DCName ) {
        Add-ValidationMessage -Message "Role Conflict: CAS or Primary role specified but a new/existing DC was not found; CAS/Primary roles require a DC." -ReturnObject $return -Warning
    }

    # Primary site without CAS
    if ($deployConfig.parameters.scenario -eq "Hierarchy" -and -not $deployConfig.parameters.CSName) {
        Add-ValidationMessage -Message "Role Conflict: Deployment requires a CAS, which was not found." -ReturnObject $return -Warning
    }

    # tech preview and hierarchy
    if ($deployConfig.parameters.scenario -eq "Hierarchy" -and $deployConfig.cmOptions.version -eq "tech-preview") {
        Add-ValidationMessage -Message "Version Conflict: Tech-Preview specfied with a Hierarchy; Tech Preview doesn't support CAS." -ReturnObject $return -Warning
    }

    # Total Memory
    # =============
    $totalMemory = $deployConfig.virtualMachines.memory | ForEach-Object { $_ / 1 } | Measure-Object -Sum
    $totalMemory = $totalMemory.Sum / 1GB
    $availableMemory = Get-AvailableMemoryGB


    if ($totalMemory -gt $availableMemory) {
        Add-ValidationMessage -Message "Deployment Validation: Total Memory Required [$($totalMemory)GB] is greater than available memory [$($availableMemory)GB]." -ReturnObject $return -Warning
    }

    # Unique Names
    # =============

    # Names in deployment
    $vmInDeployment = $deployConfig.virtualMachines.vmName
    $unique1 = $vmInDeployment | Select-Object -Unique
    $compare = Compare-Object -ReferenceObject $vmInDeployment -DifferenceObject $unique1
    if ($compare) {
        $duplicates = $compare.InputObject -join ","
        Add-ValidationMessage -Message "Name Conflict: Deployment contains duplicate VM names [$duplicates]" -ReturnObject $return -Warning
    }

    # Names in domain
    $allVMs = Get-List -Type VM | Select-Object -Expand VmName
    $all = $allVMs + $vmInDeployment
    $unique2 = $all | Select-Object -Unique
    $compare2 = Compare-Object -ReferenceObject $all -DifferenceObject $unique2
    if (-not $compare -and $compare2) {
        $duplicates = $compare2.InputObject -join ","
        Add-ValidationMessage -Message "Name Conflict: Deployment contains VM names [$duplicates] that are already in Hyper-V. You must add new machines with different names." -ReturnObject $return -Warning
        Get-List -FlushCache | Out-Null
    }

    # Return if validation failed
    if ($return.Problems -ne 0) {
        $return.Message = $return.Message.ToString().Trim()
        return $return
    }

    # everything is good
    $return.Valid = $true

    return $return
}

function New-DeployConfig {
    [CmdletBinding()]
    param (
        [Parameter()]
        [object] $configObject
    )
    try {
        if ($null -ne ($configObject.vmOptions.domainAdminName)) {
            if ($null -eq ($configObject.vmOptions.adminName)) {
                $configObject.vmOptions | Add-Member -MemberType NoteProperty -Name "adminName" -Value $configObject.vmOptions.domainAdminName
            }
            $configObject.vmOptions.PsObject.properties.Remove('domainAdminName')
        }

        $containsCS = $configObject.virtualMachines.role -contains "CAS"

        # Scenario
        if ($containsCS) {
            $scenario = "Hierarchy"
        }
        else {
            $scenario = "Standalone"
        }

        # add prefix to vm names
        $virtualMachines = $configObject.virtualMachines
        foreach ($item in $virtualMachines) {
            $item.vmName = $configObject.vmOptions.prefix + $item.vmName
        }
        #$virtualMachines | foreach-object { $_.vmName = $configObject.vmOptions.prefix + $_.vmName }

        # create params object
        try {
            $network = $configObject.vmOptions.network.Substring(0, $configObject.vmOptions.network.LastIndexOf("."))
        }
        catch {}
        $clientsCsv = ($virtualMachines | Where-Object { $_.role -eq "DomainMember" }).vmName -join ","

        # DCName (prefer name in config over existing)
        $DCName = ($virtualMachines | Where-Object { $_.role -eq "DC" }).vmName
        $existingDCName = Get-ExistingForDomain -DomainName $configObject.vmOptions.domainName -Role "DC"
        if (-not $DCName) {
            $DCName = $existingDCName
        }

        # Build DPMP List
        $DPMPNames = @()
        foreach ($dpmp in $virtualMachines | Where-Object { $_.role -eq "DPMP" }) { $DPMPNames += $dpmp.vmName }

        $containsPS = $configObject.virtualMachines.role -contains "Primary"
        $PSVM = $virtualMachines | Where-Object { $_.role -eq "Primary" } | Select-Object -First 1 # Bypass failures, validation would fail if we had multiple
        if ($PSVM) {
            # CSName (prefer name in config over existing)
            $existingCS = Get-ExistingSiteServer -DomainName $configObject.vmOptions.domainName -SiteCode ($PSVM.parentSiteCode | Select-Object -First 1) # Bypass failures, validation would fail if we had multiple
            $existingCSName = ($existingCS | Where-Object { $_.role -ne "PassiveSite" }).vmName
            $CSName = ($virtualMachines | Where-Object { $_.role -eq "CAS" }).vmName
            if (-not $CSName) {
                $CSName = $existingCSName
            }

            # Add prefix to remote SQL
            if ($PSVM.remoteSQLVM -and -not $PSVM.remoteSQLVM.StartsWith($configObject.vmOptions.prefix)) {
                $PSVM.remoteSQLVM = $configObject.vmOptions.prefix + $PSVM.remoteSQLVM
            }

            $PSName = $PSVM.vmName
        }

        # PSName
        if (-not $PSName) {
            # Set existing PS from same subnet as current config - we don't allow multiple primary sites in same subnet
            $existingPS = Get-ExistingSiteServer -DomainName $configObject.vmOptions.domainName | Where-Object { $_.role -eq "Primary" } | Select-Object -First 1 # Bypass failures, validation would fail if we had multiple
            $existingPSName = ($existingPS | Where-Object { $_.role -ne "PassiveSite" }).vmName

            # Add existing DPMP's matching existingPS site code or subnet
            foreach ($dpmp in Get-List -Type VM -DomainName $configObject.vmOptions.domainName | Where-Object { $_.role -eq "DPMP" }) {
                if ($dpmp.siteCode -eq $existingPS.siteCode -or $dpmp.network -eq $existingPS.subnet) {
                    $DPMPNames += $dpmp.vmName
                }
            }
        }

        # Existing Site Server for passive site (only allow one Passive per deployment when adding to existing)
        $PassiveVM = $virtualMachines | Where-Object { $_.role -eq "PassiveSite" } | Select-Object -First 1 # Bypass failures, validation would fail if we had multiple
        if ($PassiveVM) {
            $ActiveVMinConfig = $virtualMachines | Where-Object { $_.siteCode -eq $PassiveVM.siteCode -and $_.vmName -ne $PassiveVM.vmName }
            $activeVMName = $ActiveVMinConfig.vmName
            if (-not $ActiveVMinConfig) {
                $ActiveVM = Get-ExistingSiteServer -DomainName $configObject.vmOptions.domainName -SiteCode $PassiveVM.siteCode | Where-Object { $_.role -ne "PassiveSite" }
                $existingActiveVMName = $ActiveVM.vmName
            }

            # Add prefix to FS
            if ($PassiveVM.remoteContentLibVM -and -not $PassiveVM.remoteContentLibVM.StartsWith($configObject.vmOptions.prefix)) {
                $PassiveVM.remoteContentLibVM = $configObject.vmOptions.prefix + $PassiveVM.remoteContentLibVM
            }
        }

        if ($containsCS) {
            $CSVM = $virtualMachines | Where-Object { $_.role -eq "CAS" } | Select-Object -First 1 # Bypass failures, validation would fail if we had multiple

            # Add prefix to remote SQL
            if ($CSVM.remoteSQLVM -and -not $CSVM.remoteSQLVM.StartsWith($configObject.vmOptions.prefix)) {
                $CSVM.remoteSQLVM = $configObject.vmOptions.prefix + $CSVM.remoteSQLVM
            }
        }

        if ($existingCSName -and $containsPS) {

            if ($PSVM.parentSiteCode) {
                $scenario = "Hierarchy"
            }
            else {
                $scenario = "Standalone"
            }

        }

        $params = [PSCustomObject]@{
            DomainName         = $configObject.vmOptions.domainName
            DCName             = $DCName
            CSName             = $CSName
            PSName             = $PSName
            ActiveVMName       = $activeVMName
            DPMPNames          = $DPMPNames
            DomainMembers      = $clientsCsv
            Scenario           = $scenario
            DHCPScopeId        = $configObject.vmOptions.Network
            DHCPScopeName      = $configObject.vmOptions.Network
            DHCPDNSAddress     = $network + ".1"
            DHCPDefaultGateway = $network + ".200"
            DHCPScopeStart     = $network + ".20"
            DHCPScopeEnd       = $network + ".199"
            ExistingDCName     = $existingDCName
            ExistingCASName    = $existingCSName
            ExistingPSName     = $existingPSName
            ExistingActiveName = $existingActiveVMName
            ThisMachineName    = $null
            ThisMachineRole    = $null
        }

        $existingVMs = Get-List -Type VM -DomainName $configObject.vmOptions.domainName

        $deploy = [PSCustomObject]@{
            cmOptions       = $configObject.cmOptions
            vmOptions       = $configObject.vmOptions
            virtualMachines = $virtualMachines
            parameters      = $params
            existingVMs     = $existingVMs
        }

        return $deploy
    }
    catch {
        Write-Exception -ExceptionInfo $_ -AdditionalInfo ($configObject | ConvertTo-Json)
    }
}

function Get-ValidCASSiteCodes {
    param (
        [Parameter(Mandatory = $true)]
        [object]$Config
    )

    $existingSiteCodes = @()
    $existingSiteCodes += Get-ExistingSiteServer -DomainName $Config.vmOptions.domainName -Role "CAS" | Select-Object -ExpandProperty SiteCode

    $containsCS = $Config.virtualMachines.role -contains "CAS"
    if ($containsCS) {
        $CSVM = $Config.virtualMachines | Where-Object { $_.role -eq "CAS" }
        $existingSiteCodes += $CSVM.siteCode
    }

    return ($existingSiteCodes | Select-Object -Unique)
}

function Get-ExistingForDomain {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Domain Name")]
        [string]$DomainName,
        [Parameter(Mandatory = $false, HelpMessage = "VM Role")]
        [ValidateSet("DC", "CAS", "Primary", "DPMP", "DomainMember")]
        [string]$Role
    )

    try {

        $existingValue = @()
        $vmList = Get-List -Type VM -DomainName $DomainName
        foreach ($vm in $vmList) {
            if ($vm.Role.ToLowerInvariant() -eq $Role.ToLowerInvariant()) {
                $existingValue += $vm.VmName
            }
        }

        if ($existingValue.Count -gt 0) {
            return $existingValue
        }

        return $null

    }
    catch {
        Write-Log "Get-ExistingForDomain: Failed to get existing $Role from $DomainName. $_" -Failure
        return $null
    }
}

function Get-ExistingSiteServer {
    param(
        [Parameter(Mandatory = $false, HelpMessage = "Domain Name")]
        [string]$DomainName,
        [Parameter(Mandatory = $false, HelpMessage = "Role")]
        [ValidateSet("CAS", "Primary")]
        [string]$Role,
        [Parameter(Mandatory = $false, HelpMessage = "SiteCode")]
        [string]$SiteCode
    )

    try {

        if ($DomainName) {
            $vmList = Get-List -Type VM -DomainName $DomainName
        }
        else {
            $vmList = Get-List -Type VM
        }

        if ($Role) {
            $vmList = $vmList | Where-Object { $_.Role -eq $Role }
        }

        $existingValue = @()
        foreach ($vm in $vmList) {
            $so = $null
            if ($vm.role -in "CAS", "Primary", "Secondary") {
                if ($PSBoundParameters.ContainsKey("SiteCode") -and $vm.siteCode.ToLowerInvariant() -eq $SiteCode.ToLowerInvariant()) {

                    $so = [PSCustomObject]@{
                        VmName   = $vm.VmName
                        Role     = $vm.Role
                        SiteCode = $vm.siteCode
                        Domain   = $vm.domain
                        State    = $vm.State
                        Subnet   = $vm.Subnet
                    }
                    $existingValue += $so
                }

                if (-not $PSBoundParameters.ContainsKey("SiteCode")) {

                    $so = [PSCustomObject]@{
                        VmName   = $vm.VmName
                        Role     = $vm.Role
                        SiteCode = $vm.siteCode
                        Domain   = $vm.domain
                        State    = $vm.State
                        Subnet   = $vm.Subnet
                    }
                    $existingValue += $so
                }
            }
        }

        return $existingValue

    }
    catch {
        Write-Log "Get-ExistingSiteServer: Failed to get existing site servers. $_" -Failure
        return $null
    }
}

function Get-ExistingForSubnet {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Subnet")]
        [string]$Subnet,
        [Parameter(Mandatory = $false, HelpMessage = "VM Role")]
        [ValidateSet("DC", "CAS", "Primary", "DPMP", "DomainMember")]
        [string]$Role
    )

    try {

        $existingValue = @()
        $vmList = Get-List -Type VM | Where-Object { $_.Subnet -eq $Subnet }
        foreach ($vm in $vmList) {
            if ($vm.Role.ToLowerInvariant() -eq $Role.ToLowerInvariant()) {
                $existingValue += $vm.VmName
            }
        }

        return $existingValue

    }
    catch {
        Write-Log "Get-ExistingForSubnet: Failed to get existing $Role from $Subnet. $_" -Failure
        return $null
    }
}

function Get-SubnetList {

    param(
        [Parameter(Mandatory = $false)]
        [string] $DomainName
    )
    try {

        if ($DomainName) {
            return (Get-List -Type Subnet -DomainName $DomainName)
        }

        return (Get-List -Type Subnet)

    }
    catch {
        Write-Log "Get-SubnetList: Failed to get subnet list. $_" -Failure -LogOnly
        return $null
    }
}

function Get-DomainList {

    try {
        return (Get-List -Type UniqueDomain)
    }
    catch {
        Write-Log "Get-DomainList: Failed to get domain list. $_" -Failure -LogOnly
        return $null
    }
}

$global:vm_List = $null
function Get-List {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "Type")]
        [ValidateSet("VM", "Subnet", "Prefix", "UniqueDomain", "UniqueSubnet", "UniquePrefix")]
        [string] $Type,
        [Parameter(Mandatory = $false, ParameterSetName = "Type")]
        [string] $DomainName,
        [Parameter(Mandatory = $false, ParameterSetName = "Type")]
        [switch] $ResetCache,
        [Parameter(Mandatory = $true, ParameterSetName = "FlushCache")]
        [switch] $FlushCache
    )

    try {

        if ($FlushCache.IsPresent) {
            $global:vm_List = $null
            return
        }

        if ($ResetCache.IsPresent) {
            $global:vm_List = $null
        }

        if ($null -eq $global:vm_List) {

            Write-Log "Get-List: Obtaining '$Type' list and caching it." -Verbose
            $return = @()
            $virtualMachines = Get-VM

            foreach ($vm in $virtualMachines) {
                $vmNoteObject = $null
                try {
                    if ($vm.Notes -like "*lastUpdate*") {
                        $vmNoteObject = $vm.Notes | ConvertFrom-Json
                    }
                    else {
                        Write-Log "Get-List: VM Properties for '$($vm.Name)'' does not contain values. Assume this was not deployed by vmbuild. $_" -Warning -LogOnly
                        #continue
                    }
                }
                catch {
                    Write-Log "Get-List: Failed to get VM Properties for '$($vm.Name)'. $_" -Failure
                    #continue
                }

                # Update LastKnownIP, and timestamp
                if (-not [string]::IsNullOrWhiteSpace($vmNoteObject)) {
                    $LastUpdateTime = [Datetime]::ParseExact($vmNoteObject.LastUpdate, 'MM/dd/yyyy HH:mm', $null)
                    $datediff = New-TimeSpan -Start $LastUpdateTime -End (Get-Date)
                    if (($datediff.Hours -gt 12) -or $null -eq $vmNoteObject.LastKnownIP) {
                        $IPAddress = (Get-VM -Name $vm.Name | Get-VMNetworkAdapter).IPAddresses | Where-Object { $_ -notlike "*:*" } | Select-Object -First 1
                        if (-not [string]::IsNullOrWhiteSpace($IPAddress) -and $IPAddress -ne $vmNoteObject.LastKnownIP) {
                            if ($null -eq $vmNoteObject.LastKnownIP) {
                                $vmNoteObject | Add-Member -MemberType NoteProperty -Name "LastKnownIP" -Value $IPAddress
                            }
                            else {
                                $vmNoteObject.LastKnownIP = $IPAddress
                            }
                            Set-VMNote -vmName $vm.Name -vmNote $vmNoteObject
                        }
                        else {
                            #Update the Notes LastUpdateTime everytime we scan for it
                            if (-not [string]::IsNullOrWhiteSpace($IPAddress)) {
                                Set-VMNote -vmName $vm.Name -vmNote $vmNoteObject
                            }
                        }
                    }
                }

                #$diskSize = (Get-VHD -VMId $vm.ID | Measure-Object -Sum FileSize).Sum
                $diskSize = (Get-ChildItem $vm.Path -Recurse | Measure-Object length -sum).sum
                $diskSizeGB = $diskSize / 1GB
                $vmNet = $vm | Get-VMNetworkAdapter
                $vmName = $vm.Name
                $vmState = $vm.State.ToString()

                $vmObject = [PSCustomObject]@{
                    vmName          = $vm.Name
                    vmId            = $vm.Id
                    subnet          = $vmNet.SwitchName
                    memoryGB        = $vm.MemoryAssigned / 1GB
                    memoryStartupGB = $vm.MemoryStartup / 1GB
                    diskUsedGB      = [math]::Round($diskSizeGB, 2)
                    state           = $vmState
                }

                if ($vmNoteObject) {

                    $adminUser = $vmNoteObject.adminName
                    if (-not $adminUser) { $adminUser = $vmNoteObject.domainAdmin } # we renamed this property, read if it exists
                    $inProgress = if ($vmNoteObject.inProgress) { $true } else { $false }

                    # Detect if we need to update VM Note, if VM Note doesn't have siteCode prop
                    if ($vmNoteObject.role -in "CAS", "Primary", "PassiveSite") {
                        if ($null -eq $vmNoteObject.siteCode -or $vmNoteObject.siteCode.ToString().Length -ne 3) {
                            if ($vmState -eq "Running" -and (-not $inProgress)) {
                                try {
                                    $siteCodeFromVM = Invoke-VmCommand -VmName $vmName -ScriptBlock { Get-ItemPropertyValue -Path HKLM:\SOFTWARE\Microsoft\SMS\Identification -Name "Site Code" } -SuppressLog
                                    $siteCode = $siteCodeFromVM.ScriptBlockOutput
                                    $vmNoteObject | Add-Member -MemberType NoteProperty -Name "siteCode" -Value $siteCode.ToString() -Force
                                    Write-Log "Get-List: Site code for $vmName is missing in VM Note. Adding siteCode $siteCode." -LogOnly
                                    Set-VMNote -vmName $vmName -vmNote $vmNoteObject
                                }
                                catch {
                                    Write-Log "Get-List: Failed to obtain siteCode from registry from $vmName" -Warning -LogOnly
                                }
                            }
                            else {
                                Write-Log "Get-List: Site code for $vmName is missing in VM Note, but VM is not runnning [$vmState] or deployment is in progress [$inProgress]." -LogOnly
                            }
                        }
                    }

                    # Detect if we need to update VM Note, if VM Note doesn't have siteCode prop
                    if ($vmNoteObject.role -eq "DPMP") {
                        if ($null -eq $vmNoteObject.siteCode -or $vmNoteObject.siteCode.ToString().Length -ne 3) {
                            if ($vmState -eq "Running" -and (-not $inProgress)) {
                                try {
                                    $siteCodeFromVM = Invoke-VmCommand -VmName $vmName -ScriptBlock { Get-ItemPropertyValue -Path HKLM:\SOFTWARE\Microsoft\SMS\DP -Name "SiteCode" } -SuppressLog
                                    $siteCode = $siteCodeFromVM.ScriptBlockOutput
                                    $vmNoteObject | Add-Member -MemberType NoteProperty -Name "siteCode" -Value $siteCode.ToString() -Force
                                    Write-Log "Get-List: Site code for $vmName is missing in VM Note. Adding siteCode $siteCode after reading from registry." -LogOnly
                                    Set-VMNote -vmName $vmName -vmNote $vmNoteObject
                                }
                                catch {
                                    Write-Log "Get-List: Failed to obtain siteCode from registry from $vmName" -Warning -LogOnly
                                }
                            }
                            else {
                                Write-Log "Get-List: Site code for $vmName is missing in VM Note, but VM is not runnning [$vmState] or deployment is in progress [$inProgress]." -LogOnly
                            }
                        }
                    }

                    $vmObject | Add-Member -MemberType NoteProperty -Name "adminName" -Value $adminUser -Force
                    $vmObject | Add-Member -MemberType NoteProperty -Name "inProgress" -Value $inProgress -Force

                    foreach ($prop in $vmNoteObject.PSObject.Properties) {
                        $value = if ($prop.Value -is [string]) { $prop.Value.Trim() } else { $prop.Value }
                        $vmObject | Add-Member -MemberType NoteProperty -Name $prop.Name -Value $value -Force
                    }
                }

                $return += $vmObject
            }

            $global:vm_List = $return
        }

        $return = $global:vm_List

        if ($DomainName) {
            $return = $return | Where-Object { $_.domain -and ($_.domain.ToLowerInvariant() -eq $DomainName.ToLowerInvariant()) }
        }

        $return = $return | Sort-Object -Property * -Unique

        if ($Type -eq "VM") {
            return $return
        }

        if ($Type -eq "Subnet") {
            return $return | where-object {-not [String]::IsNullOrWhiteSpace($_.Domain) } | Select-Object -Property Subnet, Domain | Sort-Object -Property * -Unique
        }

        if ($Type -eq "Prefix") {
            return $return | where-object {-not [String]::IsNullOrWhiteSpace($_.Domain) } |Select-Object -Property Prefix, Domain | Sort-Object -Property * -Unique
        }

        if ($Type -eq "UniqueDomain") {
            return $return | where-object {-not [String]::IsNullOrWhiteSpace($_.Domain) } |Select-Object -ExpandProperty Domain -Unique -ErrorAction SilentlyContinue
        }

        if ($Type -eq "UniqueSubnet") {
            return $return | where-object {-not [String]::IsNullOrWhiteSpace($_.Domain) } |Select-Object -ExpandProperty Subnet -Unique -ErrorAction SilentlyContinue
        }

        if ($Type -eq "UniquePrefix") {
            return $return | where-object {-not [String]::IsNullOrWhiteSpace($_.Domain) } |Select-Object -ExpandProperty Prefix -Unique -ErrorAction SilentlyContinue
        }

    }
    catch {
        Write-Log "Get-List: Failed to get '$Type' list. $_" -Failure -LogOnly
        return $null
    }
}

Function Show-Summary {
    [CmdletBinding()]
    param (
        [Parameter()]
        [PsCustomObject] $deployConfig
    )

    Function Write-GreenCheck {
        [CmdletBinding()]
        param (
            [Parameter()]
            [string] $text,
            [Parameter()]
            [switch] $NoNewLine
        )
        $CHECKMARK = ([char]8730)

        Write-Host "  [" -NoNewLine
        Write-Host -ForeGroundColor Green "$CHECKMARK" -NoNewline
        Write-Host "] " -NoNewline
        Write-Host $text -NoNewline
        if (!$NoNewLine) {
            Write-Host
        }
    }

    Function Write-RedX {
        [CmdletBinding()]
        param (
            [Parameter()]
            [string] $text,
            [Parameter()]
            [switch] $NoNewLine
        )
        Write-Host "  [" -NoNewLine
        Write-Host -ForeGroundColor Red "x" -NoNewline
        Write-Host "] " -NoNewline
        Write-Host $text -NoNewline
        if (!$NoNewLine) {
            Write-Host
        }
    }

    #$CHECKMARK = ([char]8730)
    $containsPS = $deployConfig.virtualMachines.role -contains "Primary"
    $containsDPMP = $deployConfig.virtualMachines.role -contains "DPMP"
    $containsMember = $deployConfig.virtualMachines.role -contains "DomainMember"
    $containsPassive = $deployConfig.virtualMachines.role -contains "PassiveSite"

    Write-Verbose "ContainsPS: $containsPS ContainsDPMP: $containsDPMP ContainsMember: $containsMember ContainsPassive: $containsPassive"
    if ($null -ne $($deployConfig.cmOptions) -and $containsPS -and $deployConfig.cmOptions.install -eq $true) {
        if ($deployConfig.cmOptions.install -eq $true) {
            Write-GreenCheck "ConfigMgr $($deployConfig.cmOptions.version) will be installed."


            if ($deployConfig.cmOptions.updateToLatest -eq $true) {
                Write-GreenCheck "ConfigMgr will be updated to latest"
            }
            else {
                Write-RedX "ConfigMgr will NOT updated to latest"
            }
            $PSVM = $deployConfig.virtualMachines | Where-Object { $_.Role -eq "Primary" }
            if ($PSVM.ParentSiteCode) {
                Write-GreenCheck "ConfigMgr Primary server Will join a Heirarchy: $($PSVM.SiteCode) -> $($PSVM.ParentSiteCode)"
            }
            else {
                Write-GreenCheck "Primary server with Sitecode $($PSVM.SiteCode) will be installed in a standalone configuration"
            }
        }
        else {
            Write-RedX "ConfigMgr will not be installed."
        }


        if (($deployConfig.cmOptions.installDPMPRoles -or $deployConfig.cmOptions.pushClientToDomainMembers) -and $deployConfig.cmOptions.install -eq $true) {

            If ($containsDPMP) {
                $DPMP = $deployConfig.virtualMachines | Where-Object { $_.Role -eq "DPMP" }
                Write-GreenCheck "DP and MP roles will be installed on $($DPMP.vmName)" -NoNewLine
            }
            else {
                $PSVM = $deployConfig.virtualMachines | Where-Object { $_.Role -eq "Primary" }
                Write-GreenCheck "DP and MP roles will be installed on Primary Site Server $($PSVM.vmName)" -NoNewLine
            }
        }
        else {
            Write-RedX "DPMP roles will not be installed" -NoNewLine
        }

        if ($containsMember) {
            if ($deployConfig.cmOptions.pushClientToDomainMembers -and $deployConfig.cmOptions.install -eq $true) {
                Write-Host " [Client Push: Yes]"
            }
            else {
                Write-Host " [Client Push: No]"
            }
        }
        else {
            Write-Host " [Client Push: N/A]"
        }

    }
    else {
        Write-Verbose "deployConfig.cmOptions.install = $($deployConfig.cmOptions.install)"
        if (($deployConfig.cmOptions.install -eq $true) -and $containsPassive) {
            $PassiveVM = $deployConfig.virtualMachines | Where-Object { $_.Role -eq "PassiveSite" }
        }
        else {
            Write-RedX "ConfigMgr will not be installed."
        }
    }

    if (($deployConfig.cmOptions.install -eq $true) -and $containsPassive) {
        $PassiveVM = $deployConfig.virtualMachines | Where-Object { $_.Role -eq "PassiveSite" }
        Write-GreenCheck "ConfigMgr HA Passive server with Sitecode $($PassiveVM.SiteCode) will be installed"
    }
    if (-not $null -eq $($deployConfig.vmOptions)) {

        if ($null -eq $deployConfig.parameters.ExistingDCName) {
            Write-GreenCheck "Domain: $($deployConfig.vmOptions.domainName) will be created." -NoNewLine
        }
        else {
            Write-GreenCheck "Domain: $($deployConfig.vmOptions.domainName) will be joined." -NoNewLine
        }

        Write-Host " [Network $($deployConfig.vmOptions.network)]"
        Write-GreenCheck "Virtual Machine files will be stored in $($deployConfig.vmOptions.basePath) on host machine"

        $totalMemory = $deployConfig.virtualMachines.memory | ForEach-Object { $_ / 1 } | Measure-Object -Sum
        $totalMemory = $totalMemory.Sum / 1GB
        $availableMemory = Get-AvailableMemoryGB
        Write-GreenCheck "This configuration will use $($totalMemory)GB out of $($availableMemory)GB Available RAM on host machine"
    }
    Write-GreenCheck "Domain Admin account: $($deployConfig.vmOptions.adminName)  Password: $($Common.LocalAdmin.GetNetworkCredential().Password)"
    $out = $deployConfig.virtualMachines | Where-Object { -not $_.hidden } `
    | Format-table vmName, role, operatingSystem, memory,
    @{Label = "Procs"; Expression = { $_.virtualProcs } },
    @{Label = "AddedDisks"; Expression = { $_.additionalDisks.psobject.Properties.Value.count } },
    @{Label = "SQL"; Expression = {
            if ($null -ne $_.SqlVersion) {
                $_.SqlVersion
            }
            else {
                if ($null -ne $_.remoteSQLVM) {
                ("Remote -> " + $($_.remoteSQLVM))
                }
            }
        }
    } `
    | Out-String
    Write-Host
    $out.Trim() | Out-Host
}

function Copy-SampleConfigs {

    $realConfigPath = $Common.ConfigPath
    $sampleConfigPath = Join-Path $Common.ConfigPath "samples"

    Write-Log "Copy-SampleConfigs: Checking if any sample configs need to be copied to config directory" -LogOnly -Verbose
    foreach ($item in Get-ChildItem $sampleConfigPath -File -Filter *.json) {
        $copyFile = $true
        $sampleFile = $item.FullName
        $fileName = Split-Path -Path $sampleFile -Leaf
        $configFile = Join-Path -Path $realConfigPath $fileName
        if (Test-Path $configFile) {
            $sampleFileHash = Get-FileHash $sampleFile
            $configFileHash = Get-FileHash $configFile
            if ($configFileHash -ne $sampleFileHash) {
                Write-Log "Copy-SampleConfigs: Skip copying $fileName to config directory. File exists, and has different hash." -LogOnly -Verbose
                $copyFile = $false
            }
        }

        if ($copyFile) {
            Write-Log "Copy-SampleConfigs: Copying $fileName to config directory." -LogOnly -Verbose
            Copy-Item -Path $sampleFile -Destination $configFile -Force
        }
    }
}
