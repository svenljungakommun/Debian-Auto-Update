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
#         SCRIPT_VERSION="v1.4"
#
# VERSION
#     v1.4
#
#===============================================================================

#!/bin/bash

set -euo pipefail

# GLOBAL
SCRIPT_VERSION="1.4"
CRITICAL_SERVICES="nginx apache2 ssh haproxy named"
RUNNING_SERVICES=()
AUTO_REBOOT=true  # Set to false to skip reboot and restart services

# JSON logger
log_json() {
    local timestamp
    timestamp=$(date --iso-8601=seconds)

    local server="${1:-$(hostname)}"
    local action="${2:-unspecified}"
    local result="${3:-undefined}"
    local event="${4:-generic event}"
    local service="${5:-update-script}"
    local scriptversion="${SCRIPT_VERSION:-1.4}"  # fallback om global saknas

    echo "{\"timestamp\":\"$timestamp\",\"event_type\":\"auto-update\",\"service\":\"$service\",\"server\":\"$server\",\"action\":\"$action\",\"result\":\"$result\",\"message\":\"$event\",\"script_version\":\"$scriptversion\"}" \
    | systemd-cat -t auto-update
}

# Start
log_json "$(hostname)" "start" "ok" "System update initiated"

for svc in ${CRITICAL_SERVICES}; do
    if systemctl is-active --quiet "$svc"; then
        RUNNING_SERVICES+=("$svc")
        log_json "$(hostname)" "service-detect" "active" "$svc is running (will be restarted)" "$svc"
    else
        log_json "$(hostname)" "service-detect" "inactive" "$svc is not running" "$svc"
    fi
done

# apt update
if apt update; then
    log_json "$(hostname)" "apt-update" "success" "Package list updated"
else
    log_json "$(hostname)" "apt-update" "failure" "Failed to update package list"
    exit 1
fi

# apt upgrade with non-interactive config handling
if DEBIAN_FRONTEND=noninteractive \
   apt -o Dpkg::Options::="--force-confdef" \
       -o Dpkg::Options::="--force-confold" \
       upgrade -y; then
    log_json "$(hostname)" "apt-upgrade" "success" "Packages upgraded (kept local config)"
else
    log_json "$(hostname)" "apt-upgrade" "failure" "Failed to upgrade packages"
    exit 1
fi

# apt autoremove + autoclean
if apt autoremove -y && apt autoclean -y; then
    log_json "$(hostname)" "cleanup" "success" "Autoremove and autoclean completed"
else
    log_json "$(hostname)" "cleanup" "failure" "Cleanup failed"
    exit 1
fi

# Reboot check
REBOOT_REQUIRED=false

if [ -f /var/run/reboot-required ]; then
    REBOOT_REQUIRED=true
    log_json "$(hostname)" "reboot-check" "required" "System reboot required"
else
    log_json "$(hostname)" "reboot-check" "not-required" "No reboot required"
fi

# Handle reboot or service restart
if $REBOOT_REQUIRED && $AUTO_REBOOT; then
    log_json "$(hostname)" "reboot" "scheduled" "System will reboot in 1 minute"
    shutdown -r +1 "System rebooting to complete updates. Save your work!"

else
    log_json "$(hostname)" "post-update" "service-restart" "Restarting previously running services"

    systemctl daemon-reexec
    systemctl daemon-reload
    sleep 5

    for svc in "${RUNNING_SERVICES[@]}"; do
        if timeout 30 systemctl restart "$svc"; then
	    echo "Restarted $svc"
            log_json "$(hostname)" "service-restart" "success" "Restarted $svc" "$svc"
        else
            echo "Failed to restart $svc"
            log_json "$(hostname)" "service-restart" "failure" "Failed to restart $svc" "$svc"
        fi
    done
fi

# End
log_json "$(hostname)" "end" "success" "System update completed"
