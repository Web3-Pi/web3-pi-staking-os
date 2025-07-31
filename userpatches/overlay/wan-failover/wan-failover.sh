#!/bin/bash

################################################################################
# Simple Network Failover Script (optimized for fastest detection)
#
# Switches internet traffic between PRIMARY and BACKUP interface (e.g. LAN -> WiFi)
# if PRIMARY loses connectivity, and returns asap when PRIMARY is healthy again.
# Uses both ICMP (ping) and DNS resolution to determine link status.
#
# Tracks downtime and total transfer over backup during failover events.
#
# Requires: bash, iproute2, ping, dig OR nslookup, awk
################################################################################

# === FAST REACTION CONFIGURATION ===

PRIMARY_IF="end0"                   # Main interface
BACKUP_IF="wlan0"                   # Backup interface
PING_TARGETS="1.1.1.1 8.8.8.8"      # Public, reliable ping targets
PING_COUNT=1                        # Only 1 echo request per check (minimizes delay)
PING_TIMEOUT=1                      # 1 second per packet (shortest reliable)
FAIL_THRESH=1                       # Only one failed target needed for failover
CHECK_INTERVAL=5                    # Check every 5 second

DNS_TEST_DOMAIN="google.com"        # Must ALWAYS resolve if link is up
DNS_RESOLVER="8.8.8.8"

################################################################################
# ---- SCRIPT LOGIC (do not edit below unless necessary) ----

# Returns 0 (success) if interface $1 is up, 1 otherwise
if_is_up() {
    [[ "$(cat /sys/class/net/$1/operstate 2>/dev/null)" == "up" ]]
}

# Returns current default gateway IP for interface $1 (empty if down/not set)
get_gw_by_if() {
    IFACE="$1"
    ip route | awk -v dev="$IFACE" '$1=="default" && $5==dev {print $3; exit}'
}

# Returns interface which owns current default route
get_current_default_gwdev() {
    ip route | awk '$1 == "default" {print $5; exit}'
}

# Returns number of PING_TARGETS for which ping fails
check_ping() {
    failcount=0
    for IP in $PING_TARGETS; do
        if ! ping -I "$PRIMARY_IF" -c "$PING_COUNT" -W "$PING_TIMEOUT" "$IP" > /dev/null; then
            ((failcount++))
        fi
    done
    echo "$failcount"
}

# Returns 0 if DNS is working (domain resolves to an IP), 1 if not (using 1-second DNS timeout)
check_dns() {
    if command -v dig >/dev/null 2>&1; then
        dig @"$DNS_RESOLVER" "$DNS_TEST_DOMAIN" +short +timeout=1 | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+'
        return $?
    else
        # nslookup does not support easy timeout, but should be reasonably fast
        nslookup "$DNS_TEST_DOMAIN" "$DNS_RESOLVER" 2>/dev/null | grep -q "Address: "
        return $?
    fi
}

# Returns total bytes (RX + TX) transferred on interface $1
iface_bytes() {
    IF="$1"
    awk -v ifname="$IF" '$1 == ifname":" {print $2 + $10}' /proc/net/dev
}

# Main failover state and counters
CURRENT_MODE="primary"
DOWNTIME_START=0
TOTAL_DOWNTIME=0
BACKUP_BYTES_START=0
BACKUP_BYTES_TOTAL=0

################################################################################

while true; do
    # 1. Check if both interfaces are physically up
    if if_is_up "$PRIMARY_IF"; then
        PRIMARY_OK=1
    else
        PRIMARY_OK=0
    fi
    if if_is_up "$BACKUP_IF"; then
        BACKUP_OK=1
    else
        BACKUP_OK=0
    fi

    # 2. Connectivity tests
    FAILS=$(check_ping)
    check_dns
    DNS_OK=$?

    # 3. Get current gateways
    PRIMARY_GW=$(get_gw_by_if "$PRIMARY_IF")
    BACKUP_GW=$(get_gw_by_if "$BACKUP_IF")
    CUR_GWDEV=$(get_current_default_gwdev)

    # 4. Status log for observation
    echo "$(date '+%H:%M:%S') PINGfails:$FAILS DNS:$DNS_OK PRIMARY_GW:$PRIMARY_GW BACKUP_GW:$BACKUP_GW DEF_IF:$CUR_GWDEV"

    #####################
    # Main switching logic
    #
    # Failover from PRIMARY to BACKUP if:
    #  - enough ping targets failed
    #  - or interface down
    #  - or DNS test failed
    if [[ "$CURRENT_MODE" == "primary" ]]; then
        if (( FAILS >= FAIL_THRESH )) || [[ $PRIMARY_OK -eq 0 ]] || [[ $DNS_OK -ne 0 ]]; then
            if [[ -n "$BACKUP_GW" ]] && [[ $BACKUP_OK -eq 1 ]]; then
                echo "$(date '+%H:%M:%S') FAILOVER: Switching to backup: $BACKUP_IF gw $BACKUP_GW (Ping/DNS failed or IF down)"
                ip route replace default via "$BACKUP_GW" dev "$BACKUP_IF"
                CURRENT_MODE="backup"
                DOWNTIME_START=$(date +%s)
                BACKUP_BYTES_START=$(iface_bytes "$BACKUP_IF")
            else
                echo "$(date '+%H:%M:%S') Failover blocked: Backup $BACKUP_IF unavailable (not up or no gateway)"
            fi
        fi
    #
    # Recover to PRIMARY when:
    #  - not failing pings
    #  - PRIMARY is up
    #  - DNS is OK
    #  - PRIMARY has a gateway
    else
        if (( FAILS < FAIL_THRESH )) && [[ $PRIMARY_OK -eq 1 ]] && [[ $DNS_OK -eq 0 ]] && [[ -n "$PRIMARY_GW" ]]; then
            echo "$(date '+%H:%M:%S') RECOVERY: Switching back to primary: $PRIMARY_IF gw $PRIMARY_GW"
            ip route replace default via "$PRIMARY_GW" dev "$PRIMARY_IF"
            # Print failover stats
            NOW=$(date +%s)
            DURATION=$(( NOW - DOWNTIME_START ))
            TOTAL_DOWNTIME=$(( TOTAL_DOWNTIME + DURATION ))
            CUR_BACKUP_BYTES=$(iface_bytes "$BACKUP_IF")
            USAGE=$(( CUR_BACKUP_BYTES - BACKUP_BYTES_START ))
            BACKUP_BYTES_TOTAL=$(( BACKUP_BYTES_TOTAL + USAGE ))

            echo "---- FAILOVER STATS ----"
            echo "Downtime (latest event): $DURATION sec"
            echo "Traffic sent on backup:  $USAGE bytes"
            echo "Total downtime:          $TOTAL_DOWNTIME sec"
            echo "Total traffic on backup: $BACKUP_BYTES_TOTAL bytes"
            echo "------------------------"

            DOWNTIME_START=0
            BACKUP_BYTES_START=0
            CURRENT_MODE="primary"
        #
        elif ! if_is_up "$BACKUP_IF"; then
            echo "$(date '+%H:%M:%S') WARNING: Backup IF $BACKUP_IF has gone! Default route deleted."
            ip route del default
            CURRENT_MODE="unknown"
        fi
    fi

    sleep "$CHECK_INTERVAL"
done