<#
.SYNOPSIS
    Places the PVE lab access services into the T55 Cold state.

.DESCRIPTION
    This script has one purpose only:

      - remove the NAT Gateway and its Terraform-managed associations
      - remove the Azure Bastion Host
      - keep both existing Public IP resources unchanged

    The script uses the existing Terraform stack:

      <repo>\terraform\access-services

    Without -Apply the script performs validation and a guarded Terraform plan only.
    With -Apply it applies exactly that validated plan and then checks convergence.

    VM start/stop operations and T56 recreation of NAT Gateway/Bastion are deliberately
    outside the scope of this script.

.NOTES
    Script version: 2026.08.17.5

    Expected repository location:
      <repo>\scripts\Invoke-PveLabAccessServices-Cold.ps1
#>

[CmdletBinding()]
param(
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ScriptVersion = "2026.08.17.5"

# Native commands are checked explicitly via $LASTEXITCODE.
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$RepoRoot = Split-Path -Parent $PSScriptRoot
$TerraformDir = Join-Path $RepoRoot "terraform\access-services"

$PersistentPublicIpAddresses = @(
    "azurerm_public_ip.nat[0]",
    "azurerm_public_ip.bastion[0]"
)

$AllowedDeleteAddresses = @(
    "azurerm_nat_gateway.lab[0]",
    "azurerm_nat_gateway_public_ip_association.lab[0]",
    "azurerm_subnet_nat_gateway_association.pve_lab[0]",
    "azurerm_bastion_host.lab[0]"
)

# Desired T55 Cold state. Public IP resources stay enabled.
$TerraformVariables = @(
    "-var=nat_public_ip_enabled=true",
    "-var=nat_resources_enabled=false",
    "-var=nat_associations_enabled=false",
    "-var=bastion_public_ip_enabled=true",
    "-var=bastion_host_enabled=false"
)

$PlanPath = Join-Path ([System.IO.Path]::GetTempPath()) ("pve-access-cold-{0}.tfplan" -f [Guid]::NewGuid().ToString("N"))
$LocationPushed = $false
$ScriptExitCode = 0

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
    Write-Section "PVE LAB ACCESS SERVICES - T55 COLD"
    Write-Host "Script Version : $ScriptVersion"
    Write-Host "Repository     : $RepoRoot"
    Write-Host "Terraform Dir  : $TerraformDir"
    Write-Host "Apply          : $Apply"

    Write-Section "PRECHECK"

    if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
        throw "Required command 'terraform' was not found in PATH."
    }

    if (-not (Test-Path -LiteralPath $TerraformDir -PathType Container)) {
        throw "Terraform directory does not exist: $TerraformDir"
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

    Write-Section "COLD PLAN"
    Write-Host "Target state:"
    Write-Host "  NAT Public IP      : keep"
    Write-Host "  NAT Gateway        : remove"
    Write-Host "  NAT Associations   : remove"
    Write-Host "  Bastion Public IP  : keep"
    Write-Host "  Bastion Host       : remove"
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

            if ($AllowedDeleteAddresses -notcontains $change.address) {
                throw "Plan guard failed: unexpected managed resource change '$Action $($change.address)'."
            }

            if ($Action -ne "delete") {
                throw "Plan guard failed: '$($change.address)' has action '$Action'; only delete is allowed."
            }

            Write-Host "Allowed delete: $($change.address)"
        }
    }

    if ($ManagedChangeCount -eq 0) {
        Write-Host "No managed changes required. The Terraform stack is already in the Cold target state."
    }
    else {
        Write-Host ""
        Write-Host "Plan guard successful: $ManagedChangeCount managed delete(s), all explicitly allowed."
    }

    Write-Host "Persistent Public IP resources are not part of the planned changes."

    if (-not $Apply) {
        Write-Section "DRY RUN COMPLETE"
        Write-Host "Terraform plan validated successfully."
        Write-Host "No Azure resources were changed."
        Write-Host ""
        Write-Host "To create, validate and apply a new Cold plan, run:"
        Write-Host "  .\scripts\Invoke-PveLabAccessServices-Cold.ps1 -Apply"
    }
    else {
        Write-Section "APPLY COLD PLAN"

        if ($ManagedChangeCount -eq 0) {
            Write-Host "Nothing to apply. The stack is already in the Cold target state."
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

        Write-Section "POSTCHECK - TERRAFORM CONVERGENCE"

        & terraform plan `
            -input=false `
            -lock-timeout=60s `
            -detailed-exitcode `
            @TerraformVariables

        $ConvergenceExitCode = $LASTEXITCODE

        if ($ConvergenceExitCode -eq 2) {
            throw "Convergence check failed: Terraform still plans changes for the Cold target state."
        }

        if ($ConvergenceExitCode -ne 0) {
            throw "Convergence check failed with exit code $ConvergenceExitCode."
        }

        Write-Section "COLD STATE COMPLETE"
        Write-Host "NAT Gateway and NAT associations are removed."
        Write-Host "Bastion Host is removed."
        Write-Host "Both Terraform-managed Public IP resources remain in state."
        Write-Host "Terraform reports no further managed changes for the Cold target state."
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
