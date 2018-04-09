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

function check{

    param([string]$data)

    if([string]::IsNullOrEmpty($data)){

        return "Null"
      
    }
    else{
        return $data
    }
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
        Write-Host "Zabbix API endpoint is not specified...`n$($body | Out-String)"
        return
    }

    try {
        Invoke-WebRequest -Uri $Url -Method POST -Body $body
    } catch [exception] {
        $Host.UI.WriteErrorLine("ERROR: $($_.Exception.Message)")
    }
}

Function DomainMonitor {
    param(
        [Parameter(Mandatory=$true)][string]$domain
    )

    $dataForest = Get-ADForest $domain
     
    return @{
        'forest-domain-naming-master' = check -data ($dataForest|select -ExpandProperty DomainNamingMaster)
        'forest-domains' =  check -data (($dataForest |select -ExpandProperty Domains |sort) -join ", ")
        'forest-mode' =  check -data ($dataForest |select -ExpandProperty ForestMode)
        'forest-GCs' =  check -data (($dataForest |select -ExpandProperty GlobalCatalogs |sort) -join ", ")
        'forest-name' =  check -data ($dataForest|select -ExpandProperty name)
        'forest-root-domain' =  check -data ($dataForest |select -ExpandProperty RootDomain)
        'forest-schema-master' =  check -data ($dataForest |select -ExpandProperty  SchemaMaster)
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
        send-zabbix -TargetHost $zabbix_host -Data $(DomainMonitor $domain) -Url $zabbix_url
    }
    else{
        send-zabbix -TargetHost $zabbix_host -Data @{"Connection"=$(checkConnection -domain $domain)|Out-String} -Url $zabbix_url
    }
}