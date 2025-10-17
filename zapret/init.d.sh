#!/bin/sh /etc/rc.common
# Copyright (c) 2024 remittor
# Modified by TanLan for smarter boot/hotplug sync

USE_PROCD=1
START=21
STOP=89

EXEDIR=/opt/zapret
ZAPRET_BASE=/opt/zapret
SCRIPT_FILENAME=$1

. /opt/zapret/comfunc.sh

if ! is_valid_config; then
    logger -p err -t ZAPRET "Wrong main config: $ZAPRET_CONFIG"
    exit 91
fi

. $ZAPRET_ORIG_INITD

is_run_on_boot && IS_RUN_ON_BOOT=1 || IS_RUN_ON_BOOT=0

# === helper: check if WAN is up ===
is_inet_ready() {
    local iface=$(uci get network.wan.ifname 2>/dev/null)
    [ -z "$iface" ] && iface=$(uci get network.@interface[0].ifname 2>/dev/null)
    [ -z "$iface" ] && return 1

    # check IPv4 connectivity
    local has_v4=$(ip -4 addr show dev "$iface" | grep -q "inet " && echo 1)
    # check IPv6 connectivity (delayed)
    local has_v6=$(ip -6 addr show dev "$iface" | grep -q "inet6 " && echo 1)

    [ "$has_v4" = "1" ] || [ "$has_v6" = "1" ]
}

# === helper: wait for real internet connectivity ===
wait_for_inet() {
    local timeout=30
    local waited=0
    logger -t ZAPRET "Waiting for network to be ready..."

    while [ $waited -lt $timeout ]; do
        if is_inet_ready; then
            logger -t ZAPRET "Network ready after $waited seconds."
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done

    logger -p warn -t ZAPRET "Network not ready after $timeout seconds, starting anyway."
}

# === standard OpenWrt service handlers ===
enable() {
    /bin/sh /etc/rc.common $ZAPRET_ORIG_INITD enable
}

enabled() {
    /bin/sh /etc/rc.common $ZAPRET_ORIG_INITD enabled
}

boot() {
    wait_for_inet
    init_before_start "$DAEMON_LOG_ENABLE"
    /bin/sh /etc/rc.common $ZAPRET_ORIG_INITD start "$@"
}

start() {
    wait_for_inet
    init_before_start "$DAEMON_LOG_ENABLE"
    /bin/sh /etc/rc.common $ZAPRET_ORIG_INITD start "$@"
}

restart() {
    init_before_start "$DAEMON_LOG_ENABLE"
    /bin/sh /etc/rc.common $ZAPRET_ORIG_INITD restart "$@"
}

stop() {
    /bin/sh /etc/rc.common $ZAPRET_ORIG_INITD stop "$@"
}

# === HOTPLUG integration ===
add_hotplug_hook() {
    local hook_file="/etc/hotplug.d/iface/99-zapret"
    cat <<'EOF' > "$hook_file"
#!/bin/sh
[ "$INTERFACE" = "wan" ] || exit 0

case "$ACTION" in
    ifup)
        logger -t ZAPRET "WAN is up, restarting zapret..."
        /etc/init.d/zapret restart
        ;;
    ifdown)
        logger -t ZAPRET "WAN is down, stopping zapret..."
        /etc/init.d/zapret stop
        ;;
esac
EOF
    chmod +x "$hook_file"
}

# Add hotplug-hook in first run
[ ! -f /etc/hotplug.d/iface/99-zapret ] && add_hotplug_hook
