# server

[github-actions]: https://www.github.com/jeremy-code/server/actions/workflows/ci.yml
[github-actions-badge]: https://www.github.com/jeremy-code/server/actions/workflows/ci.yml/badge.svg
[license-badge]: https://img.shields.io/github/license/jeremy-code/server
[last-commit-badge]: https://img.shields.io/github/last-commit/jeremy-code/server

[![GitHub Actions][github-actions-badge]][github-actions] [![GitHub License][license-badge]](LICENSE) [![GitHub last commit][last-commit-badge]](https://github.com/jeremy-code/server/commit/main)

This repository contains the [Terraform](https://www.terraform.io/) configuration for my server. It is hosted on [Oracle Cloud](https://www.oracle.com/cloud/) and uses [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/). Currently, it runs the containers [`vaultwarden/server`](https://hub.docker.com/r/vaultwarden/server), [`rclone/rclone`](https://hub.docker.com/r/rclone/rclone), [`docker/busybox`](https://hub.docker.com/_/busybox), [`cloudflare/cloudflared`](https://hub.docker.com/r/cloudflare/cloudflared), [`linuxserver/foldingathome`](https://docs.linuxserver.io/images/docker-foldingathome/), [`freshrss/freshrss`](https://hub.docker.com/r/freshrss/freshrss) using [Docker Compose](https://docs.docker.com/compose/).

I have attempted to the best of my ability to make it as secure as possible, but I am not a security expert. I am open to any suggestions for improvement. While I cannot offer any bug bounties, I'm happy to see what I can do to help you out.

The intent is to only deploy ["Always Free"](https://www.oracle.com/cloud/free/) resources offered by Oracle Cloud.

## Usage

```
git clone https://github.com/jeremy-code/server.git
cd server
```

Then, include all variables from [variables.tf](variables.tf) into a `terraform.tfvars` file at the root.

```sh
oci session authenticate --profile-name DEFAULT --region us-phoenix-1
terraform plan "tfplan"
terraform apply -auto-approve "tfplan"
```

## Overview

At a high level, this is what the architecture looks like:

```mermaid
architecture-beta
    group oracleCloud(cloud)[Oracle Cloud]
    group vcn(internet)[Virtual Cloud Network] in oracleCloud
    group instanceSubnet(internet)[Instance Subnet] in vcn
    group dbSubnet(internet)[Database Subnet] in vcn

    service server(server)[Server] in instanceSubnet
    service disk1(disk)[Boot Volume] in oracleCloud
    service disk2(disk)[Internal Volume] in oracleCloud
    service bucket(disk)[Object Storage Bucket] in oracleCloud
    service db(database)[MySQL Database] in dbSubnet
    service internet(internet)[Internet]

    junction storageJunction in oracleCloud

    storageJunction:T -- B:server
    storageJunction:L --> R:disk1
    storageJunction:R --> L:disk2
    storageJunction:B --> T:bucket
    server:R --> L:db
    internet:B -- T:server
```

I am using a Canonical [Ubuntu](https://ubuntu.com/) 24.04 LTS (Noble Numbat) server and a [MySQL](https://www.mysql.com/) database system, both in their own subnets. The server has two block volumes attached to it: one for the boot volume and one for the internal volume. It is set up initially with [cloud-init](https://cloud-init.io/) and runs containers using Docker Compose. The server also serves the role of hosting a [WebDAV](http://www.webdav.org/) file server that syncs with a [Oracle Cloud Object Storage](https://www.oracle.com/cloud/storage/object-storage/) bucket. The server also sends email via [Oracle Cloud Infrastructure Email Delivery](https://www.oracle.com/application-development/email-delivery/). The server is finally reversed proxied via Cloudflare Tunnel for Internet access.

### Containers

1. [`vaultwarden/server`](https://hub.docker.com/r/vaultwarden/server)

[Vaultwarden](https://github.com/dani-garcia/vaultwarden) is a Rust-based [Bitwarden](https://bitwarden.com/)-compatible server. Besides being lighter, it is also much less complicated than the official implementation (see [DockerCompose.hbs](https://github.com/bitwarden/server/blob/main/util/Setup/Templates/DockerCompose.hbs) in [bitwarden/server](https://github.com/bitwarden/server/)) and supports the Arm architecture. Security-wise, there have been [audits](https://github.com/dani-garcia/vaultwarden/wiki/Audits) that assuage my concerns, and I have enabled MFA. The data is stored in the aforementioned MySQL database.

2. [`rclone/rclone`](https://github.com/rclone/rclone/tree/master)

[Rclone](https://rclone.org/) is an awesome utility that I use to host a [WebDAV](http://www.webdav.org) file server that syncs with Oracle Cloud Object Storage (aka Oracle's equivalent of AWS S3). I am using it through the official Docker image. I am a big fan of its first-class support for Oracle Cloud since I don't need to store my credentials in my compute instance since it uses [Instance Principals](https://docs.oracle.com/en-us/iaas/Content/Identity/Tasks/callingservicesfrominstances.htm) for authorization (though I do need to set up a policy to allow the instance to access the Object Storage bucket).

3. [`docker/busybox`](https://hub.docker.com/_/busybox)

I am using Docker's official [BusyBox](https://busybox.net/) image to serve a `robots.txt` file with its `httpd` server. This is to prevent bot traffic on my server. I understand this may be unconventional since it also means search engines may index my site, but since all services are behind authentication, I don't think this should leak any sensitive information (and even so, I could merely ask the search engine to remove the page or temporarily allow it before rejecting it again). While it is bizarre to have an entire container exist solely to serve one file, BusyBox is only 1.2 MB; furthermore, if I were to: (1) host it on the server itself, I would have to expose my server to the Internet (2) host it on the WebDAV file server, it may expose sensitive information from the file server.

4. [`cloudflare/cloudflared`](https://hub.docker.com/r/cloudflare/cloudflared)

In my opinion, exposing a server to the Internet is evil. Using [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/), I can delegate this evil to Cloudflare. I found some caveats while dockerizing it, see ["Cloudflare Tunnel"](#cloudflare-tunnel) in [Miscellaneous Notes](https://github.com/jeremy-code/server#miscellaneous-notes) for more information.

5. [`linuxserver/foldingathome`](https://docs.linuxserver.io/images/docker-foldingathome/)

While [Folding@home](https://foldingathome.org/) does have an official Docker image ([`foldingathome/fah-gpu`](https://hub.docker.com/r/foldingathome/fah-gpu)), it does not support ARM64 and (as of March 2025) has not been updated in three years. [LinuxServer.io](https://www.linuxserver.io/) has a much more recent image using the newly rewritten v8 _Bastet_ Folding@home client ([app.foldingathome.org](https://app.foldingathome.org)).

6. [`freshrss/freshrss`](https://hub.docker.com/r/freshrss/freshrss)

The official FreshRSS docker container. Unlike its linuxserver counterpart, it does support OIDC, though I don't believe it can be run rootless (FreshRSS/FreshRSS#8362).

## Miscellaneous Notes

### Terraform

- I am using `files/_` and `templates/_.tftpl` as a convention since it seems to be recommended as a convention by [AWS](https://docs.aws.amazon.com/prescriptive-guidance/latest/terraform-aws-provider-best-practices/structure.html) and [GCP](https://docs.cloud.google.com/docs/terraform/best-practices/general-style-structure).
- I don't think there exists a Oracle Cloud TFLint plugin (see terraform-linters/tflint#808) since the one recommended by the maintainer is no longer avaliable, and I haven't found an active maintained fork.
- Somewhat confusingly, it seems that the nomenclature for a "module" is a bit unclear. Terraform seems to prefer using it to mean [composable, reusable packages](https://developer.hashicorp.com/terraform/language/modules/develop/composition). Elsewhere, it seems many people recommending modules just mean to not have monolith main.tf and instead break it into _.tf files with a reasonable structure (note that Terraform automatically picks up any `_.tf`in the root, though I do wish it supported a `src` folder)
- Where to store the Terraform `terraform.tfstate` file seems to be a bit of a difficult issue. Using it locally is obviously the most convenient, but I am not a fan of it storing various secret information in plaintext. While open-source OpenTofu [supports encrypted local state](https://opentofu.org/docs/language/state/encryption/), Terraform does not. Conversely, using a remote backend seems to be between either using an integrated service like HCP Terraform or simply using a bucket in any cloud provider. The thing is, there is a bit of a chicken-and-egg dilemma when you consider whether the bucket should or should not be managed in Terraform. For example, even if I create the bucket manually, should it still be in the `server_compartment` compartment and should it use encryption keys from that compartment, etc.

### Oracle Cloud

- After the MySQL database is created for the first time, run the SQL command `CREATE DATABASE vaultwarden;`. I have not figured out a satisfying way to automate this yet.
  - Vaultwarden says in their FAQ ([Can Vaultwarden connect to an Oracle MySQL V8.x database?](https://github.com/dani-garcia/vaultwarden/wiki/FAQs#can-vaultwarden-connect-to-an-oracle-mysql-v8x-database)) that an Oracle v8.x MySQL databases has a different password hashing method so a command has to be run to use the native password handling. I don't recall if I did this or not, but this might be useful to know in the future.
- ~~Oracle Cloud [Custom Logs](https://docs.oracle.com/en-us/iaas/Content/Logging/Concepts/custom_logs.htm) are not supported on Canonical Ubuntu 24.04 even when `oracle-cloud-agent` is installed, despite being supported on its predecessor Ubuntu 20.04 (See [Viewing Custom Logs in a Compute Instance](https://docs.oracle.com/en-us/iaas/Content/Logging/Concepts/viewing_custom_logs_in_a_compute_instance.htm)).~~
  - I believe I have confused "Oracle Cloud Agent" and "Oracle Unified Monitoring Agent". I am still not certain if Ubuntu 24.04 is supported, see [Agent Management Overview](https://docs.oracle.com/en-us/iaas/Content/Logging/Concepts/agent_management.htm) which only lists up to Ubuntu 22.04. Since the installation seems fairly involved including setting up the [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/climanualinst.htm#Manual_Installation), I have yet to explore this option.
    - I have gotten around to attempting this install and I can confirm that yes, Ubuntu 24.04 is not supported. If you run `oci os object get --namespace axmjwnk4dzjv --bucket-name unified-monitoring-agent-config --name versionInfoV2.yml --file versionInfoV2.yml --profile DEFAULT --auth security_token`, you will get a `versionInfoV2.yml` file that says the latest stableVersion is "0.1.37". However, if you run `oci os object get --namespace axmjwnk4dzjv --bucket-name unified-monitoring-agent-ub-bucket --name unified-monitoring-agent-ub-24-0.1.37.deb --file unified-monitoring-agent-ub-24-0.1.37.deb --profile DEFAULT --auth security_token`, it 404s. If you replace that with `unified-monitoring-agent-ub-22-0.1.37.deb`, it works. I have not tried installing the 22.04 version on 24.04, but I strongly suspect it will not work. I also notice that it only lists Ubuntu under "non-FIPS agent: x86" and not "non-FIPS agent: ARM", so I suspect that also may be a problem.
    - Furthermore, the OCI CLI seems to be difficult to install on Ubuntu 24.04. It's not on `apt` or `snap` and it seems to want to be installed via Bash shell script and virtual environments. I was planning on using the containerized version, but since the aforementioned `oci os object get` command does not work, I don't have any use for the CLI.
- While Oracle Linux seems to be in general more useful on Oracle Cloud, [`cloud-init`](https://cloud-init.io/) (which itself is maintained by [Canonical](https://canonical.com/)) seems to have much better Ubuntu support. For example, it does not currently support [`dnf`](https://rpm-software-management.github.io/) (though it does support [`yum`](http://yum.baseurl.org/)).
- I am using a MySQL database for Vaultwarden rather than a block volume with an SQLite file because (1) Using a MySQL database frees up 50 GB of block storage and (2) Whenever Terraform destroys the instance, the attached block volume is also destroyed. While this may be rectified manually by detaching the block volume, using a MySQL database guarantees the instance and the database are decoupled.
  - I highly recommend having off-site backups of the MySQL database in case Oracle Cloud closes your account or something else catastrophic happens.
- Many of the security features Oracle Cloud offers are not available on the "Always Free" tier, such as [NAT Gateways](https://docs.oracle.com/iaas/Content/Network/Tasks/NATgateway.htm), ~~Web Application Firewalls~~, [Service Gateways](https://www.oracle.com/cloud/networking/service-gateway/), and [Capture Filters](https://docs.oracle.com/en-us/iaas/Content/Network/Concepts/capture-filters.htm) (and by extension, [VCN Flow Logs](https://docs.oracle.com/en-us/iaas/Content/Network/Concepts/vcn-flow-logs.htm)).
  - I believe I have confused [Network Firewalls](https://www.oracle.com/cloud/networking/network-firewall/) and [Web Application Firewalls](https://www.oracle.com/security/cloud-security/web-application-firewall/), the former being free for the first 10 TiB of traffic per month. I have yet to explore this option. The latter appears geared towards web applications.
- I am using iSCSI to attach a block volume to the instance due to the overhead of using a paravirtualized device. However, since this requires a connection to the target, I am using the Snap package `oracle-cloud-agent` to handle this automatically. The issue is that while cloud-init allows configuration of disks, partitions, and mounts, this occurs in the "init stage" while package installation occurs later in the "final stage". Installing the Snap package early during the boot command configuration led to some bizarre behavior (`snapd` is not installed by default on this image). Unfortunately, this means I cannot mount the block volume with cloud-init, and instead, once I have access to the volume, I run a command to create an `ext3` filesystem on the disk (if it does not exist) and then mount it.
- Since Email Delivery is "Always Free" for up to 100 emails sent per day, which is more than enough for my needs, I have opted to use [Oracle Cloud Infrastructure Email Delivery](https://www.oracle.com/application-development/email-delivery/) rather than a third-party service like [SendGrid](https://sendgrid.com/) or [Mailgun](https://www.mailgun.com/) just to keep everything on the same platform.
  - One slight I have against Oracle's service is that there are only two options for sending emails: sending an authenticated HTTPS request or using the SMTP credentials of a user. Since most services I am working with require SMTP for anything email-related, I have opted to use the SMTP credentials, which has some security implications. I would prefer if there was some way to have an instance authenticate to an SMTP server, but I don't believe this is possible.
- Secrets are handled in honestly a somewhat bizarre way in the Terraform Oracle provider. It seems that you have to pass the secret resource to a data source [oci_secrets_secretbundle](https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/secrets_secretbundle) and then use that to get the actual secret content. This leads to the mouthful bit of syntax: `one(data.oci_secrets_secretbundle.SECRET_BUNDLE_NAME.secret_bundle_content[*].content)`

### Cloudflare (Terraform)

- API tokens are necessary to use Cloudflare as a Terraform provider, but you have to deliberately set their permissions, which IMO are not listed intuitively, nor do I believe they are documented in relation to Terraform's resources.
- I didn't notice this initially, but it seems that my prior configuration of Cloudflare Tunnels over the UI had overwritten my local configuration, which had led to a silent error in my configuration going unnoticed (I had used freshrss as a subdomain instead of rss). It seems that if the online UI is empty, that is equivalent to saying the configuration is local-only.

### Vaultwarden

- Set `SIGNUPS_ALLOWED` to `true` temporarily when creating the first user, then set it back to `false`.
- Ensure multi-factor authentication is enabled in Vaultwarden.
- ~~The MySQL database password is stored in plain text at `/home/jeremy/docker-compose.yml` on the Compute instance. This is not ideal. I have not found a way to securely store it yet. To my knowledge, the best solution can be found here: [Using Docker Secrets with a VaultWarden / MySQL Setup](https://anujnair.com/blog/19-using-docker-secrets-with-a-vaultwarden-mysql-setup) by [Anuj Nair](https://github.com/AnujRNair/) using a shell script to set the environment variable. Ideally, I hope there will be an option to set a `DATABASE_URL_FILE` in Vaultwarden sometime in the future.~~
  - It appears that Vaultwarden can read any file listed as `${ENV_FILE}` where `ENV` is an environment variable setting. You can see this in the Vaultwarden source code here [vaultwarden/src/util.rs](https://github.com/dani-garcia/vaultwarden/blob/main/src/util.rs#L378). This appears to have been introduced in this commit dani-garcia/vaultwarden@e8ef76b8f928c8898bcd84c819d616094f123f21. Hence, I have updated the `docker-compose.yml` file to use a secret for the MySQL database URL.

### Rclone

- I am a MacOS user, hence I wanted a light (e.g. no excessive UI frontend) solution compatible with MacOS. Per [Apple: Servers and shared computers you can connect to on Mac](https://support.apple.com/guide/mac-help/servers-shared-computers-connect-mac-mchlp3015/mac), the protocols supported by MacOS are SMB/CIFS, NFS, WebDAV (FTP is also supported for only read-access). Hence, since WebDAV is the only protocol that supports HTTP (for compatability with Cloudflare Tunnel without requiring a VPN or a direct connection), it was the obvious choice. However, iOS's Files app does not support WebDAV natively.
- I am using the `rclone serve webdav` command to serve a WebDAV file server. For some reason, setting `--addr rclone:9800` fixes any connection issues I have. I am not certain why since the documentation claims it should be used for IP addresses, but it works -- whether it is a bug or an undocumented feature, I am not sure.
- I am currently using Basic HTTP authentication with a `bcrypt`-hashed (cost of 9) password. I am not certain of the security implications of this, since the server is behind a Cloudflare Tunnel which does encrypt connections from user to the connector. However, I am not certain of a better solution, as using a Cloudflare login page wouldn't work with a file server.
- It is very convenient that not only Oracle Cloud buckets can be used as a backend, but instance_principal_auth is supported (see [instance_principal](https://docs.oracle.com/en-us/iaas/Content/Identity/Tasks/callingservicesfrominstances.htm)). By using a dynamic group that allows only my compute instance to update the files, I believe this backend is very secure given the usage of certificates for verification.

### Folding@home

- You may be skeptical of running Folding@home on a cloud instance, but I have been running a similar setup since 2022 without issue. While Oracle Cloud's Acceptable Use Policy forbids "cyber currency or crypto currency mining", I could not find any mention of distributed computing projects like Folding@home. Furthermore, this official blog post ["How to deploy Folding@home in Oracle Cloud Infrastructure"](https://blogs.oracle.com/cloud-infrastructure/post/how-to-deploy-foldinghome-in-oracle-cloud-infrastructure) and this Oracle image ["FoldingATHome GPU Image"](https://cloudmarketplace.oracle.com/marketplace/en_US/adf.task-flow?tabName=O&adf.tfDoc=%2FWEB-INF%2Ftaskflow%2Fadhtf.xml&application_id=73275127&adf.tfId=adhtf) suggest it is at the very least tacitly endorsed by Oracle.
- ~~I intend to run this as a headless setup. However, this seems much more difficult in version 8 of the client than in version 7, where you could configure `web-enable`, `disable-viz`, and `gui-enable` in `config.xml`.~~
  - I was for some reason under the impression that the client had a GUI. However, I learned that on `http://localhost:7396`, it merely redirects with status code [307 Temporary Redirect](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/307) to [app.foldingathome.org](https://app.foldingathome.org/). I suspect that is why those options were removed.

### Cloudflare Tunnel

- Login to [`one.dash.cloudflare.com`](https://one.dash.cloudflare.com), proceed to Networks > Tunnels, click the "Create a tunnel" button, and select "Cloudflared". You should be given a command to run similar to `sudo cloudflared service install [TOKEN]` where `[TOKEN]` is a Base64-encoded JSON object. Run the command `base64 --decode <<< "[TOKEN]"`, which should return a JSON object with properties `a`, `t`, `s`. These correspond to `AccountTag`, `TunnelId`, and `TunnelSecret`, respectively. Add these to `terraform.tfvars`.
- It seems that Cloudflare Tunnel is deprioritizing "locally-managed tunnels" (i.e. using `--cred-file` to configure tunnels). See these comments made by Cloudflare employees on GitHub: [cloudflare/cloudflared#1029](https://github.com/cloudflare/cloudflared/issues/1029#issuecomment-1713537876) and [cloudflare/cloudflare-docs#13099](https://github.com/cloudflare/cloudflare-docs/issues/13099#issuecomment-2136204057). This is also mentioned in the [Cloudflare Tunnel documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/do-more-with-tunnels/local-management/) where it is stated that "Cloudflare recommends setting up a remotely-managed tunnel." One issue that arises is that remote configuration will always override local configuration (see cloudflare/cloudflared#843). Since I dislike the idea of hard-coding a token to `docker-compose.yml`, I have opted to use `--cred-file` and Docker secrets. I also prefer using a configuration file for predictable behavior, though if it leads to issues, I may switch to using the [Cloudflare provider on Terraform](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs).
- When debugging, I continually received the error `Incoming request ended abruptly: context canceled` (see cloudflare/cloudflared#1360). This seems to be a generic error that simply indicates the connection was closed. In my case, it was because the encoded Base64 string and the format for `--cred-file` for some reason differ.
- By default, the base directory is `/user/nonroot`. If you set the user to `root`, the base directory is then set to `/root`.
- The error `failed to sufficiently increase receive buffer size` is a red herring and Tunnels will work despite it. More information see [Cloudflare Tunnel > Troubleshoot tunnels > Common Errors](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/troubleshoot-tunnels/common-errors/#i-see-failed-to-sufficiently-increase-receive-buffer-size-in-my-cloudflared-logs), cloudflare/cloudflared#1176, [quic-go/quic-go/wiki/UDP-Buffer-Sizes](https://github.com/quic-go/quic-go/wiki/UDP-Buffer-Sizes), and quic-go/quic-go#3418.
  - Furthermore, setting `net.core.rmem_max` and `net.core.wmem_max` seems to not be possible in Docker Compose using the `sysctl` key, which I believe is because the kernel option is not namespaced (moby/moby#30778).
- The default UID and GID for the `nonroot` user is 65532:65532, which originates from the Docker image [distroless](https://github.com/GoogleContainerTools/distroless).

### FreshRSS

- While the documentation claims that the FreshRSS folder should be owned by `www-data` (33:33), it seems that most of the default files in /var/www/FreshRSS is owned by root but has group access for `www-data`
- I wanted to put a default opml.xml into /var/www/FreshRSS/data/opml.xml to set the default set of feeds using `configs` in docker-compose, but I kept getting a very strange error. The first time, Docker would error and fail, then the second time, it would work. My guess is that it's mounting a config file inside a bind mount leads to a race condition. [While it's not recommended](https://freshrss.github.io/FreshRSS/en/admins/03_Installation.html), I just ended up overwriting /var/www/FreshRSS/opml.default.xml. The error I received was:

```
Error response from daemon: failed to create task for container: failed to create shim task: OCI runtime create failed: runc create failed: unable to start container process: error during container init: error mounting "/host_mnt/$HOME/opml.xml" to rootfs at "/var/www/FreshRSS/data/opml.xml": create mountpoint for /var/www/FreshRSS/data/opml.xml mount: mountpoint "/run/host_virtiofs/$HOME/freshrss/data/opml.xml" is outside of rootfs "/var/lib/docker/rootfs/overlayfs/${layer}"
```

- It cannot be run rootless (FreshRSS/FreshRSS#8362). However, I suspect this may be possible since the fix given in the linked issue refers to setting a non-root user rather than running the Docker daemon rootless. Cron jobs inside the container should be able to be set because the container should believe it is root. I tried it initially and it didn't work, but I suspect it's possible.

## License

This project is licensed under the [MIT license](LICENSE).
