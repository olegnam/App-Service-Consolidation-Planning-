# App Service Consolidation Inventory
 
A PowerShell script that inventories App Service in an Azure resource group and exports helpful fields to plan App Service plan consolidation to a CSV file.
 
## Why This Exists
 
Organizations can accumulate unbalanced App Service plans over time. Consolidating those apps onto fewer plans reduces cost, but moving an app is not just a billing change. A move can break network paths, firewall rules, and deployment workflows if the dependencies are not identified first.
 
This script assists in determining dependencies before any app is moved: which apps can share a plan, which apps are tied to specific networking, and which downstream systems may need to be updated.
 
## Requirements
 
- PowerShell 7 or Windows PowerShell 5.1
- The `Az.Accounts` and `Az.Websites` modules
- Read access to the target subscription and resource group
## Usage
 
```powershell
.\AppService_Inventory.ps1
```
 
The script prompts for all input at runtime, including subscription, resource group, export path, and whether to include deployment slot counts. Type `exit` at any prompt to quit.
 
## CSV Columns and Their Planning Value
 
### AppName
 
The name of the App Service. This is the unit you are deciding whether to move.
 
### ResourceGroup
 
The resource group containing the app. Microsoft only allows an app to move to another plan when the source and target plans are in the same resource group, the same region, and the same OS type. Plans must also share the same internal deployment unit (called a webspace), which is determined when the plan is created. If an app lives in a different resource group than the intended target plan, a direct move is not possible and the app must be recreated or restored into the target plan instead.
 
### Location
 
The Azure region of the app. An App Service plan's region cannot be changed, and apps cannot move to a plan in another region. Apps in different regions cannot be consolidated onto the same plan.
 
### State
 
Whether the app is running or stopped. 
 
### OSType
 
Windows or Linux, determined from the app's `Kind` property. Plans are OS specific, and an app can only move to a plan of the same OS type. This column is the first filter for grouping apps into consolidation targets.
 
### ServerFarmId
 
The full resource ID of the App Service plan the app currently runs on. The CSV is sorted by this column, so apps sharing a plan appear together. This shows how densely each plan is used. Plans hosting one or two apps are the most likely consolidation sources.
 
### VNetSubnetResourceId
 
The subnet the app uses for regional virtual network integration, or `None` if the app is not integrated. This column carries the most networking risk in a consolidation effort.
 
Virtual network integration is configured at the plan level. A Windows plan supports up to two virtual network integrations, a Linux plan supports only one, and an individual app can use only one integration at a time. If two apps on different plans use different subnets, consolidating them onto one Linux plan is not possible without redesigning one app's network path.
 
Subnet capacity also matters. Each plan instance consumes one address from the integration subnet, and Windows Containers consume an additional address per app per instance. Microsoft recommends a /26 subnet to cover the maximum scale of a single plan. Moving more apps onto a plan often means scaling that plan out, so confirm the target subnet has room before moving.
 
Apps showing `None` are generally the easiest to move, since they have no subnet dependency.
 
### DeploymentSlotCount
 
The number of nonproduction deployment slots attached to the app. A value of `0` means the app runs only in its production slot. If slot counts were skipped at runtime, the column shows `Skipped`.
 
Slots matter for consolidation for two reasons. First, the target plan's tier must support the number of slots an app already uses. Standard supports only five slots, so an app with more than five cannot move to a Standard plan. Second, settings such as virtual network integration, scale settings, IP restrictions, and custom domains are slot specific. Each slot needs its own review, since the VNet column in this CSV reflects only the production slot.
 
### OutboundIPs
 
The outbound IP addresses the app currently uses when calling external systems such as databases, APIs, and partner endpoints. The address used for any given call is selected at random from this set, so downstream firewalls must allow all of them.
 
This set can change when an app moves between pricing tiers, such as between Standard and PremiumV3, or when an app is deleted and recreated in a different resource group. Before moving an app, use this column to identify every downstream firewall, SQL server rule, or third party allowlist that may need updating.
 
### PossibleOutboundIPs
 
Every outbound IP address the app could use across all pricing tiers available in its deployment unit. Adding this full set to downstream allowlists before a move reduces the risk of an outage caused by an IP change. Note that the Premium V4 tier does not provide a stable set of outbound addresses. If Premium V4 is a target, downstream systems that rely on IP allowlisting will need an alternative approach, such as a NAT gateway through virtual network integration.
 
## Suggested Planning Workflow
 
1. Run the inventory and open the CSV.
2. Remove stopped apps that can be decommissioned.
3. Group the remaining apps by Location, ResourceGroup, and OSType. Only apps within the same group can share a plan through a direct move.
4. Within each group, compare VNetSubnetResourceId values to confirm the target plan can support the required network integrations and has subnet capacity.
5. Check DeploymentSlotCount against the target plan tier's slot limit.
6. Use OutboundIPs and PossibleOutboundIPs to update downstream firewalls and allowlists before moving any app.
## Limitations
 
- The script scans one resource group per run.
- VNet integration is reported for the production slot only.
- Slot lookups suppress errors, so a value of `0` may also appear if the lookup fails due to permissions or throttling. Verify unexpected values in the portal.
## Sample Output
 
All values below are fictional.
 
| AppName | OSType | ServerFarmId (truncated) | VNetSubnetResourceId (truncated) | DeploymentSlotCount |
|---|---|---|---|---|
| contoso-api | Linux | .../serverfarms/asp-linux-01 | .../subnets/snet-apps-01 | 1 |
| contoso-web | Linux | .../serverfarms/asp-linux-01 | .../subnets/snet-apps-01 | 2 |
| contoso-reports | Windows | .../serverfarms/asp-win-03 | None | 0 |
 
## References
 
- [Manage an App Service plan](https://learn.microsoft.com/azure/app-service/app-service-plan-manage)
- [Integrate your app with an Azure virtual network](https://learn.microsoft.com/azure/app-service/overview-vnet-integration)
- [How IP addresses work in App Service](https://learn.microsoft.com/azure/app-service/overview-inbound-outbound-ips)
- [Set up staging environments in Azure App Service](https://learn.microsoft.com/azure/app-service/deploy-staging-slots)
- [Get-AzWebApp](https://learn.microsoft.com/powershell/module/az.websites/get-azwebapp)
 
