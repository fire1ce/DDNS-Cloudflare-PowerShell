# https://github.com/fire1ce/DDNS-Cloudflare-PowerShell

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

### updateDNS.log file of the last run for debug
$File_LOG = "$PSScriptRoot\update-cloudflare-dns.log"
$FileName = "update-cloudflare-dns.log"

if (!(Test-Path $File_LOG)) {
  New-Item -ItemType File -Path $PSScriptRoot -Name ($FileName) | Out-Null
}

Clear-Content $File_LOG
$DATE = Get-Date -UFormat "%Y/%m/%d %H:%M:%S"
Write-Output "==> $DATE" | Tee-Object $File_LOG -Append

### Load config file
Try {
  . $PSScriptRoot\update-cloudflare-dns_conf.ps1
}
Catch {
  Write-Output "==> Error! Missing update-cloudflare-dns_conf.ps1 or invalid syntax" | Tee-Object $File_LOG -Append
  Exit
}

### Check validity of "ttl" parameter
if (( $ttl -lt 60 ) -or ($ttl -gt 7200 ) -and ( $ttl -ne 1 )) {
  Write-Output 'Error! ttl out of range (60) or not set to 1' | Tee-Object $File_LOG -Append
  Exit
}

### Check validity of "proxied" parameter
if (!([string]$proxied) -or ($proxied.GetType().Name.Trim() -ne "Boolean")) {
  Write-Output 'Error! Incorrect "proxied" parameter choose "$true" or "$false" ' | Tee-Object $File_LOG -Append
  Exit
}


### Check validity of "what_ip" parameter
if ( ($what_ip -ne "external") -and ($what_ip -ne "internal") ) {
  Write-Output 'Error! Incorrect "what_ip" parameter choose "external" or "internal"' | Tee-Object $File_LOG -Append
  Exit
}

### Get External ip from internet
function Get-Ip-External {
    param ([bool] $IPv6)
    if ($IPv6) {
        return (Invoke-RestMethod -Uri "http://v6.ident.me" -TimeoutSec 10).Trim()
    } else {
        return (Invoke-RestMethod -Uri "https://checkip.amazonaws.com" -TimeoutSec 10).Trim()
    }
}
if ($what_ip -eq 'external') {
  $ip = Get-Ip-External -IPv6 $IPv6
  if (!([bool]$ip)) {
    Write-Output "Error! Can't get external ip from https://checkip.amazonaws.com" | Tee-Object $File_LOG -Append
    Exit
  }
  Write-Output "==> External IP is: $ip" | Tee-Object $File_LOG -Append
}

### Get Internal ip from primary interface
function Get-Ip-Internal {
    param ([bool] $IPv6)

    if ($IsLinux) {
        if ($IPv6) {
            return ip -6 addr | grep inet6 | awk -F '[ \t]+|/' '{print $3}' | grep -v ^::1 | grep -v ^f | sort | head -1
        }
        else {
            return ip -4 addr | grep inet | awk -F '[ \t]+|/' '{print $3}' | grep -v ^127 | grep -v ^192 | grep -v ^f | head -1
        }
    } elseif ($IsWindows) {
        $InternalIPTestAddress = switch ($IPv6) {
            $true { "2606:4700::1111" }
            $false { "1.1.1.1" }
        }
        $addr = $((Find-NetRoute -RemoteIPAddress $InternalIPTestAddress).IPAddress|out-string).Trim()
        if ($addr -eq "127.0.0.1" -or $addr -eq "::1") {
            return $null
        }
        return $addr
    } elseif ($IsMacOS) {
        throw "Get-Internal-IpAddress is not implemented for MacOS."
    }
}
if ($what_ip -eq 'internal') {
  $ip = Get-Ip-Internal -IPv6 $IPv6
  if (![bool]$ip) {
    Write-Output "==>Error! Can't get internal ip address" | Tee-Object $File_LOG -Append
    Exit
  }
  Write-Output "==> Internal IP is $ip" | Tee-Object $File_LOG -Append
}


### Get IP address of DNS record from 1.1.1.1 DNS server when proxied is "false"
function Resolve-DnsName-From-Cloudflare {
    param ([bool] $DoH, [string] $domain, [bool] $IPv6)
    $type = switch ($IPv6) {
        $true { "AAAA" }
        $false { "A" }
    }
    if ($DoH) {
        $response = Invoke-RestMethod -Proxy $http_proxy -ProxyCredential $proxy_credential -Uri https://cloudflare-dns.com/dns-query -Body @{
            name = $domain
            type = $type
        } -Headers @{ 'Accept' = 'application/dns-json' }
        if ($response) {
            return $response.Answer[0].data
        }
        return $null
    } else {
        $ip = (Resolve-DnsName -Name $domain -Server 1.1.1.1 -Type $type | Select-Object -First 1)
        if ($ip) {
          return $ip.IPAddress.Trim()
        }
        return $null
    }
}
if ($proxied -eq $false) {
  $dns_record_ip = Resolve-DnsName-From-Cloudflare -DoH $DNS_over_HTTPS -domain $dns_record -IPv6 $IPv6
  if (![bool]$dns_record_ip) {
    Write-Output "Error! Can't resolve the ${dns_record} via 1.1.1.1 DNS server" | Tee-Object $File_LOG -Append
    Exit
  }
  $is_proxed = $proxied
}

### Get the dns record id and current proxy status from cloudflare's api when proxied is "true"
if ($proxied -eq $true) {
  $dns_record_info = @{
    Uri     = "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records?name=$dns_record"
    Headers = @{"Authorization" = "Bearer $cloudflare_zone_api_token"; "Content-Type" = "application/json" }
  }

  $response = Invoke-RestMethod -Proxy $http_proxy -ProxyCredential $proxy_credential @dns_record_info
  if ($response.success -ne "True") {
    Write-Output "Error! Can't get dns record info from cloudflare's api" | Tee-Object $File_LOG -Append
  }
  $is_proxed = $response.result.proxied
  $dns_record_ip = $response.result.content.Trim()
}


### Check if ip or proxy have changed
if (($dns_record_ip -eq $ip) -and ($is_proxed -eq $proxied)) {
  Write-Output "==> DNS record IP of $dns_record is $dns_record_ip, no changes needed. Exiting..." | Tee-Object $File_LOG -Append
  Exit
}

Write-Output "==> DNS record of $dns_record is: $dns_record_ip. Trying to update..." | Tee-Object $File_LOG -Append

### Get the dns record information from cloudflare's api
$cloudflare_record_info = @{
  Uri     = "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records?name=$dns_record"
  Headers = @{"Authorization" = "Bearer $cloudflare_zone_api_token"; "Content-Type" = "application/json" }
}

$cloudflare_record_info_resposne = Invoke-RestMethod -Proxy $http_proxy -ProxyCredential $proxy_credential @cloudflare_record_info
if ($cloudflare_record_info_resposne.success -ne "True") {
  Write-Output "Error! Can't get $dns_record record inforamiton from cloudflare API" | Tee-Object $File_LOG -Append
  Exit
}

### Get the dns record id from response
$dns_record_id = $cloudflare_record_info_resposne.result.id.Trim()

### Push new dns record information to cloudflare's api
$update_dns_record = @{
  Uri     = "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records/$dns_record_id"
  Method  = 'PUT'
  Headers = @{"Authorization" = "Bearer $cloudflare_zone_api_token"; "Content-Type" = "application/json" }
  Body    = @{
    "type"    = switch ($IPv6) {
        $true { "AAAA" }
        $false { "A" }
    }
    "name"    = $dns_record
    "content" = $ip
    "ttl"     = $ttl
    "proxied" = $proxied
  } | ConvertTo-Json
}

$update_dns_record_response = Invoke-RestMethod -Proxy $http_proxy -ProxyCredential $proxy_credential @update_dns_record
if ($update_dns_record_response.success -ne "True") {
  Write-Output "Error! Update Failed" | Tee-Object $File_LOG -Append
  Exit
}

Write-Output "==> Success!" | Tee-Object $File_LOG -Append
Write-Output "==> $dns_record DNS Record Updated To: $ip, ttl: $ttl, proxied: $proxied" | Tee-Object $File_LOG -Append


if ($notify_me_telegram -eq "no" -And $notify_me_discord -eq "no")   {
  Exit
}

if ($notify_me_telegram -eq "yes") {
  $telegram_notification = @{
    Uri    = "https://api.telegram.org/bot$telegram_bot_API_Token/sendMessage?chat_id=$telegram_chat_id&text=$dns_record DNS Record Updated To: $ip"
    Method = 'GET'
  }
  $telegram_notification_response = Invoke-RestMethod -Proxy $http_proxy -ProxyCredential $proxy_credential @telegram_notification
  if ($telegram_notification_response.ok -ne "True") {
    Write-Output "Error! Telegram notification failed" | Tee-Object $File_LOG -Append
    Exit
  }
}

if ($notify_me_discord -eq "yes") {
  $discord_message = "$dns_record DNS Record Updated To: $ip (was $dns_record_ip)"
  $discord_payload = [PSCustomObject]@{content = $discord_message} | ConvertTo-Json
  $discord_notification = @{
    Uri    = $discord_webhook_URL
    Method = 'POST'
    Body = $discord_payload
    Headers = @{ "Content-Type" = "application/json" }
  }
    try {
      Invoke-RestMethod -Proxy $http_proxy -ProxyCredential $proxy_credential @discord_notification
    } catch {
      Write-Host "==> Discord notification request failed. Here are the details for the exception:" | Tee-Object $File_LOG -Append
      Write-Host "==> Request StatusCode:" $_.Exception.Response.StatusCode.value__  | Tee-Object $File_LOG -Append
      Write-Host "==> Request StatusDescription:" $_.Exception.Response.StatusDescription | Tee-Object $File_LOG -Append
    }
    Exit
}
