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


function domaincontroller{
    param(
        [Parameter(Mandatory=$true)][string]$domain,
        [Parameter(Mandatory=$true)][string]$dc
    )
    $Filter="(&(objectClass=user)(|(samaccountname=guest)(samaccountname=p981aaj)))"
    
    #Bing LDAP /Search Latecy
    function checkLdap{
        param($port)
        $ldap_domain ="LDAP://$($dc):$port"
        $root = New-Object DirectoryServices.DirectoryEntry $ldap_domain
        $searcher = New-Object DirectoryServices.DirectorySearcher
        $searcher.SearchRoot = $root
        $searcher.SearchScope = "subtree"
        $searcher.PageSize = 1
        #$Filter = '(cn=krbtgt)'
        $searcher.Filter = $Filter
        $result = @{
            'ComputerName' = $dc
            'Connected' = $False
        }
        try {
            #Write-Verbose ('$($MyInvocation.MyCommand): Trying to LDAP bind - {0}' -f $server)
            $adObjects = $searcher.FindAll()
           # Write-Verbose ('$($MyInvocation.MyCommand): LDAP Server {0} is up (object path = {1})' -f $server, $adObjects.Item(0).Path)
      
            $result.Connected = $True
        }
        catch {}
            
        return $result.Connected
    }

    [string]$ldapPort = checkLdap -port 389
    [string]$ldapSSLSearch = checkLdap -port 636
    [string]$gcsSearch = checkLdap -port 3269
    [string]$gcSearch = checkLdap -port 3268

    $data = Get-ADDomainController -Server $dc
    $dn = Get-ADDomain $domain |select -ExpandProperty DistinguishedName
    $LdapConnection = New-Object System.DirectoryServices.Protocols.LdapConnection $dc
	$LdapConnection.SessionOptions.ReferralChasing = [System.DirectoryServices.Protocols.ReferralChasingOptions]::None
	$LdapConnection.Timeout = New-Object TimeSpan(0, 0, 10)
	$LdapConnection.AuthType = [System.DirectoryServices.Protocols.AuthType]::Negotiate
	$LdapConnection.Bind()
	$scope = [System.DirectoryServices.Protocols.SearchScope]::Subtree
	$attrlist = ,"*"
	$SearchRequest = New-Object System.DirectoryServices.Protocols.SearchRequest($dn, $Filter, $scope, $attrlist)
	$Stopwatch = [Diagnostics.Stopwatch]::StartNew()
	$send_request = $LdapConnection.SendRequest($SearchRequest)
	$Stopwatch.Stop()
    [string]$stop_num= 0
    
	if ($send_request.Entries.Count -gt 0)
	{
		foreach ($i in $send_request.Entries)
		{
           $stop_num = $Stopwatch.ElapsedMilliseconds
		}      
    }

    
    # LDAP SSL
    $timeout = 5
    [string]$ldaps_check = $False
    $LDAPS = [ADSI]"LDAP://$($dc):636" 
    
    try{
        
        $ldapsConnection = [adsi]($LDAPS) 
       
        
    }
    catch{}

    if($ldapsConnection.path){
        $ldaps_check = $true
    }
    
    return @{
        "dc-bind-query"= $ldapPort #trigger if it's false
        "dc-search-latency" = $stop_num
        "dc-ldap-ssl-status" = $ldaps_check
        "dc-ldap-ssl-search" = $ldapSSLSearch
        "dc-gc-search" = $gcSearch
        "dc-gc-ssl-search"= $gcsSearch
    }  
    
}
function checkConnection{
    param([Parameter(Mandatory=$true)][String]$dc)

    $checkConnection = Test-Connection $dc -Quiet -Count 1
    return $checkConnection
}

$xml.list.dc.dcs|%{    
    $dcs = $_.dcsname
    if(($dcs.Split(".")).count -eq 3){
        $domain = $dcs.Split(".")[1..2] -join "."
    }
    if(($dcs.Split(".")).count -eq 4){
        $domain = $dcs.Split(".")[1..3] -join "."
    }
    $dcszabbixhost = $_.dcszabbixhost
    if($(checkConnection -dc $dcs) -eq $true){
        send-zabbix -TargetHost $dcszabbixhost -Data $(domaincontroller -domain $domain -dc $dcs) -Url $zabbix_url
    }
    else{
        send-zabbix -TargetHost $dcszabbixhost -Data @{"dc-connection"=$(checkConnection -dc $dcs)|Out-String} -Url $zabbix_url
    }
}
