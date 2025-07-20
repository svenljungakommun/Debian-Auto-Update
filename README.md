# auto-update

A production-grade Bash script for automating and logging system updates on Debian-based systems.  
Logs all activity in structured JSON format to `systemd-journal` and forwards to syslog.

---

## Features

- Non-interactive apt update, upgrade, autoremove, autoclean
- Structured logging using `systemd-cat`
- Optional automatic reboot or service restart
- Syslog forwarding via `rsyslog`
- Suitable for unattended environments

---

## Installation

1. Copy the script:

```bash
sudo cp auto-update.sh /usr/local/sbin/auto-update.sh
sudo chmod 750 /usr/local/sbin/auto-update.sh
````

2. Test it:

```bash
sudo /usr/local/sbin/auto-update.sh
```

---

## Syslog Forwarding via `/etc/rsyslog.conf`

```conf
# Forward all logs to remote server via TCP (recommended)
*.* @@syslog.example.com:514
```

* Use `@@` for TCP instead of UDP
* Restart rsyslog:

```bash
sudo systemctl restart rsyslog
```

To check that messages are being forwarded:

```bash
journalctl -t auto-update
```

---

## Scheduling with crontab

Run weekly (Sunday at 03:00):

```bash
sudo crontab -e
```

Add:

```cron
0 3 * * 0 /usr/local/sbin/auto-update.sh
```

---

## Configuration

Edit top of script:

```bash
SCRIPT_VERSION="v1.1"
AUTO_REBOOT=true
```

Set `AUTO_REBOOT=false` to restart services instead of rebooting.

---

## Log Output Example

```json
{
  "timestamp": "2025-07-20T03:00:00+02:00",
  "event_type": "auto-update",
  "server": "host01",
  "action": "apt-upgrade",
  "result": "success",
  "message": "Packages upgraded (kept local config)",
  "script_version": "v1.1"
}
```
