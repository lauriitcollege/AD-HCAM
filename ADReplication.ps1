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
        [string]$value,
        [switch]$OperationMasterRoles
    )
    
    if ([string]::IsNullOrEmpty($value)) {
        return "Null"
    }
    
    if($OperationMasterRoles){    
        return ($value -split "{}" |sort) -join ", " 
    } else {
        return ($value|sort)-join ", "
    }
}
$global:prevGPO = New-Object System.Collections.ArrayList
$global:latestDatetime = New-Object System.Collections.ArrayList
$global:datetime =@{}

function domaincontroller{
    param(
        #[Parameter(Mandatory=$true)][string]$domain,
        [Parameter(Mandatory=$true)][string]$dc
    )
    
    [string]$checkRepStatus = $false
    $checkFailure = (Get-ADReplicationPartnerMetadata -Target $dc).ConsecutiveReplicationFailures
    $checkRepLastResult = (Get-ADReplicationPartnerMetadata -Target $dc).LastReplicationResult
    
    if(($checkFailure -eq 0) -and ($checkRepLastResult -eq 0)){
        $checkRepStatus = $true
    }
    return @{        
        "dc-replication"=$checkRepStatus           
    }      
}

function checkConnection{
    param([Parameter(Mandatory=$true)][String]$dc)

    $checkConnection = Test-Connection $dc -Quiet -Count 1

    return $checkConnection
}

$global:domain = ""
$connected_dcs = New-Object System.Collections.ArrayList

$xml.list.dc.dcs|%{
    $dcs = $_.dcsname
    $dcszabbixhost = $_.dcszabbixhost

   
    if($(checkConnection -dc $dcs) -eq $true){             
        send-zabbix -TargetHost $dcszabbixhost -Data $(domaincontroller -dc $dcs) -Url $zabbix_url   
    }
    else{
        send-zabbix -TargetHost $dcszabbixhost -Data @{"Connection"=$(checkConnection -dc $dcs)|Out-String} -Url $zabbix_url
    }
    
}