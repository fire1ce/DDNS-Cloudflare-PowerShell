##### Config

## Which IP should be used for the record: internal/external
## Internal interface will be chosen automaticly as a primary default interface
$what_ip = "internal"
## DNS A record or records to be updated
## Each record is required to have the record to update, its proxied status, and cache time (60-7200 in seconds or 1 for Auto)
$dns_records = [ordered]@{
	record1 = @{
		record = "ddns.example.com";
		proxied = $true;
		ttl = 1;
	} #record 1 
	record2 = @{
			record = "ddns2.example.com";
			proxied = $false; 
			ttl = 1;
	} #record 2
}
	
## Use IPv6
$IPv6 = $false
## if use DoH to query the current IP address
$DNS_over_HTTPS = $false
## Cloudflare's Zone ID
$zoneid = "ChangeMe"
## Cloudflare Zone API Token
$cloudflare_zone_api_token = "ChangeMe"

## Use proxy when connect to DoH, Cloudflare, Telegram or Discord API
# $http_proxy = $null
# $proxy_credential = $null

## Telegram Notifications yes/no (only sent if DNS is updated)
$notify_me_telegram = "no"
## Telegram Chat ID
$telegram_chat_id = "ChangeMe"
## Telegram Bot API Key
$telegram_bot_API_Token = "ChangeMe"

## Discord Server Notifications yes/no (only sent if DNS is updated)
$notify_me_discord = "no"
## Discord Webhook URL (create a webhook on your Discord server via Server Settings > Integrations)
$discord_webhook_URL = "ChangeMe"
