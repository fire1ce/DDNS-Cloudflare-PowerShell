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

### Function to get IP address
function Get-IP {
  param (
    [string]$type,
    [string]$what_ip
  )
  if ($what_ip -eq 'external') {
    if ($type -eq 'A') {
      return (Invoke-RestMethod -Uri "https://checkip.amazonaws.com" -TimeoutSec 10).Trim()
    }
    elseif ($type -eq 'AAAA') {
      return (Invoke-RestMethod -Uri "https://api6.ipify.org" -TimeoutSec 10).Trim()
    }
  }
  elseif ($what_ip -eq 'internal') {
    if ($type -eq 'A') {
      return $((Find-NetRoute -RemoteIPAddress 1.1.1.1).IPAddress | out-string).Trim()
    }
    elseif ($type -eq 'AAAA') {
      return $((Find-NetRoute -RemoteIPAddress 2606:4700:4700::1111).IPAddress | out-string).Trim()
    }
  }
  return $null
}

### Function to update DNS record
function Update-DNSRecord {
  param (
    [string]$type,
    [string]$dns_record,
    [string]$ip,
    [int]$ttl,
    [bool]$proxied,
    [string]$comment
  )
  $dns_record_info = @{
    Uri     = "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records?name=$dns_record&type=$type"
    Headers = @{"Authorization" = "Bearer $cloudflare_zone_api_token"; "Content-Type" = "application/json" }
  }

  $response = Invoke-RestMethod @dns_record_info
  if ($response.success -ne "True") {
    Write-Output "Error! Can't get dns record info from cloudflare's api" | Tee-Object $File_LOG -Append
    return [PSCustomObject]@{
      result = $false
      dns_record_ip = $null
    }
  }

  $dns_record_id = $response.result.id.Trim()
  $dns_record_ip = $response.result.content.Trim()
  $is_proxed = $response.result.proxied

  if ($dns_record_ip -eq $ip -and $is_proxed -eq $proxied) {
    Write-Output "==> DNS record $type of $dns_record is $dns_record_ip, no changes needed" | Tee-Object $File_LOG -Append
    return [PSCustomObject]@{
      result = $false
      dns_record_ip = $dns_record_ip
    }
  }

  Write-Output "==> DNS record of $type $dns_record is: $dns_record_ip. Trying to update..." | Tee-Object $File_LOG -Append
  
  $update_dns_record = @{
    Uri     = "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records/$dns_record_id"
    Method  = 'PUT'
    Headers = @{"Authorization" = "Bearer $cloudflare_zone_api_token"; "Content-Type" = "application/json" }
    Body    = @{"type" = $type; "name" = $dns_record; "content" = $ip; "ttl" = $ttl; "proxied" = $proxied; "comment" = $comment } | ConvertTo-Json
  }

  $update_response = Invoke-RestMethod @update_dns_record
  if ($update_response.success -ne "True") {
    Write-Output "Error! Update $type Failed" | Tee-Object $File_LOG -Append
    return [PSCustomObject]@{
      result = $false
      dns_record_ip = $dns_record_ip
    }
  }

  Write-Output "==> Success!" | Tee-Object $File_LOG -Append
  Write-Output "==> $dns_record DNS Record $type Updated To: $ip, ttl: $ttl, proxied: $proxied" | Tee-Object $File_LOG -Append
  return [PSCustomObject]@{
    result = $true
    dns_record_ip = $dns_record_ip
  }
}

### Main logic
$updated_records = @()

foreach ($record in $records) {
  $ip = Get-IP -type $record.type -what_ip $record.what_ip
  if (!$ip) {
    Write-Output "Error! Can't get IP for $record.dns_record" | Tee-Object $File_LOG -Append
    continue
  }

  $update_result = Update-DNSRecord -type $record.type -dns_record $record.dns_record -ip $ip -ttl $record.ttl -proxied $record.proxied -comment $record.comment

  if ($update_result.result) {
    $updated_records += $record.dns_record + " DNS Record " + $record.type + " Updated To: $ip (was " + $update_result.dns_record_ip + ")"
  }
}

if ($updated_records.Count -eq 0) {
  Write-Output "==> No records updated. Exiting..." | Tee-Object $File_LOG -Append
  Exit
}

$notify_message = $updated_records -join "`n"
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