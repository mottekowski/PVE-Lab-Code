<#
.SYNOPSIS
    Starts the PVE Lab Azure VMs sequentially after T56 ON.

.DESCRIPTION
    Starts the VMs in the mandatory order:
      1. winadmin01
      2. pve01
      3. pve02
      4. pve03
      5. pbs01

    Before the next VM is started, the script verifies that the current VM
    has reached both of the following Azure instance states:
      - PowerState/running
      - ProvisioningState/succeeded

    If a VM is already running and provisioning succeeded, the script accepts
    that state as healthy and continues. If a VM does not reach the expected
    state within the timeout, the script stops immediately and does not start
    any subsequent VM.

.NOTES
    Project: PVE in Azure
    Script:  Start-PveLabVms.ps1
    Version: 2026.08.17.1
    Scope:   Azure VM startup and Azure instance-state validation only.
             No changes are made inside Windows, Proxmox, Corosync or Ceph.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ResourceGroup = "rg_snb_pve",

    [Parameter()]
    [string]$SubscriptionId,

    [Parameter()]
    [ValidateRange(60, 3600)]
    [int]$TimeoutSeconds = 600,

    [Parameter()]
    [ValidateRange(5, 120)]
    [int]$PollIntervalSeconds = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$VmNames = @(
    "winadmin01",
    "pve01",
    "pve02",
    "pve03",
    "pbs01"
)

function Write-Section {
    param(
        [Parameter(Mandatory)]
        [string]$Title
    )

    Write-Host ""
    Write-Host "======================================================================"
    Write-Host " $Title"
    Write-Host "======================================================================"
}

function Invoke-AzCli {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $output = & az @Arguments 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        $message = ($output | Out-String).Trim()
        throw "Azure CLI command failed (exit code $exitCode): az $($Arguments -join ' ')`n$message"
    }

    return $output
}

function Get-VmAzureState {
    param(
        [Parameter(Mandatory)]
        [string]$VmName
    )

    $raw = Invoke-AzCli -Arguments @(
        "vm", "get-instance-view",
        "--resource-group", $ResourceGroup,
        "--name", $VmName,
        "--output", "json",
        "--only-show-errors"
    )

    $view = (($raw | Out-String) | ConvertFrom-Json)

    $powerStatus = $view.instanceView.statuses |
        Where-Object { $_.code -like "PowerState/*" } |
        Select-Object -First 1

    $provisioningStatus = $view.instanceView.statuses |
        Where-Object { $_.code -like "ProvisioningState/*" } |
        Select-Object -First 1

    $powerCode = if ($null -ne $powerStatus) {
        [string]$powerStatus.code
    }
    else {
        "PowerState/unknown"
    }

    $provisioningCode = if ($null -ne $provisioningStatus) {
        [string]$provisioningStatus.code
    }
    else {
        "ProvisioningState/unknown"
    }

    [pscustomobject]@{
        VmName             = $VmName
        PowerState         = $powerCode
        ProvisioningState  = $provisioningCode
        IsReady            = (
            $powerCode -ieq "PowerState/running" -and
            $provisioningCode -ieq "ProvisioningState/succeeded"
        )
    }
}

function Wait-VmAzureReady {
    param(
        [Parameter(Mandatory)]
        [string]$VmName
    )

    $startedAt = Get-Date
    $deadline = $startedAt.AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        $state = Get-VmAzureState -VmName $VmName
        $elapsed = [int]((Get-Date) - $startedAt).TotalSeconds

        Write-Host ("[{0,3}s] {1,-12} Power={2,-24} Provisioning={3}" -f `
            $elapsed,
            $VmName,
            $state.PowerState,
            $state.ProvisioningState)

        if ($state.IsReady) {
            return $state
        }

        Start-Sleep -Seconds $PollIntervalSeconds
    }

    $lastState = Get-VmAzureState -VmName $VmName
    throw "Timeout while waiting for '$VmName'. Last state: Power=$($lastState.PowerState), Provisioning=$($lastState.ProvisioningState). Subsequent VMs were not started."
}

function Test-Prerequisites {
    Write-Section "PRECHECK"

    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw "Azure CLI 'az' was not found in PATH."
    }

    $accountRaw = Invoke-AzCli -Arguments @(
        "account", "show",
        "--output", "json",
        "--only-show-errors"
    )

    $account = (($accountRaw | Out-String) | ConvertFrom-Json)

    if ([string]::IsNullOrWhiteSpace($SubscriptionId)) {
        Write-Host "Using current Azure CLI subscription context:"
        Write-Host "  Name: $($account.name)"
        Write-Host "  ID:   $($account.id)"
    }
    else {
        if ($account.id -ne $SubscriptionId) {
            Write-Host "Setting Azure CLI subscription context to: $SubscriptionId"
            $null = Invoke-AzCli -Arguments @(
                "account", "set",
                "--subscription", $SubscriptionId,
                "--only-show-errors"
            )
        }

        $accountRaw = Invoke-AzCli -Arguments @(
            "account", "show",
            "--output", "json",
            "--only-show-errors"
        )
        $account = (($accountRaw | Out-String) | ConvertFrom-Json)

        Write-Host "Using Azure CLI subscription context:"
        Write-Host "  Name: $($account.name)"
        Write-Host "  ID:   $($account.id)"
    }

    Write-Host "Resource group: $ResourceGroup"
    Write-Host "VM order:       $($VmNames -join ' -> ')"

    $rgExists = (Invoke-AzCli -Arguments @(
        "group", "exists",
        "--name", $ResourceGroup,
        "--output", "tsv",
        "--only-show-errors"
    ) | Out-String).Trim()

    if ($rgExists -ine "true") {
        throw "Resource group '$ResourceGroup' does not exist in the active subscription."
    }

    Write-Host ""
    Write-Host "Checking all VM resources before any start operation..."

    foreach ($vmName in $VmNames) {
        $foundName = (Invoke-AzCli -Arguments @(
            "vm", "show",
            "--resource-group", $ResourceGroup,
            "--name", $vmName,
            "--query", "name",
            "--output", "tsv",
            "--only-show-errors"
        ) | Out-String).Trim()

        if ($foundName -ine $vmName) {
            throw "VM '$vmName' could not be verified. No VM was started."
        }

        Write-Host "  OK: $vmName"
    }
}

function Start-AndVerifyVm {
    param(
        [Parameter(Mandatory)]
        [string]$VmName,

        [Parameter(Mandatory)]
        [int]$SequenceNumber,

        [Parameter(Mandatory)]
        [int]$SequenceCount
    )

    Write-Section "START $SequenceNumber/$SequenceCount - $VmName"

    $initialState = Get-VmAzureState -VmName $VmName

    Write-Host "Initial state:"
    Write-Host "  Power:        $($initialState.PowerState)"
    Write-Host "  Provisioning: $($initialState.ProvisioningState)"

    if ($initialState.IsReady) {
        Write-Host "Result: $VmName is already running and provisioning succeeded. No start action required."
        return $initialState
    }

    Write-Host "Starting $VmName..."

    $null = Invoke-AzCli -Arguments @(
        "vm", "start",
        "--resource-group", $ResourceGroup,
        "--name", $VmName,
        "--no-wait",
        "--only-show-errors"
    )

    Write-Host "Start request accepted. Waiting for Azure instance state..."

    $finalState = Wait-VmAzureReady -VmName $VmName

    Write-Host "Result: $VmName verified successfully."
    Write-Host "  Power:        $($finalState.PowerState)"
    Write-Host "  Provisioning: $($finalState.ProvisioningState)"

    return $finalState
}

try {
    Write-Section "PVE LAB VM STARTUP"
    Write-Host "This script must be run after the T56 ON access-services step has completed successfully."
    Write-Host "No configuration changes are made inside the guest operating systems."

    Test-Prerequisites

    $results = @()

    for ($i = 0; $i -lt $VmNames.Count; $i++) {
        $vmName = $VmNames[$i]

        $result = Start-AndVerifyVm `
            -VmName $vmName `
            -SequenceNumber ($i + 1) `
            -SequenceCount $VmNames.Count

        $results += [pscustomobject]@{
            Order              = $i + 1
            VmName             = $result.VmName
            PowerState         = $result.PowerState
            ProvisioningState  = $result.ProvisioningState
            Result             = "OK"
        }
    }

    Write-Section "FINAL SUMMARY"
    $results | Format-Table -AutoSize

    Write-Host "All VMs reached the expected Azure state in the required order."
    Write-Host "Next step: perform the separate guest/Proxmox/cluster/Ceph health checks."
    exit 0
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Startup sequence aborted. No subsequent VM will be started." -ForegroundColor Red
    exit 1
}
