<#
    Prompts the operator for all required variables at runtime.
    Inventories App Services and exports key consolidation planning fields to CSV:
    ServerFarmId, OS Type, VNet Subnet Resource IDs, Slot Counts, and Outbound IPs.
#>

function Read-HostOrExit {
    param (
        [string]$Prompt,
        [string]$Default
    )
    $response = (Read-Host $Prompt).Trim()
    if ($response -eq 'exit') {
        Write-Host "`nExiting script. Goodbye." -ForegroundColor Yellow
        exit 0
    }
    if ([string]::IsNullOrWhiteSpace($response) -and $Default) {
        return $Default
    }
    return $response
}

# ── Authentication Check ──────────────────────────────────────────────────────
$context = Get-AzContext
if (-not $context) {
    Write-Host "`nNo active Azure session detected. Launching Connect-AzAccount..." -ForegroundColor Yellow
    Connect-AzAccount
    $context = Get-AzContext
    if (-not $context) {
        Write-Error "Authentication failed. Exiting."
        exit 1
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  App Service Consolidation Inventory" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
Write-Host "Connected As   : $($context.Account)" -ForegroundColor Gray
Write-Host "Subscription   : $($context.Subscription.Name)" -ForegroundColor Gray
Write-Host "Subscription ID: $($context.Subscription.Id)`n" -ForegroundColor Gray

# ── Subscription Selection (Optional) ────────────────────────────────────────
$switchSub = Read-HostOrExit -Prompt "Would you like to switch subscriptions? (y/N)"
if ($switchSub -match '^[Yy]$') {
    Get-AzSubscription | Format-Table Name, Id -AutoSize
    $subId = Read-HostOrExit -Prompt "Enter Subscription ID"
    Set-AzContext -SubscriptionId $subId | Out-Null
    $context = Get-AzContext
    Write-Host "Switched to: $($context.Subscription.Name)`n" -ForegroundColor Green
}

# ── Resource Group Input ───────────────────────────────────────────────────────
$ResourceGroupName = Read-HostOrExit -Prompt "Enter the Resource Group name"

# ── Export Path Input ─────────────────────────────────────────────────────────
$defaultExport = ".\AppService_Inventory_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$ExportPath    = Read-HostOrExit -Prompt "Enter export path for CSV (press Enter to use default: $defaultExport)" -Default $defaultExport

# Validate export directory exists
$exportDir = Split-Path -Path $ExportPath -Parent

# If the path given is an existing directory, auto-append a filename
if (Test-Path -Path $ExportPath -PathType Container) {
    $ExportPath = Join-Path -Path $ExportPath -ChildPath "AppService_Inventory_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    Write-Host "  Directory detected. File will be saved as: $ExportPath" -ForegroundColor Yellow
} elseif ($exportDir -and -not (Test-Path $exportDir)) {
    Write-Warning "Directory '$exportDir' does not exist. Defaulting to current directory."
    $ExportPath = $defaultExport
}

# ── Slot Count Toggle ─────────────────────────────────────────────────────────
$includeSlots = Read-HostOrExit -Prompt "`nInclude deployment slot counts? This adds per-app API calls and increases runtime. (Y/n)"
$querySlots   = $includeSlots -notmatch '^[Nn]$'

# ── Confirm Before Running ────────────────────────────────────────────────────
Write-Host "`n----------------------------------------" -ForegroundColor Cyan
Write-Host "  Configuration Summary" -ForegroundColor Cyan
Write-Host "----------------------------------------" -ForegroundColor Cyan
Write-Host "Subscription   : $($context.Subscription.Name)"
Write-Host "Resource Group : $ResourceGroupName"
Write-Host "Export Path    : $ExportPath"
Write-Host "Include Slots  : $querySlots"
Write-Host "----------------------------------------`n" -ForegroundColor Cyan

$confirm = Read-HostOrExit -Prompt "Proceed with inventory? (Y/n)"
if ($confirm -match '^[Nn]$') {
    Write-Host "Cancelled by operator." -ForegroundColor Yellow
    exit 0
}

# ── Data Collection ───────────────────────────────────────────────────────────
Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Retrieving App Services from: $ResourceGroupName..." -ForegroundColor Cyan
$webApps = @(Get-AzWebApp -ResourceGroupName $ResourceGroupName)

if ($webApps.Count -eq 0) {
    Write-Warning "No App Services found in resource group: $ResourceGroupName"
    exit 0
}

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Found $($webApps.Count) App Service(s). Processing...`n" -ForegroundColor Cyan

# ── Inventory Loop ────────────────────────────────────────────────────────────
$totalApps = $webApps.Count
$i = 0

$inventory = foreach ($app in $webApps) {
    $i++
    $percentComplete = [math]::Round(($i / $totalApps) * 100)

    Write-Progress `
        -Activity "Inventorying App Services" `
        -Status "Processing app $i of $totalApps ($percentComplete%) - $($app.Name)" `
        -PercentComplete $percentComplete

    Write-Host "  -> [$i/$totalApps] Processing: $($app.Name)" -ForegroundColor Gray

    # 1. ServerFarmId
    $serverFarmId = $app.ServerFarmId

    # 2. OS Type
    $osType = if ($app.Kind -match 'linux') { 'Linux' } else { 'Windows' }

    # 3. VNet Integration Subnet Resource ID
    $subnetResourceId = if ($app.VirtualNetworkSubnetId) { $app.VirtualNetworkSubnetId } else { 'None' }

    # 4. Deployment Slot Count (conditional)
    $slotCount = 'Skipped'
    if ($querySlots) {
        $slots = Get-AzWebAppSlot `
            -ResourceGroupName $app.ResourceGroup `
            -Name $app.Name `
            -ErrorAction SilentlyContinue
        $slotCount = @($slots).Count
    }

    # 5. Outbound IPs
    $outboundIPs         = $app.OutboundIpAddresses
    $possibleOutboundIPs = $app.PossibleOutboundIpAddresses

    [PSCustomObject]@{
        AppName              = $app.Name
        ResourceGroup        = $app.ResourceGroup
        Location             = $app.Location
        State                = $app.State
        OSType               = $osType
        ServerFarmId         = $serverFarmId
        VNetSubnetResourceId = $subnetResourceId
        DeploymentSlotCount  = $slotCount
        OutboundIPs          = $outboundIPs
        PossibleOutboundIPs  = $possibleOutboundIPs
    }
}

# Clear progress bar
Write-Progress -Activity "Inventorying App Services" -Completed

# ── Export ────────────────────────────────────────────────────────────────────
$sorted = $inventory | Sort-Object ServerFarmId, AppName
$sorted | Export-Csv -Path $ExportPath -NoTypeInformation

Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Export complete  : $ExportPath" -ForegroundColor Green
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Apps Inventoried : $(@($inventory).Count)`n" -ForegroundColor Green

# ── Console Summary ───────────────────────────────────────────────────────────
$sorted | Format-Table AppName, OSType, DeploymentSlotCount, VNetSubnetResourceId -AutoSize
