##### Config

## update IPv4 or IPv6 or Both (v4/v6/all)
$ip_version = "v4"

## Which IP should be used for the record: internal/external
## Internal interface will be chosen automaticly as a primary default interface
$what_ip_v4 = "internal"
## DNS A/AAAA record to be updated
$dns_record_v4 = "ChangeMe"
## 60-7200 in seconds or 1 for Auto
$ttl_v4 = 60
## DNS record comment
$comment_v4 = ""
## Use Cloudflare proxy on dns record true/false
$proxied_v4 = $false

## Which IP should be used for the record: internal/external
## Internal interface will be chosen automaticly as a primary default interface
$what_ip_v6 = "internal"
## DNS A/AAAA record to be updated
$dns_record_v6 = "ChangeMe"
## 60-7200 in seconds or 1 for Auto
$ttl_v6 = 60
## DNS record comment
$comment_v6 = ""
## Use Cloudflare proxy on dns record true/false
$proxied_v6 = $false

## Cloudflare's Zone ID
$zoneid = "ChangeMe"
## Cloudflare Zone API Token
$cloudflare_zone_api_token = "ChangeMe"

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

## Notifications with Proxy yes/no
$notify_with_proxy = "no"
## Proxy URL (e.g. http://127.0.0.1:7890)
$notify_proxy_URL = ""
