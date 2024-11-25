[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

### updateDNS.log file of the last run for debug
$DAY = Get-Date -UFormat "%Y-%m-%d"
$FilePath = "$PSScriptRoot\logs"
$FileName = "update-cloudflare-dns_$DAY.log"
$File_LOG = "$FilePath\$FileName"

if (!(Test-Path $File_LOG)) {
  New-Item -ItemType Directory -Path $FilePath | Out-Null
  New-Item -ItemType File -Path $FilePath -Name ($FileName) | Out-Null
}

### Clear-Content $File_LOG
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

### config checks
### Check validity of "ip_version" parameter
if ($ip_version -ne "v4" -and $ip_version -ne "v6" -and $ip_version -ne "all") {
  Write-Output "==> Error! Invalid IP version: $ip_version" | Tee-Object $File_LOG -Append
  Exit
}

### Check validity of "what_ip" parameter
if ($what_ip_v4 -ne "internal" -and $what_ip_v4 -ne "external") {
  Write-Output "==> Error! Invalid IPv4 version: $what_ip_v4" | Tee-Object $File_LOG -Append
  Exit
}
if ($what_ip_v6 -ne "internal" -and $what_ip_v6 -ne "external") {
  Write-Output "==> Error! Invalid IPv6 version: $what_ip_v6" | Tee-Object $File_LOG -Append
  Exit
}

### Check validity of "ttl" parameter
if (( $ttl_v4 -lt 60 ) -or ($ttl_v4 -gt 7200 ) -and ( $ttl_v4 -ne 1 )) {
  Write-Output 'Error! ttl_v4 out of range (60-7200) or not set to 1' | Tee-Object $File_LOG -Append
  Exit
}
if (( $ttl_v6 -lt 60 ) -or ($ttl_v6 -gt 7200 ) -and ( $ttl_v6 -ne 1 )) {
  Write-Output 'Error! ttl_v6 out of range (60-7200) or not set to 1' | Tee-Object $File_LOG -Append
  Exit
}

### Check validity of "proxied" parameter
if (!([string]$proxied_v4) -or ($proxied_v4.GetType().Name.Trim() -ne "Boolean")) {
  Write-Output 'Error! Incorrect "proxied" parameter choose "$true" or "$false" ' | Tee-Object $File_LOG -Append
  Exit
}
if (!([string]$proxied_v6) -or ($proxied_v6.GetType().Name.Trim() -ne "Boolean")) {
  Write-Output 'Error! Incorrect "proxied" parameter choose "$true" or "$false" ' | Tee-Object $File_LOG -Append
  Exit
}

$update_v4 = ($ip_version -eq "all") -or ($ip_version -eq "v4")
$update_v6 = ($ip_version -eq "all") -or ($ip_version -eq "v6")

### Get External ip from other sources
if (($what_ip_v4 -eq 'external') -and $update_v4) {
  $ip_v4 = (Invoke-RestMethod -Uri "https://checkip.amazonaws.com" -TimeoutSec 10).Trim()
  if (!([bool]$ip_v4)) {
    Write-Output "Error! Can't get external ip_v4 from https://checkip.amazonaws.com" | Tee-Object $File_LOG -Append
    $update_v4 = $false
  }
  Write-Output "==> External IPv4 is: $ip_v4" | Tee-Object $File_LOG -Append
}
if (($what_ip_v6 -eq 'external') -and $update_v6) {
  $ip_v6 = (Invoke-RestMethod -Uri "https://api6.ipify.org" -TimeoutSec 10).Trim()
  if (!([bool]$ip_v6)) {
    Write-Output "Error! Can't get external ip_v6 from https://api6.ipify.org" | Tee-Object $File_LOG -Append
    $update_v6 = $false
  }
  Write-Output "==> External IPv6 is: $ip_v6" | Tee-Object $File_LOG -Append
}

### Get Internal ip from primary interface
if (($what_ip_v4 -eq 'internal') -and $update_v4) {
  $ip_v4 = $((Find-NetRoute -RemoteIPAddress 1.1.1.1).IPAddress | out-string).Trim()
  if (!([bool]$ip_v4) -or ($ip_v4 -eq "127.0.0.1")) {
    Write-Output "==>Error! Can't get internal ip_v4 address" | Tee-Object $File_LOG -Append
    $update_v4 = $false
  }
  Write-Output "==> Internal IPv4 is $ip_v4" | Tee-Object $File_LOG -Append
}
if (($what_ip_v6 -eq 'internal') -and $update_v6) {
  $ip_v6 = $((Find-NetRoute -RemoteIPAddress 2606:4700:4700::1111).IPAddress | out-string).Trim()
  if (!([bool]$ip_v6) -or ($ip_v6 -eq "::1")) {
    Write-Output "==>Error! Can't get internal ip_v6 address" | Tee-Object $File_LOG -Append
    $update_v6 = $false
  }
  Write-Output "==> Internal IPv6 is $ip_v6" | Tee-Object $File_LOG -Append
}

### Get IP address of DNS record from DNS server when proxied is "false"
if (($proxied_v4 -eq $false) -and $update_v4) {
  $dns_record_ip_v4 = (Resolve-DnsName -Name $dns_record_v4 -Server 1.1.1.1 -Type A | Select-Object -First 1).IPAddress.Trim()
  if (![bool]$dns_record_ip_v4) {
    Write-Output "Error! Can't resolve the ${dns_record_v4} via 1.1.1.1 DNS server" | Tee-Object $File_LOG -Append
    $update_v4 = $false
  }
  $is_proxed_v4 = $proxied_v4
}
if (($proxied_v6 -eq $false) -and $update_v6) {
  $dns_record_ip_v6 = (Resolve-DnsName -Name $dns_record_v6 -Server 2606:4700:4700::1111 -Type AAAA | Select-Object -First 1).IPAddress.Trim()
  if (![bool]$dns_record_ip_v6) {
    Write-Output "Error! Can't resolve the ${dns_record_v6} via 2606:4700:4700::1111 DNS server" | Tee-Object $File_LOG -Append
    $update_v6 = $false
  }
  $is_proxed_v6 = $proxied_v6
}

### Get the dns record id and current proxy status from cloudflare's api when proxied is "true"
if (($proxied_v4 -eq $true) -and $update_v4) {
  $dns_record_info_v4 = @{
    Uri     = "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records?name=$dns_record_v4&type=A"
    Headers = @{"Authorization" = "Bearer $cloudflare_zone_api_token"; "Content-Type" = "application/json" }
  }
  
  $response_v4 = Invoke-RestMethod @dns_record_info_v4
  if ($response_v4.success -ne "True") {
    Write-Output "Error! Can't get dns record info from cloudflare's api" | Tee-Object $File_LOG -Append
    $update_v4 = $false
  }
  $is_proxed_v4 = $response_v4.result.proxied
  $dns_record_ip_v4 = $response_v4.result.content.Trim()
}
if (($proxied_v6 -eq $true) -and $update_v6) {
  $dns_record_info_v6 = @{
    Uri     = "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records?name=$dns_record_v6&type=AAAA"
    Headers = @{"Authorization" = "Bearer $cloudflare_zone_api_token"; "Content-Type" = "application/json" }
  }
  
  $response_v6 = Invoke-RestMethod @dns_record_info_v6
  if ($response_v6.success -ne "True") {
    Write-Output "Error! Can't get dns record info from cloudflare's api" | Tee-Object $File_LOG -Append
    $update_v6 = $false
  }
  $is_proxed_v6 = $response_v6.result.proxied
  $dns_record_ip_v6 = $response_v6.result.content.Trim()
}

### Check if ip or proxy have changed
if (($dns_record_ip_v4 -eq $ip_v4) -and ($is_proxed_v4 -eq $proxied_v4) -and $update_v4) {
  Write-Output "==> DNS record IPv4 of $dns_record_v4 is $dns_record_ip_v4, no changes needed" | Tee-Object $File_LOG -Append
  $update_v4 = $false
}
if (($dns_record_ip_v6 -eq $ip_v6) -and ($is_proxed_v6 -eq $proxied_v6) -and $update_v6) {
  Write-Output "==> DNS record IPv6 of $dns_record_v6 is $dns_record_ip_v6, no changes needed" | Tee-Object $File_LOG -Append
  $update_v6 = $false
}

### Update DNS record
if ($update_v4) {
  Write-Output "==> DNS record of IPv4 $dns_record_v4 is: $dns_record_ip_v4. Trying to update..." | Tee-Object $File_LOG -Append
}
if ($update_v6) {
  Write-Output "==> DNS record of IPv6 $dns_record_v6 is: $dns_record_ip_v6. Trying to update..." | Tee-Object $File_LOG -Append
}

### Update DNS record
if ($update_v4) {
  ### Get the dns record information from cloudflare's api
  $cloudflare_record_info_v4 = @{
    Uri     = "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records?name=$dns_record_v4&type=A"
    Headers = @{"Authorization" = "Bearer $cloudflare_zone_api_token"; "Content-Type" = "application/json" }
  }

  $cloudflare_record_info_resposne_v4 = Invoke-RestMethod @cloudflare_record_info_v4
  if ($cloudflare_record_info_resposne_v4.success -ne "True") {
    Write-Output "Error! Can't get $dns_record_v4 record information from cloudflare API" | Tee-Object $File_LOG -Append
    $update_v4 = $false
  }
  else {

    ### Get the dns record id from response
    $dns_record_id_v4 = $cloudflare_record_info_resposne_v4.result.id.Trim()

    ### Push new dns record information to cloudflare's api
    $update_dns_record_v4 = @{
      Uri     = "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records/$dns_record_id_v4"
      Method  = 'PUT'
      Headers = @{"Authorization" = "Bearer $cloudflare_zone_api_token"; "Content-Type" = "application/json" }
      Body    = @{
        "type"    = "A"
        "name"    = $dns_record_v4
        "content" = $ip_v4
        "ttl"     = $ttl_v4
        "proxied" = $proxied_v4
        "comment" = $comment_v4
      } | ConvertTo-Json
    }

    $update_dns_record_response_v4 = Invoke-RestMethod @update_dns_record_v4
    if ($update_dns_record_response_v4.success -ne "True") {
      Write-Output "Error! Update IPv4 Failed" | Tee-Object $File_LOG -Append
      $update_v4 = $false
    }
    else {
      Write-Output "==> Success!" | Tee-Object $File_LOG -Append
      Write-Output "==> $dns_record_v4 DNS Record A Updated To: $ip_v4, ttl: $ttl_v4, proxied: $proxied_v4" | Tee-Object $File_LOG -Append
    }
  }
}

if ($update_v6) {
  ### Get the dns record information from cloudflare's api
  $cloudflare_record_info_v6 = @{
    Uri     = "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records?name=$dns_record_v6&type=AAAA"
    Headers = @{"Authorization" = "Bearer $cloudflare_zone_api_token"; "Content-Type" = "application/json" }
  }

  $cloudflare_record_info_resposne_v6 = Invoke-RestMethod @cloudflare_record_info_v6
  if ($cloudflare_record_info_resposne_v6.success -ne "True") {
    Write-Output "Error! Can't get $dns_record_v6 record information from cloudflare API" | Tee-Object $File_LOG -Append
    $update_v6 = $false
  }
  else {

    ### Get the dns record id from response
    $dns_record_id_v6 = $cloudflare_record_info_resposne_v6.result.id.Trim()

    ### Push new dns record information to cloudflare's api
    $update_dns_record_v6 = @{
      Uri     = "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records/$dns_record_id_v6"
      Method  = 'PUT'
      Headers = @{"Authorization" = "Bearer $cloudflare_zone_api_token"; "Content-Type" = "application/json" }
      Body    = @{
        "type"    = "AAAA"
        "name"    = $dns_record_v6
        "content" = $ip_v6
        "ttl"     = $ttl_v6
        "proxied" = $proxied_v6
        "comment" = $comment_v6
      } | ConvertTo-Json
    }

    $update_dns_record_response_v6 = Invoke-RestMethod @update_dns_record_v6
    if ($update_dns_record_response_v6.success -ne "True") {
      Write-Output "Error! Update IPv6 Failed" | Tee-Object $File_LOG -Append
      $update_v6 = $false
    }
    else {
      Write-Output "==> Success!" | Tee-Object $File_LOG -Append
      Write-Output "==> $dns_record_v6 DNS Record AAAA Updated To: $ip_v6, ttl: $ttl_v6, proxied: $proxied_v6" | Tee-Object $File_LOG -Append
    }
  }
}

if (![bool]$update_v4 -and ![bool]$update_v6) {
  Write-Output "==> Both IPv4 and IPv6 addresses no changes needed. Exiting..." | Tee-Object $File_LOG -Append
  Exit
}

if ($notify_me_telegram -eq "no" -And $notify_me_discord -eq "no") {
  Exit
}


$notify_message_v4 = if ($update_v4) { "$dns_record_v4 DNS Record A Updated To: $ip_v4 (was $dns_record_ip_v4)" } else { "" }
$notify_message_v6 = if ($update_v6) { "$dns_record_v6 DNS Record AAAA Updated To: $ip_v6 (was $dns_record_ip_v6)" } else { "" }
$notify_message = "$notify_message_v4`n$notify_message_v6".Trim()
Write-Output $notify_message
if ($notify_me_telegram -eq "yes") {
  $telegram_notification = @{
    Uri    = "https://api.telegram.org/bot$telegram_bot_API_Token/sendMessage?chat_id=$telegram_chat_id&text=$notify_message"
    Method = 'GET'
  }
  if ($notify_with_proxy -eq "yes") {
    $telegram_notification.Proxy = $notify_proxy_URL
  }
  $telegram_notification_response = Invoke-RestMethod @telegram_notification
  if ($telegram_notification_response.ok -ne "True") {
    Write-Output "Error! Telegram notification failed" | Tee-Object $File_LOG -Append
    Exit
  }
}

if ($notify_me_discord -eq "yes") { 
  $discord_payload = [PSCustomObject]@{content = $notify_message } | ConvertTo-Json
  $discord_notification = @{
    Uri     = $discord_webhook_URL
    Method  = 'POST'
    Body    = $discord_payload
    Headers = @{ "Content-Type" = "application/json" }
  }
  if ($notify_with_proxy -eq "yes") {
    $discord_notification.Proxy = $notify_proxy_URL
  }
  try {
    Invoke-RestMethod @discord_notification
  }
  catch {
    Write-Host "==> Discord notification request failed. Here are the details for the exception:" | Tee-Object $File_LOG -Append
    Write-Host "==> Request StatusCode:" $_.Exception.Response.StatusCode.value__  | Tee-Object $File_LOG -Append
    Write-Host "==> Request StatusDescription:" $_.Exception.Response.StatusDescription | Tee-Object $File_LOG -Append
  }
  Exit
}
