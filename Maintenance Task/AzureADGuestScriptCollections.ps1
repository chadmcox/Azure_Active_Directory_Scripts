#This will produce a report of every guest object
Get-AzureADUser -Filter "userType eq 'Guest'" -all $true | select objectid, userprincipalname,Mail, usertype, accountenabled,CreationType, `
  UserState, UserStateChangedOn | export-csv .\azureadGuest.csv -NoTypeInformation 
  
 #this will produce a list of guest that show no logons for the last 30 days
 Get-AzureADUser -Filter "userType eq 'Guest'" -all $true -PipelineVariable guest | where {$_.userstate -ne 'PendingAcceptance'} | `
    where {!(Get-AzureADAuditSignInLogs -Filter "userid eq '$($guest.objectid)'" -top 1)} | `
        select objectid, displayname, userprincipalname,Mail,usertype, accountenabled,CreationType, `
            UserState, UserStateChangedOn | export-csv .\azureadGuestNoRecentLogons.csv
            
#this will create a list of guest that are pending acceptance.
Get-AzureADUser -Filter "userType eq 'Guest'" -all $true -PipelineVariable guest | where {$_.userstate -eq 'PendingAcceptance'} | `
    select select objectid, displayname, userprincipalname,Mail,usertype, accountenabled,CreationType, `
            UserState, UserStateChangedOn | export-csv .\azureadGuestInPending.csv 
            
#Disable guest that have been in pending acceptance for longer than 7 days.
Get-AzureADUser -Filter "userType eq 'Guest'" -all $true -PipelineVariable guest | `
    where {($_.userstate -eq 'PendingAcceptance') -and ((get-date $($_.UserStateChangedOn)) -lt $((get-date).adddays(-7)))} | `
        Set-AzureADUser -AccountEnabled $false
 
 #Delete guest that are pending acceptance and disabled for longer than 30 days
 Get-AzureADUser -Filter "userType eq 'Guest'" -all $true -PipelineVariable guest | `
    where {($_.userstate -eq 'PendingAcceptance') -and ((get-date $($_.UserStateChangedOn)) -lt $((get-date).adddays(-30))) -and $_.accountenabled -eq $false} | `
        Remove-AzureADUser

#Disable Users not showing any logons over the last 30 days
Get-AzureADUser -Filter "userType eq 'Guest'" -all $true -PipelineVariable guest | where {$_.userstate -ne 'PendingAcceptance'} | `
    where {!(Get-AzureADAuditSignInLogs -Filter "userid eq '$($guest.objectid)'" -top 1)} | `
        Set-AzureADUser -AccountEnabled $false

#list Guest accounts from known popular personal email
Get-AzureADUser -Filter "userType eq 'Guest'" -all $true -PipelineVariable guest | `
    where {$_.UserPrincipalName -match "gmail.com|hotmail.com|msn.com|ymail.com|aol.com|msn.com|outlook.com|live.com|googlemail.com|yahoo.com"} | `
        select objectid, displayname, userprincipalname,Mail,usertype, accountenabled,CreationType, `
            UserState, UserStateChangedOn | export-csv .\azureadGuestKnownPersonalEmail.csv
 
 #Disable Guest Objects from common personal emails with no recent logons
 Get-AzureADUser -Filter "userType eq 'Guest'" -all $true -PipelineVariable guest | `
    where {$_.UserPrincipalName -match "gmail.com|hotmail.com|msn.com|ymail.com|aol.com|msn.com|outlook.com|live.com|googlemail.com|yahoo.com"} | `
    where {!(Get-AzureADAuditSignInLogs -Filter "userid eq '$($guest.objectid)'" -top 1)} | `
        Set-AzureADUser -AccountEnabled $false
 
            
            
