##### Config

## DNS records to be updated
$records = @(
    @{
        type       = "A"
        what_ip    = "internal"
        dns_record = "ddns.example.com"
        ttl        = 60
        comment    = ""
        proxied    = $false
    }
    <# Comment out the following line to disable IPv6 support
    ,
    @{
        type       = "AAAA"
        what_ip    = "internal"
        dns_record = "ddns.example.com"
        ttl        = 60
        comment    = ""
        proxied    = $false
    }
    #>
)

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
