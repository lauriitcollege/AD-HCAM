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

function domaincontroller{
    param(
        
        [Parameter(Mandatory=$true)][string]$dc
    )    

    # WMI Objects query
    $computerSystem = get-wmiobject Win32_ComputerSystem -Computer $dc 
    $computerOS = get-wmiobject Win32_OperatingSystem -Computer $dc
    $computerHDD = Get-WmiObject Win32_LogicalDisk -ComputerName $dc -Filter drivetype=3
    # CIM Query
    $dcomProtocol = New-CimSessionOption -Protocol Dcom
    $cimSession = New-CimSession -ComputerName $dc -SessionOption $dcomProtocol
    $computerRAM = Get-CimInstance -ClassName Win32_OperatingSystem -CimSession $cimSession
    $Status=""
    $pctFree = [math]::Round(($computerRAM.FreePhysicalMemory/$computerRAM.TotalVisibleMemorySize)*100,2)
    <#
    if ($pctFree -ge 45) {
        $Status = "OK"
    }
    elseif ($pctFree -ge 15 ) {
        $Status = "Warning"
    }
    else {
        $Status = "Critical"
    }
    #>
    $memFreeSize =  [math]::Round($computerRAM.FreePhysicalMemory/1mb,2)
    $memTotalSize = [int]($computerRAM.TotalVisibleMemorySize/1mb)
    
    return @{
        "hdd-total"  = [int]("{0:N2}" -f ($computerHDD.Size/1GB))
        "hdd-used" = [int](($computerHDD.Size -$computerHDD.FreeSpace)/1GB)
        "ram-total" = [int]("{0:N2}" -f ($computerSystem.TotalPhysicalMemory/1GB))    
        "ram-used" = [int]($memTotalSize - $memFreeSize)
        "last-boot" = ($computerOS.ConvertToDateTime($computerOS.LastBootUpTime)).toString()   
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
