[CmdletBinding()]
param (
    [Parameter(Mandatory = $false, HelpMessage = "Used when calling from New-Lab")]
    [Switch] $InternalUseOnly
)

$return = [PSCustomObject]@{
    ConfigFileName = $null
    DeployNow      = $false
    ForceNew       = $false
}

# Set Debug & Verbose
$enableVerbose = if ($PSBoundParameters.Verbose -eq $true) { $true } else { $false };
$enableDebug = if ($PSBoundParameters.Debug -eq $true) { $true } else { $false };
$DebugPreference = "SilentlyContinue"
if (-not $InternalUseOnly.IsPresent) {
    if ($Common.Initialized) {
        $Common.Initialized = $false
    }

    # Dot source common
    . $PSScriptRoot\Common.ps1 -VerboseEnabled:$enableVerbose
}

$configDir = Join-Path $PSScriptRoot "config"

Write-Host -ForegroundColor Cyan ""
Write-Host -ForegroundColor Green "New-Lab Configuration generator:"
Write-Host -ForegroundColor Cyan "You can use this tool to customize your MemLabs deployment."
Write-Host -ForegroundColor Cyan "Press Ctrl-C to exit without saving."
Write-Host -ForegroundColor Cyan ""
Write-Host -ForegroundColor White "Select the " -NoNewline
Write-Host -ForegroundColor Yellow "numbers or letters" -NoNewline
Write-Host -ForegroundColor White " on the left side of the options menu to navigate."
function write-help {
    $color = [System.ConsoleColor]::DarkGray
    Write-Host -ForegroundColor $color "Press " -NoNewline
    Write-Host -ForegroundColor Yellow "[Enter]" -NoNewline
    Write-Host -ForegroundColor $color " to skip a section Press " -NoNewline
    Write-Host -ForegroundColor Yellow "[Ctrl-C]" -NoNewline
    Write-Host -ForegroundColor $color " to exit without saving."
}

function Write-Option {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Option to display. Eg 1")]
        [string] $option,
        [Parameter(Mandatory = $true, HelpMessage = "Description of the option")]
        [string] $text,
        [Parameter(Mandatory = $false, HelpMessage = "Description Color")]
        [object] $color,
        [Parameter(Mandatory = $false, HelpMessage = "Option Color")]
        [object] $color2
    )

    if ($null -eq $color) {
        $color = [System.ConsoleColor]::Gray
    }
    if ($null -eq $color2) {
        $color2 = [System.ConsoleColor]::White
    }
    write-host "[" -NoNewline
    Write-Host -ForegroundColor $color2 $option -NoNewline
    Write-Host "] ".PadRight(4 - $option.Length) -NoNewLine

    while (-not [string]::IsNullOrWhiteSpace($text)) {
        #write-host $text
        $indexLeft = $text.IndexOf('[')
        $indexRight = $text.IndexOf(']')
        if ($indexRight -eq -1 -and $indexLeft -eq -1) {
            Write-Host -ForegroundColor $color "$text" -NoNewline
            break
        }
        else {

            if ($indexRight -eq -1) {
                $indexRight = 100000000
            }
            if ($indexLeft -eq -1) {
                $indexLeft = 10000000
            }

            if ($indexRight -lt $indexLeft) {
                $text2Display = $text.Substring(0, $indexRight)
                Write-Host -ForegroundColor $color "$text2Display" -NoNewline
                Write-Host -ForegroundColor DarkGray "]" -NoNewline
                $text = $text.Substring($indexRight)
                $text = $text.Substring(1)
            }
            if ($indexLeft -lt $indexRight) {
                $text2Display = $text.Substring(0, $indexLeft)
                Write-Host -ForegroundColor $color "$text2Display" -NoNewline
                Write-Host -ForegroundColor DarkGray "[" -NoNewline
                $text = $text.Substring($indexLeft)
                $text = $text.Substring(1)
            }
        }

    }
    write-host
}

function Select-ConfigMenu {
    while ($true) {
        $customOptions = [ordered]@{ "1" = "Create New Domain%white%green" }
        $domainCount = (get-list -Type UniqueDomain | Measure-Object).Count
        if ($domainCount -gt 0) {
            $customOptions += [ordered]@{"2" = "Expand Existing Domain [$($domainCount) existing domain(s)]%white%green"; }
        }
        if ($null -ne $Global:SavedConfig) {
            $customOptions += [ordered]@{"!" = "Restore In-Progress configuration%white%green" }
        }
        $customOptions += [ordered]@{"*B" = ""; "*BREAK" = "---  Load Config ($configDir)%cyan"; "3" = "Load saved config from File%gray%green"; }
        if ($Global:common.Devbranch) {
            $customOptions += [ordered]@{"4" = "Load TEST config from File%gray%yellow"; }
        }
        $customOptions += [ordered]@{"*B3" = ""; }
        $vmsRunning = (Get-List -Type VM | Where-Object { $_.State -eq "Running" } | Measure-Object).Count
        $vmsTotal = (Get-List -Type VM | Measure-Object).Count
        $os = Get-Ciminstance Win32_OperatingSystem | Select-Object @{Name = "FreeGB"; Expression = { [math]::Round($_.FreePhysicalMemory / 1mb, 0) } }, @{Name = "TotalGB"; Expression = { [int]($_.TotalVisibleMemorySize / 1mb) } }
        $availableMemory = [math]::Round($(Get-AvailableMemoryGB), 0)
        $disk = Get-Volume -DriveLetter E
        $customOptions += [ordered]@{"*BREAK2" = "---  Manage Lab [Mem Free: $($availableMemory)GB/$($os.TotalGB)GB] [E: Free $([math]::Round($($disk.SizeRemaining/1GB),0))GB/$([math]::Round($($disk.Size/1GB),0))GB] [VMs Running: $vmsRunning/$vmsTotal]%cyan"; }
        $customOptions += [ordered]@{"R" = "Regenerate Rdcman file (memlabs.rdg) from Hyper-V config%gray%green" ; "D" = "Domain Hyper-V management (Start/Stop/Snapshot/Compact/Delete)%gray%green"; "P" = "Show Passwords" }

        $pendingCount = (get-list -type VM | Where-Object { $_.InProgress -eq "True" } | Measure-Object).Count

        if ($pendingCount -gt 0 ) {
            $customOptions += @{"F" = "Delete ($($pendingCount)) Failed/In-Progress VMs (These may have been orphaned by a cancelled deployment)%Yellow%Yellow" }
        }
        Write-Host
        Write-Host -ForegroundColor cyan "---  Create Config"
        $response = Get-Menu -Prompt "Select menu option" -AdditionalOptions $customOptions -NoNewLine

        write-Verbose "1 response $response"
        if (-not $response) {
            continue
        }
        $SelectedConfig = $null
        switch ($response.ToLowerInvariant()) {
            "1" { $SelectedConfig = Select-NewDomainConfig }
            "2" { $SelectedConfig = Show-ExistingNetwork }
            #"3" { $SelectedConfig = Select-Config $sampleDir -NoMore }
            "3" { $SelectedConfig = Select-Config $configDir -NoMore }
            "4" {
                $testPath = Join-Path $configDir "tests"
                $SelectedConfig = Select-Config $testPath -NoMore
            }
            "!" {
                $SelectedConfig = $Global:SavedConfig
                $Global:SavedConfig = $null
            }
            "r" { New-RDCManFileFromHyperV -rdcmanfile $Global:Common.RdcManFilePath -OverWrite:$true }
            "f" { Select-DeletePending }
            "d" { Select-DomainMenu }
            "P" {
                Write-Host
                Write-Host "Password for all accounts is: " -NoNewline
                Write-Host -foregroundColor Green "$($Global:Common.LocalAdmin.GetNetworkCredential().Password)"
                Write-Host
                get-list -type vm | Where-Object { $_.Role -eq "DC" } | Format-Table domain, adminName , @{Name = "Password"; Expression = { $($Common.LocalAdmin.GetNetworkCredential().Password) } } | out-host
            }
            Default {}
        }
        if ($SelectedConfig) {
            Write-Verbose "SelectedConfig : $SelectedConfig"
            return $SelectedConfig
        }
    }
}


function Select-DomainMenu {

    $domainList = @()
    foreach ($item in (Get-DomainList)) {
        $stats = Get-DomainStatsLine -DomainName $item

        $domainList += "$($item.PadRight(22," ")) $stats"
    }

    if ($domainList.Count -eq 0) {
        Write-Host
        Write-Host -ForegroundColor Red "No Domains found. Please delete VM's manually from hyper-v"

        return
    }

    $domainExpanded = Get-Menu -Prompt "Select existing domain" -OptionArray $domainList
    if ([string]::isnullorwhitespace($domainExpanded)) {
        return $null
    }
    $domain = ($domainExpanded -Split " ")[0]

    Write-Verbose "2 Select-DomainMenu"
    while ($true) {
        Write-Host
        Write-Host "Domain '$domain' contains these resources:"
        Write-Host
        $vmsInDomain = get-list -type vm  -DomainName $domain
        if (-not $vmsInDomain) {
            return
        }
        ($vmsInDomain | Select-Object VmName, State, Role, SiteCode, DeployedOS, MemoryStartupGB, DiskUsedGB, SqlVersion | Format-Table | Out-String).Trim() | out-host
        #get-list -Type VM -DomainName $domain | Format-Table | Out-Host

        $customOptions = [ordered]@{
            "*d1" = "---  VM Management%cyan";
            "1"   = "Start VMs in domain%white%green";
            "2"   = "Stop VMs in domain%white%green";
            "3"   = "Compact all VHDX's in domain (requires domain to be stopped)%white%green";
            "*S"  = "";
            "*S1" = "---  Snapshot Management%cyan"
            "S"   = "Snapshot all VM's in domain%white%green"
        }
        $checkPoint = $null
        $DC = get-list -type vm -DomainName $domain | Where-Object { $_.role -eq "DC" }
        if ($DC) {
            $checkPoint = Get-VMCheckpoint2 -vmname $DC.vmName | where-object { $_.Name -like '*MemLabs*' }
        }
        if ($checkPoint) {
            $customOptions += [ordered]@{ "R" = "Restore all VM's to last snapshot%white%green"; "X" = "Delete (merge) domain Snapshots%white%green" }
        }
        $customOptions += [ordered]@{"*Z" = ""; "*Z1" = "---  Danger Zone%cyan"; "D" = "Delete VMs in Domain%Yellow%Red" }
        $response = Get-Menu -Prompt "Select domain options" -AdditionalOptions $customOptions

        write-Verbose "1 response $response"
        if (-not $response) {
            return
        }

        switch ($response.ToLowerInvariant()) {
            "2" { Select-StopDomain -domain $domain }
            "1" { Select-StartDomain -domain $domain }
            "3" { select-OptimizeDomain -domain $domain }
            "d" {
                Select-DeleteDomain -domain $domain
                return
            }
            "s" { select-SnapshotDomain -domain $domain }
            "r" { select-RestoreSnapshotDomain -domain $domain }
            "x" { select-DeleteSnapshotDomain -domain $domain }
            Default {}
        }
    }
}

function select-SnapshotDomain {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Domain To SnapShot")]
        [string] $domain
    )
    Write-Host
    Write-Host -ForegroundColor Yellow "It is reccommended to stop Critical VM's before snapshotting. Please select which VM's to stop."
    Select-StopDomain -domain $domain
    get-SnapshotDomain -domain $domain
    Select-StartDomain -domain $domain

}


function get-SnapshotDomain {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Domain To SnapShot")]
        [string] $domain,
        [Parameter(Mandatory = $false, HelpMessage = "Comment")]
        [string] $comment
    )
    $vms = get-list -type vm -DomainName $domain
    Write-Log "Snapshotting Virtual Machines in '$domain'" -Activity
    Write-Log "Domain $domain has $(($vms | Measure-Object).Count) resources"
    $date = Get-Date -Format "yyyy-MM-dd hh.mmtt"
    $snapshot = $date + " (MemLabs)"
    $valid = $false
    while (-not $valid) {
        if (-not $comment) {
            $comment = Read-Host2 -Prompt "Snapshot Comment (Optional) []" $splitpath -HideHelp
        }
        if (-not [string]::IsNullOrWhiteSpace($comment) -and $comment -match "^[\\\/\:\*\?\<\>\|]*$") {
            Write-Host "$comment contains invalid characters"
            $comment = $null
        }
        else {
            $valid = $true
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($comment)) {
        $snapshot = $snapshot + " " + $comment
    }
    foreach ($vm in $vms) {
        $complete = $false
        $tries = 0
        While ($complete -ne $true) {
            try {
                if ($tries -gt 10) {
                    return
                }
                Write-Host "Checkpointing $($vm.VmName) to [$($snapshot)]"
                $json = $snapshot + ".json"
                $notesFile = Join-Path (Get-VM2 -Name $($vm.VmName)).Path $json
                (Get-VM2 -Name $($vm.VmName)).notes | Out-File $notesFile


                Checkpoint-VM2 -Name $vm.VmName -SnapshotName $snapshot -ErrorAction Stop
                $complete = $true
            }
            catch {
                write-log "Error: $_"
                write-log "Retrying."
                $tries++
                Start-Sleep 10

            }
        }
    }

    write-host
    Write-Host "$domain has been CheckPointed"
}

function select-RestoreSnapshotDomain {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Domain To SnapShot")]
        [string] $domain
    )


    $vms = get-list -type vm -DomainName $domain
    $dc = $vms | Where-Object { $_.role -eq "DC" }

    $snapshots = Get-VMCheckpoint2 -VMName $dc.vmName -ErrorAction SilentlyContinue | where-object { $_.Name -like "*MemLabs*" } | Sort-Object CreationTime | Select-Object -ExpandProperty Name
    if (-not $snapshots) {
        write-host "No snapshots found for $domain"
        return
    }
    $response = get-menu -Prompt "Select Snapshot to restore" -OptionArray $snapshots
    if ([string]::IsNullOrWhiteSpace($response) -or $response -eq "None") {
        return
    }
    $missingVMS = @()

    foreach ($vm in $vms) {
        $checkPoint = Get-VMCheckpoint2 -VMName $vm.vmName -Name $response -ErrorAction SilentlyContinue | Sort-Object CreationTime | Select-Object -Last 1
        if (-not $checkPoint) {
            $missingVMS += $vm.VmName
        }
    }
    if ($missingVMS.Count -gt 0) {
        Write-Host
        $DeleteVMs = Read-Host2 -Prompt "The following VM's do not have checkpoints. [$($missingVMs -join ",")]  Delete them? (y/N)" -HideHelp
    }

    $startAll = Read-Host2 -Prompt "Start All vms after restore? (Y/n)" -HideHelp
    if ($startAll.ToLowerInvariant() -eq "n" -or $startAll.ToLowerInvariant() -eq "no") {
        $startAll = $null
    }
    else {
        $startAll = "A"
    }

    Write-Log "Restoring Virtual Machines in '$domain' to previous snapshot" -Activity

    foreach ($vm in $vms) {
        $complete = $false
        $tries = 0
        While ($complete -ne $true) {
            try {
                if ($tries -gt 10) {
                    return
                }
                $checkPoint = Get-VMCheckpoint2 -VMName $vm.vmName -Name $response -ErrorAction SilentlyContinue | Sort-Object CreationTime | Select-Object -Last 1

                if ($checkPoint) {
                    Write-Host "Restoring $($vm.VmName)"
                    $checkPoint | Restore-VMCheckpoint -Confirm:$false
                    if ($response -eq "MemLabs Snapshot") {
                        $notesFile = Join-Path (Get-VM2 -Name $($vm.VmName)).Path 'MemLabs.Notes.json'
                    }
                    else {
                        $jsonfile = $response + ".json"
                        $notesFile = Join-Path (Get-VM2 -Name $($vm.VmName)).Path $jsonfile
                    }
                    if (Test-Path $notesFile) {
                        $notes = Get-Content $notesFile
                        set-vm -VMName $vm.vmName -notes $notes
                    }

                }
                $complete = $true
            }
            catch {
                write-log "$_"
                write-host "Retrying..."
                Start-Sleep 10
                $tries++

            }
        }
    }
    Get-List -type VM -SmartUpdate | out-null

    if ($missingVMS.Count -gt 0) {
        #Write-Host
        #$response2 = Read-Host2 -Prompt "The following VM's do not have checkpoints. [$($missingVMs -join ",")]  Delete them? (y/N)" -HideHelp
        if ($DeleteVMs.ToLowerInvariant() -eq "y" -or $DeleteVMs.ToLowerInvariant() -eq "yes") {
            foreach ($item in $missingVMS) {
                Remove-VirtualMachine -VmName $item
            }
            New-RDCManFileFromHyperV -rdcmanfile $Global:Common.RdcManFilePath -OverWrite:$false
        }

    }
    write-host
    Write-Host "$domain has been Restored"
    Select-StartDomain -domain $domain -response $startAll
}

function select-DeleteSnapshotDomain {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Domain To SnapShot")]
        [string] $domain
    )
    $vms = get-list -type vm -DomainName $domain
    $dc = $vms | Where-Object { $_.role -eq "DC" }

    $snapshots = Get-VMCheckpoint2 -VMName $dc.vmName -ErrorAction SilentlyContinue | where-object { $_.Name -like "*MemLabs*" } | Sort-Object CreationTime | Select-Object -ExpandProperty Name
    if (-not $snapshots) {
        write-host "No snapshots found for $domain"
        return
    }
    $response = get-menu -Prompt "Select Snapshot to merge/delete" -OptionArray $snapshots -additionalOptions @{"A" = "All Snapshots" }
    if ([string]::IsNullOrWhiteSpace($response) -or $response -eq "None") {
        return
    }

    Write-Log "Removing previous snapshots of Virtual Machines in '$domain'" -Activity
    $vms = get-list -type vm -DomainName $domain

    foreach ($vm in $vms) {
        $complete = $false
        $tries = 0
        While ($complete -ne $true) {
            try {
                if ($tries -gt 10) {
                    return
                }
                $snapshots = Get-VMCheckpoint2 -VMName $vm.vmName -ErrorAction SilentlyContinue | where-object { $_.Name -like "*MemLabs*" } | Sort-Object CreationTime | Select-Object -ExpandProperty Name
                #$checkPoint = Get-VMCheckpoint2 -VMName $vm.vmName -Name 'MemLabs Snapshot' -ErrorAction SilentlyContinue

                if ($snapshots) {
                    foreach ($snapshot in $snapshots) {
                        if ($snapshot -eq $response -or $response -eq "A") {
                            Write-Host "Removing $snapshot for $($vm.VmName) and merging into vhdx"
                            Remove-VMCheckpoint2 -VMName $vm.vmName -Name $snapshot

                            if ($snapshot -eq "MemLabs Snapshot") {
                                $notesFile = Join-Path (Get-VM2 -Name $($vm.VmName)).Path 'MemLabs.Notes.json'
                            }
                            else {
                                $notesFile = Join-Path (Get-VM2 -Name $($vm.VmName)).Path $snapshot + '.json'
                            }

                            if (Test-Path $notesFile) {
                                Remove-Item $notesFile -Force
                            }
                        }
                    }
                }

                $complete = $true
            }
            catch {
                Start-Sleep 10
                $tries++

            }
        }
    }
    get-list -type vm -SmartUpdate | out-null
    write-host
    Write-Host "$domain snapshots have been merged"

}

function select-OptimizeDomain {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Domain To Optimize")]
        [string] $domain
    )
    select-StopDomain $domain

    $vms = get-list -type vm -DomainName $domain

    $size = (Get-List -type vm -domain $domain | measure-object -sum DiskUsedGB).sum
    write-Host "Total size of VMs in $domain before optimize: $([math]::Round($size,2))GB"
    foreach ($vm in $vms) {
        #Get-VHD -VMId $vm.VmId | Optimize-VHD -Mode Full
        foreach ($hd in Get-VHD -VMId $vm.VmId) {
            #    Mount-VHD -Path $hd.Path
            try {
                Mount-VHD -Path $hd.Path -ReadOnly -ErrorAction Stop
                Optimize-VHD -Path $hd.Path -Mode Full -ErrorAction Continue
            }
            finally {
                Dismount-VHD -Path $hd.Path
            }
        }
    }

    get-list -type VM -SmartUpdate | out-null
    $sizeAfter = (Get-List -type vm -domain $domain | measure-object -sum DiskUsedGB).sum
    write-Host "Total size of VMs in $domain after optimize: $([math]::Round($sizeAfter,2))GB"
    write-host
    Write-Host "$domain has been stopped and optimized. Make sure to restart the domain if neccessary."

}

function Select-StartDomain {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Domain To Stop")]
        [string] $domain,
        [Parameter(Mandatory = $false, HelpMessage = "Prepopulate response")]
        [string] $response = $null
    )

    if ($response) {
        $preResponse = $response
    }
    $response = $null
    while ($true) {
        Write-Host

        $vms = get-list -type vm -DomainName $domain -SmartUpdate

        $notRunning = $vms | Where-Object { $_.State -ne "Running" }
        if ($notRunning -and ($notRunning | Measure-Object).count -gt 0) {
            Write-Host "$(($notRunning | Measure-Object).count) VM's in '$domain' are not Running"
        }
        else {
            Write-Host "All VM's in '$domain' are already Running"
            return
        }


        $vmsname = $notRunning | Select-Object -ExpandProperty vmName
        $customOptions = [ordered]@{"A" = "Start All VMs" ; "C" = "Start Critial VMs only (DC/SiteServers/Sql)" }

        if (-not $preResponse) {
            $response = Get-Menu -Prompt "Select VM to Start" -OptionArray $vmsname -AdditionalOptions $customOptions -Test:$false -CurrentValue "None"
        }
        else {
            $response = $preResponse
            $preResponse = $null
        }


        if ([string]::IsNullOrWhiteSpace($response) -or $response -eq "None") {
            return
        }
        if ($response -eq "A" -or $response -eq "C") {
            $CriticalOnly = $false
            if ($response -eq "C") {
                $CriticalOnly = $true
            }
            $response = $null
            $dc = $vms | Where-Object { $_.Role -eq "DC" }
            $sqlServers = $vms | Where-Object { $_.Role -eq "DomainMember" -and $null -ne $_.SqlVersion }
            $cas = $vms | Where-Object { $_.Role -eq "CAS" }
            $pri = $vms | Where-Object { $_.Role -eq "Primary" }
            $other = $vms | Where-Object { $_.vmName -notin $dc.vmName -and $_.vmName -notin $sqlServers.vmName -and $_.vmName -notin $cas.vmName -and $_.vmName -notin $pri.vmName }

            $waitSecondsDC = 20
            $waitSeconds = 10
            if ($dc -and ($dc.State -ne "Running")) {
                write-host "DC [$($dc.vmName)] state is [$($dc.State)]. Starting VM and waiting $waitSecondsDC seconds before continuing"
                start-vm2 $dc.vmName
                start-Sleep -Seconds $waitSecondsDC
            }

            if ($sqlServers) {
                foreach ($sql in $sqlServers) {
                    if ($sql.State -ne "Running") {
                        write-host "SQL Server [$($sql.vmName)] state is [$($sql.State)]. Starting VM and waiting $waitSeconds seconds before continuing"
                        start-vm2 $sql.vmName
                    }
                }
                start-sleep $waitSeconds
            }

            if ($cas) {
                foreach ($ss in $cas) {
                    if ($ss.State -ne "Running") {
                        write-host "CAS [$($ss.vmName)] state is [$($ss.State)]. Starting VM and waiting $waitSeconds seconds before continuing"
                        start-vm2 $ss.vmName
                    }
                }
                start-sleep $waitSeconds
            }

            if ($pri) {
                foreach ($ss in $pri) {
                    if ($ss.State -ne "Running") {
                        write-host "Primary [$($ss.vmName)] state is [$($ss.State)]. Starting VM and waiting $waitSeconds seconds before continuing"
                        start-vm2 $ss.vmName
                    }
                }
                start-sleep $waitSeconds
            }
            if ($CriticalOnly -eq $false) {
                foreach ($vm in $other) {
                    if ($vm.State -ne "Running") {
                        write-host "VM [$($vm.vmName)] state is [$($vm.State)]. Starting VM"
                        #start-job -Name $vm.vmName -ScriptBlock { param($vm) start-vm2 $vm } -ArgumentList $vm.vmName | Out-Null
                        $vm2 = get-vm2 -Name $vm.VmName
                        start-vm -VM $vm2 -AsJob  | Out-Null

                    }
                }
            }
            Write-Log -HostOnly "Waiting for VM Start Jobs to complete" -Verbose
            get-job | wait-job | out-null
            Write-Log -HostOnly "VM Start Jobs are complete" -Verbose
            get-job | remove-job | out-null

            get-list -type VM -SmartUpdate | out-null
            return

        }
        else {
            start-vm2 $response
            get-job | wait-job | out-null
            get-job | remove-job | out-null
            #get-list -type VM -SmartUpdate | out-null
            $response = $null
        }
    }
    get-list -type VM -SmartUpdate | out-null
}


function Select-StopDomain {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Domain To Stop")]
        [string] $domain,
        [Parameter(Mandatory = $false, HelpMessage = "Prepopulate response")]
        [string] $response = $null
    )

    if ($response) {
        $preResponse = $response
    }

    While ($true) {
        $response = $null
        Write-Host
        $vms = get-list -type vm -DomainName $domain -SmartUpdate
        $running = $vms | Where-Object { $_.State -ne "Off" }
        if ($running -and ($running | Measure-Object).count -gt 0) {
            Write-host "$(($running| Measure-Object).count) VM's in '$domain' are currently running."
        }
        else {
            Write-host "All VM's in '$domain' are already turned off."
            return
        }

        $vmsname = $running | Select-Object -ExpandProperty vmName
        $customOptions = [ordered]@{"A" = "Stop All VMs" ; "N" = "Stop non-critical VMs (All except: DC/SiteServers/SQL)"; "C" = "Stop Critical VMs (DC/SiteServers/SQL)" }
        if (-not $preResponse) {
            $response = Get-Menu -Prompt "Select VM to Stop" -OptionArray $vmsname -AdditionalOptions $customOptions -Test:$false -CurrentValue "None"
        }
        else {
            $response = $preResponse
            $preResponse = $null
        }

        if ([string]::IsNullOrWhiteSpace($response) -or $response -eq "None") {
            return
        }
        if ($response -eq "A" -or $response -eq "C" -or $response -eq "N") {

            $nonCriticalOnly = $false
            if ($response -eq "N") {
                $nonCriticalOnly = $true
            }
            if ($response -eq "C") {
                $criticalOnly = $true
            }
            foreach ($vm in $vms) {
                if ($nonCriticalOnly -eq $true) {
                    if ($vm.Role -eq "CAS" -or $vm.Role -eq "Primary" -or $vm.Role -eq "Secondary" -or $vm.Role -eq "DC" -or ($vm.Role -eq "DomainMember" -and $null -ne $vm.SqlVersion) ) {
                        continue
                    }
                }
                if ($criticalOnly -eq $true) {
                    if ($vm.Role -eq "CAS" -or $vm.Role -eq "Primary" -or $vm.Role -eq "Secondary" -or $vm.Role -eq "DC" -or ($vm.Role -eq "DomainMember" -and $null -ne $vm.SqlVersion) ) {

                    }
                    else {
                        continue
                    }
                }
                $vm2 = Get-VM2 -Name $vm.vmName -ErrorAction SilentlyContinue
                if ($vm2.State -eq "Running") {
                    Write-Host "$($vm.vmName) is [$($vm2.State)]. Shutting down VM. Will forcefully stop after 5 mins"
                    stop-vm -VM $VM2 -force -AsJob | Out-Null
                }
            }
            get-job | wait-job | Out-Null
            get-job | remove-job | Out-Null
            get-list -type VM -SmartUpdate | out-null
            return
        }
        else {
            stop-vm2 $response -force
            get-job | wait-job | Out-Null
            get-job | remove-job | Out-Null
            get-list -type VM -SmartUpdate | out-null
        }

    }
}

function Select-DeleteDomain {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Domain To Stop")]
        [string] $domain
    )

    while ($true) {
        $vms = get-list -type vm -DomainName $domain -SmartUpdate | Select-Object -ExpandProperty vmName
        if (-not $vms) {
            return
        }
        $customOptions = [ordered]@{"D" = "Delete All VMs" }
        $response = Get-Menu -Prompt "Select VM to Delete" -OptionArray $vms -AdditionalOptions $customOptions -Test:$false

        if ([string]::IsNullOrWhiteSpace($response)) {
            return
        }
        if ($response -eq "D") {
            Write-Host "Selecting 'Yes' will permantently delete all VMs and scopes."
            $response = Read-Host2 -Prompt "Are you sure? (y/N)" -HideHelp
            if (-not [String]::IsNullOrWhiteSpace($response)) {
                if ($response.ToLowerInvariant() -eq "y" -or $response.ToLowerInvariant() -eq "yes") {
                    Remove-Domain -DomainName $domain
                    return
                }
            }
        }
        else {
            $response2 = Read-Host2 -Prompt "Delete VM $response? (Y/n)" -HideHelp

            if ($response2.ToLowerInvariant() -eq "n" -or $response2.ToLowerInvariant() -eq "no") {
                continue
            }
            else {
                Remove-VirtualMachine -VmName $response
                Get-List -type VM -SmartUpdate | Out-Null
                New-RDCManFileFromHyperV -rdcmanfile $Global:Common.RdcManFilePath -OverWrite:$false
                continue
            }
        }
    }
}

function Select-DeletePending {

    get-list -Type VM -SmartUpdate | Where-Object { $_.InProgress -eq "True" } | Format-Table -Property vmname, Role, SiteCode, DeployedOS, MemoryStartupGB, @{Label = "DiskUsedGB"; Expression = { [Math]::Round($_.DiskUsedGB, 2) } }, State, Domain, Subnet, SQLVersion | Out-Host
    Write-Host "Please confirm these VM's are not currently in process of being deployed."
    Write-Host "Selecting 'Yes' will permantently delete all VMs and scopes."
    $response = Read-Host2 -Prompt "Are you sure? (y/N)" -HideHelp
    if (-not [String]::IsNullOrWhiteSpace($response)) {
        if ($response.ToLowerInvariant() -eq "y" -or $response.ToLowerInvariant() -eq "yes") {
            Remove-InProgress
            Get-List -type VM -SmartUpdate | Out-Null
        }
    }
}
function get-VMOptionsSummary {

    $options = $Global:Config.vmOptions
    if ($null -eq $options.timeZone) {
        $currentTimeZone = (Get-TimeZone).Id
        $options | Add-Member -MemberType NoteProperty -Name "timeZone" -Value $currentTimeZone -Force
    }
    $domainName = "[$($options.domainName)]".PadRight(21)
    $Output = "$domainName [Prefix $($options.prefix)] [Network $($options.network)] [Username $($options.adminName)] [Location $($options.basePath)] [TZ $($options.timeZone)]"
    return $Output
}

function get-CMOptionsSummary {

    $options = $Global:Config.cmOptions
    $ver = "[$($options.version)]".PadRight(21)
    $Output = "$ver [Install $($options.install)] [Update $($options.updateToLatest)] [Push Clients $($options.pushClientToDomainMembers)]"
    return $Output
}

function get-VMSummary {

    $vms = $Global:Config.virtualMachines

    $numVMs = ($vms | Measure-Object).Count
    $numDCs = ($vms | Where-Object { $_.Role -eq "DC" } | Measure-Object).Count
    $numDPMP = ($vms | Where-Object { $_.Role -eq "DPMP" } | Measure-Object).Count
    $numPri = ($vms | Where-Object { $_.Role -eq "Primary" } | Measure-Object).Count
    $numSec = ($vms | Where-Object { $_.Role -eq "Secondary" } | Measure-Object).Count
    $numCas = ($vms | Where-Object { $_.Role -eq "CAS" } | Measure-Object).Count
    $numMember = ($vms | Where-Object { $_.Role -eq "WorkgroupMember" -or $_.Role -eq "AADClient" -or $_.Role -eq "InternetClient" -or ($_.Role -eq "DomainMember" -and $null -eq $_.SqlVersion) } | Measure-Object).Count
    $numSQL = ($vms | Where-Object { $_.Role -eq "DomainMember" -and $null -ne $_.SqlVersion } | Measure-Object).Count
    $RoleList = ""
    if ($numDCs -gt 0 ) {
        $RoleList += "[DC]"
    }
    if ($numCas -gt 0 ) {
        $RoleList += "[CAS]"
    }
    if ($numPri -gt 0 ) {
        $RoleList += "[Primary]"
    }
    if ($numSec -gt 0 ) {
        $RoleList += "[Secondary]"
    }
    if ($numDPMP -gt 0 ) {
        $RoleList += "[DPMP]"
    }
    if ($numSQL -gt 0 ) {
        $RoleList += "[$numSQL SQL]"
    }
    if ($numMember -gt 0 ) {
        $RoleList += "[$numMember Member(s)]"
    }
    $num = "[$numVMs VM(s)]".PadRight(21)
    $Output = "$num $RoleList"
    if ($numVMs -lt 4) {
        $Output += " {$(($vms | Select-Object -ExpandProperty vmName) -join ",")}"
    }
    return $Output
}

function Select-MainMenu {
    while ($true) {
        $global:StartOver = $false
        $preOptions = [ordered]@{}
        $preOptions += [ordered]@{ "*G" = "---  Global Options%cyan%cyan"; "V" = "Global VM Options `t $(get-VMOptionsSummary)%gray%green" }
        if ($Global:Config.cmOptions) {
            $preOptions += [ordered]@{"C" = "Global CM Options `t $(get-CMOptionsSummary)%gray%green" }
        }
        $preOptions += [ordered]@{ "*V1" = ""; "*V" = "---  Virtual Machines%cyan%cyan" }
        $customOptions = [ordered]@{}
        #$customOptions += @{"3" = "Virtual Machines `t`t $(get-VMSummary)" }

        $i = 0
        #$valid = Get-TestResult -SuccessOnError
        foreach ($virtualMachine in $global:config.virtualMachines) {
            if ($null -eq $virtualMachine) {
                $global:config.virtualMachines | convertTo-Json -Depth 5 | out-host
            }
            $i = $i + 1
            $name = Get-VMString $virtualMachine
            $customOptions += [ordered]@{"$i" = "$name%white%green" }
            #write-Option "$i" "$($name)"
        }

        $customOptions += [ordered]@{ "N" = "New Virtual Machine%DarkGreen%Green"; "*D1" = ""; "*D" = "---  Deployment%cyan%cyan"; "!" = "Return to main menu%gray%green"; "S" = "Save Configuration and Exit%gray%green" }
        if ($InternalUseOnly.IsPresent) {
            $customOptions += [ordered]@{ "D" = "Deploy Config%Green%Green" }
        }
        if ($enableDebug) {
            $customOptions += [ordered]@{ "R" = "Return deployConfig" }
            $customOptions += [ordered]@{ "P" = "Return PerVM thisParams" }
            $customOptions += [ordered]@{ "Z" = "Generate DSC.Zip" }
        }

        $response = Get-Menu -Prompt "Select menu option" -OptionArray $optionArray -AdditionalOptions $customOptions -preOptions $preOptions -Test:$false
        write-Verbose "response $response"
        if (-not $response) {
            continue
        }
        switch ($response.ToLowerInvariant()) {
            "v" { Select-Options -Rootproperty $($Global:Config) -PropertyName vmOptions -prompt "Select Global Property to modify" }
            "c" { Select-Options -Rootproperty $($Global:Config) -PropertyName cmOptions -prompt "Select ConfigMgr Property to modify" }
            "d" { return $true }
            "s" { return $false }
            "r" {
                $c = Test-Configuration -InputObject $Global:Config
                $global:DebugConfig = $c
                $global:DebugConfigEx = ConvertTo-DeployConfigEx -DeployConfig $c.DeployConfig
                write-Host 'Debug Config stored in $global:DebugConfig and $global:DebugConfigEx'
                return $global:DebugConfig
            }
            "p" {
                $returnArray = [pscustomObject]@{
                    VMs = @()
                }
                $config = Test-Configuration -InputObject $Global:Config
                foreach ($currentItem in $config.deployConfig.virtualMachines) {
                    $deployConfigCopy = $config.deployConfig | ConvertTo-Json -Depth 5 | ConvertFrom-Json
                    Add-PerVMSettings -deployConfig $deployConfigCopy -thisVM $currentItem
                    $vm = $currentItem
                    $vm | Add-Member -MemberType NoteProperty -Name "thisParams" -Value $deployConfigCopy.thisParams -Force
                    $returnArray.VMs += $vm
                }
                $global:DebugPerVMSettings = $returnArray
                write-Host 'Per VM Settings stored in $global:DebugPerVMSettings'
                return $global:DebugPerVMSettings

            }
            "!" {
                $global:StartOver = $true
                return $false
            }
            "z" {
                $i = 0
                $filename = Save-Config $Global:Config
                #$creds = New-Object System.Management.Automation.PSCredential ($Global:Config.vmOptions.adminName, $Global:Common.LocalAdmin.GetNetworkCredential().Password)
                $t = Test-Configuration -InputObject $Global:Config
                Add-ExistingVMsToDeployConfig -config $t.DeployConfig
                foreach ($virtualMachine in $t.DeployConfig.virtualMachines) {
                    $i = $i + 1
                    $name = $virtualMachine
                    write-Option "$i" "$($name)"
                }
                $response = get-ValidResponse "Which VM do you want" $i $null
                $i = 0
                foreach ($virtualMachine in  $t.DeployConfig.virtualMachines) {
                    $i = $i + 1
                    if ($i -eq $response) {
                        $vmName = $virtualMachine.vmName
                        break
                    }
                }


                $params = @{configName = $filename; vmName = $vmName; Debug = $false }

                write-host "& .\dsc\createGuestDscZip.ps1 -configName ""$fileName"" -vmName $vmName"
                #Invoke-Expression  ".\dsc\createGuestDscZip.ps1 -configName ""$fileName"" -vmName $vmName -confirm:$false"
                & ".\dsc\createGuestDscZip.ps1" @params | Out-Host
                Set-Location $PSScriptRoot | Out-Null
            }
            default { Select-VirtualMachines $response }
        }
    }
}

function Get-ValidSubnets {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, HelpMessage = "Config")]
        [object] $configToCheck = $global:config
    )

    $subnetlist = @()
    for ($i = 1; $i -lt 254; $i++) {
        $newSubnet = "192.168." + $i + ".0"
        $found = $false
        foreach ($subnet in (Get-SubnetList)) {
            if ($subnet.Subnet -eq $newSubnet) {
                $found = $true
                break
            }
        }
        if (-not $found) {
            $subnetlist += $newSubnet
            if ($subnetlist.Count -gt 2) {
                break
            }

        }

    }

    for ($i = 1; $i -lt 254; $i++) {
        $newSubnet = "172.16." + $i + ".0"
        $found = $false
        foreach ($subnet in (Get-SubnetList)) {
            if ($subnet.Subnet -eq $newSubnet) {
                $found = $true
                break
            }
        }
        if (-not $found) {
            $subnetlist += $newSubnet
            if ($subnetlist.Count -gt 5) {
                break
            }

        }
    }

    for ($i = 1; $i -lt 254; $i++) {
        $newSubnet = "10.0." + $i + ".0"
        $found = $false
        foreach ($subnet in (Get-SubnetList)) {
            if ($subnet.Subnet -eq $newSubnet) {
                $found = $true
                break
            }
        }
        if (-not $found) {
            $subnetlist += $newSubnet
            if ($subnetlist.Count -gt 8) {
                break
            }
        }
    }
    return $subnetlist
}

function Get-NewMachineName {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "VM to rename")]
        [object] $vm,
        [Parameter(Mandatory = $false, HelpMessage = "Config to modify")]
        [Object] $ConfigToCheck = $global:config,
        [Parameter(Mandatory = $false, HelpMessage = "ClusterName")]
        [switch] $ClusterName,
        [Parameter(Mandatory = $false, HelpMessage = "AlwaysOnName")]
        [switch] $AOName,
        [Parameter(Mandatory = $false, HelpMessage = "Skip 1 in machine name")]
        [switch] $SkipOne
    )

    #Get-PSCallStack | Out-Host

    $Domain = $vm.vmOptions.DomainName
    $OS = $vm.OperatingSystem
    $SiteCode = $vm.SiteCode
    $InstallDP = $vm.InstallDP
    $InstallMP = $vm.InstallMP
    $CurrentName = $vm.vmName
    $Role = $vm.Role
    $RoleName = $vm.Role
    if ($Role -eq "OSDClient") {
        $RoleName = "OSD"
    }
    if ($Role -eq "DomainMember" -or [string]::IsNullOrWhiteSpace($Role) -or $Role -eq "WorkgroupMember" -or $Role -eq "AADClient" -or $role -eq "InternetClient") {
        if (($ConfigToCheck.vmOptions.prefix.length) -gt 4) {
            $RoleName = "Mem"
        }
        else {
            $RoleName = "Member"
        }

        if ($OS -like "*Server*") {
            if ($vm.SqlVersion) {
                $RoleName = "SQL"
            }
            else {
                if (($ConfigToCheck.vmOptions.prefix.length) -gt 4) {
                    $RoleName = "Srv"
                }
                else {
                    $RoleName = "Server"
                }
            }

        }
        else {
            if (($ConfigToCheck.vmOptions.prefix.length) -gt 4) {
                $RoleName = "Cli"
            }
            else {
                $RoleName = "Client"
            }


        }


        if ($Role -eq "WorkgroupMember") {
            $RoleName = "WG"
        }
        if ($Role -eq "InternetClient") {
            $RoleName = "INT"
        }
        if ($Role -eq "AADClient") {
            $RoleName = "AAD"
        }
        if ($Role -eq "FileServer") {
            $RoleName = "FS"
        }
        Write-Verbose "Rolename is now $RoleName"

        if ($OS -like "Windows 10*") {

            $RoleName = "W10" + $RoleName
        }
        if ($OS -like "Windows 11*") {

            $RoleName = "W11" + $RoleName
        }

        switch ($OS) {
            "Server 2022" {

                $RoleName = "W22" + $RoleName
            }
            "Server 2019" {

                $RoleName = "W19" + $RoleName
            }
            "Server 2016" {

                $RoleName = "W16" + $RoleName
            }
            Default {}
        }
    }

    if (($role -eq "Primary") -or ($role -eq "CAS") -or ($role -eq "PassiveSite") -or ($role -eq "Secondary")) {
        if ([String]::IsNullOrWhiteSpace($SiteCode)) {
            $newSiteCode = Get-NewSiteCode $Domain -Role $Role
        }
        else {
            $newSiteCode = $SiteCode
        }
        $NewName = $newSiteCode + "SITE"
        if ($role -eq "PassiveSite") {
            $NewName = $NewName + "-P"
        }
        return $NewName
    }

    #if ($role -eq "DPMP") {
    #    $PSVM = $ConfigToCheck.VirtualMachines | Where-Object { $_.Role -eq "Primary" } | Select-Object -First 1
    #    if ($PSVM -and $PSVM.SiteCode) {
    #        return $($PSVM.SiteCode) + $role
    #    }
    #}

    if ($role -eq "DPMP") {
        $RoleName = $siteCode + $role

        if ($InstallMP -and -not $InstallDP) {
            $RoleName = $siteCode + "MP"

        }
        if ($InstallDP -and -not $InstallMP) {
            $RoleName = $siteCode + "DP"

        }

    }
    if ($Role -eq "FileServer") {
        $RoleName = "FS"

    }

    if ($Role -eq "SQLAO") {
        if ($ClusterName) {
            $RoleName = "SqlCluster"
        }
        if ($AoName) {
            $RoleName = "AlwaysOn"
        }
    }

    [int]$i = 1
    while ($true) {
        if ($SkipOne -and $i -eq 1) {
            $NewName = $RoleName
        }
        else {
            $NewName = $RoleName + ($i)
        }
        if ($null -eq $ConfigToCheck) {
            write-log "Config is NULL..  Machine names will not be checked. Please notify someone of this bug."
            #break
        }
        if (($ConfigToCheck.virtualMachines | Where-Object { ($_.vmName -eq $NewName -or $_.AlwaysOnName -eq $NewName -or $_.ClusterName -eq $NewName) -and $NewName -ne $CurrentName } | Measure-Object).Count -eq 0) {

            $newNameWithPrefix = ($ConfigToCheck.vmOptions.prefix) + $NewName
            if ((Get-List -Type VM | Where-Object { $_.vmName -eq $newNameWithPrefix -or $_.ClusterName -eq $newNameWithPrefix -or $_.AlwaysOnName -eq $newNameWithPrefix } | Measure-Object).Count -eq 0) {
                break
            }
        }
        write-log -verbose "$newName already exists [$CurrentName].. Trying next"
        $i++
    }
    return $NewName.ToUpper()
}

function Get-NewSiteCode {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Domain Name")]
        [String] $Domain,
        [Parameter(Mandatory = $true, HelpMessage = "Role of the machine CAS/Primary")]
        [String] $Role
    )

    if ($Role -eq "CAS") {
        $NumberOfCAS = (Get-ExistingForDomain -DomainName $Domain -Role CAS | Measure-Object).Count
        #     if ($NumberOfCAS -eq 0) {
        #         return "CAS"
        #     }
        #else {
        return "CS" + ($NumberOfCAS + 1)
        #}
    }
    if ($role -eq "Primary") {
        $NumberOfPrimaries = (Get-ExistingForDomain -DomainName $Domain -Role Primary | Measure-Object).Count
        #$NumberOfCas = (Get-ExistingForDomain -DomainName $Domain -Role CAS | Measure-Object).Count

        return "PS" + ($NumberOfPrimaries + 1)
    }

    if ($role -eq "Secondary") {
        $NumberOfSecondaries = (Get-ExistingForDomain -DomainName $Domain -Role Secondary | Measure-Object).Count
        #$NumberOfCas = (Get-ExistingForDomain -DomainName $Domain -Role CAS | Measure-Object).Count

        return "SS" + ($NumberOfSecondaries + 1)
    }
}

function Get-ValidDomainNames {
    # Old List.. Some have netbios portions longer than 15 chars
    #$ValidDomainNames = [System.Collections.ArrayList]("adatum.com", "adventure-works.com", "alpineskihouse.com", "bellowscollege.com", "bestforyouorganics.com", "contoso.com", "contososuites.com",
    #   "consolidatedmessenger.com", "fabrikam.com", "fabrikamresidences.com", "firstupconsultants.com", "fourthcoffee.com", "graphicdesigninstitute.com", "humongousinsurance.com",
    #   "lamnahealthcare.com", "libertysdelightfulsinfulbakeryandcafe.com", "lucernepublishing.com", "margiestravel.com", "munsonspicklesandpreservesfarm.com", "nodpublishers.com",
    #   "northwindtraders.com", "proseware.com", "relecloud.com", "fineartschool.net", "southridgevideo.com", "tailspintoys.com", "tailwindtraders.com", "treyresearch.net", "thephone-company.com",
    #  "vanarsdelltd.com", "wideworldimporters.com", "wingtiptoys.com", "woodgrovebank.com", "techpreview.com" )

    #Trimmed list, only showing domains with 15 chars or less in netbios portion
    $ValidDomainNames = @{"adatum.com" = "ADA-" ; "adventure-works.com" = "ADV-" ; "alpineskihouse.com" = "ALP-" ; "bellowscollege.com" = "BLC-" ; "contoso.com" = "CON-" ; "contososuites.com" = "COS-" ;
        "fabrikam.com" = "FAB-" ; "fourthcoffee.com" = "FOR-" ;
        "lamnahealthcare.com" = "LAM-"  ; "margiestravel.com" = "MGT-" ; "nodpublishers.com" = "NOD-" ;
        "proseware.com" = "PRO-" ; "relecloud.com" = "REL-" ; "fineartschool.net" = "FAS-" ; "southridgevideo.com" = "SRV-" ; "tailspintoys.com" = "TST-" ; "tailwindtraders.com" = "TWT-" ; "treyresearch.net" = "TRY-";
        "vanarsdelltd.com" = "VAN-" ; "wingtiptoys.com" = "WTT-" ; "woodgrovebank.com" = "WGB-" #; "techpreview.com" = "CTP-" #techpreview.com is reserved for tech preview CM Installs
    }
    foreach ($domain in (Get-DomainList)) {
        $ValidDomainNames.Remove($domain.ToLowerInvariant())
    }

    $usedPrefixes = Get-List -Type UniquePrefix
    $ValidDomainNamesClone = $ValidDomainNames.Clone()
    foreach ($dname in $ValidDomainNamesClone.Keys) {
        foreach ($usedPrefix in $usedPrefixes) {
            if ($usedPrefix -and $ValidDomainNames[$dname]) {
                if ($ValidDomainNames[$dname].ToLowerInvariant() -eq $usedPrefix.ToLowerInvariant()) {
                    Write-Verbose ("Removing $dname")
                    $ValidDomainNames.Remove($dname)
                }
            }
        }
    }
    return $ValidDomainNames
}


function get-PrefixForDomain {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Domain Name")]
        [String] $Domain
    )

    $existingDomains = get-list -Type UniqueDomain
    if ($existingDomains -contains $Domain) {
        $existingPrefix = (Get-List -type VM -DomainName $domain | Where-Object { $_.Role -eq "DC" }).Prefix

        if (-not [string]::IsNullOrWhiteSpace($existingPrefix)) {
            return $existingPrefix
        }
    }
    $ValidDomainNames = Get-ValidDomainNames
    $prefix = $($ValidDomainNames[$domain])
    if ([String]::IsNullOrWhiteSpace($prefix)) {
        $prefix = ($domain.ToUpper().SubString(0, 3) + "-") -replace "\.", ""
    }
    if ([string]::IsNullOrWhiteSpace($prefix)) {
        $prefix = "NULL-"
    }
    return $prefix

}


function select-timezone {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, HelpMessage = "Config to modify")]
        [Object] $ConfigToCheck = $global:config
    )

    $commonTimeZones = @()
    $commonTimeZones += $((Get-TimeZone).Id)
    $commonTimeZones += "Pacific Standard Time"
    $commonTimeZones += "Central Standard Time"
    $commonTimeZones += "Eastern Standard Time"
    $commonTimeZones += "Mountain Standard Time"
    $commonTimeZones += "UTC"
    $commonTimeZones += "Central Europe Standard Time"
    $commonTimeZones += "China Standard Time"
    $commonTimeZones += "Tokyo Standard Time"
    $commonTimeZones += "India Standard Time"
    $commonTimeZones += "Russian Standard Time"

    $commonTimeZones = $commonTimeZones | Select-Object -Unique

    $timezone = Get-Menu -Prompt "Select Timezone" -OptionArray $commonTimeZones -CurrentValue $($ConfigToCheck.vmOptions.timezone) -additionalOptions @{"F" = "Display Full List" }
    if ($timezone -eq "F") {
        $timezone = Get-Menu -Prompt "Select Timezone" -OptionArray $((Get-TimeZone -ListAvailable).Id) -CurrentValue $($ConfigToCheck.vmOptions.timezone)
    }
    return $timezone
}
function select-NewDomainName {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, HelpMessage = "Config to modify")]
        [Object] $ConfigToCheck = $global:config
    )
    if ($ConfigToCheck.virtualMachines.role -contains "DC") {
        while ($true) {
            $ValidDomainNames = Get-ValidDomainNames

            $domain = $null
            $customOptions = @{ "C" = "Custom Domain" }

            while (-not $domain) {
                $domain = Get-Menu -Prompt "Select Domain" -OptionArray $($ValidDomainNames.Keys | Sort-Object { $_.length }) -additionalOptions $customOptions -CurrentValue ((Get-ValidDomainNames).Keys | sort-object { $_.Length } | Select-Object -first 1) -Test:$false
                if ($domain.ToLowerInvariant() -eq "c") {
                    $domain = Read-Host2 -Prompt "Enter Custom Domain Name:"
                }
                if ($domain.Length -lt 3) {
                    $domain = $null
                }
            }
            if ((get-list -Type UniqueDomain) -contains $domain.ToLowerInvariant()) {
                Write-Host
                Write-Host -ForegroundColor Red "Domain is already in use. Please use the Expand option to expand the domain"
                continue
            }
            return $domain
        }
    }
    else {
        $existingDomains = @()
        $existingDomains += get-list -Type UniqueDomain
        if ($existingDomains.count -eq 0) {
            Write-Host
            Write-Host "No DC configured, and no existing domains found. Please Ctrl-C to start over and create a new domain"
            return
        }
        $domain = $null
        while (-not $domain) {
            $domain = Get-Menu -Prompt "Select Domain" -OptionArray $existingDomains -CurrentValue $ConfigToCheck.vmoptions.domainName -test:$false
        }
        return $domain
    }
}



function Select-NewDomainConfig {

    $subnetlist = Get-ValidSubnets

    $valid = $false
    while ($valid -eq $false) {

        $customOptions = [ordered]@{ "1" = "CAS and Primary%gray%green"; "2" = "Primary Site only%gray%green"; "3" = "Tech Preview (NO CAS)%red%green" ; "4" = "No ConfigMgr%yellow%green"; }
        $response = $null
        while (-not $response) {
            Write-Host
            Write-Host -ForegroundColor Yellow "Tip: You can enable Configuration Manager High Availability by editing the properties of a CAS or Primary VM, and selecting ""H"""

            $response = Get-Menu -Prompt "Select ConfigMgr Options" -AdditionalOptions $customOptions
            if ([string]::IsNullOrWhiteSpace($response)) {
                return
            }
        }


        $templateDomain = "TEMPLATE2222.com"
        $newconfig = New-UserConfig -Domain $templateDomain -Subnet "10.234.241.0"
        $test = $false
        $version = $null
        switch ($response.ToLowerInvariant()) {
            "1" {
                Add-NewVMForRole -Role "DC" -Domain $templateDomain -ConfigToModify $newconfig -Quiet:$true -test:$test
                Add-NewVMForRole -Role "CAS" -Domain $templateDomain -ConfigToModify $newconfig -SiteCode "CS1" -Quiet:$true -test:$test
                Add-NewVMForRole -Role "DomainMember" -Domain $templateDomain -ConfigToModify $newconfig -OperatingSystem "Windows 11 Latest" -Quiet:$true -test:$test
                Add-NewVMForRole -Role "DomainMember" -Domain $templateDomain -ConfigToModify $newconfig -OperatingSystem "Windows 10 Latest (64-bit)" -Quiet:$true -test:$test
                $version = "current-branch"
            }

            "2" {
                Add-NewVMForRole -Role "DC" -Domain $templateDomain -ConfigToModify $newconfig -Quiet:$true -test:$test
                Add-NewVMForRole -Role "Primary" -Domain $templateDomain -ConfigToModify $newconfig -SiteCode "PS1" -Quiet:$true -test:$test
                Add-NewVMForRole -Role "DomainMember" -Domain $templateDomain -ConfigToModify $newconfig -OperatingSystem "Windows 11 Latest" -Quiet:$true -test:$test
                Add-NewVMForRole -Role "DomainMember" -Domain $templateDomain -ConfigToModify $newconfig -OperatingSystem "Windows 10 Latest (64-bit)" -Quiet:$true -test:$test
                $version = "current-branch"

            }
            "3" {
                Add-NewVMForRole -Role "DC" -Domain $templateDomain -ConfigToModify $newconfig -Quiet:$true -test:$test
                Add-NewVMForRole -Role "Primary" -Domain $templateDomain -ConfigToModify $newconfig -SiteCode "CTP" -Quiet:$true -test:$test
                Add-NewVMForRole -Role "DomainMember" -Domain $templateDomain -ConfigToModify $newconfig -OperatingSystem "Windows 11 Latest" -Quiet:$true -test:$test
                Add-NewVMForRole -Role "DomainMember" -Domain $templateDomain -ConfigToModify $newconfig -OperatingSystem "Windows 10 Latest (64-bit)" -Quiet:$true -test:$test
                $usedPrefixes = Get-List -Type UniquePrefix
                if ("CTP-" -notin $usedPrefixes) {
                    $prefix = "CTP-"
                    $domain = "techpreview.com"
                }
                $version = "tech-preview"
            }
            "4" {
                Add-NewVMForRole -Role "DC" -Domain $templateDomain -ConfigToModify $newconfig -Quiet:$true -test:$test
                Add-NewVMForRole -Role "DomainMember" -Domain $templateDomain -ConfigToModify $newconfig -OperatingSystem "Windows 11 Latest" -Quiet:$true -test:$test
                Add-NewVMForRole -Role "DomainMember" -Domain $templateDomain -ConfigToModify $newconfig -OperatingSystem "Windows 10 Latest (64-bit)" -Quiet:$true -test:$test
            }
        }
        $valid = Get-TestResult -Config $newConfig -SuccessOnWarning

        if ($valid) {
            $valid = $false
            while ($valid -eq $false) {
                if (-not $domain) {
                    $domain = select-NewDomainName -ConfigToCheck $newConfig
                }
                if (-not $prefix) {
                    $prefix = get-PrefixForDomain -Domain $domain
                }
                Write-Verbose "Prefix = $prefix"
                $newConfig.vmOptions.domainName = $domain
                $newConfig.vmOptions.prefix = $prefix
                if ($version) {
                    $newConfig.cmOptions.version = $version
                }
                $valid = Get-TestResult -Config $newConfig -SuccessOnWarning
                if (-not $valid) {
                    $domain = $null
                }
            }
        }

        if ($valid) {
            Show-SubnetNote

            $valid = $false
            while ($valid -eq $false) {
                $customOptions = @{ "C" = "Custom Subnet" }
                $network = $null
                while (-not $network) {
                    $network = Get-Menu -Prompt "Select Network" -OptionArray $subnetlist -additionalOptions $customOptions -CurrentValue ($subnetList | Select-Object -First 1)
                    if ($network.ToLowerInvariant() -eq "c") {
                        $network = Read-Host2 -Prompt "Enter Custom Subnet (eg 192.168.1.0):"
                    }
                }
                $newConfig.vmOptions.network = $network
                $valid = Get-TestResult -Config $newConfig -SuccessOnWarning
            }
        }
    }
    return $newConfig
}

# Gets the json files from the config\samples directory, and offers them up for selection.
# if 'M' is selected, shows the json files from the config directory.
function Select-Config {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Directory to look for .json files")]
        [string] $ConfigPath,
        # -NoMore switch will hide the [M] More options when we go into the submenu
        [Parameter(Mandatory = $false, HelpMessage = "will hide the [M] More options when we go into the submenu")]
        [switch] $NoMore
    )

    if (-not (Test-Path $ConfigPath)) {
        write-log "No files found in $configPath"
        return
    }
    $files = @()
    $files += Get-ChildItem $ConfigPath\*.json -Include "Standalone.json", "Hierarchy.json" | Sort-Object -Property Name -Descending
    $files += Get-ChildItem $ConfigPath\*.json -Include "TechPreview.json"
    $files += Get-ChildItem $ConfigPath\*.json -Include "NoConfigMgr.json"
    $files += Get-ChildItem $ConfigPath\*.json -Include "AddToExisting.json"
    $files += Get-ChildItem $ConfigPath\*.json -Exclude "_*", "Hierarchy.json", "Standalone.json", "AddToExisting.json", "TechPreview.json", "NoConfigMgr.json" | Sort-Object -Descending -Property CreationTime
    write-host $ConfigPath
    if ($ConfigPath.EndsWith("tests")) {
        $files = $files | sort-Object -Property Name
    }
    $responseValid = $false

    while ($responseValid -eq $false) {
        $i = 0
        foreach ($file in $files) {
            $i = $i + 1
            Write-Option $i $($file.Name)
        }
        if (-Not $NoMore.IsPresent) {
            Write-Option "M" "Show More (Custom and Previous config files)" -color DarkGreen -Color2 Green
            Write-Option "E" "Expand existing network" -color DarkGreen -Color2 Green

        }

        Write-Host
        Write-Verbose "3 Select-Config"
        $response = Read-Host2 -Prompt "Which config do you want to load"
        try {
            if ([int]$response -is [int]) {
                if ([int]$response -le [int]$i -and [int]$response -gt 0 ) {
                    $responseValid = $true
                }
            }
        }
        catch {}
        if (-Not $NoMore.IsPresent) {
            if ($response.ToLowerInvariant() -eq "m") {
                $configSelected = Select-Config $configDir -NoMore
                if (-not ($null -eq $configSelected)) {
                    return $configSelected
                }
                $i = 0
                foreach ($file in $files) {
                    $i = $i + 1
                    write-Host "[$i] $($file.Name)"
                }
                if (-Not $NoMore.IsPresent) {
                    Write-Option "M" "Show More (Custom and Previous config files)" -color DarkGreen -Color2 Green
                    Write-Option "E" "Expand existing network" -color DarkGreen -Color2 Green
                }
            }
            if ($response.ToLowerInvariant() -eq "e") {
                $newConfig = Show-ExistingNetwork
                if ($newConfig) {
                    return $newConfig
                }
            }
        }
        else {
            if ($response -eq "") {
                return $null
            }
        }
    }
    $Global:configfile = $files[[int]$response - 1]
    $configSelected = Get-Content $Global:configfile -Force | ConvertFrom-Json
    if ($null -ne $configSelected.vmOptions.domainAdminName) {
        if ($null -eq ($configSelected.vmOptions.adminName)) {
            $configSelected.vmOptions | Add-Member -MemberType NoteProperty -Name "adminName" -Value $configSelected.vmOptions.domainAdminName
        }
        $configSelected.vmOptions.PsObject.properties.Remove('domainAdminName')
    }
    if ($null -ne $configSelected.cmOptions.installDPMPRoles) {
        $configSelected.cmOptions.PsObject.properties.Remove('installDPMPRoles')
        foreach ($vm in $configSelected.virtualMachines) {
            if ($vm.Role -eq "DPMP") {
                $vm  | Add-Member -MemberType NoteProperty -Name "installDP" -Value $true -Force
                $vm  | Add-Member -MemberType NoteProperty -Name "installMP" -Value $true -Force
            }
        }
    }

    return $configSelected
}

Function Get-DomainStatsLine {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Domain Name")]
        [string]$DomainName
    )
    $stats = ""
    $ListCache = Get-List -Type VM -Domain $DomainName
    $ExistingCasCount = ($ListCache | Where-Object { $_.Role -eq "CAS" } | Measure-Object).Count
    $ExistingPriCount = ($ListCache | Where-Object { $_.Role -eq "Primary" } | Measure-Object).Count
    $ExistingSecCount = ($ListCache | Where-Object { $_.Role -eq "Secondary" } | Measure-Object).Count
    $ExistingDPMPCount = ($ListCache | Where-Object { $_.Role -eq "DPMP" } | Measure-Object).Count
    $ExistingSQLCount = ($ListCache | Where-Object { $_.Role -eq "DomainMember" -and $null -ne $_.SqlVersion } | Measure-Object).Count
    $ExistingSubnetCount = ($ListCache | Select-Object -Property Subnet -unique | measure-object).Count
    $TotalVMs = ($ListCache | Measure-Object).Count
    $TotalRunningVMs = ($ListCache | Where-Object { $_.State -ne "Off" } | Measure-Object).Count
    $TotalMem = ($ListCache | Measure-Object -Sum MemoryGB).Sum
    $TotalMaxMem = ($ListCache | Measure-Object -Sum MemoryStartupGB).Sum
    $TotalDiskUsed = ($ListCache | Measure-Object -Sum DiskUsedGB).Sum
    $stats += "[$TotalRunningVMs/$TotalVMs Running VMs, Mem: $($TotalMem.ToString().PadLeft(2," "))GB/$($TotalMaxMem)GB Disk: $([math]::Round($TotalDiskUsed,2))GB]"
    if ($ExistingCasCount -gt 0) {
        $stats += "[CAS VMs: $ExistingCasCount] "
    }
    if ($ExistingPriCount -gt 0) {
        $stats += "[Primary VMs: $ExistingPriCount] "
    }
    if ($ExistingSecCount -gt 0) {
        $stats += "[Secondary VMs: $ExistingSecCount] "
    }
    if ($ExistingSQLCount -gt 0) {
        $stats += "[SQL VMs: $ExistingSQLCount] "
    }
    if ($ExistingDPMPCount -gt 0) {
        $stats += "[DPMP Vms: $ExistingDPMPCount] "
    }

    if ([string]::IsNullOrWhiteSpace($stats)) {
        $stats = "[No ConfigMgr Roles installed] "
    }

    if ($ExistingSubnetCount -gt 0) {
        $stats += "[Number of Networks: $ExistingSubnetCount] "
    }
    return $stats
}



function Show-ExistingNetwork {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUserDeclaredVarsMoreThanAssignments', '', Scope = 'Function')]

    $domainList = @()

    foreach ($item in (Get-DomainList)) {
        $stats = Get-DomainStatsLine -DomainName $item

        $domainList += "$($item.PadRight(22," ")) $stats"
    }

    if ($domainList.Count -eq 0) {
        Write-Host
        Write-Host -ForegroundColor Red "No Domains found. Please deploy a new domain"

        return
    }

    while ($true) {
        $domainExpanded = Get-Menu -Prompt "Select existing domain" -OptionArray $domainList
        if ([string]::isnullorwhitespace($domainExpanded)) {
            return $null
        }
        $domain = ($domainExpanded -Split " ")[0]

        get-list -Type VM -DomainName $domain | Format-Table -Property vmname, Role, SiteCode, DeployedOS, MemoryStartupGB, @{Label = "DiskUsedGB"; Expression = { [Math]::Round($_.DiskUsedGB, 2) } }, State, Domain, Subnet, SQLVersion | Out-Host

        $response = Read-Host2 -Prompt "Add new VMs to this domain? (Y/n)" -HideHelp
        if (-not [String]::IsNullOrWhiteSpace($response)) {
            if ($response.ToLowerInvariant() -eq "n" -or $response.ToLowerInvariant() -eq "no") {
                continue
            }
            else {
                break
            }
        }
        else { break }

    }

    $TotalStoppedVMs = (Get-List -Type VM -Domain $domain | Where-Object { $_.State -ne "Running" -and ($_.Role -eq "CAS" -or $_.Role -eq "Primary" -or $_.Role -eq "DC") } | Measure-Object).Count
    if ($TotalStoppedVMs -gt 0) {
        $response = Read-Host2 -Prompt "$TotalStoppedVMs Critical VM's in this domain are not running. Do you wish to start them now? (Y/n)" -HideHelp
        if ($response.ToLowerInvariant() -eq "n" -or $response.ToLowerInvariant() -eq "no") {
        }
        else {
            Select-StartDomain -domain $domain -response "C"
        }

    }
    [string]$role = Select-RolesForExisting


    if ($role -eq "H") {
        $role = "PassiveSite"
    }


    $parentSiteCode = Get-ParentSiteCodeMenu -role $role -CurrentValue $null -Domain $domain
    #if ($role -eq "Primary") {
    #    $ExistingCasCount = (Get-List -Type VM -Domain $domain | Where-Object { $_.Role -eq "CAS" } | Measure-Object).Count
    #    if ($ExistingCasCount -gt 0) {
    #
    #        $existingSiteCodes = @()
    #        $existingSiteCodes += (Get-List -Type VM -Domain $domain | Where-Object { $_.Role -eq "CAS" }).SiteCode
    #        #$existingSiteCodes += ($global:config.virtualMachines | Where-Object { $_.Role -eq "CAS" } | Select-Object -First 1).SiteCode
    #
    #        $additionalOptions = @{ "X" = "No Parent - Standalone Primary" }
    #        $result = Get-Menu -Prompt "Select CAS sitecode to connect Primary to:" -OptionArray $existingSiteCodes -CurrentValue $value -additionalOptions $additionalOptions -Test $false
    #        if ($result.ToLowerInvariant() -eq "x") {
    #            $parentSiteCode = $null
    #        }
    #        else {
    #            $parentSiteCode = $result
    #        }
    #        Get-TestResult -SuccessOnError | out-null
    #    }
    #}
    #
    #if ($role -eq "Secondary") {
    #
    #    $priSiteCodes = Get-ValidPRISiteCodes -config $global:config
    #    if ($priSiteCodes -gt 0) {
    #        while (-not $result) {
    #            $result = Get-Menu -Prompt "Select Primary sitecode to connect Secondary to" -OptionArray $priSiteCodes -CurrentValue $value  -Test $false
    #        }
    #        $parentsiteCode = $result
    #        Get-TestResult -SuccessOnError | out-null
    #    }
    #    else {
    #        write-host "No valid primaries found to attach secondary to"
    #        return
    #    }
    #}
    #
    if ($role -eq "Secondary") {
        if (-not $parentSiteCode) {
            return
        }
    }
    if ($role -eq "PassiveSite") {
        $existingPassive = Get-List -Type VM -Domain $domain | Where-Object { $_.Role -eq "PassiveSite" }
        $existingSS = Get-List -Type VM -Domain $domain | Where-Object { $_.Role -eq "CAS" -or $_.Role -eq "Primary" }

        $PossibleSS = @()
        foreach ($item in $existingSS) {
            if ($existingPassive.SiteCode -contains $item.Sitecode) {
                continue
            }
            $PossibleSS += $item
        }

        if ($PossibleSS.Count -eq 0) {
            Write-Host
            Write-Host "No siteservers found that are elegible for HA"
            return
        }
        $result = Get-Menu -Prompt "Select sitecode to expand to HA" -OptionArray $PossibleSS.Sitecode -Test $false
        if ([string]::IsNullOrWhiteSpace($result)) {
            return
        }
        $SiteCode = $result
    }

    if ($role -eq "DPMP") {
        $SiteCode = Get-SiteCodeForDPMP -Domain $domain
        #write-host "Get-SiteCodeForDPMP return $SiteCode"
    }

    [string]$subnet = (Get-List -type VM -DomainName $domain | Where-Object { $_.Role -eq "DC" } | Select-Object -First 1).Subnet
    if ($role -ne "InternetClient" -and $role -ne "AADClient" -and $role -ne "PassiveSite") {
        $subnet = Select-ExistingSubnets -Domain $domain -Role $role -SiteCode $SiteCode
        Write-verbose "[Show-ExistingNetwork] Subnet returned from Select-ExistingSubnets '$subnet'"
        if ([string]::IsNullOrWhiteSpace($subnet)) {
            return $null
        }
    }

    Write-verbose "[Show-ExistingNetwork] Calling Get-ExistingConfig '$domain' '$subnet' '$role' '$SiteCode'"
    $newConfig = Get-ExistingConfig -Domain $domain -Subnet $subnet -role $role -parentSiteCode $parentSiteCode -SiteCode $Sitecode
    return $newConfig
}
function Select-RolesForExistingList {
    $existingRoles = $Common.Supported.RolesForExisting | Where-Object { $_ -ne "PassiveSite" }
    return $existingRoles
}

function Select-RolesForNewList {
    $Roles = $Common.Supported.Roles | Where-Object { $_ -ne "PassiveSite" }
    return $Roles
}

function Format-Roles {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Roles Array")]
        [object]$Roles
    )

    $newRoles = @()

    $padding = 22
    foreach ($role in $Roles) {
        switch ($role) {
            "DC" { $newRoles += "$($role.PadRight($padding))`t[New Domain Controller.. Only 1 allowed per domain!]" }
            "CAS" { $newRoles += "$($role.PadRight($padding))`t[New CAS.. Only 1 allowed per subnet!]" }
            "CAS and Primary" { $newRoles += "$($role.PadRight($padding))`t[New CAS and Primary Site]" }
            "Primary" { $newRoles += "$($role.PadRight($padding))`t[New Primary site (Standalone or join a CAS)]" }
            "Secondary" { $newRoles += "$($role.PadRight($padding))`t[New Secondary site (Attach to Primary)]" }
            "FileServer" { $newRoles += "$($role.PadRight($padding))`t[New File Server]" }
            "DPMP" { $newRoles += "$($role.PadRight($padding))`t[New DP/MP for an existing Primary Site]" }
            "DomainMember" { $newRoles += "$($role.PadRight($padding))`t[New VM joined to the domain]" }
            "DomainMember (Server)" { $newRoles += "$($role.PadRight($padding))`t[New VM with Server OS joined to the domain]" }
            "DomainMember (Client)" { $newRoles += "$($role.PadRight($padding))`t[New VM with Client OS joined to the domain]" }
            "WorkgroupMember" { $newRoles += "$($role.PadRight($padding))`t[New VM in workgroup with Internet Access]" }
            "InternetClient" { $newRoles += "$($role.PadRight($padding))`t[New VM in workgroup with Internet Access, isolated from the domain]" }
            "AADClient" { $newRoles += "$($role.PadRight($padding))`t[New VM that boots to OOBE, allowing AAD join from OOBE]" }
            "OSDClient" { $newRoles += "$($role.PadRight($padding))`t[New bare VM without any OS]" }
            default { $newRoles += $role }
        }
    }

    return $newRoles

}

function Select-RolesForExisting {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, HelpMessage = "Enhance Roles")]
        [bool]$enhance = $true
    )
    $existing = get-list -type vm -domain $global:config.vmOptions.domainName | Where-Object { $_.Role -eq "DC" }
    if ($existing) {

        $existingRoles = Select-RolesForExistingList
        $ha_Text = "Enable High Availability (HA) on an Existing Site Server"
    }
    else {
        $existingRoles = Select-RolesForNewList
        $ha_Text = "Enable High Availability (HA) on a Site Server"
    }

    $existingRoles2 = @()
    $CurrentValue = $null
    if ($enhance) {
        $CurrentValue = "DomainMember"
        foreach ($item in $existingRoles) {

            switch ($item) {
                "CAS" { $existingRoles2 += "CAS and Primary" }
                "DomainMember" {
                    $existingRoles2 += "DomainMember (Server)"
                    $existingRoles2 += "DomainMember (Client)"
                }
                "PassiveSite" {}
                Default { $existingRoles2 += $item }
            }
        }
    }
    else {
        $existingRoles2 = $existingRoles
    }
    $existingRoles2 = Format-Roles $existingRoles2

    $OptionArray = @{ "H" = $ha_Text }

    $role = Get-Menu -Prompt "Select Role to Add" -OptionArray $($existingRoles2) -CurrentValue $CurrentValue -additionalOptions $OptionArray

    $role = $role.Split("[")[0].Trim()
    if ($role -eq "CAS and Primary") {
        $role = "CAS"
    }

    return $role

}

function Select-RolesForNew {
    [System.Collections.ArrayList]$existingRoles = [System.Collections.ArrayList]($Common.Supported.Roles)
    if ($global:config.VirtualMachines.role -contains "DC") {
        $existingRoles.Remove("DC")
    }
    if ($global:config.VirtualMachines.role -contains "Primary") {
        $existingRoles.Remove("Primary")
    }
    if ($global:config.VirtualMachines.role -contains "Secondary") {
        $existingRoles.Remove("Secondary")
    }
    if ($global:config.VirtualMachines.role -contains "CAS") {
        $existingRoles.Remove("CAS")
    }
    # if ($global:config.VirtualMachines.role -contains "DPMP") {
    #     $existingRoles.Remove("DPMP")
    # }
    $existingRoles.Remove("PassiveSite")
    $role = Get-Menu -Prompt "Select Role to Add" -OptionArray $($existingRoles) -CurrentValue "DomainMember"
    return $role
}

function Select-OSForNew {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, HelpMessage = "Role")]
        [String] $Role
    )

    $defaultValue = "Server 2022"
    if (($Role -eq "DomainMember") -or ($null -eq $Role) -or ($Role -eq "WorkgroupMember") -or ($Role -eq "InternetClient") ) {
        $OSList = $Common.Supported.OperatingSystems
    }
    else {
        $OSList = $Common.Supported.OperatingSystems | Where-Object { $_ -like "*Server*" }
    }

    if ($Role -eq "InternetClient") {
        $defaultValue = "Windows 10 Latest (64-bit)"
    }
    if ($Role -eq "AADClient") {
        $OSList = $Common.Supported.OperatingSystems | Where-Object { -not ( $_ -like "*Server*" ) }
        $defaultValue = "Windows 10 Latest (64-bit)"
    }
    if ($role -eq "OSDClient") {
        return $null
    }

    if ($role -eq "Secondary") {
        return $defaultValue
    }
    $role = Get-Menu -Prompt "Select OS" -OptionArray $($OSList) -CurrentValue $defaultValue
    return $role
}

function Select-Subnet {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, HelpMessage = "Config")]
        [object] $configToCheck = $global:config,
        [Parameter(Mandatory = $false, HelpMessage = "CurrentNetworkIsValid")]
        [bool] $CurrentNetworkIsValid = $true
    )
    Show-SubnetNote

    if ($configToCheck.virtualMachines.role -contains "DC") {
        $subnetlist = Get-ValidSubnets
        $customOptions = @{ "C" = "Custom Subnet" }
        $network = $null
        if ($CurrentNetworkIsValid) {
            $current = $configToCheck.vmOptions.network
        }
        else{
            $subnetList = $subnetList | where-object {$_ -ne $configToCheck.vmOptions.network}
            $current =  $subnetlist[0]
        }
        while (-not $network) {
            $network = Get-Menu -Prompt "Select Network" -OptionArray $subnetlist -additionalOptions $customOptions -Test:$false -CurrentValue $current
            if ($network.ToLowerInvariant() -eq "c") {
                $network = Read-Host2 -Prompt "Enter Custom Subnet (eg 192.168.1.0):"
            }
        }
        $response = [string]$network
        return $response
    }
    else {
        $domain = $configToCheck.vmOptions.DomainName
        return Select-ExistingSubnets -Domain $domain -ConfigToCheck $configToCheck
    }



}

function Show-SubnetNote {
    $noteColor = "cyan"
    $textColor = "gray"
    $highlightColor = "darkyellow"
    Write-Host
    write-host -ForegroundColor $noteColor "Note: " -NoNewline
    write-host -foregroundcolor $textColor "You can only have 1 " -NoNewLine
    write-host -ForegroundColor $highlightColor "Primary" -NoNewLine
    write-host -ForegroundColor $textColor " or " -NoNewline
    write-host -ForegroundColor $highlightColor "Secondary" -NoNewLine
    write-host -ForegroundColor $textColor " server per " -NoNewline
    write-host -ForegroundColor $highlightColor "subnet" -NoNewline
    write-host -ForegroundColor $textColor "."
    write-host -ForegroundColor $textColor "   MemLabs automatically configures this subnet as a Boundary Group for the specified SiteCode."
    write-host -ForegroundColor $textColor "   This limitation exists to prevent overlapping Boundary Groups."
    write-host -ForegroundColor $textColor "   Subnets without a siteserver do NOT automatically get added to any boundary groups."

}
function Select-ExistingSubnets {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Domain Name")]
        [String] $Domain,
        [Parameter(Mandatory = $false, HelpMessage = "Role")]
        [String] $Role,
        [Parameter(Mandatory = $false, HelpMessage = "SiteCode")]
        [String] $SiteCode,
        [Parameter(Mandatory = $false, HelpMessage = "config")]
        [object] $ConfigToCheck
    )

    $valid = $false
    if ($ConfigToCheck) {
        $Role = "DomainMember"
        if ($configToCheck.virtualMachines.role -contains "Primary") {
            $Role = "Primary"
        }
        if ($configToCheck.virtualMachines.role -contains "CAS") {
            $Role = "CAS"
        }
        if ($configToCheck.virtualMachines.role -contains "Secondary") {
            $Role = "Secondary"
        }
    }
    while ($valid -eq $false) {

        $customOptions = @{ "N" = "add New Subnet to domain" }
        $subnetList = @()
        $subnetList += Get-SubnetList -DomainName $Domain | Select-Object -Expand Subnet | Sort-Object | Get-Unique

        $subnetListNew = @()
        if ($Role -eq "Primary" -or $Role -eq "CAS" -or $Role -eq "Secondary") {
            foreach ($subnet in $subnetList) {
                # If a subnet has a Primary or a CAS in it.. we can not add either.
                $existingRolePri = Get-ExistingForSubnet -Subnet $subnet -Role Primary
                $existingRoleCAS = Get-ExistingForSubnet -Subnet $subnet -Role CAS
                $existingRoleSec = Get-ExistingForSubnet -Subnet $subnet -Role Secondary
                if ($null -eq $existingRolePri -and $null -eq $existingRoleCAS -and $null -eq $existingRoleSec) {
                    $subnetListNew += $subnet
                }
            }
        }
        else {
            $subnetListNew = $subnetList
        }

        $subnetListModified = @()
        foreach ($sb in $subnetListNew) {
            if ($sb -eq "Internet" -or ($sb -eq "cluster")) {
                continue
            }
            $SiteCodes = get-list -Type VM -Domain $domain | Where-Object { $null -ne $_.SiteCode -and ($_.Role -eq "Primary" -or $_.Role -eq "CAS" -or $_.Role -eq "Secondary") } | Group-Object -Property Subnet | Select-Object Name, @{l = "SiteCode"; e = { $_.Group.SiteCode -join "," } } | Where-Object { $_.Name -eq $sb }  | Select-Object -expand SiteCode
            if ([string]::IsNullOrWhiteSpace($SiteCodes)) {
                $subnetListModified += "$sb"
            }
            else {
                $subnetListModified += "$sb ($SiteCodes)"
            }
        }
        Show-SubnetNote

        while ($true) {
            [string]$response = $null

            $CurrentValue = $null
            if ($configToCheck) {
                $Currentvalue = $configToCheck.vmOptions.network
            }
            if ($subnetListModified.Length -eq 0) {
                Write-Host
                Write-Host -ForegroundColor Yellow "No valid subnets for the selected role exists in the domain. Please create a new subnet"
                $response = "n"
            }
            else {
                $response = Get-Menu -Prompt "Select existing subnet" -OptionArray $subnetListModified -AdditionalOptions $customOptions -test:$false -CurrentValue $CurrentValue
            }
            write-Verbose "[Select-ExistingSubnets] Get-menu response $response"
            if ([string]::IsNullOrWhiteSpace($response)) {
                Write-Verbose "[Select-ExistingSubnets] Subnet response = null"
                continue
            }
            write-Verbose "response $response"
            $response = $response -Split " " | Select-Object -First 1
            write-Verbose "Sanitized response '$response'"

            if ($response.ToLowerInvariant() -eq "n") {

                $subnetlist = Get-ValidSubnets
                $customOptions = @{ "C" = "Custom Subnet" }
                $network = $null
                while (-not $network) {
                    $network = Get-Menu -Prompt "Select New Network" -OptionArray $subnetlist -additionalOptions $customOptions -Test:$false -CurrentValue $($subnetList | Select-Object -First 1)
                    if ($network.ToLowerInvariant() -eq "c") {
                        $network = Read-Host2 -Prompt "Enter Custom Subnet (eg 192.168.1.0):"
                    }
                }
                $response = [string]$network
                break

            }
            else {
                write-Verbose "Sanitized response was not 'N' it was '$response'"
                break
            }
        }
        $valid = Get-TestResult -Config (Get-ExistingConfig -Domain $Domain -Subnet $response -Role $Role -SiteCode $sitecode -test:$true) -SuccessOnWarning
    }
    Write-Verbose "[Select-ExistingSubnets] Subnet response = $response"
    return [string]$response
}

function New-UserConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Domain Name")]
        [String] $Domain,
        [Parameter(Mandatory = $true, HelpMessage = "Subnet Name")]
        [string] $Subnet
    )

    $adminUser = (Get-List -Type vm -DomainName $Domain | Where-Object { $_.Role -eq "DC" }).adminName

    if ([string]::IsNullOrWhiteSpace($adminUser)) {
        $adminUser = "admin"
    }
    $prefix = get-PrefixForDomain -Domain $Domain
    if ([string]::IsNullOrWhiteSpace($prefix)) {
        $prefix = "NULL-"
    }
    $vmOptions = [PSCustomObject]@{
        prefix     = $prefix
        basePath   = "E:\VirtualMachines"
        domainName = $Domain
        adminName  = $adminUser
        network    = $Subnet
    }
    Write-Verbose "[Get-ExistingConfig] vmOptions: $vmOptions"
    $configGenerated = $null
    $configGenerated = [PSCustomObject]@{
        #cmOptions       = $newCmOptions
        vmOptions       = $vmOptions
        virtualMachines = $()
    }
    return $configGenerated
}
function Get-ExistingConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Domain Name")]
        [String] $Domain,
        [Parameter(Mandatory = $true, HelpMessage = "Subnet Name")]
        [string] $Subnet,
        [Parameter(Mandatory = $true, HelpMessage = "Role")]
        [String] $Role,
        [Parameter(Mandatory = $false, HelpMessage = "Parent Site code, if we are deploying a primary in a Hierarchy")]
        [string] $parentSiteCode = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Site code, if we are deploying PassiveSite")]
        [string] $SiteCode = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Site code, if we are deploying PassiveSite")]
        [bool] $test = $false

    )

    Write-Verbose "[Get-ExistingConfig] Generating $Domain $Subnet $role $parentSiteCode"

    $configGenerated = New-UserConfig -Domain $Domain -Subnet $Subnet

    Write-Verbose "[Get-ExistingConfig] Config: $configGenerated $($configGenerated.vmOptions.domainName)"
    Add-NewVMForRole -Role $Role -Domain $Domain -ConfigToModify $configGenerated -parentSiteCode $parentSiteCode -SiteCode $SiteCode -Quiet:$true -test:$test
    Write-Verbose "[Get-ExistingConfig] Config: $configGenerated"
    return $configGenerated
}

# Replacement for Read-Host that offers a colorized prompt
function Read-Host2 {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Prompt to display")]
        [string] $prompt,
        [Parameter(Mandatory = $false, HelpMessage = "shows current value in []")]
        [string] $currentValue,
        [Parameter(Mandatory = $false, HelpMessage = "Dont display the help before the prompt")]
        [switch] $HideHelp
    )
    if (-not $HideHelp.IsPresent) {
        write-help
    }
    Write-Host -ForegroundColor Cyan $prompt -NoNewline
    if (-not [String]::IsNullOrWhiteSpace($currentValue)) {
        Write-Host " [" -NoNewline
        Write-Host -ForegroundColor yellow $currentValue -NoNewline
        Write-Host "]" -NoNewline
    }
    Write-Host " : " -NoNewline
    $response = Read-Host
    return $response
}

# Offers a menu for any array passed in.
# This is used for Sql Versions, Roles, Etc
function Get-Menu {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Prompt to display")]
        [string] $prompt,
        [Parameter(Mandatory = $false, HelpMessage = "Array of objects to display a menu from")]
        [object] $OptionArray,
        [Parameter(Mandatory = $false, HelpMessage = "The default if enter is pressed")]
        [string] $CurrentValue,
        [Parameter(Mandatory = $false, HelpMessage = "Additional Menu options, in dictionary format.. X = Exit")]
        [object] $additionalOptions = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Pre Menu options, in dictionary format.. X = Exit")]
        [object] $preOptions = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Run a configuration test. Default True")]
        [bool] $Test = $true,
        [Parameter(Mandatory = $false, HelpMessage = "Supress newline")]
        [switch] $NoNewLine
    )

    if (!$NoNewLine) {
        write-Host
        Write-Verbose "4 Get-Menu"
    }

    if ($null -ne $preOptions) {
        foreach ($item in $preOptions.keys) {
            $value = $preOptions."$($item)"
            $color1 = "DarkGreen"
            $color2 = "Green"

            #Write-Host -ForegroundColor DarkGreen [$_] $value
            if (-not [String]::IsNullOrWhiteSpace($item)) {
                $TextValue = $value -split "%"

                if (-not [string]::IsNullOrWhiteSpace($TextValue[1])) {
                    $color1 = $TextValue[1]
                }
                if (-not [string]::IsNullOrWhiteSpace($TextValue[2])) {
                    $color2 = $TextValue[2]
                }
                if ($item.StartsWith("*")) {
                    write-host -ForeGroundColor $color1 $TextValue[0]
                    continue
                }
                Write-Option $item $TextValue[0] -color $color1 -Color2 $color2
            }
        }
    }


    $i = 0

    foreach ($option in $OptionArray) {
        $i = $i + 1
        if (-not [String]::IsNullOrWhiteSpace($option)) {
            Write-Option $i $option
        }
    }

    if ($null -ne $additionalOptions) {
        foreach ($item in $additionalOptions.keys) {
            $value = $additionalOptions."$($item)"

            $color1 = "DarkGreen"
            $color2 = "Green"

            #Write-Host -ForegroundColor DarkGreen [$_] $value
            if (-not [String]::IsNullOrWhiteSpace($item)) {
                $TextValue = $value -split "%"

                if (-not [string]::IsNullOrWhiteSpace($TextValue[1])) {
                    $color1 = $TextValue[1]
                }
                if (-not [string]::IsNullOrWhiteSpace($TextValue[2])) {
                    $color2 = $TextValue[2]
                }
                if ($item.StartsWith("*")) {
                    write-host -ForeGroundColor $color1 $TextValue[0]
                    continue
                }
                Write-Option $item $TextValue[0] -color $color1 -Color2 $color2
            }
        }
    }
    $totalOptions = $preOptions + $additionalOptions

    $response = get-ValidResponse -Prompt $Prompt -max $i -CurrentValue $CurrentValue -AdditionalOptions $totalOptions -TestBeforeReturn:$Test

    if (-not [String]::IsNullOrWhiteSpace($response)) {
        $i = 0
        foreach ($option in $OptionArray) {
            $i = $i + 1
            if ($i -eq $response) {
                Write-Verbose "[Get-Menu] Returned (O) '$option'"
                return $option
            }
        }
        Write-Verbose "[Get-Menu] Returned (R) '$response'"
        return $response
    }
    else {
        Write-Verbose "[Get-Menu] Returned (CV) '$CurrentValue'"
        return $CurrentValue
    }
}

#Checks if the response from the menu was valid.
# Prompt is the prompt to display
# Max is the max int allowed [1], [2], [3], etc
# The current value of the option
# additionalOptions , like [N] New VM, [S] Add SQL, either as a single letter in a string, or keys in a dictionary.
function get-ValidResponse {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Prompt to display")]
        [string] $prompt,
        [Parameter(Mandatory = $true, HelpMessage = "Max # to be valid.  If your Menu is 1-5, 5 is the max. Higher numbers will fail")]
        [int] $max,
        [Parameter(Mandatory = $false, HelpMessage = "Current value will be returned if enter is pressed")]
        [string] $currentValue,
        [Parameter(Mandatory = $false, HelpMessage = "Extra Valid entries that allow escape.. EG X = Exit")]
        [object] $additionalOptions,
        [switch]
        $AnyString,
        [Parameter(Mandatory = $false, HelpMessage = "Run a test-Configuration before exiting")]
        [switch] $TestBeforeReturn

    )

    $responseValid = $false
    while ($responseValid -eq $false) {
        Write-Host
        Write-Verbose "5 get-ValidResponse"
        $response = Read-Host2 -Prompt $prompt $currentValue
        try {
            if ([String]::IsNullOrWhiteSpace($response)) {
                $responseValid = $true
            }
            else {
                try {
                    if ([int]$response -is [int]) {
                        if ([int]$response -le [int]$max -and [int]$response -gt 0 ) {
                            $responseValid = $true
                        }
                    }
                }
                catch {}
            }
            if ($responseValid -eq $false -and $null -ne $additionalOptions) {
                try {
                    if ($response.ToLowerInvariant() -eq $additionalOptions.ToLowerInvariant()) {
                        $responseValid = $true
                    }
                }
                catch {}

                foreach ($i in $($additionalOptions.keys)) {
                    if ($response.ToLowerInvariant() -eq $i.ToLowerInvariant()) {
                        $responseValid = $true
                    }
                }
            }
            if ($responseValid -eq $false -and $currentValue -is [bool]) {
                if ($currentValue.ToLowerInvariant() -eq "true" -or $currentValue.ToLowerInvariant() -eq "false") {
                    $responseValid = $false
                    if ($response.ToLowerInvariant() -eq "true") {
                        $response = $true
                        $responseValid = $true
                    }
                    if ($response.ToLowerInvariant() -eq "false") {
                        $response = $false
                        $responseValid = $true
                    }
                }
            }
        }
        catch {}
        if (-not $responseValid) {
            $validResponses = @()
            if ($max -gt 0) {
                $validResponses += 1..$max
            }
            if ($additionalOptions) {
                $validResponses += $additionalOptions.Keys | Where-Object { -not $_.StartsWith("*") }
            }
            write-host -ForegroundColor Red "Invalid response.  " -NoNewline
            write-host "Valid Responses are: " -NoNewline
            write-host -ForegroundColor Green "$($validResponses -join ",")"
        }
        if ($TestBeforeReturn.IsPresent -and $responseValid) {
            $responseValid = Get-TestResult -SuccessOnError
        }
    }
    #Write-Host "Returning: $response"
    return $response
}

Function Get-SupportedOperatingSystemsForRole {
    param (
        [Parameter(Mandatory = $true, HelpMessage = "vm")]
        [object] $vm
    )
    $role = $vm.Role
    $ServerList = $Common.Supported.OperatingSystems | Where-Object { $_ -like 'Server*' }
    $ClientList = $Common.Supported.OperatingSystems | Where-Object { $_ -notlike 'Server*' }
    $AllList = $Common.Supported.OperatingSystems
    switch ($role) {
        "DC" { return $ServerList }
        "CAS" { return $ServerList }
        "CAS and Primary" { return $ServerList }
        "Primary" { return $ServerList }
        "Secondary" { return $ServerList }
        "FileServer" { return $ServerList }
        "DPMP" { return $ServerList }
        "SQLAO" { return $ServerList }
        "DomainMember" {
            if ($vm.SqlVersion) {
                return $ServerList
            }
            else {
                return $AllList
            }
        }
        "DomainMember (Server)" { return $ServerList }
        "DomainMember (Client)" { return $ClientList }
        "WorkgroupMember" { return $AllList }
        "InternetClient" { return $ClientList }
        "AADClient" { return $ClientList }
        "OSDClient" { return $null }
        default {
            return $AllList
        }
    }
    return $AllList
}


Function Get-OperatingSystemMenu {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Base Property Object")]
        [Object] $property,
        [Parameter(Mandatory = $true, HelpMessage = "Name of Notefield to Modify")]
        [string] $name,
        [Parameter(Mandatory = $true, HelpMessage = "Current value")]
        [Object] $CurrentValue
    )

    $valid = $false
    while ($valid -eq $false) {
        $OSList = Get-SupportedOperatingSystemsForRole -vm $property
        if ($null -eq $OSList ) {
            return
        }
        $property."$name" = Get-Menu "Select OS Version" $OSList $CurrentValue -Test:$false
        if (Get-TestResult -SuccessOnWarning) {
            return
        }
        else {
            if ($property."$name" -eq $value) {
                return
            }
        }
    }
}

Function Get-ParentSiteCodeMenu {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Base Property Object")]
        [String] $role,
        [Parameter(Mandatory = $false, HelpMessage = "Current value")]
        [Object] $CurrentValue,
        [Parameter(Mandatory = $false, HelpMessage = "Config")]
        [Object] $ConfigToCheck = $global:config,
        [Parameter(Mandatory = $false, HelpMessage = "Domain")]
        [string] $Domain
    )

    if ($Role -eq "Primary") {
        $casSiteCodes = Get-ValidCASSiteCodes -config $global:config -domain $Domain

        $additionalOptions = @{ "X" = "No Parent - Standalone Primary" }
        do {
            $result = Get-Menu -Prompt "Select CAS sitecode to connect primary to" -OptionArray $casSiteCodes -CurrentValue $CurrentValue -additionalOptions $additionalOptions -Test:$false
        } while (-not $result)
        if ($result.ToLowerInvariant() -eq "x") {
            return $null
        }
        else {
            return $result
        }
    }
    if ($Role -eq "Secondary") {
        $priSiteCodes = Get-ValidPRISiteCodes -config $global:config -domain $Domain
        if (($priSiteCodes | Measure-Object).Count -eq 0) {
            write-Host "No valid primaries available to connect secondary to."
            return $null
        }
        do {
            $result = Get-Menu -Prompt "Select Primary sitecode to connect secondary to" -OptionArray $priSiteCodes -CurrentValue $CurrentValue -Test:$false
        } while (-not $result)
        return $result
    }
    return $null
}
Function Set-ParentSiteCodeMenu {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Base Property Object")]
        [Object] $property,
        [Parameter(Mandatory = $true, HelpMessage = "Name of Notefield to Modify")]
        [string] $name,
        [Parameter(Mandatory = $true, HelpMessage = "Current value")]
        [Object] $CurrentValue
    )
    $valid = $false
    while ($valid -eq $false) {


        $value = Get-ParentSiteCodeMenu -role $property.role -CurrentValue $CurrentValue -domain $global:config.vmOptions.domainName
        if ($value.Trim()) {
            $property."$name" = $value
        }

        if (Get-TestResult -SuccessOnWarning) {
            return
        }
        else {
            if ($property."$name" -eq $value) {
                return
            }
        }
    }
}

Function Get-SiteCodeForDPMP {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, HelpMessage = "Current value")]
        [Object] $CurrentValue,
        [Parameter(Mandatory = $false, HelpMessage = "Config")]
        [string] $Domain
    )
    $valid = $false
    #Get-PSCallStack | out-host
    while ($valid -eq $false) {
        $siteCodes = @()
        $tempSiteCode = ($ConfigToCheck.VirtualMachines | Where-Object { $_.role -eq "Primary" } | Select-Object -first 1)
        if (-not [String]::IsNullOrWhiteSpace($tempSiteCode)) {
            $siteCodes += "$($tempSiteCode.SiteCode) (New Primary Server - $($tempSiteCode.vmName))"
        }
        $tempSiteCode = ($ConfigToCheck.VirtualMachines | Where-Object { $_.role -eq "Secondary" } | Select-Object -first 1)
        if (-not [String]::IsNullOrWhiteSpace($tempSiteCode)) {
            $siteCodes += "$($tempSiteCode.SiteCode) (New Secondary Server - $($tempSiteCode.vmName)"
        }
        if ($Domain) {
            #$siteCodes += Get-ExistingSiteServer -DomainName $Domain -Role "Primary" | Select-Object -ExpandProperty SiteCode -Unique
            #$siteCodes += Get-ExistingSiteServer -DomainName $Domain -Role "Secondary" | Select-Object -ExpandProperty SiteCode -Unique
            foreach ($item in (Get-ExistingSiteServer -DomainName $Domain -Role "Primary" | Select-Object SiteCode, Subnet, VmName -Unique)) {
                $sitecodes += "$($item.SiteCode) ($($item.vmName), $($item.Subnet))"
            }
            foreach ($item in (Get-ExistingSiteServer -DomainName $Domain -Role "Secondary" | Select-Object SiteCode, Subnet, VmName -Unique)) {
                $sitecodes += "$($item.SiteCode) ($($item.vmName), $($item.Subnet))"
            }

            if ($siteCodes.Length -eq 0) {
                Write-Host
                write-host "No valid site codes are eligible to accept this DPMP"
                return $null
            }
            else {
                #write-host $siteCodes
            }
            $result = $null
            while (-not $result) {
                $result = Get-Menu -Prompt "Select sitecode to connect DPMP to" -OptionArray $siteCodes -CurrentValue $CurrentValue -Test:$false
            }
            if ($result.ToLowerInvariant() -eq "x") {
                return $null
            }
            else {
                return ($result -Split " ")[0]
            }
        }
    }
}
Function Get-SiteCodeMenu {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Base Property Object")]
        [Object] $property,
        [Parameter(Mandatory = $true, HelpMessage = "Name of Notefield to Modify")]
        [string] $name,
        [Parameter(Mandatory = $true, HelpMessage = "Current value")]
        [Object] $CurrentValue,
        [Parameter(Mandatory = $false, HelpMessage = "Config")]
        [Object] $ConfigToCheck = $global:config
    )

    #Get-PSCallStack | out-host
    $result = Get-SiteCodeForDPMP -CurrentValue $CurrentValue -Domain $configToCheck.vmoptions.domainName

    if ($result.ToLowerInvariant() -eq "x") {
        $property."$name" = $null
    }
    else {
        $property | Add-Member -MemberType NoteProperty -Name $name -Value $result -Force
        #$property."$name" = $result
    }
    if (Get-TestResult -SuccessOnWarning) {
        return
    }
    else {
        if ($property."$name" -eq $CurrentValue) {
            return
        }
    }
}


Function Get-SqlVersionMenu {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Base Property Object")]
        [Object] $property,
        [Parameter(Mandatory = $true, HelpMessage = "Name of Notefield to Modify")]
        [string] $name,
        [Parameter(Mandatory = $true, HelpMessage = "Current value")]
        [Object] $CurrentValue
    )

    $valid = $false
    while ($valid -eq $false) {
        $property."$name" = Get-Menu "Select SQL Version" $($Common.Supported.SqlVersions) $CurrentValue -Test:$false
        if (Get-TestResult -SuccessOnWarning) {
            return
        }
        else {
            if ($property."$name" -eq $CurrentValue) {
                return
            }
        }
    }
}


Function Set-SiteServerLocalSql {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Site Server VM Object")]
        [Object] $virtualMachine
    )

    if ($null -eq $virtualMachine.sqlVersion) {
        $virtualMachine | Add-Member -MemberType NoteProperty -Name 'sqlVersion' -Value "SQL Server 2019"
        $virtualMachine | Add-Member -MemberType NoteProperty -Name 'sqlInstanceName' -Value "MSSQLSERVER"
        $virtualMachine | Add-Member -MemberType NoteProperty -Name 'sqlInstanceDir' -Value "F:\SQL"
    }
    $virtualMachine.virtualProcs = 8
    $virtualMachine.memory = "12GB"

    if ($null -eq $virtualMachine.additionalDisks) {
        $disk = [PSCustomObject]@{"E" = "250GB"; "F" = "100GB" }
        $virtualMachine | Add-Member -MemberType NoteProperty -Name 'additionalDisks' -Value $disk
    }
    else {

        if ($null -eq $virtualMachine.additionalDisks.E) {
            $virtualMachine.additionalDisks | Add-Member -MemberType NoteProperty -Name "E" -Value "250GB"
        }
        if ($null -eq $virtualMachine.additionalDisks.F) {
            $virtualMachine.additionalDisks | Add-Member -MemberType NoteProperty -Name "F" -Value "100GB"
        }
    }

    if ($null -ne $virtualMachine.remoteSQLVM) {
        $SQLVM = $virtualMachine.remoteSQLVM
        $virtualMachine.PsObject.Members.Remove('remoteSQLVM')
        Remove-VMFromConfig -vmName $SQLVM -Config $global:config

    }

}

Function Set-SiteServerRemoteSQL {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Site Server VM Object")]
        [Object] $virtualMachine,
        [Parameter(Mandatory = $true, HelpMessage = "VmName")]
        [string] $vmName
    )

    if ($null -ne $virtualMachine.sqlVersion) {
        $virtualMachine.PsObject.Members.Remove('sqlVersion')
        $virtualMachine.PsObject.Members.Remove('sqlInstanceName')
        $virtualMachine.PsObject.Members.Remove('sqlInstanceDir')
    }
    $virtualMachine.memory = "4GB"
    $virtualMachine.virtualProcs = 4
    if ($null -ne $virtualMachine.additionalDisks.F) {
        $virtualMachine.additionalDisks.PsObject.Members.Remove('F')
    }
    if ($null -ne $virtualMachine.remoteSQLVM) {
        $virtualMachine.PsObject.Members.Remove('remoteSQLVM')
    }
    $virtualMachine | Add-Member -MemberType NoteProperty -Name 'remoteSQLVM' -Value $vmName
}

Function Get-remoteSQLVM {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Base Property Object")]
        [Object] $property,
        [Parameter(Mandatory = $false, HelpMessage = "Name of Notefield to Modify")]
        [string] $name,
        [Parameter(Mandatory = $false, HelpMessage = "Current value")]
        [Object] $CurrentValue
    )

    $valid = $false
    while ($valid -eq $false) {
        $additionalOptions = @{ "L" = "Local SQL" }

        $validVMs = $Global:Config.virtualMachines | Where-Object { ($_.Role -eq "DomainMember" -and $null -ne $_.SqlVersion) -or ($_.Role -eq "SQLAO" -and $_.OtherNode ) } | Select-Object -ExpandProperty vmName

        $CASVM = $Global:Config.virtualMachines | Where-Object { $_.Role -eq "CAS" }
        $PRIVM = $Global:Config.virtualMachines | Where-Object { $_.Role -eq "Primary" }

        if ($Property.Role -eq "CAS") {
            if ($null -ne $PRIVM.remoteSQLVM) {
                #Write-Verbose "Checking "
                $validVMs = $validVMs | Where-Object { $_ -ne $PRIVM.remoteSQLVM }
            }
        }
        if ($Property.Role -eq "Primary") {
            if ($null -ne $CASVM.remoteSQLVM) {
                $validVMs = $validVMs | Where-Object { $_ -ne $CASVM.remoteSQLVM }
            }
        }

        if (($validVMs | Measure-Object).Count -eq 0) {
            $additionalOptions += @{ "N" = "Create a New SQL VM" }
            $additionalOptions += @{ "A" = "Create a New SQL Always On Cluster" }
        }
        $result = Get-Menu "Select Remote SQL VM, or Select Local" $($validVMs) $CurrentValue -Test:$false -additionalOptions $additionalOptions

        switch ($result.ToLowerInvariant()) {
            "l" {
                Set-SiteServerLocalSql $property
            }
            "n" {
                $name = $($property.SiteCode) + "SQL"
                Add-NewVMForRole -Role "SqlServer" -Domain $global:config.vmOptions.domainName -ConfigToModify $global:config -Name $name
                Set-SiteServerRemoteSQL $property $name
            }
            "a" {
                $name1 = $($property.SiteCode) + "SQLAO1"
                $name2 = $($property.SiteCode) + "SQLAO2"
                Add-NewVMForRole -Role "SQLAO" -Domain $global:config.vmOptions.domainName -ConfigToModify $global:config -Name $name1 -Name2 $Name2
                Set-SiteServerRemoteSQL $property $name1
            }
            Default {
                if ([string]::IsNullOrWhiteSpace($result)) {
                    continue
                }
                Set-SiteServerRemoteSQL $property $result
            }
        }
        if (Get-TestResult -SuccessOnWarning) {
            return
        }
        else {
            if ($null -ne $name) {
                if ($property."$name" -eq $CurrentValue) {
                    return
                }
            }
        }
    }
}

Function Get-domainUser {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Base Property Object")]
        [Object] $property,
        [Parameter(Mandatory = $true, HelpMessage = "Name of Notefield to Modify")]
        [string] $name,
        [Parameter(Mandatory = $false, HelpMessage = "Current value")]
        [Object] $CurrentValue
    )

    $users = get-list2 -DeployConfig $Global:Config | Where-Object { $_.domainUser } | Select-Object -ExpandProperty domainUser -Unique
    $valid = $false
    while ($valid -eq $false) {
        $additionalOptions = @{ "N" = "New User" }


        $result = Get-Menu "Select User" $($users) $CurrentValue -Test:$false -additionalOptions $additionalOptions

        switch ($result.ToLowerInvariant()) {
            "n" {
                $result = Read-Host2 -Prompt "Enter desired Username"
            }

            Default {
                if ([string]::IsNullOrWhiteSpace($result)) {
                    if (-not $CurrentValue) {
                        $property.psobject.properties.remove($name)
                    }
                    else {
                        $property | Add-Member -MemberType NoteProperty -Name $name -Value $CurrentValue -force
                    }
                    return
                }
            }
        }
        if ($null -ne $name) {
            $property | Add-Member -MemberType NoteProperty -Name $name -Value $result -force
        }
        if (Get-TestResult -SuccessOnWarning) {
            return
        }
        else {
            if ($null -ne $name) {
                if ($property."$name" -eq $CurrentValue) {
                    return
                }
            }
        }
    }
}

Function Get-CMVersionMenu {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Base Property Object")]
        [Object] $property,
        [Parameter(Mandatory = $true, HelpMessage = "Name of Notefield to Modify")]
        [string] $name,
        [Parameter(Mandatory = $true, HelpMessage = "Current value")]
        [Object] $CurrentValue
    )

    $valid = $false
    while ($valid -eq $false) {
        $property."$name" = Get-Menu "Select ConfigMgr Version" $($Common.Supported.CmVersions) $CurrentValue -Test:$false
        if (Get-TestResult -SuccessOnWarning) {
            return
        }
        else {
            if ($property."$name" -eq $value) {
                return
            }
        }
    }
}
Function Get-RoleMenu {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Base Property Object")]
        [Object] $property,
        [Parameter(Mandatory = $true, HelpMessage = "Name of Notefield to Modify")]
        [string] $name,
        [Parameter(Mandatory = $true, HelpMessage = "Current value")]
        [Object] $CurrentValue
    )

    $valid = $false
    while ($valid -eq $false) {
        $DC = Get-List -type VM -domain $global:config.vmOptions.domainName | Where-Object { $_.Role -eq "DC" }
        if ($DC) {
            $role = Get-Menu "Select Role" $(Select-RolesForExistingList) $CurrentValue -Test:$false
            $property."$name" = $role
        }
        else {
            $role = Get-Menu "Select Role" $(Select-RolesForNewList) $CurrentValue -Test:$false
            $property."$name" = $role
        }

        # If the value is the same.. Dont delete and re-create the VM
        if ($property."$name" -eq $value) {
            # return false if the VM object is still viable.
            return $false
        }

        # In order to make sure the default params like SQLVersion, CMVersion are correctly applied.  Delete the VM and re-create with the same name.
        Remove-VMFromConfig -vmName $property.vmName -ConfigToModify $global:config
        Add-NewVMForRole -Role $Role -Domain $Global:Config.vmOptions.domainName -ConfigToModify $global:config -Name $property.vmName -Quiet:$true

        # We cant do anything with the test result, as our underlying object is no longer in config.
        Get-TestResult -config $global:config -SuccessOnWarning | out-null

        # return true if the VM is deleted.
        return $true
    }
}

function Get-AdditionalValidations {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Base Property Object")]
        [Object] $property,
        [Parameter(Mandatory = $true, HelpMessage = "Name of Notefield to Modify")]
        [string] $name,
        [Parameter(Mandatory = $true, HelpMessage = "Current value")]
        [Object] $CurrentValue
    )
    $value = $property."$($Name)"
    #$name = $($item.Name)
    Write-Verbose "[Get-AdditionalValidations] Prop:'$property' Name:'$name' Current:'$CurrentValue' New:'$value'"
    switch ($name) {
        "E" {
            if (-not ($value.EndsWith("GB")) -and (-not ($value.EndsWith("MB")))) {
                if ($CurrentValue.EndsWith("GB")) {
                    $property.$name = $value.Trim() + "GB"
                }
                if ($CurrentValue.EndsWith("MB")) {
                    $property.$name = $value.Trim() + "MB"
                }
            }
        }
        "F" {
            if (-not ($value.EndsWith("GB")) -and (-not ($value.EndsWith("MB")))) {
                if ($CurrentValue.EndsWith("GB")) {
                    $property.$name = $value.Trim() + "GB"
                }
                if ($CurrentValue.EndsWith("MB")) {
                    $property.$name = $value.Trim() + "MB"
                }
            }
        }
        "G" {
            if (-not ($value.EndsWith("GB")) -and (-not ($value.EndsWith("MB")))) {
                if ($CurrentValue.EndsWith("GB")) {
                    $property.$name = $value.Trim() + "GB"
                }
                if ($CurrentValue.EndsWith("MB")) {
                    $property.$name = $value.Trim() + "MB"
                }
            }
        }
        "memory" {
            if (-not ($value.EndsWith("GB")) -and (-not ($value.EndsWith("MB")))) {
                if ($CurrentValue.EndsWith("GB")) {
                    $property.$name = $value.Trim() + "GB"
                }
                if ($CurrentValue.EndsWith("MB")) {
                    $property.$name = $value.Trim() + "MB"
                }
            }
        }

        "SqlServiceAccount" {
            if ($property.Role -eq "SQLAO") {
                $SQLAO = $Global:Config.virtualMachines | Where-Object { $_.Role -eq "SQLAO" }
                foreach ($sql in $SQLAO) {
                    $sql.$name = $value
                }
            }
        }
        "SqlAgentAccount" {
            if ($property.Role -eq "SQLAO") {
                $SQLAO = $Global:Config.virtualMachines | Where-Object { $_.Role -eq "SQLAO" }
                foreach ($sql in $SQLAO) {
                    $sql.$name = $value
                }
            }
        }
        "sqlVersion" {
            if ($property.Role -eq "SQLAO") {
                $SQLAO = $Global:Config.virtualMachines | Where-Object { $_.Role -eq "SQLAO" }
                foreach ($sql in $SQLAO) {
                    $sql.$name = $value
                }
            }
        }
        "sqlInstanceName" {
            if ($property.Role -eq "SQLAO") {
                $SQLAO = $Global:Config.virtualMachines | Where-Object { $_.Role -eq "SQLAO" }
                foreach ($sql in $SQLAO) {
                    $sql.$name = $value
                }
            }

        }
        "sqlInstanceDir" {
            if ($property.Role -eq "SQLAO") {
                $SQLAO = $Global:Config.virtualMachines | Where-Object { $_.Role -eq "SQLAO" }
                foreach ($sql in $SQLAO) {
                    $sql.$name = $value
                }
            }

        }

        "vmName" {

            $CASVM = $Global:Config.virtualMachines | Where-Object { $_.Role -eq "CAS" }
            $PRIVM = $Global:Config.virtualMachines | Where-Object { $_.Role -eq "Primary" }

            $Passives = $Global:Config.virtualMachines | Where-Object { $_.Role -eq "PassiveSite" }
            $SQLAOs = $Global:Config.virtualMachines | Where-Object { $_.Role -eq "SQLAO" -and $_.OtherNode }
            #This is a SQL Server being renamed.  Lets check if we need to update CAS or PRI
            if (($Property.Role -eq "DomainMember") -and ($null -ne $Property.sqlVersion)) {
                if (($null -ne $PRIVM.remoteSQLVM) -and $PRIVM.remoteSQLVM -eq $CurrentValue) {
                    $PRIVM.remoteSQLVM = $value
                }
                if (($null -ne $CASVM.remoteSQLVM) -and ($CASVM.remoteSQLVM -eq $CurrentValue)) {
                    $CASVM.remoteSQLVM = $value
                }
            }

            if ($Property.Role -eq "FileServer" -and $null -ne $SQLAO) {
                foreach ($SQLAO in $SQAOs) {
                    if ($SQLAO.FileServerVM -eq $CurrentValue) {
                        $SQLAO.FileServerVM = $value
                    }
                }
            }
            if ($Property.Role -eq "FileServer" -and $null -ne $Passive) {
                foreach ($Passive in $Passives) {
                    if ($Passive.remoteContentLibVM -eq $CurrentValue) {
                        $Passive.remoteContentLibVM = $value
                    }
                }
            }
        }
        "installMP" {
            if ((get-RoleForSitecode -ConfigToCheck $Global:Config -siteCode $property.siteCode) -eq "Secondary") {
                write-host -ForegroundColor Yellow "Can not install an MP for a secondary site"
                $property.installMP = $false
            }
            $newName = Get-NewMachineName -vm $property
            if ($($property.vmName) -ne $newName) {
                $rename = $true
                $response = Read-Host2 -Prompt "Rename $($property.vmName) to $($newName)? (Y/n)" -HideHelp
                if (-not [String]::IsNullOrWhiteSpace($response)) {
                    if ($response.ToLowerInvariant() -eq "n" -or $response.ToLowerInvariant() -eq "no") {
                        $rename = $false
                    }
                }
                if ($rename -eq $true) {
                    $property.vmName = $newName
                }
            }
        }
        "installDP" {
            $newName = Get-NewMachineName -vm $property
            if ($($property.vmName) -ne $newName) {
                $rename = $true
                $response = Read-Host2 -Prompt "Rename $($property.vmName) to $($newName)? (Y/n)" -HideHelp
                if (-not [String]::IsNullOrWhiteSpace($response)) {
                    if ($response.ToLowerInvariant() -eq "n" -or $response.ToLowerInvariant() -eq "no") {
                        $rename = $false
                    }
                }
                if ($rename -eq $true) {
                    $property.vmName = $newName
                }
            }
        }
        "siteCode" {
            if ($property.RemoteSQLVM) {
                $newSQLName = $value + "SQL"
                #Check if the new name is already in use:
                $NewSQLVM = $Global:Config.virtualMachines | Where-Object { $_.vmName -eq $newSQLName }
                if ($NewSQLVM) {
                    write-host
                    write-host -ForegroundColor Red "Changing Sitecode would rename SQL VM to " -NoNewline
                    write-host -ForegroundColor Yellow $($NewSQLVM.vmName) -NoNewline
                    write-host -ForegroundColor Red " which already exists. Unable to change sitecode."
                    $property.siteCode = $CurrentValue
                    return
                }
            }

            $newName = Get-NewMachineName -vm $property
            $NewSSName = $Global:Config.virtualMachines | Where-Object { $_.vmName -eq $newName }
            if ($NewSSName) {
                write-host
                write-host -ForegroundColor Red "Changing Sitecode would rename VM to " -NoNewline
                write-host -ForegroundColor Yellow $($NewSSName.vmName) -NoNewline
                write-host -ForegroundColor Red " which already exists. Unable to change sitecode."
                $property.siteCode = $CurrentValue
                return
            }
            #Set the SQL Name after all checks are done.
            if ($property.RemoteSQLVM) {
                $RemoteSQLVM = $Global:Config.virtualMachines | Where-Object { $_.vmName -eq $($property.RemoteSQLVM) }
                $RemoteSQLVM.vmName = $newSQLName
                $property.RemoteSQLVM = $newSQLName
            }
            if ($($property.vmName) -ne $newName) {
                $rename = $true
                $response = Read-Host2 -Prompt "Rename $($property.vmName) to $($newName)? (Y/n)" -HideHelp
                if (-not [String]::IsNullOrWhiteSpace($response)) {
                    if ($response.ToLowerInvariant() -eq "n" -or $response.ToLowerInvariant() -eq "no") {
                        $rename = $false
                    }
                }
                if ($rename -eq $true) {
                    $property.vmName = $newName
                }
            }
            Write-Verbose "New Name: $newName"
            if ($property.role -eq "CAS") {
                $PRIVM = $Global:Config.virtualMachines | Where-Object { $_.Role -eq "Primary" }
                if ($PRIVM) {
                    $PRIVM.parentSiteCode = $value
                }
                $VMs = @()
                $VMs += $Global:Config.virtualMachines | Where-Object { $_.Role -eq "PassiveSite" }
                if ($VMs) {
                    foreach ($VM in $VMS) {
                        if ($VM.siteCode -eq $CurrentValue ) {
                            $VM.SiteCode = $value
                            Get-AdditionalValidations -property $VM -name "SiteCode" -CurrentValue $CurrentValue
                        }
                    }
                }
            }
            if ($property.role -eq "Primary") {
                $VMs = @()
                $VMs += $Global:Config.virtualMachines | Where-Object { $_.Role -eq "DPMP" }
                $VMs += $Global:Config.virtualMachines | Where-Object { $_.Role -eq "PassiveSite" }
                $SecVM = $Global:Config.virtualMachines | Where-Object { $_.Role -eq "Secondary" }
                if ($VMs) {
                    foreach ($VM in $VMS) {
                        if ($VM.siteCode -eq $CurrentValue ) {
                            $VM.SiteCode = $value
                            Get-AdditionalValidations -property $VM -name "SiteCode" -CurrentValue $CurrentValue
                        }
                    }
                }
                if ($SecVM) {
                    $SecVM.parentSiteCode = $value
                }
            }

            if ($property.role -eq "Secondary") {
                $VMs = $Global:Config.virtualMachines | Where-Object { $_.Role -eq "DPMP" }
                if ($VMs) {
                    foreach ($VM in $VMS) {
                        if ($VM.siteCode -eq $CurrentValue ) {
                            $VM.SiteCode = $value
                        }
                    }
                }
            }
        }
    }
}


function Get-SortedProperties {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, HelpMessage = "Property to Sort")]
        [object] $property
    )

    $Sorted = @()
    $members = $property | Get-Member -MemberType NoteProperty

    if ($members.Name -contains "domainName") {
        $sorted += "domainName"
    }
    if ($members.Name -contains "prefix") {
        $sorted += "prefix"
    }
    if ($members.Name -contains "network") {
        $sorted += "network"
    }
    if ($members.Name -contains "adminName") {
        $sorted += "adminName"
    }
    if ($members.Name -contains "basePath") {
        $sorted += "basePath"
    }

    if ($members.Name -contains "vmName") {
        $sorted += "vmName"
    }
    if ($members.Name -contains "role") {
        $sorted += "role"
    }
    if ($members.Name -contains "memory") {
        $sorted += "memory"
    }
    if ($members.Name -contains "virtualProcs") {
        $sorted += "virtualProcs"
    }
    if ($members.Name -contains "operatingSystem") {
        $sorted += "operatingSystem"
    }
    if ($members.Name -contains "sqlVersion") {
        $sorted += "sqlVersion"
    }
    if ($members.Name -contains "sqlInstanceName") {
        $sorted += "sqlInstanceName"
    }
    if ($members.Name -contains "sqlInstanceDir") {
        $sorted += "sqlInstanceDir"
    }
    if ($members.Name -contains "remoteSQLVM") {
        $sorted += "remoteSQLVM"
    }
    if ($members.Name -contains "cmInstallDir") {
        $sorted += "cmInstallDir"
    }
    if ($members.Name -contains "parentSiteCode") {
        $sorted += "parentSiteCode"
    }
    if ($members.Name -contains "siteCode") {
        $sorted += "siteCode"
    }
    if ($members.Name -contains "remoteContentLibVM") {
        $sorted += "remoteContentLibVM"
    }

    if ($members.Name -contains "additionalDisks") {
        $sorted += "additionalDisks"
    }

    switch ($members.Name) {
        "vmName" {  }
        "role" {  }
        "memory" { }
        "virtualProcs" { }
        "operatingSystem" {  }
        "siteCode" { }
        "parentSiteCode" { }
        "sqlVersion" { }
        "sqlInstanceName" {  }
        "sqlInstanceDir" { }
        "additionalDisks" { }
        "cmInstallDir" { }
        "domainName" { }
        "prefix" { }
        "network" { }
        "adminName" { }
        "basePath" { }
        "remoteSQLVM" {}
        "remoteContentLibVM" {}

        Default { $sorted += $_ }
    }
    return $sorted
}

# Displays a Menu based on a property, offers options in [1], [2],[3] format
# With additional options passed in via additionalOptions
function Select-Options {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, HelpMessage = "Root of Property to Enumerate and automatically display a menu")]
        [object] $Rootproperty,
        [Parameter(Mandatory = $false, HelpMessage = "Property name")]
        [object] $propertyName,
        [Parameter(Mandatory = $false, HelpMessage = "Property to enumerate.. Can be used instead of RootProperty and propertyName")]
        [object] $propertyEnum,
        [Parameter(Mandatory = $false, HelpMessage = "If Property is an array.. find this element to work on (Base = 1).")]
        [object] $propertyNum,
        [Parameter(Mandatory = $true, HelpMessage = "Prompt to display")]
        [string] $prompt,
        [Parameter(Mandatory = $false, HelpMessage = "Append additional Items to menu.. Eg X = Exit")]
        [PSCustomObject] $additionalOptions,
        [Parameter(Mandatory = $false, HelpMessage = "Run a configuration test. Default True")]
        [bool] $Test = $true
    )

    $property = $null
    :MainLoop   while ($true) {
        if ($null -eq $property -and $null -ne $Rootproperty) {
            $property = $Rootproperty."$propertyName"
        }

        if ($null -ne $propertyNum) {
            $i = 0;
            while ($true) {
                if ($i -eq [int]($propertyNum - 1)) {
                    $property = $propertyEnum[$i]
                    break
                }
                $i = $i + 1
            }
        }

        if ($null -eq $property) {
            $property = $propertyEnum
        }

        Write-Host
        Write-Verbose "6 Select-Options '$property' Root: '$Rootproperty' Name: '$propertyName' Enum: '$propertyEnum' Num '$propertyNum'"
        $i = 0
        #Write-Host "Trying to get $property"
        if ($null -eq $property) {
            return $null
        }

        # Get the Property Names and Values.. Present as Options.
        foreach ($item in (Get-SortedProperties $property)) {
            $i = $i + 1
            $value = $property."$($item)"
            #$padding = 27 - ($i.ToString().Length)
            $padding = 26
            Write-Option $i "$($($item).PadRight($padding," "")) = $value"
        }

        if ($null -ne $additionalOptions) {
            foreach ($item in $additionalOptions.keys) {
                $value = $additionalOptions."$($item)"

                $color1 = "DarkGreen"
                $color2 = "Green"

                #Write-Host -ForegroundColor DarkGreen [$_] $value
                if (-not [String]::IsNullOrWhiteSpace($item)) {
                    $TextValue = $value -split "%"

                    if (-not [string]::IsNullOrWhiteSpace($TextValue[1])) {
                        $color1 = $TextValue[1]
                    }
                    if (-not [string]::IsNullOrWhiteSpace($TextValue[2])) {
                        $color2 = $TextValue[2]
                    }
                    if ($item.StartsWith("*")) {
                        write-host -ForegroundColor $color1 $TextValue[0]
                        continue
                    }
                    Write-Option $item $TextValue[0] -color $color1 -Color2 $color2
                }
            }
        }
        $response = get-ValidResponse $prompt $i $null $additionalOptions
        if ([String]::IsNullOrWhiteSpace($response)) {
            return
        }

        $return = $null
        if ($null -ne $additionalOptions) {
            foreach ($item in $($additionalOptions.keys)) {
                if ($response.ToLowerInvariant() -eq $item.ToLowerInvariant()) {
                    # Return fails here for some reason. If the values were the same, let the user escape, as no changes were made.
                    $return = $item
                }
            }
        }
        #Return here instead.
        if ($null -ne $return) {
            return $return
        }
        # We got the [1] Number pressed. Lets match that up to the actual value.
        $i = 0
        foreach ($item in (Get-SortedProperties $property)) {

            $i = $i + 1

            if (-not ($response -eq $i)) {
                continue
            }

            $value = $property."$($item)"
            $name = $($item)

            switch ($name) {
                "operatingSystem" {
                    Get-OperatingSystemMenu -property $property -name $name -CurrentValue $value
                    if ($property.role -eq "DomainMember") {
                        #if (-not $property.SqlVersion) {
                        $newName = Get-NewMachineName -vm $property
                        if ($($property.vmName) -ne $newName) {
                            $rename = $true
                            $response = Read-Host2 -Prompt "Rename $($property.vmName) to $($newName)? (Y/n)" -HideHelp
                            if (-not [String]::IsNullOrWhiteSpace($response)) {
                                if ($response.ToLowerInvariant() -eq "n" -or $response.ToLowerInvariant() -eq "no") {
                                    $rename = $false
                                }
                            }
                            if ($rename -eq $true) {
                                $property.vmName = $newName
                            }
                        }
                        #}
                    }
                    continue MainLoop
                }
                "remoteContentLibVM" {
                    $property.remoteContentLibVM = select-FileServerMenu -HA:$true
                    continue MainLoop
                }
                "fileServerVM" {
                    $property.fileServerVM = select-FileServerMenu -HA:$false
                    continue MainLoop
                }
                "domainName" {
                    $domain = select-NewDomainName
                    $property.domainName = $domain
                    $property.prefix = get-PrefixForDomain -Domain $domain
                    Get-TestResult -SuccessOnError | out-null
                    continue MainLoop
                }
                "timeZone" {
                    $timezone = Select-TimeZone
                    $property.timeZone = $timezone
                    Get-TestResult -SuccessOnError | out-null
                    continue MainLoop
                }
                "network" {
                    $network = Select-Subnet
                    $property.network = $network
                    Get-TestResult -SuccessOnError | out-null
                    continue MainLoop
                }
                "parentSiteCode" {
                    Set-ParentSiteCodeMenu -property $property -name $name -CurrentValue $value
                    continue MainLoop
                }
                "sqlVersion" {
                    Get-SqlVersionMenu -property $property -name $name -CurrentValue $value
                    continue MainLoop
                }
                "remoteSQLVM" {
                    Get-remoteSQLVM -property $property -name $name -CurrentValue $value
                    return "REFRESH"
                }
                "domainUser" {
                    Get-domainUser -property $property -name $name -CurrentValue $value
                    return "REFRESH"
                }
                "siteCode" {
                    if ($property.role -eq "PassiveSite") {
                        write-host
                        write-host -ForegroundColor Yellow "siteCode can not be manually modified on a Passive server."
                        continue MainLoop
                    }
                    if ($property.role -eq "DPMP") {
                        Get-SiteCodeMenu -property $property -name $name -CurrentValue $value
                        $newName = Get-NewMachineName -vm $property
                        if ($($property.vmName) -ne $newName) {
                            $rename = $true
                            $response = Read-Host2 -Prompt "Rename $($property.vmName) to $($newName)? (Y/n)" -HideHelp
                            if (-not [String]::IsNullOrWhiteSpace($response)) {
                                if ($response.ToLowerInvariant() -eq "n" -or $response.ToLowerInvariant() -eq "no") {
                                    $rename = $false
                                }
                            }
                            if ($rename -eq $true) {
                                $property.vmName = $newName
                            }
                        }
                        continue MainLoop
                    }
                }
                "role" {
                    if ($property.role -eq "PassiveSite") {
                        write-host
                        write-host -ForegroundColor Yellow "role can not be manually modified on a Passive server. Please disable HA or delete the VM."
                        continue MainLoop
                    }
                    if (Get-RoleMenu -property $property -name $name -CurrentValue $value) {
                        Write-Host -ForegroundColor Yellow "VirtualMachine object was re-created with new role. Taking you back to VM Menu."
                        # VM was deleted.. Lets get outta here.
                        return
                    }
                    else {
                        #VM was not deleted.. We can still edit other properties.
                        continue MainLoop
                    }
                }
                "version" {
                    Get-CMVersionMenu -property $property -name $name -CurrentValue $value
                    continue MainLoop
                }
            }
            # If the property is another PSCustomObject, recurse, and call this function again with the inner object.
            # This is currently only used for AdditionalDisks
            if ($value -is [System.Management.Automation.PSCustomObject]) {
                Select-Options -Rootproperty $property -PropertyName "$Name" -Prompt "Select data to modify" | out-null
            }
            else {
                #The option was not a known name with its own menu, and it wasnt another PSCustomObject.. We can edit it directly.
                $valid = $false
                Write-Host
                Write-Verbose "7 Select-Options"
                while ($valid -eq $false) {
                    if ($value -is [bool]) {
                        $response2 = Get-Menu -Prompt "Select new Value for $($Name)" -CurrentValue $value -OptionArray @("True", "False") -NoNewLine -Test:$false
                    }
                    else {
                        $response2 = Read-Host2 -Prompt "Select new Value for $($Name)" $value
                    }
                    if (-not [String]::IsNullOrWhiteSpace($response2)) {
                        if ($property."$($Name)" -is [Int]) {
                            $property."$($Name)" = [Int]$response2
                        }
                        else {
                            if ($value -is [bool]) {
                                if ($([string]$value).ToLowerInvariant() -eq "true" -or $([string]$value).ToLowerInvariant() -eq "false") {
                                    if ($response2.ToLowerInvariant() -eq "true") {
                                        $response2 = $true
                                    }
                                    elseif ($response2.ToLowerInvariant() -eq "false") {
                                        $response2 = $false
                                    }
                                    else {
                                        $response2 = $value
                                    }
                                }

                            }

                            Write-Verbose ("$_ name = $($_.Name) or $name = $response2 value = '$value'")
                            $property."$($Name)" = $response2
                        }
                        Get-AdditionalValidations -property $property -name $Name -CurrentValue $value
                        if ($Test) {
                            $valid = Get-TestResult -SuccessOnWarning
                        }
                        else {
                            $valid = $true
                        }
                        if ($response2 -eq $value) {
                            $valid = $true
                        }

                    }
                    else {
                        # Enter was pressed. Set the Default value, and test, but dont block.
                        $property."$($Name)" = $value
                        $valid = Get-TestResult -SuccessOnError
                    }
                }
            }
        }
    }
}

Function Get-TestResult {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, HelpMessage = "Returns true even if warnings are present")]
        [switch] $SuccessOnWarning,
        [Parameter(Mandatory = $false, HelpMessage = "Returns true even if errors are present")]
        [switch] $SuccessOnError,
        [Parameter(Mandatory = $false, HelpMessage = "Config to check")]
        [object] $config = $Global:Config
    )

    #If Config hasnt been generated yet.. Nothing to test
    if ($null -eq $config) {
        return $true
    }
    try {
        $c = Test-Configuration -InputObject $Config
        $valid = $c.Valid
        if ($valid -eq $false) {
            Write-Host "`r`nERROR: Validation Failures were encountered:`r`n" -ForegroundColor Red
            Write-ValidationMessages -TestObject $c
            #$MyInvocation | Out-Host
            if ($enableVerbose) {
                Get-PSCallStack | out-host
            }
        }
        if ($SuccessOnWarning.IsPresent) {
            if ( $c.Failures -eq 0) {
                $valid = $true
            }
        }
        if ($SuccessOnError.IsPresent) {
            $valid = $true
        }
    }
    catch {
        return $true
    }
    return $valid
}

function get-VMString {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "VirtualMachine Object from config")]
        [object] $virtualMachine
    )

    $machineName = $($($Global:Config.vmOptions.Prefix) + $($virtualMachine.vmName)).PadRight(19, " ")
    $name = "$machineName " + $("[" + $($virtualmachine.role) + "]").PadRight(16, " ")
    $mem = $($virtualMachine.memory).PadLEft(4, " ")
    $procs = $($virtualMachine.virtualProcs).ToString().PadLeft(2, " ")
    $name += " VM [$mem RAM,$procs CPU, $($virtualMachine.OperatingSystem)"

    if ($virtualMachine.additionalDisks) {
        $name += ", $($virtualMachine.additionalDisks.psobject.Properties.Value.count) Extra Disk(s)]"
    }
    else {
        $name += "]"
    }

    if ($virtualMachine.siteCode -and $virtualMachine.cmInstallDir) {
        $SiteCode = $virtualMachine.siteCode
        if ($virtualMachine.parentSiteCode) {
            $SiteCode += "->$($virtualMachine.parentSiteCode)"
        }
        $name += "  CM [SiteCode $SiteCode ($($virtualMachine.cmInstallDir))]"
    }

    if ($virtualMachine.siteCode -and -not $virtualMachine.cmInstallDir) {
        $SiteCode = $virtualMachine.siteCode
        if ($virtualMachine.parentSiteCode) {
            $SiteCode += "->$($virtualMachine.parentSiteCode)"
        }
        $name += "  CM [SiteCode $SiteCode]"
        if ($virtualMachine.role -eq "DPMP") {
            if ($virtualMachine.installMP) {
                $name += " [MP]"
            }
            if ($virtualMachine.installDP) {
                $name += " [DP]"
            }
        }
    }

    if ($virtualMachine.remoteSQLVM) {
        $name += "  Remote SQL [$($virtualMachine.remoteSQLVM)]"
    }

    if ($virtualMachine.sqlVersion -and -not $virtualMachine.sqlInstanceDir) {
        $name += "  SQL [$($virtualMachine.sqlVersion)]"
    }

    if ($virtualMachine.sqlVersion -and $virtualMachine.sqlInstanceDir) {
        $name += "  SQL [$($virtualMachine.sqlVersion), "
        $name += "$($virtualMachine.sqlInstanceName) ($($virtualMachine.sqlInstanceDir))]"
    }

    return "$name"
}

function Add-NewVMForRole {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Role")]
        [String] $Role,
        [Parameter(Mandatory = $true, HelpMessage = "Domain Name")]
        [String] $Domain,
        [Parameter(Mandatory = $false, HelpMessage = "Config to Modify")]
        [object] $ConfigToModify = $global:config,
        [Parameter(Mandatory = $false, HelpMessage = "Force VM Name. Otherwise auto-generated")]
        [string] $Name = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Force VM Name for 2nd Node. Otherwise auto-generated")]
        [string] $Name2 = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Parent Side Code if this is a Primary or Secondary in a Hierarchy")]
        [string] $parentSiteCode = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Site Code if this is a PassiveSite or a DPMP")]
        [string] $SiteCode = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Override default OS")]
        [string] $OperatingSystem = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Return Created Machine Name")]
        [bool] $ReturnMachineName = $false,
        [Parameter(Mandatory = $false, HelpMessage = "Quiet Mode")]
        [bool] $Quiet = $false,
        [Parameter(Mandatory = $false, HelpMessage = "Test Mode")]
        [bool] $test = $false,
        [Parameter(Mandatory = $false, HelpMessage = "True if this is the Secondary SQLAO Node")]
        [bool] $secondSQLAO = $false
    )


    $oldConfig = $configToModify | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    Write-Verbose "[Add-NewVMForRole] Start Role: $Role Domain: $Domain Config: $ConfigToModify OS: $OperatingSystem"

    if ([string]::IsNullOrWhiteSpace($OperatingSystem)) {
        if ($role -eq "WorkgroupMember" -or $role -eq "AADClient" -or $role -eq "InternetClient") {
            $operatingSystem = "Windows 10 Latest (64-bit)"
        }
        else {
            $OperatingSystem = "Server 2022"
        }
    }
    $actualRoleName = ($Role -split " ")[0]

    if ($role -eq "SqlServer") {
        $actualRoleName = "DomainMember"
    }

    $memory = "2GB"
    $vprocs = 2

    $installSSMS = $false
    if ($OperatingSystem.Contains("Server")) {
        $memory = "4GB"
        $vprocs = 4
        $installSSMS = $true
    }
    $virtualMachine = [PSCustomObject]@{
        vmName          = $null
        role            = $actualRoleName
        operatingSystem = $OperatingSystem
        memory          = $memory
        virtualProcs    = $vprocs
    }

    if ($role -notin ("OSDCLient", "AADJoined")) {
        $virtualMachine | Add-Member -MemberType NoteProperty -Name 'installSSMS' -Value $installSSMS
    }
    $existingPrimary = $null
    $existingDPMP = $null
    $NewFSServer = $null
    switch ($Role) {
        "SqlServer" {
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'sqlVersion' -Value "SQL Server 2019"
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'sqlInstanceName' -Value "MSSQLSERVER"
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'sqlInstanceDir' -Value "E:\SQL"
            $disk = [PSCustomObject]@{"E" = "120GB" }
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'additionalDisks' -Value $disk
            $virtualMachine.Memory = "8GB"
            $virtualMachine.virtualProcs = 8
            $virtualMachine.operatingSystem = $OperatingSystem
        }
        "SQLAO" {
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'sqlVersion' -Value "SQL Server 2019"
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'sqlInstanceName' -Value "MSSQLSERVER"
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'sqlInstanceDir' -Value "E:\SQL"
            $disk = [PSCustomObject]@{"E" = "120GB" }
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'additionalDisks' -Value $disk
            $virtualMachine.Memory = "8GB"
            $virtualMachine.virtualProcs = 8
            $virtualMachine.operatingSystem = $OperatingSystem

        }
        "CAS" {
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'sqlVersion' -Value "SQL Server 2019"
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'sqlInstanceName' -Value "MSSQLSERVER"
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'sqlInstanceDir' -Value "F:\SQL"
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'cmInstallDir' -Value "E:\ConfigMgr"
            $disk = [PSCustomObject]@{"E" = "250GB"; "F" = "120GB" }
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'additionalDisks' -Value $disk
            $newSiteCode = Get-NewSiteCode $Domain -Role $actualRoleName
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'siteCode' -Value $newSiteCode
            $virtualMachine.Memory = "12GB"
            $virtualMachine.virtualProcs = 8
            $virtualMachine.operatingSystem = $OperatingSystem
            $existingPrimary = ($ConfigToModify.virtualMachines | Where-Object { $_.Role -eq "Primary" } | Measure-Object).Count
            $existingPrimaryVM = $ConfigToModify.virtualMachines | Where-Object { $_.Role -eq "Primary" } | Select-Object -First 1
            if ($existingPrimaryVM) {
                $existingPrimaryVM | Add-Member -MemberType NoteProperty -Name 'parentSiteCode' -Value $newSiteCode -Force
            }
        }
        "Primary" {
            $existingCAS = ($ConfigToModify.virtualMachines | Where-Object { $_.Role -eq "CAS" } | Measure-Object).Count
            if ([string]::IsNullOrWhiteSpace($parentSiteCode)) {
                $parentSiteCode = $null
                if ($existingCAS -eq 1) {
                    $parentSiteCode = ($ConfigToModify.virtualMachines | Where-Object { $_.Role -eq "CAS" } | Select-Object -First 1).SiteCode
                }
            }
            if ($parentSiteCode) {
                $virtualMachine | Add-Member -MemberType NoteProperty -Name 'parentSiteCode' -Value $parentSiteCode
            }
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'sqlVersion' -Value "SQL Server 2019"
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'sqlInstanceName' -Value "MSSQLSERVER"
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'sqlInstanceDir' -Value "F:\SQL"
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'cmInstallDir' -Value "E:\ConfigMgr"
            $disk = [PSCustomObject]@{"E" = "250GB"; "F" = "120GB" }
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'additionalDisks' -Value $disk
            $newSiteCode = Get-NewSiteCode $Domain -Role $actualRoleName
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'siteCode' -Value $newSiteCode
            $virtualMachine.Memory = "12GB"
            $virtualMachine.virtualProcs = 8
            $virtualMachine.operatingSystem = $OperatingSystem
            $existingDPMP = ($ConfigToModify.virtualMachines | Where-Object { $_.Role -eq "DPMP" } | Measure-Object).Count

        }
        "Secondary" {
            $virtualMachine.memory = "4GB"
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'parentSiteCode' -Value $parentSiteCode
            $virtualMachine.operatingSystem = $OperatingSystem
            $newSiteCode = Get-NewSiteCode $Domain -Role $actualRoleName
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'siteCode' -Value $newSiteCode
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'cmInstallDir' -Value 'E:\ConfigMgr'
            $disk = [PSCustomObject]@{"E" = "250GB" }
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'additionalDisks' -Value $disk
            if ($configToModify.virtualMachines.role -contains "CAS" -or $configToModify.virtualMachines.role -contains "Primary" -or $configToModify.virtualMachines.role -contains "Secondary"){
                $network  = Select-Subnet -config $configToModify -CurrentNetworkIsValid:$false
                $virtualMachine | Add-Member -MemberType NoteProperty -Name 'network' -Value $network
            }
        }
        "PassiveSite" {
            $virtualMachine.memory = "4GB"
            $NewFSServer = $true
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'siteCode' -Value $SiteCode
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'cmInstallDir' -Value 'E:\ConfigMgr'
            $disk = [PSCustomObject]@{"E" = "250GB" }
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'additionalDisks' -Value $disk
        }
        "WorkgroupMember" {}
        "InternetClient" {}
        "AADClient" {}
        "DomainMember" { }
        "DomainMember (Server)" { }
        "DomainMember (Client)" {
            if ($OperatingSystem -like "*Server*") {
                $virtualMachine.operatingSystem = "Windows 10 Latest (64-bit)"
            }
            else {
                $virtualMachine.operatingSystem = $OperatingSystem
            }
            $virtualMachine.Memory = "2GB"
        }
        "OSDClient" {
            $virtualMachine.memory = "2GB"
            $virtualMachine.PsObject.Members.Remove('operatingSystem')
        }
        "DPMP" {
            $virtualMachine.memory = "3GB"
            $disk = [PSCustomObject]@{"E" = "250GB" }
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'additionalDisks' -Value $disk
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'installDP' -Value $true
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'installMP' -Value $true
            if (-not $SiteCode) {
                $SiteCode = ($ConfigToModify.virtualMachines | Where-Object { $_.Role -eq "Primary" } | Select-Object -First 1).SiteCode
                if ($test) {
                    $virtualMachine | Add-Member -MemberType NoteProperty -Name 'siteCode' -Value $SiteCode -Force
                }
                else {
                    Get-SiteCodeMenu -property $virtualMachine -name "siteCode" -CurrentValue $SiteCode -ConfigToCheck $configToModify
                }
            }
            else {
                #write-log "Adding new DPMP for sitecode $newSiteCode"
                $virtualMachine | Add-Member -MemberType NoteProperty -Name 'siteCode' -Value $SiteCode -Force
            }
            $siteCode = $virtualMachine.siteCode
            if ((get-RoleForSitecode -ConfigToCheck $ConfigToModify -siteCode $siteCode) -eq "Secondary") {
                $virtualMachine.installMP = $false
            }
        }
        "FileServer" {
            $virtualMachine.memory = "3GB"
            $disk = [PSCustomObject]@{"E" = "500GB"; "F" = "200GB" }
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'additionalDisks' -Value $disk
        }
        "DC" {
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'InstallCA' -Value $true
        }
    }

    if ([string]::IsNullOrWhiteSpace($Name)) {
        if ($virtualMachine.InstallMP -or $virtualMachine.InstallDP) {
            $machineName = Get-NewMachineName -ConfigToCheck $oldConfig -vm $virtualMachine
        }
        else {
            $machineName = Get-NewMachineName -ConfigToCheck $oldConfig -vm $virtualMachine
        }
        Write-Verbose "Machine Name Generated $machineName"
    }
    else {
        $machineName = $Name
    }
    $virtualMachine.vmName = $machineName

    if ($null -eq $ConfigToModify.VirtualMachines) {
        $ConfigToModify.virtualMachines = @()
    }

    $ConfigToModify.virtualMachines += $virtualMachine

    if ($role -eq "Primary" -or $role -eq "CAS" -or $role -eq "PassiveSite" -or $role -eq "DPMP" -or $role -eq "Secondary") {
        if ($null -eq $ConfigToModify.cmOptions) {
            $newCmOptions = [PSCustomObject]@{
                version                   = "current-branch"
                install                   = $true
                updateToLatest            = $false
                pushClientToDomainMembers = $true
            }
            $ConfigToModify | Add-Member -MemberType NoteProperty -Name 'cmOptions' -Value $newCmOptions
        }
    }

    if ($existingPrimary -eq 0) {
        Add-NewVMForRole -Role Primary -Domain $Domain -ConfigToModify $ConfigToModify -OperatingSystem $OperatingSystem -Quiet:$Quiet
    }

    if ($existingPrimary -gt 0) {
        ($ConfigToModify.virtualMachines | Where-Object { $_.Role -eq "Primary" } | Select-Object -First 1).parentSiteCode = ($ConfigToModify.virtualMachines | Where-Object { $_.Role -eq "CAS" } | Select-Object -First 1).siteCode
    }

    if ($existingDPMP -eq 0) {
        if (-not $newSiteCode) {
            $newSiteCode = ($ConfigToModify.virtualMachines | Where-Object { $_.Role -eq "Primary" } | Select-Object -First 1).SiteCode
        }
        if (-not $test) {
            Write-Host "New Primary server found. Adding new DPMP for sitecode $newSiteCode"
        }
        Add-NewVMForRole -Role DPMP -Domain $Domain -ConfigToModify $ConfigToModify -OperatingSystem $OperatingSystem -SiteCode $newSiteCode -Quiet:$Quiet
    }
    if ($Role -eq "SQLAO" -and (-not $secondSQLAO)) {
        write-host "$($virtualMachine.VmName) is the 1st SQLAO"
        $SQLAONode = Add-NewVMForRole -Role SQLAO -Domain $Domain -ConfigToModify $ConfigToModify -OperatingSystem $OperatingSystem -Name $Name2 -secondSQLAO:$true -Quiet:$Quiet -ReturnMachineName:$true
        $virtualMachine | Add-Member -MemberType NoteProperty -Name 'OtherNode' -Value $SQLAONode
        if ($test -eq $false ) {
            $FSName = select-FileServerMenu -ConfigToModify $ConfigToModify -HA:$false
            $virtualMachine | Add-Member -MemberType NoteProperty -Name 'fileServerVM' -Value $FSName
        }
        #$virtualMachine | Add-Member -MemberType NoteProperty -Name 'SQLAgentAccount' -Value "SqlAgentUser"
        #$virtualMachine | Add-Member -MemberType NoteProperty -Name 'SqlServiceAccount' -Value "SqlServiceUser"
        $ClusterName = Get-NewMachineName -vm $virtualMachine -ConfigToCheck $ConfigToModify -ClusterName:$true -SkipOne:$true
        $virtualMachine | Add-Member -MemberType NoteProperty -Name 'ClusterName' -Value $ClusterName
        $AOName = Get-NewMachineName -vm $virtualMachine -ConfigToCheck $ConfigToModify -AOName:$true -SkipOne:$true
        $virtualMachine | Add-Member -MemberType NoteProperty -Name 'AlwaysOnName' -Value $AOName

        $ServiceAccount = "$($ClusterName)Svc"
        $AgentAccount = "$($ClusterName)Agent"

        $virtualMachine | Add-Member -MemberType NoteProperty -Name 'SqlServiceAccount' -Value $ServiceAccount
        $virtualMachine | Add-Member -MemberType NoteProperty -Name 'SqlAgentAccount' -Value $AgentAccount

        $otherNode = $ConfigToModify.VirtualMachines | Where-Object { $_.vmName -eq $SQLAONode }
        $otherNode | Add-Member -MemberType NoteProperty -Name 'SqlServiceAccount' -Value $ServiceAccount
        $otherNode | Add-Member -MemberType NoteProperty -Name 'SqlAgentAccount' -Value $AgentAccount


    }
    if ($NewFSServer -eq $true) {
        #Get-PSCallStack | out-host
        $FSName = select-FileServerMenu -ConfigToModify $ConfigToModify -HA:$true
        $virtualMachine | Add-Member -MemberType NoteProperty -Name 'remoteContentLibVM' -Value $FSName
    }
    #Get-PSCallStack | out-host
    if (-not $Quiet) {
        Write-Host -ForegroundColor Yellow "New Virtual Machine $machineName ($role) was added"
    }
    Write-verbose "[Add-NewVMForRole] Config: $ConfigToModify"
    if ($ReturnMachineName) {
        return $machineName
    }
}



function select-FileServerMenu {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, HelpMessage = "Display HA message")]
        [bool] $HA = $false,
        [Parameter(Mandatory = $false, HelpMessage = "Config to Modify")]
        [object] $ConfigToModify = $global:config
    )
    #Get-PSCallStack | Out-Host
    $result = $null
    if ((Get-ListOfPossibleFileServers -Config $ConfigToModify).Count -eq 0) {
        $result = "n"
    }

    $additionalOptions = @{}
    if ($HA) {
        $additionalOptions += @{ "N" = "Create new FileServer to host Content Library" }
    }
    else {
        $additionalOptions += @{ "N" = "Create a New FileServer VM" }
    }
    while ([string]::IsNullOrWhiteSpace($result)) {
        $result = Get-Menu "Select FileServer VM" $(Get-ListOfPossibleFileServers -Config $ConfigToModify) -Test:$false -additionalOptions $additionalOptions
    }
    switch ($result.ToLowerInvariant()) {
        "n" {
            $result = Add-NewVMForRole -Role "FileServer" -Domain $ConfigToModify.vmOptions.DomainName -ConfigToModify $ConfigToModify -ReturnMachineName:$true
        }
    }
    return $result
}
function Get-ListOfPossibleFileServers {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, HelpMessage = "Config")]
        [object] $Config = $global:config
    )
    $FSList = @()
    $FS = $Config.virtualMachines | Where-Object { $_.role -eq "FileServer" }
    foreach ($item in $FS) {
        $FSList += $item.vmName
    }
    $domain = $Config.vmOptions.DomainName
    if ($null -ne $domain) {
        $FSFromList = get-list -type VM -domain $domain | Where-Object { $_.role -eq "FileServer" }
        foreach ($item in $FSFromList) {
            $FSList += $item.vmName
        }
    }
    else {
        if ($null -ne $Config ) {
            Write-Verbose $Config | ConvertTo-Json | Out-Host
        }
        else {
            write-host "Config was null!"
            Get-PSCallStack | Out-Host
        }
    }
    return $FSList
}


function Select-VirtualMachines {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, HelpMessage = "pre supplied response")]
        [string] $response = $null
    )
    while ($true) {
        Write-Host
        Write-Verbose "8 Select-VirtualMachines"
        if (-not $response) {
            $i = 0
            #$valid = Get-TestResult -SuccessOnError
            foreach ($virtualMachine in $global:config.virtualMachines) {
                $i = $i + 1
                $name = Get-VMString $virtualMachine
                write-Option "$i" "$($name)"
            }
            write-Option -color DarkGreen -Color2 Green "N" "New Virtual Machine"
            $response = get-ValidResponse "Which VM do you want to modify" $i $null "n"
        }
        Write-Log -HostOnly -Verbose "response = $response"
        if (-not [String]::IsNullOrWhiteSpace($response)) {
            if ($response.ToLowerInvariant() -eq "n") {
                #$role = Select-RolesForNew
                $role = Select-RolesForExisting -enhance:$false
                if (-not $role) {
                    return
                }
                if ($role -eq "H") {
                    $role = "PassiveSite"
                }

                $os = Select-OSForNew -Role $role
                $parentSiteCode = Get-ParentSiteCodeMenu -role $role -CurrentValue $null -Domain $Global:Config.vmOptions.domainName

                if ($role -eq "Secondary") {
                    if (-not $parentSiteCode) {
                        return
                    }
                }

                if ($role -eq "PassiveSite") {
                    $domain = $global:config.vmOptions.DomainName
                    $existingPassive = @()
                    $existingSS = @()

                    $existingPassive = Get-List -Type VM -Domain $domain | Where-Object { $_.Role -eq "PassiveSite" }
                    $existingSS = Get-List -Type VM -Domain $domain | Where-Object { $_.Role -eq "CAS" -or $_.Role -eq "Primary" }

                    $exisitingPassive += $global:config.virtualMachines | Where-Object { $_.Role -eq "PassiveSite" }
                    $existingSS += $global:config.virtualMachines | Where-Object { $_.Role -eq "CAS" -or $_.Role -eq "Primary" }

                    $existingSS = $existingSS | Where-Object { $_ }
                    $exisitingPassive = $exisitingPassive | Where-Object { $_ }

                    $PossibleSS = @()
                    foreach ($item in $existingSS) {
                        if ($existingPassive.SiteCode -contains $item.Sitecode) {
                            continue
                        }
                        $PossibleSS += $item
                    }

                    if ($PossibleSS.Count -eq 0) {
                        Write-Host
                        Write-Host "No siteservers found that are elegible for HA"
                        return
                    }
                    $result = Get-Menu -Prompt "Select sitecode to expand to HA" -OptionArray $PossibleSS.Sitecode -Test $false
                    if ([string]::IsNullOrWhiteSpace($result)) {
                        return
                    }
                    $SiteCode = $result
                }


                $machineName = Add-NewVMForRole -Role $Role -Domain $Global:Config.vmOptions.domainName -ConfigToModify $global:config -OperatingSystem $os -parentSiteCode $parentSiteCode -SiteCode $siteCode -ReturnMachineName $true
                if ($role -eq "DC") {
                    $Global:Config.vmOptions.domainName = select-NewDomainName
                    $Global:Config.vmOptions.prefix = get-PrefixForDomain -Domain $($Global:Config.vmOptions.domainName)
                }
                Get-TestResult -SuccessOnError | out-null
                if (-not $machineName) {
                    return
                }
            }
            :VMLoop while ($true) {
                $i = 0
                foreach ($virtualMachine in $global:config.virtualMachines) {
                    $i = $i + 1
                    if ($i -eq $response -or ($machineName -and $machineName -eq $virtualMachine.vmName)) {
                        $newValue = "Start"
                        while ($newValue -ne "D" -and -not ([string]::IsNullOrWhiteSpace($($newValue)))) {
                            Write-Log -HostOnly -Verbose "NewValue = '$newvalue'"
                            $customOptions = [ordered]@{ "*B1" = ""; "*B" = "---  Disks%cyan%cyan"; "A" = "Add Additional Disk" }
                            if ($null -eq $virtualMachine.additionalDisks) {
                            }
                            else {
                                $customOptions += [ordered]@{"R" = "Remove Last Additional Disk" }
                            }
                            if (($virtualMachine.Role -eq "Primary") -or ($virtualMachine.Role -eq "CAS")) {
                                $customOptions += [ordered]@{"*B2" = ""; "*S" = "---  ConfigMgr%cyan"; "S" = "Configure SQL (Set local or remote [Standalone or Always-On] SQL)" }
                                $PassiveNode = $global:config.virtualMachines | Where-Object { $_.role -eq "PassiveSite" -and $_.siteCode -eq $virtualMachine.siteCode }
                                if ($PassiveNode) {
                                    $customOptions += [ordered]@{"H" = "Remove High Availibility (HA) - Removes the Passive Site Server" }
                                }
                                else {
                                    $customOptions += [ordered]@{"H" = "Enable High Availibility (HA) - Adds a Passive Site Server" }
                                }
                            }
                            else {
                                if ($virtualMachine.Role -eq "DomainMember") {
                                    if (-not $virtualMachine.domainUser) {
                                        $customOptions += [ordered]@{"*U" = ""; "*U2" = "---  Domain User (This account will be made a local admin)%cyan"; "U" = "Add domain user as admin on this machine" }
                                    }
                                    else {
                                        $customOptions += [ordered]@{"*U" = ""; "*U2" = "---  Domain User%cyan"; "U" = "Remove domainUser from this machine" }
                                    }
                                }
                                if ($virtualMachine.OperatingSystem -and $virtualMachine.OperatingSystem.Contains("Server") -and -not ($virtualMachine.Role -eq "DC")) {
                                    if ($null -eq $virtualMachine.sqlVersion) {
                                        if ($virtualMachine.Role -eq "Secondary") {
                                            $customOptions += [ordered]@{"*B2" = ""; "*S" = "---  SQL%cyan"; "S" = "Use Full SQL for Secondary Site" }
                                        }
                                        else {
                                            $customOptions += [ordered]@{"*B2" = ""; "*S" = "---  SQL%cyan"; "S" = "Add SQL" }
                                        }
                                    }
                                    else {
                                        if ($virtualMachine.Role -eq "Secondary") {
                                            $customOptions += [ordered]@{"*B2" = ""; "*S" = "---  SQL%cyan"; "X" = "Remove Full SQL and use SQL Express for Secondary Site" }
                                        }
                                        else {
                                            if ($virtualMachine.Role -ne "SQLAO") {
                                                $customOptions += [ordered]@{"*B2" = ""; "*S" = "---  SQL%cyan"; "X" = "Remove SQL" }
                                            }
                                        }
                                    }
                                }
                            }

                            $customOptions += [ordered]@{"*B3" = ""; "*D" = "---  VM Management%cyan"; "D" = "Delete this VM%Red%Red" }
                            $newValue = Select-Options -propertyEnum $global:config.virtualMachines -PropertyNum $i -prompt "Which VM property to modify" -additionalOptions $customOptions -Test:$true
                            if (([string]::IsNullOrEmpty($newValue))) {
                                return
                            }
                            if ($newValue -eq "REFRESH") {
                                continue VMLoop
                            }
                            if ($null -ne $newValue -and $newValue -is [string]) {
                                $newValue = [string]$newValue.Trim()
                                #Write-Host "NewValue = '$newValue'"
                                $newValue = [string]$newValue.ToUpper()
                            }
                            if (([string]::IsNullOrEmpty($newValue))) {
                                break VMLoop
                            }
                            if ($newValue -eq "H") {
                                $PassiveNode = $global:config.virtualMachines | Where-Object { $_.role -eq "PassiveSite" -and $_.siteCode -eq $virtualMachine.siteCode }
                                if ($PassiveNode) {
                                    $FSVM = $global:config.virtualMachines | Where-Object { $_.vmName -eq $PassiveNode.remoteContentLibVM }
                                    if ($FSVM) {
                                        Remove-VMFromConfig -vmName $FSVM.vmName -ConfigToModify $global:config
                                    }
                                    #$virtualMachine.psobject.properties.remove('remoteContentLibVM')
                                    Remove-VMFromConfig -vmName $PassiveNode.vmName -ConfigToModify $global:config
                                }
                                else {
                                    Add-NewVMForRole -Role "PassiveSite" -Domain $global:config.vmOptions.domainName -ConfigToModify $global:config -Name $($virtualMachine.vmName + "-P")  -SiteCode $virtualMachine.siteCode
                                }
                                continue VMLoop

                            }
                            if ($newValue -eq "U") {
                                if ($virtualMachine.domainUser) {
                                    $virtualMachine.psobject.properties.remove('domainUser')
                                }
                                else {
                                    Get-DomainUser -property $virtualMachine -name "domainUser"
                                    #$virtualMachine | Add-Member -MemberType NoteProperty -Name 'domainUser' -Value "bob"
                                }
                            }
                            if ($newValue -eq "S") {
                                if ($virtualMachine.Role -eq "Primary" -or $virtualMachine.Role -eq "CAS") {
                                    Get-remoteSQLVM -property $virtualMachine
                                    continue VMLoop
                                }
                                else {
                                    $virtualMachine | Add-Member -MemberType NoteProperty -Name 'sqlVersion' -Value "SQL Server 2019"
                                    $virtualMachine | Add-Member -MemberType NoteProperty -Name 'sqlInstanceDir' -Value "C:\SQL"
                                    $virtualMachine | Add-Member -MemberType NoteProperty -Name 'sqlInstanceName' -Value "MSSQLSERVER"
                                    $virtualMachine.virtualProcs = 4
                                    if ($($virtualMachine.memory) / 1GB -lt "4GB" / 1GB) {
                                        $virtualMachine.memory = "4GB"
                                    }
                                    if ($virtualMachine.role -eq "Secondary") {
                                        if ($($virtualMachine.memory) / 1GB -lt "6GB" / 1GB) {
                                            $virtualMachine.memory = "6GB"
                                        }
                                    }

                                    $newName = Get-NewMachineName -vm $virtualMachine
                                    if ($($virtualMachine.vmName) -ne $newName) {
                                        $rename = $true
                                        $response = Read-Host2 -Prompt "Rename $($virtualMachine.vmName) to $($newName)? (Y/n)" -HideHelp
                                        if (-not [String]::IsNullOrWhiteSpace($response)) {
                                            if ($response.ToLowerInvariant() -eq "n" -or $response.ToLowerInvariant() -eq "no") {
                                                $rename = $false
                                            }
                                        }
                                        if ($rename -eq $true) {
                                            $virtualMachine.vmName = $newName
                                        }
                                    }

                                }
                            }
                            if ($newValue -eq "X") {
                                $virtualMachine.psobject.properties.remove('sqlversion')
                                $virtualMachine.psobject.properties.remove('sqlInstanceDir')
                                $virtualMachine.psobject.properties.remove('sqlInstanceName')
                                $newName = Get-NewMachineName -vm $virtualMachine
                                if ($($virtualMachine.vmName) -ne $newName) {
                                    $rename = $true
                                    $response = Read-Host2 -Prompt "Rename $($virtualMachine.vmName) to $($newName)? (Y/n)" -HideHelp
                                    if (-not [String]::IsNullOrWhiteSpace($response)) {
                                        if ($response.ToLowerInvariant() -eq "n" -or $response.ToLowerInvariant() -eq "no") {
                                            $rename = $false
                                        }
                                    }
                                    if ($rename -eq $true) {
                                        $virtualMachine.vmName = $newName
                                    }
                                }
                            }
                            if ($newValue -eq "A") {
                                if ($null -eq $virtualMachine.additionalDisks) {
                                    $disk = [PSCustomObject]@{"E" = "120GB" }
                                    $virtualMachine | Add-Member -MemberType NoteProperty -Name 'additionalDisks' -Value $disk
                                }
                                else {
                                    $letters = 69
                                    $virtualMachine.additionalDisks | Get-Member -MemberType NoteProperty | ForEach-Object {
                                        $letters++
                                    }
                                    if ($letters -lt 90) {
                                        $letter = $([char]$letters).ToString()
                                        $virtualMachine.additionalDisks | Add-Member -MemberType NoteProperty -Name $letter -Value "120GB"
                                    }
                                }
                            }
                            if ($newValue -eq "R") {
                                $diskscount = 0
                                $virtualMachine.additionalDisks | Get-Member -MemberType NoteProperty | ForEach-Object {
                                    $diskscount++
                                }
                                if ($diskscount -eq 1) {
                                    $virtualMachine.psobject.properties.remove('additionalDisks')
                                }
                                else {
                                    $i = 0
                                    $virtualMachine.additionalDisks | Get-Member -MemberType NoteProperty | ForEach-Object {
                                        $i = $i + 1
                                        if ($i -eq $diskscount) {
                                            $virtualMachine.additionalDisks.psobject.properties.remove($_.Name)
                                        }
                                    }
                                }
                                if ($diskscount -eq 1) {
                                    $virtualMachine.psobject.properties.remove('additionalDisks')
                                }
                            }
                            if (-not ($newValue -eq "D")) {
                                Get-TestResult -SuccessOnError | out-null
                            }
                        }
                        break VMLoop
                    }
                }
            }
            if ($newValue -eq "D") {
                $i = 0
                $removeVM = $true
                foreach ($virtualMachine in $global:config.virtualMachines) {
                    $i = $i + 1
                    if ($i -eq $response) {
                        $response = Read-Host2 -Prompt "Are you sure you want to remove $($virtualMachine.vmName)? (Y/n)" -HideHelp
                        if ($response.ToLowerInvariant() -eq "n" -or $response.ToLowerInvariant() -eq "no") {
                        }
                        else {
                            if ($virtualMachine.role -eq "FileServer") {
                                $passiveVMs = $global:config.virtualMachines | Where-Object { $_.role -eq "PassiveSite" }
                                if ($passiveVMs) {
                                    foreach ($passiveVM in $PassiveVMs) {
                                        if ($passiveVM.remoteContentLibVM -eq $virtualMachine.vmName) {
                                            Write-Host
                                            write-host -ForegroundColor Yellow "This VM is currently used as the RemoteContentLib for $($passiveVM.vmName) and can not be deleted at this time."
                                            $removeVM = $false
                                        }
                                    }
                                }
                                $SQLAOVMs = $global:config.virtualMachines | Where-Object { $_.role -eq "SQLAO" -and $_.fileServerVM }
                                if ($SQLAOVMs) {
                                    foreach ($SQLAOVM in $SQLAOVMs) {
                                        if ($SQLAOVM.fileServerVM -eq $virtualMachine.vmName) {
                                            Write-Host
                                            write-host -ForegroundColor Yellow "This VM is currently used as the fileServerVM for $($SQLAOVM.vmName) and can not be deleted at this time."
                                            $removeVM = $false
                                        }
                                    }
                                }
                            }
                            if ($virtualMachine.role -eq "SQLAO") {
                                if (-not ($virtualMachine.OtherNode)) {
                                    Write-Host
                                    write-host -ForegroundColor Yellow "This VM is Secondary node in a SQLAO cluster. Please delete the Primary node to remove both VMs"
                                    $removeVM = $false
                                }
                                else {
                                    Remove-VMFromConfig -vmName $virtualMachine.OtherNode -ConfigToModify $global:config
                                }
                            }
                            if ($removeVM -eq $true) {
                                Remove-VMFromConfig -vmName $virtualMachine.vmName -ConfigToModify $global:config
                            }

                        }
                    }
                }
                return
            }
        }
        else {
            Get-TestResult -SuccessOnError | Out-Null
            return
        }
    }
}

function Remove-VMFromConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Name of VM to remove.")]
        [string] $vmName,
        [Parameter(Mandatory = $false, HelpMessage = "Config to modify")]
        [object] $configToModify = $global:config
    )
    $DeletedVM = $null
    $newvm = $configToModify.virtualMachines | ConvertTo-Json | ConvertFrom-Json
    $configToModify.virtualMachines = @()
    foreach ($virtualMachine in $newvm) {

        if ($virtualMachine.vmName -ne $vmName) {
            $configToModify.virtualMachines += $virtualMachine
        }
        else {
            $DeletedVM = $virtualMachine
        }
    }
    if ($DeletedVM.Role -eq "CAS") {
        $primaryParentSideCode = ($ConfigToModify.virtualMachines | Where-Object { $_.Role -eq "Primary" } | Select-Object -First 1).parentSiteCode
        if ($primaryParentSideCode -eq $DeletedVM.SiteCode) {
            ($ConfigToModify.virtualMachines | Where-Object { $_.Role -eq "Primary" } | Select-Object -First 1).parentSiteCode = $null
        }

    }
}

function Save-Config {
    [CmdletBinding()]
    param (
        [Parameter()]
        [object]
        $config
    )
    Write-Host
    Write-Verbose "9 Save-Config"



    $file = "$($config.vmOptions.domainName)"
    if ($config.vmOptions.existingDCNameWithPrefix) {
        $file += "-ADD-"
    }
    elseif (-not $config.cmOptions) {
        $file += "-NOSCCM-"
    }
    elseif ($Config.virtualMachines | Where-Object { $_.Role.ToLowerInvariant() -eq "cas" }) {
        $file += "-CAS-$($config.cmOptions.version)-"
    }
    elseif ($Config.virtualMachines | Where-Object { $_.Role.ToLowerInvariant() -eq "primary" }) {
        $file += "-PRI-$($config.cmOptions.version)-"
    }

    $file += "$($config.virtualMachines.Count)VMs"
    $date = Get-Date -Format "yyyy-MM-dd"
    $file = $date + "-" + $file

    $filename = Join-Path $configDir $file
    if ($Global:configfile) {
        $filename = [System.Io.Path]::GetFileNameWithoutExtension(($Global:configfile).Name)
        $filename = Join-Path $configDir $filename
        $fullFilename = Join-Path $configDir (($Global:configfile).Name)
        $contentEqual = (Get-Content $fullFileName | ConvertFrom-Json | ConvertTo-Json -Depth 5 -Compress) -eq
                ($config | ConvertTo-Json -Depth 5 -Compress)
        if ($contentEqual) {
            return Split-Path -Path $fileName -Leaf
        }
        else {
            # Write-Host "Content Not Equal"
            # (Get-Content $fullFilename | ConvertFrom-Json| ConvertTo-Json -Depth 5) | out-host
            # ($config | ConvertTo-Json -Depth 5) | out-host
        }
    }
    $splitpath = Split-Path -Path $fileName -Leaf
    $response = Read-Host2 -Prompt "Save Filename" -currentValue $splitpath -HideHelp

    if (-not [String]::IsNullOrWhiteSpace($response)) {
        $filename = Join-Path $configDir $response
    }

    if (!$filename.EndsWith(".json")) {
        $filename += ".json"
    }

    $config | ConvertTo-Json -Depth 5 | Out-File $filename
    #$return.ConfigFileName = Split-Path -Path $fileName -Leaf
    Write-Host "Saved to $filename"
    Write-Host
    Write-Verbose "11"
    return Split-Path -Path $fileName -Leaf
}

# Automatically update DSC.Zip
if ($Common.DevBranch) {
    $psdLastWriteTime = (Get-ChildItem ".\DSC\TemplateHelpDSC\TemplateHelpDSC.psd1").LastWriteTime
    $psmLastWriteTime = (Get-ChildItem ".\DSC\TemplateHelpDSC\TemplateHelpDSC.psm1").LastWriteTime
    if (Test-Path ".\DSC\DSC.zip") {
        $zipLastWriteTime = (Get-ChildItem ".\DSC\DSC.zip").LastWriteTime + (New-TimeSpan -Minutes 1)
    }
    if (-not $zipLastWriteTime -or ($psdLastWriteTime -gt $zipLastWriteTime) -or ($psmLastWriteTime -gt $zipLastWriteTime)) {
        & ".\dsc\createGuestDscZip.ps1" | Out-Host
        Set-Location $PSScriptRoot | Out-Null
    }
}

$Global:SavedConfig = $null
do {
    $Global:Config = $null
    $Global:configfile = $null
    $Global:Config = Select-ConfigMenu

    # $DeployConfig = (Test-Configuration -InputObject $Global:Config).DeployConfig

    $valid = $false
    while ($valid -eq $false) {
        $global:StartOver = $false
        $return.DeployNow = Select-MainMenu
        if ($global:StartOver -eq $true) {
            Write-Host -ForegroundColor Yellow "Saving Configuration... use ""!"" to return."
            $Global:SavedConfig = $global:config
            Write-Host
            break
        }
        if ($return.DeployNow -is [PSCustomObject]) {
            return $return.DeployNow
        }
        $c = Test-Configuration -InputObject $Global:Config
        Write-Host
        Write-Verbose "12"

        if ($c.Valid) {
            $valid = $true
        }
        else {
            if ($return.DeployNow -eq $false) {
                write-host -ForegroundColor Red "Configuration is not valid. Saving is not advised. Proceed with caution. Hit CTRL-C to exit.`r`n"
                Write-ValidationMessages -TestObject $c
                $valid = $true
                break
            }
            else {
                Write-Host -ForegroundColor Red "Config file is not valid:`r`n"
                Write-ValidationMessages -TestObject $c
                Write-Host -ForegroundColor Red "`r`nPlease fix the problem(s), or hit CTRL-C to exit."
            }
        }

        if ($valid) {
            Show-Summary ($c.DeployConfig)
            Write-Host
            Write-verbose "13"
            if ($return.DeployNow -eq $true) {
                Write-Host -ForegroundColor Green "Please save and exit any RDCMan sessions you have open, as deployment will make modifications to the memlabs.rdg file on the desktop"
            }
            Write-Host "Answering 'no' below will take you back to the previous menu to allow you to make modifications"
            $response = Read-Host2 -Prompt "Everything correct? (Y/n)" -HideHelp
            if (-not [String]::IsNullOrWhiteSpace($response)) {
                if ($response.ToLowerInvariant() -eq "n" -or $response.ToLowerInvariant() -eq "no") {
                    $valid = $false
                }
                else {
                    break
                }
            }
            else {
                break
            }
        }
    }
} while ($null -ne $Global:SavedConfig -and $global:StartOver -eq $true)

$return.ConfigFileName = Save-Config $Global:Config

if (-not $InternalUseOnly.IsPresent) {
    Write-Host "You may deploy this configuration by running the following command:"
    Write-Host "$($PSScriptRoot)\New-Lab.ps1 -Configuration ""$($return.ConfigFileName)"""
}

#================================= NEW LAB SCENERIO ============================================
if ($InternalUseOnly.IsPresent) {
    $domainExists = Get-List -Type VM -DomainName $Global:Config.vmOptions.domainName
    if ($domainExists) {
        write-host -ForegroundColor Green "This configuration will make modifications to $($Global:Config.vmOptions.DomainName)"
        Write-OrangePoint -NoIndent "Without a snapshot, if something fails it may not be possible to recover"
        $response = Read-Host2 -Prompt "Do you wish to take a Hyper-V snapshot of the domain now? (Y/n)" -HideHelp
        if ([String]::IsNullOrWhiteSpace($response) -or $response.ToLowerInvariant() -eq "y" -or $response.ToLowerInvariant() -eq "yes" ) {
            Select-StopDomain -domain $Global:Config.vmOptions.DomainName -response "C"
            $filename = $splitpath = Split-Path -Path $return.ConfigFileName -Leaf
            $comment = [System.Io.Path]::GetFileNameWithoutExtension($filename)
            if ($comment -ne $splitpath) {
                get-SnapshotDomain -domain $Global:Config.vmOptions.DomainName -comment $comment
            }
            else {
                get-SnapshotDomain -domain $Global:Config.vmOptions.DomainName
            }
            Select-StartDomain -domain $Global:Config.vmOptions.DomainName -response "C"
        }
    }
    return $return
}

