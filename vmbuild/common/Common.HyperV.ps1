function Get-VM2 {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $vmFromList = Get-List -Type VM -SmartUpdate | Where-Object { $_.vmName -eq $Name }

    if ($vmFromList) {
        return (Get-VM -Id $vmFromList.vmId)
    }
    else {
        return [System.Management.Automation.Internal.AutomationNull]::Value
    }
}

function Start-VM2 {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $false)]
        [switch]$Passthru
    )

    $vm = Get-VM2 -Name $Name

    if ($vm) {
        try {
            Start-VM -VM $vm -ErrorAction Stop
            if ($Passthru.IsPresent) {
                return $true
            }
        }
        catch {
            Write-Log "$Name`: Failed to start VM. $($_.Exception.Message)" -Failure
            if ($Passthru.IsPresent) {
                return $false
            }
        }
    }
    else {
        if ($Passthru.IsPresent) {
            Write-Log "$Name`: VM was not found in Hyper-V." -Warning
            return $false
        }
    }
}