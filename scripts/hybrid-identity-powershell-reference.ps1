<#
.SYNOPSIS
    Active Directory & Microsoft Entra ID Hybrid Identity - PowerShell Reference
    Environment: DC01, arthurlab.test (Windows Server 2025, Entra Cloud Sync, Hyper-V)

.DESCRIPTION
    Consolidates the PowerShell/console commands documented while building a
    hybrid identity environment connecting on-premises Active Directory to
    Microsoft Entra ID via Microsoft Entra Cloud Sync, in workflow order,
    with a short explanation of why each command was used.

    Note: several commands are intentionally repeated at different
    checkpoints (e.g. Get-ADUser, Get-DnsServerForwarder). Those repetitions
    are validation steps, not duplicates -- they show before/after state and
    are useful evidence when explaining troubleshooting or lifecycle testing.

.NOTES
    Author: Anthony Arthur
    Full write-up with screenshots: ../README.md
#>

# ---------------------------------------------------------------------------
# Environment and server validation
# ---------------------------------------------------------------------------

# Confirmed the Windows Server VM hostname was DC01.
hostname

# Validated the Active Directory domain/forest configuration.
Get-ADDomain

# Verified the server operating system and build.
Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion, OsBuildNumber

# Checked the VM's assigned physical memory in bytes.
Get-CimInstance Win32_ComputerSystem | Select-Object TotalPhysicalMemory

# Converted the VM memory value to GB for easier validation.
Get-CimInstance Win32_ComputerSystem | Select-Object `
    @{Name="RAM_GB";Expression={[math]::Round($_.TotalPhysicalMemory/1GB,2)}}

# Checked free and used space on the DC01 C: drive before installing Cloud Sync components.
Get-PSDrive C

# Reviewed PowerShell execution policy at each scope.
Get-ExecutionPolicy -List

# Verified the installed .NET Framework release value.
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' | Select-Object Release

# ---------------------------------------------------------------------------
# DNS and Microsoft cloud connectivity troubleshooting
# ---------------------------------------------------------------------------

# Confirmed DC01 was using its local AD DNS service rather than a public resolver.
Get-DnsClientServerAddress -AddressFamily IPv4

# Inspected configured DNS forwarders and identified the stale forwarder.
Get-DnsServerForwarder

# Reviewed DC01 IPv4 address, gateway, DHCP and DNS configuration.
ipconfig /all

# Removed the stale DNS forwarder that was preventing reliable external resolution.
Remove-DnsServerForwarder -IPAddress 172.30.224.1 -Force

# Added a working upstream DNS forwarder while keeping DC01 pointed at its own AD DNS service.
Add-DnsServerForwarder -IPAddress 1.1.1.1

# Verified the updated DNS forwarder configuration.
Get-DnsServerForwarder

# Cleared cached DNS responses after correcting the forwarder.
Clear-DnsClientCache

# Validated DNS resolution for Microsoft's sign-in endpoint.
Resolve-DnsName login.microsoftonline.com

# Validated outbound HTTPS connectivity from DC01 to Microsoft services.
Test-NetConnection login.microsoftonline.com -Port 443

# ---------------------------------------------------------------------------
# Active Directory UPN preparation
# ---------------------------------------------------------------------------

# Reviewed AD users and their existing UPNs before hybrid synchronization.
Get-ADUser -Filter * -Properties UserPrincipalName |
    Select-Object Name, SamAccountName, UserPrincipalName | Format-Table -AutoSize

# Set the pilot user's UPN to the tenant-compatible alternative suffix used for the hybrid identity lab.
Set-ADUser dwilson -UserPrincipalName "dwilson@aarthur89gmail.onmicrosoft.com"

# Verified David Wilson's updated UPN.
Get-ADUser dwilson -Properties UserPrincipalName | Select-Object Name,SamAccountName,UserPrincipalName

# ---------------------------------------------------------------------------
# Provisioning agent discovery and launch
# ---------------------------------------------------------------------------

# Attempted to launch the provisioning agent executable (produced trace output).
& "C:\Program Files\Microsoft Azure AD Connect Provisioning Agent\AADConnectProvisioningAgent.exe"

# Located the installed Microsoft Entra provisioning agent executables.
Get-ChildItem "C:\Program Files" -Recurse -Filter "*Provisioning*.exe" -ErrorAction SilentlyContinue |
    Select-Object FullName

# Launched the Microsoft Entra provisioning agent configuration wizard.
& "C:\Program Files\Microsoft Azure AD Connect Provisioning Agent\AADConnectProvisioningAgentWizard.exe"

# Service-health check for the Microsoft Entra provisioning agent during troubleshooting/recovery.
Get-Service -Name AADConnectProvisioningAgent

# ---------------------------------------------------------------------------
# Pilot security group and synchronization scope
# ---------------------------------------------------------------------------

# Created the dedicated security group used to limit Cloud Sync to a controlled pilot.
New-ADGroup `
    -Name "GG-Entra-CloudSync-Pilot" `
    -SamAccountName "GG-Entra-CloudSync-Pilot" `
    -GroupCategory Security `
    -GroupScope Global `
    -Path "OU=ArthurLab Groups,DC=arthurlab,DC=test"

# Added David Wilson as the direct pilot member.
Add-ADGroupMember `
    -Identity "GG-Entra-CloudSync-Pilot" `
    -Members "dwilson"

# Verified that David Wilson was the intended pilot member.
Get-ADGroupMember "GG-Entra-CloudSync-Pilot" | Select-Object Name,SamAccountName,ObjectClass

# ---------------------------------------------------------------------------
# Provision on Demand preparation
# ---------------------------------------------------------------------------

# Retrieved David Wilson's exact distinguished name for the Entra Provision on Demand test.
Get-ADUser dwilson | Select-Object Name,DistinguishedName

# ---------------------------------------------------------------------------
# Automatic attribute synchronization test
# ---------------------------------------------------------------------------

# Captured David's original job title and department before the synchronization test.
Get-ADUser dwilson -Properties Title,Department | Select-Object Name,Title,Department

# Changed David's job title only in on-premises Active Directory.
Set-ADUser dwilson -Title "Senior Sales Representative"

# Verified the title change in AD before waiting for automatic Cloud Sync.
Get-ADUser dwilson -Properties Title,Department | Select-Object Name,Title,Department

# ---------------------------------------------------------------------------
# Hybrid offboarding / leaver test
# ---------------------------------------------------------------------------

# Captured the pre-offboarding baseline showing the source account enabled.
Get-ADUser dwilson -Properties Enabled,Title,Department,UserPrincipalName |
    Select-Object Name,Enabled,Title,Department,UserPrincipalName

# Disabled David Wilson in on-premises AD to simulate a leaver/offboarding event.
Disable-ADAccount -Identity dwilson

# Verified Enabled = False in AD before Cloud Sync propagated the account state to Entra.
Get-ADUser dwilson -Properties Enabled,Title,Department,UserPrincipalName |
    Select-Object Name,Enabled,Title,Department,UserPrincipalName
