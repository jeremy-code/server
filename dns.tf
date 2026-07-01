resource "cloudflare_zone" "main" {
  account = {
    id = var.cloudflare_account_id
  }
  name = var.server_domain
  type = "full"
}

resource "cloudflare_dns_record" "www" {
  comment = "Created during Cloudflare Rules deployment process for Redirect from WWW to root"
  content = "192.0.2.1"
  name    = "www"
  proxied = true
  ttl     = 1
  type    = "A"
  zone_id = cloudflare_zone.main.id
}

resource "cloudflare_dns_record" "tunnels" {
  for_each = toset(["@", "webdav", "vault", "rss", "status", "auth"])
  content  = "${cloudflare_zero_trust_tunnel_cloudflared.main.id}.cfargotunnel.com"
  name     = each.value
  proxied  = true
  ttl      = 1
  type     = "CNAME"
  zone_id  = cloudflare_zone.main.id
}

resource "cloudflare_dns_record" "ssh" {
  content = oci_core_instance.main.public_ip
  name    = "ssh"
  proxied = false
  ttl     = 1
  type    = "A"
  zone_id = cloudflare_zone.main.id
}

resource "cloudflare_dns_record" "mail" {
  content = oci_email_email_return_path.main.cname_record_value
  name    = oci_email_email_return_path.main.dns_subdomain_name
  proxied = false
  ttl     = 1
  type    = "CNAME"
  zone_id = cloudflare_zone.main.id
}

resource "cloudflare_dns_record" "dkim" {
  content = data.oci_email_dkim.main.cname_record_value
  name    = "${data.oci_email_dkim.main.name}._domainkey"
  proxied = false
  ttl     = 1
  type    = "CNAME"
  zone_id = cloudflare_zone.main.id
}

# https://docs.oracle.com/en-us/iaas/Content/Email/Tasks/configurespf.htm
resource "cloudflare_dns_record" "spf" {
  content = "\"v=spf1 include:rp.oracleemaildelivery.com ~all\""
  name    = "@"
  proxied = false
  ttl     = 1
  type    = "TXT"
  zone_id = cloudflare_zone.main.id
}
