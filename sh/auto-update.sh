#!/bin/bash
#===============================================================================
# NAME
#     auto-update – Automated, logged system update script for Debian-based systems
#
# SYNOPSIS
#     Performs unattended system updates via apt, with structured JSON logging 
#     to the systemd journal. Detects and optionally handles reboots or service restarts.
#
# DESCRIPTION
#     This script performs a full system update workflow:
#
#     1. Runs 'apt update' and logs the result.
#     2. Runs 'apt upgrade' with non-interactive handling of config files 
#        (preserving local changes).
#     3. Performs 'autoremove' and 'autoclean' to remove obsolete packages and clean cache.
#     4. Checks if a reboot is required by the system.
#     5. If reboot is required:
#         - Schedules a reboot in 1 minute if AUTO_REBOOT=true.
#         - Otherwise, attempts to restart common services: nginx, apache2, ssh, haproxy, named.
#
#     All logging is done in structured JSON format via 'systemd-cat', including:
#         - timestamp
#         - event_type
#         - server
#         - action
#         - result
#         - message
#         - script_version
#
#     Any failure in update or cleanup steps will cause the script to abort immediately.
#
# REQUIREMENTS
#     - systemd (for journal logging)
#     - Debian-based system with apt
#
# CONFIGURATION
#     The following variables can be adjusted at the top of the script:
#
#         AUTO_REBOOT=true     # Set to false to skip reboot and restart services instead
#         SCRIPT_VERSION="v1.1"
#
# VERSION
#     v1.1
#
#===============================================================================

set -euo pipefail
SCRIPT_NAME="auto-update"
SCRIPT_VERSION="v1.1"
AUTO_REBOOT=true  # Set to false to skip reboot and restart services

# JSON logger
SHWriteJson() {
    local timestamp
    timestamp=$(date --iso-8601=seconds)

    local server="${1:-$(hostname)}"
    local action="${2:-unspecified}"
    local result="${3:-undefined}"
    local event="${4:-generic event}"
    local service="${5:-update-script}"
    local scriptversion="${SCRIPT_VERSION:-v0.0.1}"  # global fallback

    echo "{\"timestamp\":\"$timestamp\",\"event_type\":\"$SCRIPT_NAME\",\"service\":\"$service\",\"server\":\"$server\",\"action\":\"$action\",\"result\":\"$result\",\"message\":\"$event\",\"script_version\":\"$scriptversion\"}" \
    | systemd-cat -t $SCRIPT_NAME
}

# Start
SHWriteJson "$(hostname)" "start" "ok" "System update initiated"

# apt update
if apt update -y; then
    SHWriteJson "$(hostname)" "apt-update" "success" "Package list updated"
else
    SHWriteJson "$(hostname)" "apt-update" "failure" "Failed to update package list"
    exit 1
fi

# apt upgrade with non-interactive config handling
if DEBIAN_FRONTEND=noninteractive \
   apt -o Dpkg::Options::="--force-confdef" \
       -o Dpkg::Options::="--force-confold" \
       upgrade -y; then
    SHWriteJson "$(hostname)" "apt-upgrade" "success" "Packages upgraded (kept local config)"
else
    SHWriteJson "$(hostname)" "apt-upgrade" "failure" "Failed to upgrade packages"
    exit 1
fi

# apt autoremove + autoclean
if apt autoremove -y && apt autoclean -y; then
    SHWriteJson "$(hostname)" "cleanup" "success" "Autoremove and autoclean completed"
else
    SHWriteJson "$(hostname)" "cleanup" "failure" "Cleanup failed"
    exit 1
fi

# Reboot check
REBOOT_REQUIRED=false

if [ -f /var/run/reboot-required ]; then
    REBOOT_REQUIRED=true
    SHWriteJson "$(hostname)" "reboot-check" "required" "System reboot required"
else
    SHWriteJson "$(hostname)" "reboot-check" "not-required" "No reboot required"
fi

# Handle reboot or service restart
if $REBOOT_REQUIRED && $AUTO_REBOOT; then
    SHWriteJson "$(hostname)" "reboot" "scheduled" "System will reboot in 1 minute"
    shutdown -r +1 "System rebooting to complete updates. Save your work!"
elif $REBOOT_REQUIRED && ! $AUTO_REBOOT; then
    SHWriteJson "$(hostname)" "reboot" "skipped" "Reboot required but skipped – restarting services"

    for svc in nginx apache2 ssh haproxy named; do
        if systemctl list-units --type=service | grep -q "${svc}.service"; then
            if systemctl is-active --quiet "$svc"; then
                systemctl restart "$svc"
                SHWriteJson "$(hostname)" "service-restart" "success" "Restarted $svc" "$svc"
            else
                SHWriteJson "$(hostname)" "service-restart" "skipped" "$svc is not active" "$svc"
            fi
        else
            SHWriteJson "$(hostname)" "service-restart" "missing" "$svc not installed" "$svc"
        fi
    done
fi

# End
SHWriteJson "$(hostname)" "end" "success" "System update completed"
