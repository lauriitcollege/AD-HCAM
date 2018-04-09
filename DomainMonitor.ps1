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
        Write-Host "Zabbix API endpoint is not specified...`n$($body | Out-String)"
        return
    }

    try {
        Invoke-WebRequest -Uri $Url -Method POST -Body $body
    } catch [exception] {
        $Host.UI.WriteErrorLine("ERROR: $($_.Exception.Message)")
    }
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

Function DomainMonitor {
    param(
        [Parameter(Mandatory=$true)][string]$domain
    )

    $data = Get-ADDomain $domain

    $context = New-Object System.DirectoryServices.ActiveDirectory.DirectoryContext("domain",$domain)

    $dcs = (([System.DirectoryServices.ActiveDirectory.Domain]::GetDomain($context)).DomainControllers).name
    return @{
        # Domain data
        
        'domain-dns-suffixes' = check -data (($data |select -ExpandProperty AllowedDNSSuffixes|sort) -join ', ')
        'domain-child-domains'= check -data(($data |select -ExpandProperty ChildDomains |sort) -join ', ')
        'domain-computer-container' = check -data ($data |Select -ExpandProperty ComputersContainer)
        'domain-dcs' =check -data (($dcs|sort) -join ", ")    
        'domain-deleted-objects-container' = check -data ($data |Select -ExpandProperty DeletedObjectsContainer)
        'domain-dn' = check -data ($data |select -ExpandProperty DistinguishedName)
        'domain-dns-root' = check -data ($data |select -ExpandProperty DNSRoot)    
        'domain-DCs-container' = check -data ($data |select -ExpandProperty DomainControllersContainer)
        'domain-mode' = check -data ($data |select -ExpandProperty DomainMode)
        'domain-sid' = check -data (($data | select -ExpandProperty DomainSID).ToString())
        'domain-foreign-sec-principals-container' = check -data ($data | select -ExpandProperty ForeignSecurityPrincipalsContainer) 
        'domain-forest' = check -data ($data|select  -ExpandProperty Forest)
        'domain-infra-master' = check -data ($data|select  -ExpandProperty InfrastructureMaster)
        # TODO: Figure out whether we actually need this
        # 'domain.last-logon-replication-interval' = $data|select  -ExpandProperty LastLogonReplicationInterval
        'domain-linked-gpos' = check -data (($data |select -ExpandProperty LinkedGroupPolicyObjects|sort) -join ', ')      
        'domain-name' = check -data ($data |Select -ExpandProperty Name)
        'domain-netbios-name' = check -data ($data |select -ExpandProperty NetBIOSName)
        'domain-object-class' = check -data ($data |select -ExpandProperty ObjectClass)
        'domain-object-guid' = check -data  (($data | select -ExpandProperty ObjectGUID).ToString())
        'domain-parent-domain' = check -data ($data |select -ExpandProperty ParentDomain)     
        'domain-PDCEmu' = check -data ($data |select -ExpandProperty PDCEmulator)
        'domain-quotas-container'= check -data ($data |select -ExpandProperty QuotasContainer)
        'domain-replication-dcs' = check -data (($data |Select -ExpandProperty ReplicaDirectoryServers |sort ) -join ', ')
        'domain-RODCs' = check -data (($data |select -ExpandProperty ReadOnlyReplicaDirectoryServers|sort) -join ', ')
        'domain-rid-master' = check -data ($data|select -ExpandProperty RIDMaster)
        'domain-subordinate-refs' = check -data (($data |select -ExpandProperty SubordinateReferences |sort) -join ', ')
        'domain-system-container' = check -data ($data|select -ExpandProperty SystemsContainer)
        'domain-user-container'= check -data ($data|select -ExpandProperty UsersContainer)
        # Global catalog data
        'domain-GC-server' = check -data ((dsquery server -isgc -domain $domain|sort).replace("""","") -join '; ')
        #>
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
        send-zabbix -TargetHost $zabbix_host -Data @{"Connection"=$(checkConnection -domain $domain)|out-string} -Url $zabbix_url
    }
}