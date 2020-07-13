#Requires -modules azureadpreview,Az.Resources,Az.Accounts
#Requires -version 4.0
<#PSScriptInfo
.VERSION 2020.7.10
.GUID 476739f9-d907-4d5a-856e-71f9279955de
.AUTHOR Chad.Cox@microsoft.com
    https://blogs.technet.microsoft.com/chadcox/
    https://github.com/chadmcox
.COMPANYNAME 
.COPYRIGHT This Sample Code is provided for the purpose of illustration only and is not
intended to be used in a production environment.  THIS SAMPLE CODE AND ANY
RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.  We grant You a
nonexclusive, royalty-free right to use and modify the Sample Code and to
reproduce and distribute the object code form of the Sample Code, provided
that You agree: (i) to not use Our name, logo, or trademarks to market Your
software product in which the Sample Code is embedded; (ii) to include a valid
copyright notice on Your software product in which the Sample Code is embedded;
and (iii) to indemnify, hold harmless, and defend Us and Our suppliers from and
against any claims or lawsuits, including attorneys` fees, that arise or result
from the use or distribution of the Sample Code..
.DESCRIPTION 
 Export all azure subscription, resources and management groups along with all the PIM and Role assignments.

Need to add Get-AzUserAssignedIdentity
https://docs.microsoft.com/en-us/powershell/module/az.managedserviceidentity/get-azuserassignedidentity?view=azps-4.3.0
Get-AzKeyVault
https://docs.microsoft.com/en-us/powershell/module/az.keyvault/get-azkeyvault?view=azps-4.3.0
Get-AzApplicationGateway
Also AKS is still a blackhole around ID's

research
https://github.com/JulianHayward/Azure-MG-Sub-Governance-Reporting/blob/master/pwsh/AzGovViz.ps1
https://github.com/rodrigosantosms/azure-subscription-migration/blob/master/export-RBAC.ps1
#>

param($scriptpath="$env:USERPROFILE\Documents\AzureAccessReport")
if(!(test-path $scriptpath)){
    new-item -Path $scriptpath -ItemType Directory
}

#when enumerating large environments this also enumerates all the visual studio subs.  
#the goal of this is to make sure to return the script back to the default sub for later
$default_sub = Get-AzContext

cd $scriptpath

if(!(Get-AzureADCurrentSessionInfo)){
    write-host "Logon to Azure AD"
    Connect-AzureAD
}
if(!(Get-AzSubscription)){
    write-host "logon to Azure"
    Connect-AzAccount
}

#region Supporting Functions
function enumerate-aadgroup{
    param($objectid)
    get-azureadgroupmember -ObjectId $objectid -pv mem | foreach{
        $_ | select @{Name="ObjectID";Expression={$mem.objectId}}, `
            @{Name="ObjectType";Expression={"GroupMember - $($mem.ObjectType)"}}, `
            @{Name="Displayname";Expression={$mem.DisplayName}}, `
            @{Name="SigninName";Expression={$mem.userprincipalname}}
        if($_.group){
            enumerate-aadgroup -ObjectId $_.objectid
        }
    }
}
function check-file{
    param($file)
    if(!(Test-Path $file)){
        write-host "$file not found"
        return $true      
    }elseif(!((Get-Item $file).length/1KB -gt 1/1kb)){
        write-host "$file is empty"
        return $true
    }elseif((get-item -Path .\grpm.tmp).LastWriteTime -lt (get-date).AddDays(-3)){
        write-host "$file is older than 3 days"
        return $true
    }else{
        write-host "$file seems reusable"
        return $false
    }
}
function expand-azuremg{
    param($mg,$mglevel)
    if($mg){
        $hash_mg[$mg] | foreach{
            $_ | select @{Name="ID";Expression={$amg.id}}, `
            @{Name="name";Expression={$amg.displayname}}, `
            @{Name="type";Expression={$amg.type}}, `
            @{Name="ChildID";Expression={$_.Child}}, `
            @{Name="ChildType";Expression={$_.childtype}}, `
            @{Name="Childname";Expression={$_.childname}}, `
            @{Name="Childlevel";Expression={$mglevel}}
            expand-azuremg -mg $_.child -mglevel $($mglevel + 1)
        }
    }
}
#endregion
#region Management Groups Exports
$mg_File = ".\mg.tmp"
if(check-file -file $mg_file){
    write-host "Exporting Azure Management Group Relationships"
    $hash_mg = Get-AzManagementGroup | foreach{
        $_ | where Displayname -eq "Tenant Root Group" | select @{Name="Parent";Expression={"\"}}, @{Name="Child";Expression={$_.id}}, `
        @{Name="childname";Expression={$_.displayname}},@{Name="ChildType";Expression={$_.type}}
        Get-AzManagementGroup -GroupName $_.name -Expand -pv parent | select -ExpandProperty Children | select @{Name="Parent";Expression={$parent.ID}}, @{Name="Child";Expression={$_.id}}, `
        @{Name="childname";Expression={$_.displayname}},@{Name="ChildType";Expression={$_.type}}
    } | group parent -AsHashTable -AsString

    Get-AzManagementGroup -pv amg | foreach{
        $MGLevel = 1
        expand-azuremg -mg $amg.id -mglevel 1
    } | export-csv $mg_File -NoTypeInformation
}

$res_file = ".\res.tmp"
if(check-file -file $res_file){
    write-host "Exporting Azure Management Groups"    
    get-azManagementGroup | select `
        @{Name="ParentID";Expression={$_.id}}, `
        @{Name="ParentName";Expression={$_.displayname}}, `
        @{Name="ParentType";Expression={$_.type}}, `
        @{Name="ResourceID";Expression={$_.ID}}, `
        @{Name="ResourceName";Expression={$_.displayname}}, `
        @{Name="ResourceType";Expression={$_.type}}, `
        ResourceGroupName | export-csv $res_file -NoTypeInformation

    Write-host "Exporting All Azure Subscriptions and Resources"
    get-azsubscription -pv azs | Set-AzContext | foreach{
        $azs | select @{Name="ParentID";Expression={"/subscriptions/$($azs.ID)"}}, `
            @{Name="ParentName";Expression={"$($azs.name)"}}, `
            @{Name="ParentType";Expression={"/subscriptions"}}, `
            @{Name="ResourceID";Expression={"/subscriptions/$($azs.ID)"}}, `
            @{Name="ResourceName";Expression={"$($azs.name)"}}, `
            @{Name="ResourceType";Expression={"/subscriptions"}}, `
            @{Name="ResourceGroupName";Expression={}}
        get-azResource -pv azr | select @{Name="ParentID";Expression={"/subscriptions/$($azs.ID)"}}, `
            @{Name="ParentName";Expression={"$($azs.name)"}}, `
            @{Name="ParentType";Expression={"/subscriptions"}}, `
            @{Name="ResourceID";Expression={$azr.resourceid}}, `
            @{Name="ResourceName";Expression={$azr.name}}, `
            @{Name="ResourceType";Expression={$azr.ResourceType}}, `
            @{Name="ResourceGroupName";Expression={$azr.ResourceGroupName}}
    } | export-csv $res_file -NoTypeInformation -Append
}
#endregion
#region Role Export
$rbac_file = ".\rbac.tmp"
if(check-file -file $rbac_file){
    write-host "Exporting all Azure Role Assignment from Subscriptions"
    get-azsubscription -pv azs | Set-AzContext | foreach{
        get-azRoleAssignment -pv azr | select scope, RoleDefinitionName,RoleDefinitionId,ObjectId,ObjectType, `
            DisplayName,SignInName,AssignmentState, @{Name="AssignmentType";Expression={"azRoleAssignment"}}
    } | select * -unique | export-csv $rbac_file -NoTypeInformation
}

$pim_File = ".\pim.tmp"
if(check-file -file $pim_File){
    write-host "Exporting all Privileged Identity Management Enabled Azure Roles and Members"
    import-csv $rbac_file  | where Displayname -eq "MS-PIM" | group scope -pv azr  | foreach{
        Get-AzureADMSPrivilegedResource -ProviderId AzureResources -filter "externalId eq '$(($azr).name)'" -pv pim | foreach{
            Get-AzureADMSPrivilegedRoleAssignment -ProviderId AzureResources -ResourceId $pim.ID -pv azpra | where MemberType -eq "Direct" | foreach{
                $role = Get-AzureADMSPrivilegedRoleDefinition -ProviderId AzureResources -id $azpra.RoleDefinitionId -ResourceId $azpra.ResourceId
                    Get-AzureADObjectByObjectId -ObjectId $azpra.SubjectId -pv member | select `
                         @{Name="Scope";Expression={$(($azr).name)}}, `
                         @{Name="RoleDefinitionName";Expression={$role.DisplayName}}, `
                         @{Name="RoleDefinitionId";Expression={$azpra.RoleDefinitionId}}, `
                         @{Name="ObjectID";Expression={$azpra.SubjectId}}, `
                         @{Name="ObjectType";Expression={$member.ObjectType}}, `
                         @{Name="Displayname";Expression={$member.DisplayName}}, `
                         @{Name="SigninName";Expression={$member.userprincipalname}}, `
                         @{Name="AssignmentState";Expression={$azpra.AssignmentState}}, `
                         @{Name="AssignmentType";Expression={"PrivilegedRoleAssignment"}}
            }
        }
    } | export-csv $pim_File -notypeinformation
}
#endregion
#region Formatting and Creating Final Report

Set-AzContext -Subscription $default_sub.Subscription

write-host "Creating Azure Resource Lookup Hash Table"
$hash_res = import-csv $res_file | group ParentID -AsHashTable -AsString

write-host "Creating Hash Lookup Table for PIM Enabled Resources"
$hash_pimenabled = import-csv $rbac_file -pv azr | where Displayname -eq "MS-PIM" | group scope -AsHashTable -AsString

$resm_File = ".\AzureResourceRelationShips.csv"
write-host "Mapping Management Groups to subscriptions and resources"
import-csv $mg_File -pv mg | foreach{
    $hash_res[$mg.childid] | select @{Name="ScopeID";Expression={$mg.ID}},@{Name="ScopeName";Expression={$mg.name}}, `
        @{Name="ScopeType";Expression={$mg.Type}},ResourceID,ResourceName,ResourceType,ResourceGroup, `
        @{Name="PIMEnabled";Expression={$hash_pimenabled.ContainsKey($_.resourceid)}}
} | export-csv $resm_File
import-csv $res_file -pv mg | select @{Name="ScopeID";Expression={$_.ResourceID}},@{Name="ScopeName";Expression={$_.ResourceName}}, `
    @{Name="ScopeType";Expression={$_.ResourceType}},ResourceID,ResourceName,ResourceType,ResourceGroup, `
    @{Name="PIMEnabled";Expression={$hash_pimenabled.ContainsKey($_.resourceid)}} | export-csv $resm_File -Append


write-host "Flushing Azure Resource Lookup Hash Table"
$hash_res = @{}

$grpm_File = ".\grpm.tmp"
if(check-file -file $grpm_File){
    write-host "Expanding Azure AD Groups being used in Azure Roles"
    @(import-csv $rbac_file; import-csv $pim_File) | where ObjectType -eq "group" -PipelineVariable grp | foreach{
        enumerate-aadgroup -objectid $_.objectid | select @{Name="Scope";Expression={$grp.scope}}, `
            @{Name="RoleDefinitionName";Expression={$grp.RoleDefinitionName}}, `
            @{Name="RoleDefinitionId";Expression={$grp.RoleDefinitionId}}, `
            ObjectId,ObjectType,DisplayName,SignInName, `
            @{Name="AssignmentState";Expression={$grp.AssignmentState}}, `
            @{Name="AssignmentType";Expression={$grp.AssignmentType}} 
    } | sort scope,objectid | select * -Unique | export-csv $grpm_File -NoTypeInformation
}
$role_File = ".\RoleAssignment.csv"
@(import-csv $rbac_file; import-csv $pim_File; import-csv $grpm_File) | export-csv $role_File -NoTypeInformation