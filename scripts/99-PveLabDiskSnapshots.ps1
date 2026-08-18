[CmdletBinding()]
param(
    [string]$ResourceGroup = "rg_snb_pve",

    [string[]]$VmNames = @(
        "pve01",
        "pve02",
        "pve03",
        "winadmin01"
    ),

    [int]$ExpectedDiskCount = 7,

    [int]$ExpectedTotalGB = 320,

    [string]$Checkpoint = (Get-Date -Format "yyyyMMdd-HHmmss"),

    [switch]$Apply
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
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$AzArguments
    )

    $output = & az @AzArguments --only-show-errors --output json

    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed: az $($AzArguments -join ' ')"
    }

    $text = ($output | Out-String).Trim()

    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    return ($text | ConvertFrom-Json)
}


function Get-ObjectPropertyValue {
    param(
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]

    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function ConvertTo-SafeToken {
    param([Parameter(Mandatory = $true)][string]$Value)

    $token = $Value.ToLowerInvariant()
    $token = $token -replace '[^a-z0-9-]', '-'
    $token = $token -replace '-+', '-'
    return $token.Trim('-')
}

Write-Section "PVE LAB - MANAGED DISK SNAPSHOT"

Write-Host "Mode           : $(if ($Apply) { 'APPLY - snapshots will be created' } else { 'PLAN - read only' })"
Write-Host "Resource Group : $ResourceGroup"
Write-Host "Checkpoint     : $Checkpoint"
Write-Host "Target VMs     : $($VmNames -join ', ')"
Write-Host "Expected Disks : $ExpectedDiskCount"
Write-Host "Expected GB    : $ExpectedTotalGB"

# -----------------------------------------------------------------------------
# 01 - Local prerequisites
# -----------------------------------------------------------------------------
Write-Section "01 - LOCAL PREREQUISITES"

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI 'az' was not found in PATH."
}

$account = Invoke-AzJson -AzArguments @("account", "show")

Write-Host "Azure account  : $($account.user.name)"
Write-Host "Subscription   : $($account.name)"
Write-Host "SubscriptionId : $($account.id)"
Write-Host "TenantId       : $($account.tenantId)"

$rg = Invoke-AzJson -AzArguments @(
    "group", "show",
    "--name", $ResourceGroup
)

Write-Host "Resource Group : $($rg.name)"
Write-Host "RG Location    : $($rg.location)"

# -----------------------------------------------------------------------------
# 02 - VM state inventory
# -----------------------------------------------------------------------------
Write-Section "02 - VM POWER STATE - READ ONLY"

$vmStates = [System.Collections.Generic.List[object]]::new()
$vmObjects = @{}

foreach ($vmName in $VmNames) {
    $vm = Invoke-AzJson -AzArguments @(
        "vm", "show",
        "--resource-group", $ResourceGroup,
        "--name", $vmName
    )

    $instanceView = Invoke-AzJson -AzArguments @(
        "vm", "get-instance-view",
        "--resource-group", $ResourceGroup,
        "--name", $vmName
    )

    $powerStatus = @(
        $instanceView.instanceView.statuses |
            Where-Object { $_.code -like "PowerState/*" }
    ) | Select-Object -First 1

    $powerCode = if ($null -ne $powerStatus) {
        $powerStatus.code
    }
    else {
        "PowerState/unknown"
    }

    $vmStates.Add([PSCustomObject]@{
        VM         = $vmName
        PowerState = ($powerCode -replace '^PowerState/', '')
        PowerCode  = $powerCode
        Location   = $vm.location
    })

    $vmObjects[$vmName] = $vm
}

$vmStates |
    Select-Object VM, PowerState, Location |
    Format-Table -AutoSize

# -----------------------------------------------------------------------------
# 03 - Discover ALL attached managed disks of the target VMs
# -----------------------------------------------------------------------------
Write-Section "03 - MANAGED DISK INVENTORY - READ ONLY"

$inventory = [System.Collections.Generic.List[object]]::new()

foreach ($vmName in $VmNames) {
    $vm = $vmObjects[$vmName]

    # OS disk
    $osDiskId = $vm.storageProfile.osDisk.managedDisk.id

    if ([string]::IsNullOrWhiteSpace($osDiskId)) {
        throw "VM '$vmName' has no managed OS disk ID."
    }

    $osDisk = Invoke-AzJson -AzArguments @(
        "disk", "show",
        "--ids", $osDiskId
    )

    $inventory.Add([PSCustomObject]@{
        VM         = $vmName
        Role       = "os"
        Lun        = $null
        DiskName   = $osDisk.name
        DiskId     = $osDisk.id
        UniqueId   = $osDisk.uniqueId
        SizeGB     = [int64]$osDisk.diskSizeGB
        SKU        = $osDisk.sku.name
        State      = $osDisk.diskState
        Location   = $osDisk.location
    })

    # All managed data disks
    foreach ($dataDisk in @($vm.storageProfile.dataDisks)) {
        if ($null -eq $dataDisk) {
            continue
        }

        $dataDiskId = $dataDisk.managedDisk.id

        if ([string]::IsNullOrWhiteSpace($dataDiskId)) {
            throw "VM '$vmName' contains a data disk without a managed disk ID."
        }

        $disk = Invoke-AzJson -AzArguments @(
            "disk", "show",
            "--ids", $dataDiskId
        )

        $role = if ($vmName -like "pve*") {
            "ceph-osd-lun$($dataDisk.lun)"
        }
        else {
            "data-lun$($dataDisk.lun)"
        }

        $inventory.Add([PSCustomObject]@{
            VM         = $vmName
            Role       = $role
            Lun        = $dataDisk.lun
            DiskName   = $disk.name
            DiskId     = $disk.id
            UniqueId   = $disk.uniqueId
            SizeGB     = [int64]$disk.diskSizeGB
            SKU        = $disk.sku.name
            State      = $disk.diskState
            Location   = $disk.location
        })
    }
}

$duplicates = @(
    $inventory |
        Group-Object DiskId |
        Where-Object { $_.Count -gt 1 }
)

if ($duplicates.Count -gt 0) {
    throw "Duplicate managed disk IDs were discovered. Aborting."
}

$inventory |
    Sort-Object VM, Role |
    Select-Object VM, Role, DiskName, SizeGB, SKU, State, Location |
    Format-Table -AutoSize

$totalGB = ($inventory | Measure-Object -Property SizeGB -Sum).Sum

Write-Host "Discovered disks : $($inventory.Count)"
Write-Host "Total capacity   : $totalGB GB"

$expectedLayout = @{
    pve01      = 2
    pve02      = 2
    pve03      = 2
    winadmin01 = 1
}

foreach ($vmName in $VmNames) {
    if ($expectedLayout.ContainsKey($vmName)) {
        $actualCount = @($inventory | Where-Object { $_.VM -eq $vmName }).Count
        $expectedCount = $expectedLayout[$vmName]

        if ($actualCount -ne $expectedCount) {
            throw "Safety gate failed for VM '$vmName': expected $expectedCount managed disk(s), discovered $actualCount."
        }
    }
}

if ($inventory.Count -ne $ExpectedDiskCount) {
    throw "Safety gate failed: expected $ExpectedDiskCount managed disks, discovered $($inventory.Count). No snapshots will be created."
}

if ($totalGB -ne $ExpectedTotalGB) {
    throw "Safety gate failed: expected $ExpectedTotalGB GB total managed disk capacity, discovered $totalGB GB. No snapshots will be created."
}

# -----------------------------------------------------------------------------
# 04 - Build deterministic snapshot plan
# -----------------------------------------------------------------------------
Write-Section "04 - SNAPSHOT PLAN - READ ONLY"

$existingSnapshots = @(Invoke-AzJson -AzArguments @(
    "snapshot", "list",
    "--resource-group", $ResourceGroup
))

$existingByName = @{}
foreach ($snapshot in $existingSnapshots) {
    $existingByName[$snapshot.name] = $snapshot
}

$plan = [System.Collections.Generic.List[object]]::new()

foreach ($disk in ($inventory | Sort-Object VM, Role)) {
    $vmToken = ConvertTo-SafeToken -Value $disk.VM
    $roleToken = ConvertTo-SafeToken -Value $disk.Role
    $snapshotName = "snap-$vmToken-$roleToken-$Checkpoint"

    if ($snapshotName.Length -gt 80) {
        throw "Snapshot name exceeds 80 characters: $snapshotName"
    }

    $action = "CREATE"

    if ($existingByName.ContainsKey($snapshotName)) {
        $existing = $existingByName[$snapshotName]

        $existingSourceResourceId = Get-ObjectPropertyValue -Object $existing.creationData -Name "sourceResourceId"
        $existingSourceUniqueId = Get-ObjectPropertyValue -Object $existing.creationData -Name "sourceUniqueId"

        if ($existingSourceResourceId -ne $disk.DiskId) {
            throw "Snapshot name collision: '$snapshotName' exists but references another source disk."
        }

        if ($null -ne $existingSourceUniqueId -and
            -not [string]::IsNullOrWhiteSpace([string]$existingSourceUniqueId) -and
            $existingSourceUniqueId -ne $disk.UniqueId) {
            throw "Snapshot '$snapshotName' references a different source disk generation (SourceUniqueId mismatch)."
        }

        if ($existing.incremental -ne $true) {
            throw "Snapshot '$snapshotName' already exists but is not incremental."
        }

        if ($existing.provisioningState -ne "Succeeded") {
            throw "Snapshot '$snapshotName' exists but provisioning state is '$($existing.provisioningState)'."
        }

        $action = "SKIP-EXISTS"
    }

    $plan.Add([PSCustomObject]@{
        VM           = $disk.VM
        Role         = $disk.Role
        DiskName     = $disk.DiskName
        SizeGB       = $disk.SizeGB
        SnapshotName = $snapshotName
        Action       = $action
        DiskId       = $disk.DiskId
        UniqueId     = $disk.UniqueId
        Location     = $disk.Location
    })
}

$plan |
    Select-Object VM, Role, SizeGB, Action, SnapshotName |
    Format-Table -AutoSize

# -----------------------------------------------------------------------------
# 05 - Plan-only stop gate
# -----------------------------------------------------------------------------
if (-not $Apply) {
    Write-Section "05 - STOP GATE"
    Write-Host "PLAN completed successfully."
    Write-Host "No Azure resources were created or changed."
    Write-Host ""
    Write-Host "For the cold snapshot APPLY run, all four target VMs must first be deallocated."
    Write-Host "After the controlled PVE/Ceph shutdown, use the SAME checkpoint for APPLY:"
    Write-Host ".\scripts\99-PveLabDiskSnapshots.ps1 -Checkpoint '$Checkpoint' -Apply"
    exit 0
}

# -----------------------------------------------------------------------------
# 06 - APPLY safety gate: cold-state required
# -----------------------------------------------------------------------------
Write-Section "05 - APPLY SAFETY GATE"

$notDeallocated = @(
    $vmStates |
        Where-Object { $_.PowerCode -ne "PowerState/deallocated" }
)

if ($notDeallocated.Count -gt 0) {
    $stateText = ($notDeallocated | ForEach-Object { "$($_.VM)=$($_.PowerState)" }) -join ", "
    throw "Cold snapshot safety gate failed. All target VMs must be deallocated. Current non-deallocated VMs: $stateText"
}

Write-Host "All target VMs are deallocated."
Write-Host "Disk count safety gate passed: $($inventory.Count) disks."
Write-Host "Snapshot creation is permitted."

# -----------------------------------------------------------------------------
# 07 - Create incremental snapshots
# -----------------------------------------------------------------------------
Write-Section "06 - CREATE INCREMENTAL SNAPSHOTS"

$created = [System.Collections.Generic.List[object]]::new()

foreach ($item in $plan) {
    if ($item.Action -eq "SKIP-EXISTS") {
        Write-Host "SKIP   $($item.SnapshotName)"
        continue
    }

    Write-Host "CREATE $($item.SnapshotName) <- $($item.DiskName)"

    $snapshot = Invoke-AzJson -AzArguments @(
        "snapshot", "create",
        "--resource-group", $ResourceGroup,
        "--name", $item.SnapshotName,
        "--source", $item.DiskId,
        "--location", $item.Location,
        "--sku", "Standard_LRS",
        "--incremental", "true",
        "--tags",
            "Project=PVE-Lab",
            "Purpose=Golden-Checkpoint",
            "Checkpoint=$Checkpoint",
            "SourceVM=$($item.VM)",
            "SourceDisk=$($item.DiskName)",
            "DiskRole=$($item.Role)"
    )

    if ($snapshot.provisioningState -ne "Succeeded") {
        throw "Snapshot '$($item.SnapshotName)' was created but provisioning state is '$($snapshot.provisioningState)'."
    }

    if ($snapshot.incremental -ne $true) {
        throw "Snapshot '$($item.SnapshotName)' was created but is not incremental."
    }

    if ($snapshot.creationData.sourceResourceId -ne $item.DiskId) {
        throw "Snapshot '$($item.SnapshotName)' source verification failed."
    }

    $created.Add([PSCustomObject]@{
        VM                = $item.VM
        Role              = $item.Role
        SnapshotName      = $snapshot.name
        ProvisioningState = $snapshot.provisioningState
        Incremental       = $snapshot.incremental
        Location          = $snapshot.location
        SourceDisk        = $item.DiskName
    })
}

# -----------------------------------------------------------------------------
# 08 - Final verification
# -----------------------------------------------------------------------------
Write-Section "07 - FINAL SNAPSHOT VERIFICATION - READ ONLY"

$finalSnapshots = @(Invoke-AzJson -AzArguments @(
    "snapshot", "list",
    "--resource-group", $ResourceGroup
)) | Where-Object {
    (Get-ObjectPropertyValue -Object $_.tags -Name "Checkpoint") -eq $Checkpoint
}

$verification = foreach ($item in $plan) {
    $snapshot = @(
        $finalSnapshots |
            Where-Object { $_.name -eq $item.SnapshotName }
    ) | Select-Object -First 1

    if ($null -eq $snapshot) {
        [PSCustomObject]@{
            VM                = $item.VM
            Role              = $item.Role
            SnapshotName      = $item.SnapshotName
            State             = "MISSING"
            Incremental       = $null
            SourceMatch       = $false
        }
        continue
    }

    [PSCustomObject]@{
        VM                = $item.VM
        Role              = $item.Role
        SnapshotName      = $snapshot.name
        State             = $snapshot.provisioningState
        Incremental       = $snapshot.incremental
        SourceMatch       = ($snapshot.creationData.sourceResourceId -eq $item.DiskId)
    }
}

$verification | Format-Table -AutoSize

$failed = @(
    $verification |
        Where-Object {
            $_.State -ne "Succeeded" -or
            $_.Incremental -ne $true -or
            $_.SourceMatch -ne $true
        }
)

if ($failed.Count -gt 0) {
    throw "Final verification failed for $($failed.Count) snapshot(s)."
}

Write-Section "SNAPSHOT CHECKPOINT COMPLETE"
Write-Host "Checkpoint       : $Checkpoint"
Write-Host "Target VMs       : $($VmNames.Count)"
Write-Host "Source disks     : $($inventory.Count)"
Write-Host "Source capacity  : $totalGB GB"
Write-Host "Snapshots valid  : $($verification.Count)"
Write-Host "Result           : SUCCESS"
Write-Host ""
Write-Host "No VM was started, stopped, deallocated, deleted, or otherwise modified by this script."
