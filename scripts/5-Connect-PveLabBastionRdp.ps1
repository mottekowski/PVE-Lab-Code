[CmdletBinding()]
param(
    [string]$ResourceGroup = "rg_snb_pve",
    [string]$BastionName = "vnet_snb_pve_bastion",
    [string]$VmName = "winadmin01",
    [string]$SubscriptionId,
    [int]$TimeoutSeconds = 600,
    [int]$PollIntervalSeconds = 10,
    [switch]$CheckOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Section {
    param([Parameter(Mandatory = $true)][string]$Title)

    Write-Host ""
    Write-Host "======================================================================"
    Write-Host " $Title"
    Write-Host "======================================================================"
}

function Invoke-AzJson {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $output = & az @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed: az $($Arguments -join ' ')"
    }

    $text = ($output -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    return ($text | ConvertFrom-Json)
}

function Invoke-AzText {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $output = & az @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed: az $($Arguments -join ' ')"
    }

    return (($output -join "`n").Trim())
}

function Get-BastionState {
    return Invoke-AzJson -Arguments @(
        "network", "bastion", "show",
        "--name", $BastionName,
        "--resource-group", $ResourceGroup,
        "--query", "{Name:name,ProvisioningState:provisioningState,Sku:sku.name,EnableTunneling:enableTunneling,DnsName:dnsName,PublicIpId:ipConfigurations[0].publicIPAddress.id}",
        "--output", "json",
        "--only-show-errors"
    )
}

function Get-VmPowerState {
    return Invoke-AzText -Arguments @(
        "vm", "get-instance-view",
        "--resource-group", $ResourceGroup,
        "--name", $VmName,
        "--query", "instanceView.statuses[?starts_with(code, 'PowerState/')].code | [0]",
        "--output", "tsv",
        "--only-show-errors"
    )
}

Write-Section -Title "PVE LAB BASTION RDP"
Write-Host "Resource group: $ResourceGroup"
Write-Host "Bastion:       $BastionName"
Write-Host "Target VM:     $VmName"

Write-Section -Title "PRECHECK - AZURE CLI"

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI ('az') was not found in PATH."
}

try {
    $account = Invoke-AzJson -Arguments @(
        "account", "show",
        "--query", "{Name:name,Id:id}",
        "--output", "json",
        "--only-show-errors"
    )
}
catch {
    throw "Azure CLI is not logged in or the account context cannot be read. Run 'az login' and retry. Details: $($_.Exception.Message)"
}

if (-not [string]::IsNullOrWhiteSpace($SubscriptionId)) {
    if ($account.Id -ne $SubscriptionId) {
        Write-Host "Switching Azure CLI subscription context to: $SubscriptionId"
        & az account set --subscription $SubscriptionId --only-show-errors
        if ($LASTEXITCODE -ne 0) {
            throw "Could not switch Azure CLI subscription context to '$SubscriptionId'."
        }

        $account = Invoke-AzJson -Arguments @(
            "account", "show",
            "--query", "{Name:name,Id:id}",
            "--output", "json",
            "--only-show-errors"
        )
    }
}

Write-Host "Azure subscription:"
Write-Host "  Name: $($account.Name)"
Write-Host "  ID:   $($account.Id)"

Write-Section -Title "PRECHECK - BASTION HOST"

try {
    $bastion = Get-BastionState
}
catch {
    throw "Bastion Host '$BastionName' was not found or could not be queried in resource group '$ResourceGroup'. Details: $($_.Exception.Message)"
}

Write-Host "Initial Bastion state:"
Write-Host "  Provisioning:  $($bastion.ProvisioningState)"
Write-Host "  SKU:           $($bastion.Sku)"
Write-Host "  Tunneling:     $($bastion.EnableTunneling)"
Write-Host "  DNS name:      $($bastion.DnsName)"

if ($bastion.ProvisioningState -ne "Succeeded") {
    Write-Host "Bastion is not ready yet. Waiting for ProvisioningState/Succeeded..."

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    do {
        Start-Sleep -Seconds $PollIntervalSeconds
        $bastion = Get-BastionState
        Write-Host ("[{0,3}s] Bastion Provisioning={1}" -f [int]$stopwatch.Elapsed.TotalSeconds, $bastion.ProvisioningState)

        if ($bastion.ProvisioningState -eq "Failed") {
            throw "Bastion provisioning state is 'Failed'. RDP will not be started."
        }
    }
    until (
        $bastion.ProvisioningState -eq "Succeeded" -or
        $stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds
    )

    $stopwatch.Stop()

    if ($bastion.ProvisioningState -ne "Succeeded") {
        throw "Timeout after $TimeoutSeconds seconds waiting for Bastion ProvisioningState/Succeeded."
    }
}

if ($bastion.Sku -notin @("Standard", "Premium")) {
    throw "Bastion SKU '$($bastion.Sku)' is not suitable for the expected native-client RDP workflow. Expected Standard or Premium."
}

if ($bastion.EnableTunneling -ne $true) {
    throw "Native Client Support / Bastion tunneling is not enabled. RDP will not be started."
}

if ([string]::IsNullOrWhiteSpace([string]$bastion.DnsName)) {
    throw "Bastion has no DNS endpoint. RDP will not be started."
}

if ([string]::IsNullOrWhiteSpace([string]$bastion.PublicIpId)) {
    throw "No Public IP association was found on the Bastion Host. RDP will not be started."
}

$publicIp = Invoke-AzJson -Arguments @(
    "network", "public-ip", "show",
    "--ids", ([string]$bastion.PublicIpId),
    "--query", "{Name:name,IpAddress:ipAddress,ProvisioningState:provisioningState}",
    "--output", "json",
    "--only-show-errors"
)

Write-Host "Bastion Public IP:"
Write-Host "  Name:          $($publicIp.Name)"
Write-Host "  Address:       $($publicIp.IpAddress)"
Write-Host "  Provisioning:  $($publicIp.ProvisioningState)"

if ($publicIp.ProvisioningState -ne "Succeeded" -or [string]::IsNullOrWhiteSpace([string]$publicIp.IpAddress)) {
    throw "The Bastion Public IP is not ready. RDP will not be started."
}

Write-Host "Result: Bastion configuration is ready for native-client RDP."

Write-Section -Title "PRECHECK - TARGET VM"

try {
    $vmId = Invoke-AzText -Arguments @(
        "vm", "show",
        "--resource-group", $ResourceGroup,
        "--name", $VmName,
        "--query", "id",
        "--output", "tsv",
        "--only-show-errors"
    )
}
catch {
    throw "Target VM '$VmName' was not found or could not be queried. Details: $($_.Exception.Message)"
}

if ([string]::IsNullOrWhiteSpace($vmId)) {
    throw "Azure returned no resource ID for VM '$VmName'."
}

$vmProvisioningState = Invoke-AzText -Arguments @(
    "vm", "show",
    "--resource-group", $ResourceGroup,
    "--name", $VmName,
    "--query", "provisioningState",
    "--output", "tsv",
    "--only-show-errors"
)

$vmPowerState = Get-VmPowerState

Write-Host "VM state:"
Write-Host "  Power:         $vmPowerState"
Write-Host "  Provisioning:  $vmProvisioningState"
Write-Host "  Resource ID:   $vmId"

if ($vmPowerState -ne "PowerState/running") {
    throw "Target VM '$VmName' is not running. Current state: '$vmPowerState'. Run the VM startup script first."
}

if ($vmProvisioningState -ne "Succeeded") {
    throw "Target VM '$VmName' provisioning state is '$vmProvisioningState', not 'Succeeded'. RDP will not be started."
}

Write-Host "Result: Target VM is ready for the Bastion RDP connection attempt."

if ($CheckOnly) {
    Write-Section -Title "CHECK-ONLY RESULT"
    Write-Host "All Azure-side Bastion and target-VM prechecks passed."
    Write-Host "No RDP session was started because -CheckOnly was specified."
    exit 0
}

Write-Section -Title "START RDP VIA AZURE BASTION"
Write-Host "Starting native RDP session with --configure..."
Write-Host ""
Write-Host "Command:"
Write-Host "az network bastion rdp --name `"$BastionName`" --resource-group `"$ResourceGroup`" --target-resource-id `"$vmId`" --configure"
Write-Host ""

& az network bastion rdp `
    --name $BastionName `
    --resource-group $ResourceGroup `
    --target-resource-id $vmId `
    --configure

if ($LASTEXITCODE -ne 0) {
    throw "Azure Bastion RDP command failed with exit code $LASTEXITCODE."
}

Write-Section -Title "RDP COMMAND COMPLETED"
Write-Host "The Azure Bastion RDP command completed without an Azure CLI error."
