param (
    [Parameter(Mandatory=$false)][string]$zabbix_url="https://evdetect.sbcore.net/ZBX/api/sender.php"
)

$xml = [XML](Get-Content C:\Temp\p998wph\HealthCheck\domain.xml)

function TrustCert{
add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
    $AllProtocols = [System.Net.SecurityProtocolType]'Ssl3,Tls,Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
}

if (-not ([System.Management.Automation.PSTypeName]'TrustAllCertsPolicy').Type)
{
    TrustCert
}

function send-zabbix {

    param(
        [Parameter(Mandatory=$true)]
        [string]$TargetHost,
        [Parameter(Mandatory=$true)]
        $data,
        [Parameter(Mandatory=$false)]
        [string]$Url
    ) 
    $body = ($data.Keys | % { @{host=$TargetHost; key=$_ ; value=$data[$_]} } | ConvertTo-Json)

    if (!$Url) {
        Write-Host "Zabbix API endpoint not specified...`n$($body | Out-String)"
        return
    }

    try {
        Invoke-WebRequest -Uri $Url -Method POST -Body $body
    } catch [exception] {
        $Host.UI.WriteErrorLine("ERROR: $($_.Exception.Message)")
    }
}

function DomainMonitor{
    param(
        [Parameter(Mandatory=$true)][string]$domain
    )
    
    [string]$DN = (Get-ADDomain -server $domain).DistinguishedName
 
    $SERVER_TRUST_ACCOUNT = 0x2000
    $TRUSTED_FOR_DELEGATION = 0x80000
    $TRUSTED_TO_AUTH_FOR_DELEGATION= 0x1000000
    $PARTIAL_SECRETS_ACCOUNT = 0x4000000  
    $bitmask = $TRUSTED_FOR_DELEGATION -bor $TRUSTED_TO_AUTH_FOR_DELEGATION -bor $PARTIAL_SECRETS_ACCOUNT
 
    # LDAP filter to find all accounts having some form of delegation.
    # 1.2.840.113556.1.4.804 is an OR query. 
    $filter = @"
    (&
      (servicePrincipalname=*)
      (|
        (msDS-AllowedToActOnBehalfOfOtherIdentity=*)
        (msDS-AllowedToDelegateTo=*)
        (UserAccountControl:1.2.840.113556.1.4.804:=$bitmask)
      )
      (|
        (objectcategory=computer)
        (objectcategory=person)
        (objectcategory=msDS-GroupManagedServiceAccount)
        (objectcategory=msDS-ManagedServiceAccount
        )
      )
    )
"@ -replace "[\s\n]", ''

    $propertylist = @(
        "servicePrincipalname", 
        "useraccountcontrol", 
        "samaccountname", 
        "msDS-AllowedToDelegateTo", 
        "msDS-AllowedToActOnBehalfOfOtherIdentity"
    )
    $count_users = 0
    $count_com=0
    Get-ADObject -server $domain -LDAPFilter $filter -SearchBase $DN -SearchScope Subtree -Properties $propertylist -PipelineVariable account | ForEach-Object {
        $isDC = ($account.useraccountcontrol -band $SERVER_TRUST_ACCOUNT) -ne 0
        $fullDelegation = ($account.useraccountcontrol -band $TRUSTED_FOR_DELEGATION) -ne 0
        $constrainedDelegation = ($account.'msDS-AllowedToDelegateTo').count -gt 0
        $isRODC = ($account.useraccountcontrol -band $PARTIAL_SECRETS_ACCOUNT) -ne 0
        $resourceDelegation = $account.'msDS-AllowedToActOnBehalfOfOtherIdentity' -ne $null
             
           
        if($account.objectclass -eq "user"){
            $count_users++
        }
        if($account.objectclass -eq "computer"){
            $count_com++
        }        
    }
         
    return @{
        "domain-unconstrained-users" = $count_users
        "domain-unconstrained-computers" = $count_com        
    }  
}



function checkConnection{
    param([parameter(Mandatory=$true)][string]$domain)

    
    $checkConnection  = Test-Connection $domain -Quiet -count 1
    
    return $checkConnection
}

$xml.list.domain.Host|%{
    $domain = $_.domainname
    $zabbix_host=$_.zabbixhost
    if($(checkConnection -domain $domain) -eq $true){
        send-zabbix -TargetHost $zabbix_host -Data $(DomainMonitor -domain $domain) -Url $zabbix_url
    }
    else{
        send-zabbix -TargetHost $zabbix_host -Data @{"Connection"=$(checkConnection -domain $domain)|Out-String} -Url $zabbix_url
    }
    
}

