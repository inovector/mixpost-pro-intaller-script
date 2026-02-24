# Mixpost Pro — VPS Installer

One-command installer that provisions a fresh Ubuntu VPS and sets up Mixpost Pro ready for use.

```bash
curl -fsSL https://mixpost.app/install.sh | bash
```

## What it installs

| Component       | Details                                      |
|-----------------|----------------------------------------------|
| PHP 8.3         | FPM + CLI with all required extensions        |
| Nginx           | Reverse proxy with WebSocket support          |
| MySQL 8.0       | Database server                               |
| Redis           | Cache, sessions, and queue backend            |
| Supervisor      | Manages Horizon (queue) and Reverb (WebSocket)|
| FFmpeg & libvips| Media processing                              |
| Certbot         | SSL via Let's Encrypt (optional)              |
| UFW             | Firewall (SSH, HTTP, HTTPS, WebSocket)        |

## Requirements

- **OS:** Ubuntu 22.04 or 24.04
- **Access:** Root user or sudo
- **RAM:** 2 GB minimum (4 GB recommended)
- **License:** Valid [Mixpost Pro](https://mixpost.app) license key
- **Domain:** Pointed to the server's IP address

## Interactive Setup

The installer prompts for:

| Prompt              | Required | Default              |
|---------------------|----------|----------------------|
| Domain name         | Yes      | —                    |
| SSL (Let's Encrypt) | No       | Yes                  |
| License key         | Yes      | —                    |
| Database name       | No       | `mixpost_db`         |
| Database username   | No       | `mixpost`            |
| Database password   | No       | Auto-generated       |
| Timezone            | No       | `UTC`                |
| SMTP configuration  | No       | Skipped              |

A summary is shown before installation begins.

## After Installation

Once complete, the script prints all credentials and connection details. **Save them immediately.**

Visit your domain to create your admin account and start using Mixpost.

### Service Management

```bash
# Check status
supervisorctl status                  # Horizon & Reverb
systemctl status nginx
systemctl status mysql
systemctl status redis-server

# Restart services
supervisorctl restart mixpost-horizon
supervisorctl restart mixpost-reverb
systemctl restart nginx
systemctl restart php8.3-fpm

# View logs
tail -f /var/log/nginx/mixpost-error.log
tail -f /var/www/html/storage/logs/*.log
tail -f /var/log/supervisor/horizon.log
tail -f /var/log/supervisor/reverb.log
```

### Key File Locations

| File                                  | Purpose                 |
|---------------------------------------|-------------------------|
| `/var/www/html/.env`                  | Application config      |
| `/etc/nginx/sites-available/mixpost`  | Nginx virtual host      |
| `/etc/supervisor/conf.d/mixpost-*.conf` | Supervisor processes  |
| `/etc/cron.d/mixpost`                 | Laravel scheduler       |
| `/etc/php/8.3/fpm/conf.d/99-mixpost.ini` | PHP settings        |

## SSL

When SSL is enabled during setup, Certbot configures Nginx automatically with auto-renewal.

To enable SSL after installation:

```bash
apt install certbot python3-certbot-nginx
certbot --nginx -d yourdomain.com
```

## License

Requires a valid [Mixpost Pro](https://mixpost.app) license.
