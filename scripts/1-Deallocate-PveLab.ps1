#requires -Version 5.1

<#
.SYNOPSIS
    Deallokiert die Azure VMs des PVE Labs nach einem sauberen Shutdown.

.DESCRIPTION
    Das Script verarbeitet folgende VMs:

      - pve01
      - pve02
      - pve03
      - pbs01
      - winadmin01

    Sicherheitsverhalten:
      - Running VMs werden NICHT ausgeschaltet.
      - Bereits deallokierte VMs werden übersprungen.
      - VMs im Status "stopping" werden kurz überwacht.
      - Nur VMs im Status "PowerState/stopped" werden deallokiert.
      - Anschließend wird geprüft, ob alle VMs tatsächlich
        "PowerState/deallocated" erreicht haben.

.REQUIREMENTS
    - Azure CLI (az)
    - gültige Azure CLI Anmeldung
    - Berechtigung zum Lesen und Deallokieren der VMs
#>

param (
    [string]$ResourceGroup = "rg_snb_pve",

    [int]$TimeoutSeconds = 600,

    [int]$PollIntervalSeconds = 5
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$VmNames = @(
    "pve01",
    "pve02",
    "pve03",
    "pbs01",
    "winadmin01"
)


function Get-VmPowerState {

    param (
        [Parameter(Mandatory)]
        [string]$VmName
    )

    $state = az vm get-instance-view `
        --resource-group $ResourceGroup `
        --name $VmName `
        --query "instanceView.statuses[?starts_with(code, 'PowerState/')].code | [0]" `
        --output tsv `
        --only-show-errors

    if ($LASTEXITCODE -ne 0) {
        throw "Power State von VM '$VmName' konnte nicht ermittelt werden."
    }

    return $state.Trim()
}


Write-Host ""
Write-Host "============================================================"
Write-Host " PVE LAB - AZURE VM DEALLOCATION"
Write-Host "============================================================"
Write-Host ""
Write-Host "Resource Group : $ResourceGroup"
Write-Host "VMs            : $($VmNames -join ', ')"
Write-Host ""


# ------------------------------------------------------------
# 1. Azure CLI prüfen
# ------------------------------------------------------------

Write-Host "Pruefe Azure CLI..."

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI 'az' wurde nicht gefunden."
}

$subscriptionId = az account show `
    --query "id" `
    --output tsv `
    --only-show-errors 2>$null

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($subscriptionId)) {
    throw "Keine aktive Azure CLI Session gefunden. Zuerst 'az login' ausfuehren."
}

$subscriptionName = az account show `
    --query "name" `
    --output tsv `
    --only-show-errors

Write-Host "Azure Subscription: $subscriptionName"
Write-Host "Subscription ID   : $subscriptionId"
Write-Host ""


# ------------------------------------------------------------
# 2. Existenz aller VMs pruefen
# ------------------------------------------------------------

Write-Host "Pruefe VMs..."
Write-Host ""

foreach ($vm in $VmNames) {

    $vmId = az vm show `
        --resource-group $ResourceGroup `
        --name $vm `
        --query "id" `
        --output tsv `
        --only-show-errors 2>$null

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($vmId)) {
        throw "VM '$vm' wurde in Resource Group '$ResourceGroup' nicht gefunden."
    }

    Write-Host "  OK: $vm"
}

Write-Host ""


# ------------------------------------------------------------
# 3. Aktuellen Power State pruefen
# ------------------------------------------------------------

Write-Host "Pruefe aktuellen Power State..."
Write-Host ""

$States = @()

foreach ($vm in $VmNames) {

    $state = Get-VmPowerState -VmName $vm

    $States += [PSCustomObject]@{
        VM    = $vm
        State = $state
    }
}

$States | Format-Table -AutoSize


# ------------------------------------------------------------
# 4. Sicherstellen, dass keine VM mehr laeuft
# ------------------------------------------------------------

$runningVMs = $States | Where-Object {
    $_.State -notin @(
        "PowerState/stopped",
        "PowerState/deallocated",
        "PowerState/stopping"
    )
}

if ($runningVMs) {

    Write-Host ""
    Write-Host "ABBRUCH: Folgende VMs sind noch nicht gestoppt:" -ForegroundColor Red

    $runningVMs | Format-Table -AutoSize

    throw "VMs zuerst sauber herunterfahren. Es wurde KEINE Deallocation gestartet."
}


# ------------------------------------------------------------
# 5. Eventuell noch laufenden Shutdown abwarten
# ------------------------------------------------------------

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)

while ($true) {

    $stoppingVMs = @()

    foreach ($vm in $VmNames) {

        $state = Get-VmPowerState -VmName $vm

        if ($state -eq "PowerState/stopping") {
            $stoppingVMs += $vm
        }
    }

    if ($stoppingVMs.Count -eq 0) {
        break
    }

    if ((Get-Date) -ge $deadline) {
        throw "Timeout beim Warten auf den Shutdown: $($stoppingVMs -join ', ')"
    }

    Write-Host "Warte auf Shutdown: $($stoppingVMs -join ', ')"

    Start-Sleep -Seconds $PollIntervalSeconds
}


# ------------------------------------------------------------
# 6. Deallocation starten
# ------------------------------------------------------------

Write-Host ""
Write-Host "Starte Azure Deallocation..."
Write-Host ""

foreach ($vm in $VmNames) {

    $state = Get-VmPowerState -VmName $vm

    if ($state -eq "PowerState/deallocated") {

        Write-Host "  $vm ist bereits deallocated - ueberspringe."

        continue
    }

    if ($state -ne "PowerState/stopped") {

        throw "VM '$vm' hat unerwarteten Status '$state'. Abbruch."
    }

    Write-Host "  Deallocate: $vm"

    az vm deallocate `
        --resource-group $ResourceGroup `
        --name $vm `
        --no-wait `
        --only-show-errors

    if ($LASTEXITCODE -ne 0) {
        throw "Deallocation fuer '$vm' konnte nicht gestartet werden."
    }
}


# ------------------------------------------------------------
# 7. Auf Deallocation warten
# ------------------------------------------------------------

Write-Host ""
Write-Host "Warte auf PowerState/deallocated..."
Write-Host ""

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)

do {

    $allDeallocated = $true
    $currentStates = @()

    foreach ($vm in $VmNames) {

        $state = Get-VmPowerState -VmName $vm

        $currentStates += [PSCustomObject]@{
            VM    = $vm
            State = $state
        }

        if ($state -ne "PowerState/deallocated") {
            $allDeallocated = $false
        }
    }

    Clear-Host

    Write-Host "============================================================"
    Write-Host " PVE LAB - AZURE VM DEALLOCATION STATUS"
    Write-Host "============================================================"
    Write-Host ""

    $currentStates | Format-Table -AutoSize

    if ($allDeallocated) {
        break
    }

    if ((Get-Date) -ge $deadline) {

        Write-Host ""
        Write-Host "TIMEOUT: Nicht alle VMs wurden deallokiert." -ForegroundColor Red

        exit 1
    }

    Start-Sleep -Seconds $PollIntervalSeconds

}
while ($true)


# ------------------------------------------------------------
# 8. Abschluss
# ------------------------------------------------------------

Write-Host ""
Write-Host "============================================================"
Write-Host " ERFOLGREICH"
Write-Host "============================================================"
Write-Host ""

Write-Host "Alle Lab-VMs sind jetzt deallocated:"
Write-Host ""

foreach ($vm in $VmNames) {
    Write-Host "  [OK] $vm"
}

Write-Host ""
Write-Host "Die Compute-Ressourcen der VMs sind damit freigegeben."
Write-Host "Managed Disks und andere Azure-Ressourcen koennen weiterhin Kosten verursachen."
Write-Host ""