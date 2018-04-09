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

function getData{
    param(
        [string]$value
    )
    
    if ([string]::IsNullOrEmpty($value)) {
        return "Null"
    }   
    else {
        return $value
    }
}

function domaincontroller{
    param(
        
        [Parameter(Mandatory=$true)][string]$dc
    )

    $data = Get-ADDomainController -Server $dc

    return @{
        "dc-RODCs" = $(getData -value $data.isReadonly)
        "dc-domain" = $(getData -value $data.Domain) 
        "dc-enabled" = $(getData -value $data.Enabled) 
        "dc-hostname" = $(getData -value $data.HostName) 
        "dc-ipv4" = $(getData -value $data.IPv4Address) 
        "dc-ipv6" = $(getData -value $data.IPv6Address) 
        "dc-gc" = $(getData -value $data.IsGlobalCatalog) 
        "dc-readonly" = $(getData -value $data.IsReadOnly) 
        "dc-ldap-port" = $(getData -value $data.LdapPort) 
        "dc-os" = $(getData -value $data.OperatingSystem)
        "dc-os-hotfix" = $(getData -value $data.OperatingSystemHotfix)
        "dc-os-service-pack" = $(getData -value $data.OperatingSystemServicePack)       
        "dc-os-version" = $(getData -value $data.OperatingSystemVersion)     
        "dc-operating-master-roles" = $(getData -value (($data.OperationMasterRoles -split "{}" |sort) -join ", ")) 
        "dc-site" = $(getData -value $data.Site) 
        "dc-ssl-port" = $(getData -value $data.SslPort)    
    }  
}

function checkConnection{
    param([Parameter(Mandatory=$true)][String]$dc)

    $checkConnection = Test-Connection $dc -Quiet -Count 1
    return $checkConnection
}

$xml.list.dc.dcs|%{
    $dcs = $_.dcsname
    $dcszabbixhost = $_.dcszabbixhost
    if($(checkConnection -dc $dcs) -eq $true){
        send-zabbix -TargetHost $dcszabbixhost -Data $(domaincontroller -dc $dcs) -Url $zabbix_url
    }
    else{
        send-zabbix -TargetHost $dcszabbixhost -Data @{"dc-connection"=$(checkConnection -dc $dcs)|Out-String} -Url $zabbix_url
    }
}