[<img src="./art/page-cover.png" alt="Cover" />](https://mixpost.app)

*** 

# Mixpost — VPS Installers

One-command bash installers that provision a fresh Ubuntu VPS and set up Mixpost ready for use.

## Editions

| Edition | Install Command | License Required |
|---------|----------------|------------------|
| **Lite** | `curl -fsSL https://mixpost.app/install-lite.sh \| bash` | No |
| **Pro** | `curl -fsSL https://mixpost.app/install-pro.sh \| bash` | Yes |
| **Enterprise** | `curl -fsSL https://mixpost.app/install-enterprise.sh \| bash` | Yes |

## Docker Testing

Test installer scripts locally using Docker. This simulates a fresh Ubuntu 24.04 VPS.

> **Note:** The installer uses `systemctl` which won't fully work in Docker (services won't actually start). This is fine for testing the script flow, package installation, config generation, and catching errors — but a full end-to-end test still needs a real VPS.

### Build

```bash
docker build -t mixpost-deployment-test .
```

### Test Editions

```bash
# Lite
docker run -it mixpost-deployment-test bash lite/install.sh

# Pro
docker run -it mixpost-deployment-test bash pro/install.sh

# Enterprise
docker run -it mixpost-deployment-test bash enterprise/install.sh
```

### Debug

Drop into a shell to inspect or run commands manually:

```bash
docker run -it mixpost-deployment-test
```

## Documentation

Official documentation: [docs.mixpost.app](https://docs.mixpost.app)