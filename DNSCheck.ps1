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
       
        [Parameter(Mandatory=$true)][string]$dc,
        [Parameter(Mandatory=$true)][string]$ipv4
    )
    [string]$dns_check = $false

    $get_ipv4 = Resolve-DnsName $dc | select -ExpandProperty IPAddress
    if($get_ipv4 -eq $ipv4){
        $dns_check  = $true
    }
     
    return @{       

        "dc-dns-query" = $dns_check 
    }  

}
$xml.list.dc.dcs|%{
    $dcs = $_.dcsname
    $dcszabbixhost = $_.dcszabbixhost
    $ipv4 = $_.ip
    send-zabbix -TargetHost $dcszabbixhost -Data $(domaincontroller -dc $dcs -ipv4 $ipv4) -Url $zabbix_url
}
