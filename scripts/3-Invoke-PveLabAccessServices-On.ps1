<#
.SYNOPSIS
    Places the PVE lab access services into the T56 On state.

.DESCRIPTION
    This script has one purpose only:

      - recreate the NAT Gateway and its Terraform-managed associations
      - recreate the Azure Bastion Host
      - reuse both existing Public IP resources unchanged

    The script uses the existing Terraform stack:

      <repo>\terraform\access-services

    Without -Apply the script performs validation, persistent Public IP guards,
    and a guarded Terraform plan only.

    With -Apply it applies exactly that validated plan, performs read-only Azure
    postchecks, and then verifies Terraform convergence.

    VM start/stop operations, Proxmox/Ceph/cluster checks, Bastion RDP tests,
    and T55 Cold operations are deliberately outside the scope of this script.

.NOTES
    Script version: 2026.08.17.1

    Expected repository location:
      <repo>\scripts\Invoke-PveLabAccessServices-On.ps1
#>

[CmdletBinding()]
param(
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ScriptVersion = "2026.08.17.1"

# Native commands are checked explicitly via $LASTEXITCODE.
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$RepoRoot = Split-Path -Parent $PSScriptRoot
$TerraformDir = Join-Path $RepoRoot "terraform\access-services"

$ResourceGroupName = "rg_snb_pve"
$VnetName = "vnet_snb_pve"
$PveSubnetName = "snet-pve-lab"

$NatGatewayName = "nat-snb-pve"
$NatPublicIpName = "pip-nat-snb-pve"
$ExpectedNatPublicIp = "20.234.220.234"

$BastionName = "vnet_snb_pve_bastion"
$BastionPublicIpName = "pip-bas-snb-pve"
$ExpectedBastionPublicIp = "137.117.136.137"

$PersistentPublicIpAddresses = @(
    "azurerm_public_ip.nat[0]",
    "azurerm_public_ip.bastion[0]"
)

$AllowedCreateAddresses = @(
    "azurerm_nat_gateway.lab[0]",
    "azurerm_nat_gateway_public_ip_association.lab[0]",
    "azurerm_subnet_nat_gateway_association.pve_lab[0]",
    "azurerm_bastion_host.lab[0]"
)

# Desired T56 On state. Existing Public IP resources stay enabled and must not change.
$TerraformVariables = @(
    "-var=nat_public_ip_enabled=true",
    "-var=nat_resources_enabled=true",
    "-var=nat_associations_enabled=true",
    "-var=bastion_public_ip_enabled=true",
    "-var=bastion_host_enabled=true"
)

$PlanPath = Join-Path ([System.IO.Path]::GetTempPath()) ("pve-access-on-{0}.tfplan" -f [Guid]::NewGuid().ToString("N"))
$LocationPushed = $false
$ScriptExitCode = 0

$NatPublicIpIdBefore = $null
$BastionPublicIpIdBefore = $null

function Write-Section {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title
    )

    Write-Host ""
    Write-Host "======================================================================"
    Write-Host " $Title"
    Write-Host "======================================================================"
}

try {
    Write-Section "PVE LAB ACCESS SERVICES - T56 ON"
    Write-Host "Script Version : $ScriptVersion"
    Write-Host "Repository     : $RepoRoot"
    Write-Host "Terraform Dir  : $TerraformDir"
    Write-Host "Resource Group : $ResourceGroupName"
    Write-Host "Apply          : $Apply"

    Write-Section "PRECHECK"

    if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
        throw "Required command 'terraform' was not found in PATH."
    }

    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw "Required command 'az' was not found in PATH."
    }

    if (-not (Test-Path -LiteralPath $TerraformDir -PathType Container)) {
        throw "Terraform directory does not exist: $TerraformDir"
    }

    Write-Host "Checking Azure CLI session ..."
    & az account show --only-show-errors --output none 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "No active Azure CLI session. Authenticate with 'az login' before running this script."
    }

    Push-Location $TerraformDir
    $LocationPushed = $true

    Write-Host "Running terraform init ..."
    & terraform init -input=false
    if ($LASTEXITCODE -ne 0) {
        throw "terraform init failed with exit code $LASTEXITCODE."
    }

    Write-Host "Running terraform fmt -check ..."
    & terraform fmt -check
    if ($LASTEXITCODE -ne 0) {
        throw "terraform fmt -check failed with exit code $LASTEXITCODE."
    }

    Write-Host "Running terraform validate ..."
    & terraform validate
    if ($LASTEXITCODE -ne 0) {
        throw "terraform validate failed with exit code $LASTEXITCODE."
    }

    Write-Section "PERSISTENT PUBLIC IP STATE GUARD"

    foreach ($address in $PersistentPublicIpAddresses) {
        & terraform state show $address *> $null
        if ($LASTEXITCODE -ne 0) {
            throw "Persistent Public IP is missing from Terraform state: $address"
        }

        Write-Host "State contains: $address"
    }

    Write-Section "PERSISTENT PUBLIC IP IDENTITY GUARD"

    $NatPipJsonText = (& az network public-ip show `
        --resource-group $ResourceGroupName `
        --name $NatPublicIpName `
        --query "{id:id,name:name,ipAddress:ipAddress,provisioningState:provisioningState}" `
        --only-show-errors `
        --output json 2>&1 | Out-String).Trim()
    $NatPipExitCode = $LASTEXITCODE

    if ($NatPipExitCode -ne 0) {
        throw "Azure CLI failed to read Public IP '$NatPublicIpName' with exit code $NatPipExitCode. $NatPipJsonText"
    }

    if ([string]::IsNullOrWhiteSpace($NatPipJsonText)) {
        throw "Azure CLI returned no data for Public IP '$NatPublicIpName'."
    }

    $NatPip = $NatPipJsonText | ConvertFrom-Json

    if ([string]$NatPip.name -ne $NatPublicIpName) {
        throw "Unexpected NAT Public IP resource name '$($NatPip.name)'; expected '$NatPublicIpName'."
    }

    if ([string]$NatPip.ipAddress -ne $ExpectedNatPublicIp) {
        throw "NAT Public IP address is '$($NatPip.ipAddress)'; expected '$ExpectedNatPublicIp'."
    }

    if ([string]$NatPip.provisioningState -ne "Succeeded") {
        throw "NAT Public IP provisioning state is '$($NatPip.provisioningState)'; expected 'Succeeded'."
    }

    if ([string]::IsNullOrWhiteSpace([string]$NatPip.id)) {
        throw "NAT Public IP '$NatPublicIpName' has no Azure Resource ID."
    }

    $NatPublicIpIdBefore = [string]$NatPip.id
    Write-Host "Verified NAT Public IP     : $NatPublicIpName / $ExpectedNatPublicIp / Succeeded"
    Write-Host "NAT Public IP Resource ID  : $NatPublicIpIdBefore"

    $BastionPipJsonText = (& az network public-ip show `
        --resource-group $ResourceGroupName `
        --name $BastionPublicIpName `
        --query "{id:id,name:name,ipAddress:ipAddress,provisioningState:provisioningState}" `
        --only-show-errors `
        --output json 2>&1 | Out-String).Trim()
    $BastionPipExitCode = $LASTEXITCODE

    if ($BastionPipExitCode -ne 0) {
        throw "Azure CLI failed to read Public IP '$BastionPublicIpName' with exit code $BastionPipExitCode. $BastionPipJsonText"
    }

    if ([string]::IsNullOrWhiteSpace($BastionPipJsonText)) {
        throw "Azure CLI returned no data for Public IP '$BastionPublicIpName'."
    }

    $BastionPip = $BastionPipJsonText | ConvertFrom-Json

    if ([string]$BastionPip.name -ne $BastionPublicIpName) {
        throw "Unexpected Bastion Public IP resource name '$($BastionPip.name)'; expected '$BastionPublicIpName'."
    }

    if ([string]$BastionPip.ipAddress -ne $ExpectedBastionPublicIp) {
        throw "Bastion Public IP address is '$($BastionPip.ipAddress)'; expected '$ExpectedBastionPublicIp'."
    }

    if ([string]$BastionPip.provisioningState -ne "Succeeded") {
        throw "Bastion Public IP provisioning state is '$($BastionPip.provisioningState)'; expected 'Succeeded'."
    }

    if ([string]::IsNullOrWhiteSpace([string]$BastionPip.id)) {
        throw "Bastion Public IP '$BastionPublicIpName' has no Azure Resource ID."
    }

    $BastionPublicIpIdBefore = [string]$BastionPip.id
    Write-Host "Verified Bastion Public IP : $BastionPublicIpName / $ExpectedBastionPublicIp / Succeeded"
    Write-Host "Bastion Public IP Resource ID: $BastionPublicIpIdBefore"

    Write-Section "ON PLAN"
    Write-Host "Target state:"
    Write-Host "  NAT Public IP      : keep existing"
    Write-Host "  NAT Gateway        : present"
    Write-Host "  NAT Associations   : present"
    Write-Host "  Bastion Public IP  : keep existing"
    Write-Host "  Bastion Host       : present"
    Write-Host ""

    & terraform plan `
        -input=false `
        -lock-timeout=60s `
        -detailed-exitcode `
        "-out=$PlanPath" `
        @TerraformVariables

    $PlanExitCode = $LASTEXITCODE
    if ($PlanExitCode -ne 0 -and $PlanExitCode -ne 2) {
        throw "terraform plan failed with exit code $PlanExitCode."
    }

    Write-Section "PLAN GUARD"

    $PlanJsonText = (& terraform show -json $PlanPath | Out-String).Trim()
    $ShowExitCode = $LASTEXITCODE

    if ($ShowExitCode -ne 0) {
        throw "terraform show -json failed with exit code $ShowExitCode."
    }

    if ([string]::IsNullOrWhiteSpace($PlanJsonText)) {
        throw "terraform show -json returned no JSON."
    }

    $PlanJson = $PlanJsonText | ConvertFrom-Json -Depth 100
    $ManagedChangeCount = 0
    $ResourceChangesProperty = $PlanJson.PSObject.Properties["resource_changes"]

    if ($null -ne $ResourceChangesProperty) {
        foreach ($change in $ResourceChangesProperty.Value) {
            if ($change.mode -ne "managed") {
                continue
            }

            $Action = $change.change.actions -join ","

            if ($Action -eq "no-op") {
                continue
            }

            $ManagedChangeCount++

            if ($AllowedCreateAddresses -notcontains $change.address) {
                throw "Plan guard failed: unexpected managed resource change '$Action $($change.address)'."
            }

            if ($Action -ne "create") {
                throw "Plan guard failed: '$($change.address)' has action '$Action'; only create is allowed."
            }

            Write-Host "Allowed create: $($change.address)"
        }
    }

    if ($ManagedChangeCount -gt $AllowedCreateAddresses.Count) {
        throw "Plan guard failed: Terraform contains $ManagedChangeCount managed changes; at most $($AllowedCreateAddresses.Count) explicitly allowed creates are possible."
    }

    if ($ManagedChangeCount -eq 0) {
        Write-Host "No managed changes required. The Terraform stack is already in the On target state."
    }
    else {
        Write-Host ""
        Write-Host "Plan guard successful: $ManagedChangeCount managed create(s), all explicitly allowed."
    }

    Write-Host "Persistent Public IP resources are not part of the planned changes."

    if (-not $Apply) {
        Write-Section "DRY RUN COMPLETE"
        Write-Host "Terraform plan validated successfully."
        Write-Host "No Azure resources were changed."
        Write-Host ""
        Write-Host "To apply this exact On plan, run:"
        Write-Host "  .\scripts\Invoke-PveLabAccessServices-On.ps1 -Apply"
    }
    else {
        Write-Section "APPLY ON PLAN"

        if ($ManagedChangeCount -eq 0) {
            Write-Host "Nothing to apply. The stack is already in the On target state."
        }
        else {
            & terraform apply -input=false $PlanPath
            if ($LASTEXITCODE -ne 0) {
                throw "terraform apply failed with exit code $LASTEXITCODE."
            }
        }

        Write-Section "POSTCHECK - PERSISTENT PUBLIC IPS"

        foreach ($address in $PersistentPublicIpAddresses) {
            & terraform state show $address *> $null
            if ($LASTEXITCODE -ne 0) {
                throw "Postcheck failed: persistent Public IP is missing from Terraform state: $address"
            }

            Write-Host "State still contains: $address"
        }

        $NatPipAfterJsonText = (& az network public-ip show `
            --resource-group $ResourceGroupName `
            --name $NatPublicIpName `
            --query "{id:id,name:name,ipAddress:ipAddress,provisioningState:provisioningState}" `
            --only-show-errors `
            --output json 2>&1 | Out-String).Trim()
        $NatPipAfterExitCode = $LASTEXITCODE

        if ($NatPipAfterExitCode -ne 0) {
            throw "Postcheck failed to read Public IP '$NatPublicIpName' with exit code $NatPipAfterExitCode. $NatPipAfterJsonText"
        }

        $NatPipAfter = $NatPipAfterJsonText | ConvertFrom-Json

        if ([string]$NatPipAfter.id -ne $NatPublicIpIdBefore) {
            throw "NAT Public IP Resource ID changed. Before='$NatPublicIpIdBefore' After='$($NatPipAfter.id)'."
        }

        if ([string]$NatPipAfter.ipAddress -ne $ExpectedNatPublicIp) {
            throw "NAT Public IP address changed. Current='$($NatPipAfter.ipAddress)' Expected='$ExpectedNatPublicIp'."
        }

        if ([string]$NatPipAfter.provisioningState -ne "Succeeded") {
            throw "NAT Public IP provisioning state is '$($NatPipAfter.provisioningState)'; expected 'Succeeded'."
        }

        Write-Host "NAT Public IP unchanged     : $NatPublicIpName / $ExpectedNatPublicIp / Succeeded"

        $BastionPipAfterJsonText = (& az network public-ip show `
            --resource-group $ResourceGroupName `
            --name $BastionPublicIpName `
            --query "{id:id,name:name,ipAddress:ipAddress,provisioningState:provisioningState}" `
            --only-show-errors `
            --output json 2>&1 | Out-String).Trim()
        $BastionPipAfterExitCode = $LASTEXITCODE

        if ($BastionPipAfterExitCode -ne 0) {
            throw "Postcheck failed to read Public IP '$BastionPublicIpName' with exit code $BastionPipAfterExitCode. $BastionPipAfterJsonText"
        }

        $BastionPipAfter = $BastionPipAfterJsonText | ConvertFrom-Json

        if ([string]$BastionPipAfter.id -ne $BastionPublicIpIdBefore) {
            throw "Bastion Public IP Resource ID changed. Before='$BastionPublicIpIdBefore' After='$($BastionPipAfter.id)'."
        }

        if ([string]$BastionPipAfter.ipAddress -ne $ExpectedBastionPublicIp) {
            throw "Bastion Public IP address changed. Current='$($BastionPipAfter.ipAddress)' Expected='$ExpectedBastionPublicIp'."
        }

        if ([string]$BastionPipAfter.provisioningState -ne "Succeeded") {
            throw "Bastion Public IP provisioning state is '$($BastionPipAfter.provisioningState)'; expected 'Succeeded'."
        }

        Write-Host "Bastion Public IP unchanged : $BastionPublicIpName / $ExpectedBastionPublicIp / Succeeded"

        Write-Section "POSTCHECK - AZURE ACCESS SERVICES"

        $NatJsonText = (& az network nat gateway show `
            --resource-group $ResourceGroupName `
            --name $NatGatewayName `
            --query "{id:id,name:name,provisioningState:provisioningState}" `
            --only-show-errors `
            --output json 2>&1 | Out-String).Trim()
        $NatExitCode = $LASTEXITCODE

        if ($NatExitCode -ne 0) {
            throw "NAT Gateway '$NatGatewayName' could not be read with exit code $NatExitCode. $NatJsonText"
        }

        $NatGateway = $NatJsonText | ConvertFrom-Json

        if ([string]$NatGateway.name -ne $NatGatewayName) {
            throw "Unexpected NAT Gateway name '$($NatGateway.name)'; expected '$NatGatewayName'."
        }

        if ([string]$NatGateway.provisioningState -ne "Succeeded") {
            throw "NAT Gateway provisioning state is '$($NatGateway.provisioningState)'; expected 'Succeeded'."
        }

        $NatGatewayId = [string]$NatGateway.id
        if ([string]::IsNullOrWhiteSpace($NatGatewayId)) {
            throw "NAT Gateway '$NatGatewayName' has no Azure Resource ID."
        }

        $NatPipIds = (& az network nat gateway show `
            --resource-group $ResourceGroupName `
            --name $NatGatewayName `
            --query "publicIpAddresses[].id" `
            --only-show-errors `
            --output tsv 2>&1 | Out-String).Trim()
        $NatPipAssociationExitCode = $LASTEXITCODE

        if ($NatPipAssociationExitCode -ne 0) {
            throw "Could not read NAT Gateway Public IP association with exit code $NatPipAssociationExitCode. $NatPipIds"
        }

        if (($NatPipIds -split '\r?\n') -notcontains $NatPublicIpIdBefore) {
            throw "NAT Gateway '$NatGatewayName' is not associated with expected Public IP '$NatPublicIpName'."
        }

        $SubnetNatGatewayId = (& az network vnet subnet show `
            --resource-group $ResourceGroupName `
            --vnet-name $VnetName `
            --name $PveSubnetName `
            --query "natGateway.id" `
            --only-show-errors `
            --output tsv 2>&1 | Out-String).Trim()
        $SubnetExitCode = $LASTEXITCODE

        if ($SubnetExitCode -ne 0) {
            throw "Could not read subnet '$PveSubnetName' NAT Gateway association with exit code $SubnetExitCode. $SubnetNatGatewayId"
        }

        if ($SubnetNatGatewayId -ne $NatGatewayId) {
            throw "Subnet '$PveSubnetName' is not associated with NAT Gateway '$NatGatewayName'."
        }

        Write-Host "NAT Gateway              : $NatGatewayName / Succeeded"
        Write-Host "NAT Public IP association: $NatPublicIpName / verified"
        Write-Host "NAT Subnet association   : $PveSubnetName -> $NatGatewayName / verified"

        $BastionJsonText = (& az network bastion show `
            --resource-group $ResourceGroupName `
            --name $BastionName `
            --query "{id:id,name:name,provisioningState:provisioningState}" `
            --only-show-errors `
            --output json 2>&1 | Out-String).Trim()
        $BastionExitCode = $LASTEXITCODE

        if ($BastionExitCode -ne 0) {
            throw "Bastion Host '$BastionName' could not be read with exit code $BastionExitCode. $BastionJsonText"
        }

        $Bastion = $BastionJsonText | ConvertFrom-Json

        if ([string]$Bastion.name -ne $BastionName) {
            throw "Unexpected Bastion Host name '$($Bastion.name)'; expected '$BastionName'."
        }

        if ([string]$Bastion.provisioningState -ne "Succeeded") {
            throw "Bastion Host provisioning state is '$($Bastion.provisioningState)'; expected 'Succeeded'."
        }

        $BastionPipIds = (& az network bastion show `
            --resource-group $ResourceGroupName `
            --name $BastionName `
            --query "ipConfigurations[].publicIPAddress.id" `
            --only-show-errors `
            --output tsv 2>&1 | Out-String).Trim()
        $BastionPipAssociationExitCode = $LASTEXITCODE

        if ($BastionPipAssociationExitCode -ne 0) {
            throw "Could not read Bastion Public IP association with exit code $BastionPipAssociationExitCode. $BastionPipIds"
        }

        if (($BastionPipIds -split '\r?\n') -notcontains $BastionPublicIpIdBefore) {
            throw "Bastion Host '$BastionName' is not associated with expected Public IP '$BastionPublicIpName'."
        }

        Write-Host "Bastion Host              : $BastionName / Succeeded"
        Write-Host "Bastion Public IP assoc.  : $BastionPublicIpName / verified"

        Write-Section "POSTCHECK - TERRAFORM CONVERGENCE"

        & terraform plan `
            -input=false `
            -lock-timeout=60s `
            -detailed-exitcode `
            @TerraformVariables

        $ConvergenceExitCode = $LASTEXITCODE

        if ($ConvergenceExitCode -eq 2) {
            throw "Convergence check failed: Terraform still plans changes for the On target state."
        }

        if ($ConvergenceExitCode -ne 0) {
            throw "Convergence check failed with exit code $ConvergenceExitCode."
        }

        Write-Section "ON STATE COMPLETE"
        Write-Host "Verified final state:"
        Write-Host "  NAT Public IP       : ON / existing / unchanged"
        Write-Host "  NAT Gateway         : ON / Succeeded"
        Write-Host "  NAT PIP Association : ON / verified"
        Write-Host "  NAT Subnet Assoc.   : ON / verified"
        Write-Host "  Bastion Public IP   : ON / existing / unchanged"
        Write-Host "  Bastion Host        : ON / Succeeded"
        Write-Host "  Terraform           : converged / no changes"
    }
}
catch {
    $ScriptExitCode = 1

    Write-Host ""
    Write-Host "======================================================================"
    Write-Host " ERROR"
    Write-Host "======================================================================"
    Write-Host $_.Exception.Message
}
finally {
    if ($LocationPushed) {
        Pop-Location
    }

    if (Test-Path -LiteralPath $PlanPath -PathType Leaf) {
        try {
            Remove-Item -LiteralPath $PlanPath -Force -ErrorAction Stop
        }
        catch {
            Write-Warning "Could not remove temporary Terraform plan file '$PlanPath': $($_.Exception.Message)"
        }
    }
}

exit $ScriptExitCode
