#!/bin/sh /etc/rc.common
# Copyright (c) 2024 remittor
# Modified by Anton (2025) — добавлена проверка доступности сети и автоконтроль zapret

USE_PROCD=1
# after network
START=21

SCRIPT_FILENAME=$1

. /opt/zapret/comfunc.sh

if ! is_valid_config ; then
	logger -p err -t ZAPRET "Wrong main config: $ZAPRET_CONFIG"
	exit 91
fi

. $ZAPRET_ORIG_INITD

EXEDIR=/opt/zapret
ZAPRET_BASE=/opt/zapret

is_run_on_boot && IS_RUN_ON_BOOT=1 || IS_RUN_ON_BOOT=0


# ---------- новые функции ----------

get_iface() {
	local IFACE
	IFACE="$(uci -q get network.wan.ifname 2>/dev/null)"
	[ -z "$IFACE" ] && IFACE="$(uci -q get network.internet.ifname 2>/dev/null)"
	[ -z "$IFACE" ] && IFACE="$(uci -q get network.@interface[0].ifname 2>/dev/null)"
	[ -z "$IFACE" ] && IFACE="pppoe-wan"
	echo "$IFACE"
}

wait_for_internet() {
	local IFACE="$(get_iface)"
	local WAIT_SECS=0
	local MAX_WAIT=60
	logger -t ZAPRET "Ожидание появления интернет-соединения на интерфейсе $IFACE..."

	while [ $WAIT_SECS -lt $MAX_WAIT ]; do
		if ping -c1 -W2 -I "$IFACE" 1.1.1.1 >/dev/null 2>&1; then
			logger -t ZAPRET "Интернет IPv4 доступен."
			break
		fi
		sleep 3
		WAIT_SECS=$((WAIT_SECS + 3))
	done

	# дополнительная задержка для IPv6
	sleep 5
	logger -t ZAPRET "Проверка IPv6..."
	if ping6 -c1 -W2 -I "$IFACE" 2606:4700:4700::1111 >/dev/null 2>&1; then
		logger -t ZAPRET "Интернет IPv6 доступен."
	else
		logger -t ZAPRET "IPv6 не отвечает, продолжаем запуск."
	fi
}

monitor_internet() {
	local IFACE="$(get_iface)"
	while true; do
		if ping -c1 -W2 -I "$IFACE" 1.1.1.1 >/dev/null 2>&1; then
			sleep 15
			continue
		else
			logger -p notice -t ZAPRET "Интернет потерян — останавливаю zapret."
			/etc/init.d/zapret stop

			# ждём восстановления
			while ! ping -c1 -W2 -I "$IFACE" 1.1.1.1 >/dev/null 2>&1; do
				sleep 5
			done

			logger -t ZAPRET "Интернет восстановлен — перезапускаю zapret."
			/etc/init.d/zapret start
		fi
	done &
}


# ---------- оригинальные функции ----------

function enable {
	local run_on_boot=""
	patch_luci_header_ut
	if [ "$IS_RUN_ON_BOOT" = "1" ]; then
		if [ -n "$ZAPRET_CFG_SEC_NAME" ]; then
			run_on_boot=$( get_run_on_boot_option )
			if [ $run_on_boot != 1 ]; then
				logger -p notice -t ZAPRET "Attempt to enable service, but service blocked!"
				return 61
			fi
		fi
	fi
	if [ -n "$ZAPRET_CFG_SEC_NAME" ]; then
		uci set $ZAPRET_CFG_NAME.config.run_on_boot=1
		uci commit
	fi
	/bin/sh /etc/rc.common $ZAPRET_ORIG_INITD enable
}

function enabled {
	local run_on_boot=""
	if [ -n "$ZAPRET_CFG_SEC_NAME" ]; then
		run_on_boot=$( get_run_on_boot_option )
		if [ $run_on_boot != 1 ]; then
			if [ "$IS_RUN_ON_BOOT" = "1" ]; then
				logger -p notice -t ZAPRET "Service is blocked!"
			fi
			return 61
		fi
	fi
	/bin/sh /etc/rc.common $ZAPRET_ORIG_INITD enabled
}

function boot {
	local run_on_boot=""
	patch_luci_header_ut
	if [ "$IS_RUN_ON_BOOT" = "1" ]; then
		if [ -n "$ZAPRET_CFG_SEC_NAME" ]; then
			run_on_boot=$( get_run_on_boot_option )
			if [ $run_on_boot != 1 ]; then
				logger -p notice -t ZAPRET "Attempt to run service on boot! Service is blocked!"
				return 61
			fi
		fi
	fi
	wait_for_internet
	init_before_start "$DAEMON_LOG_ENABLE"
	/bin/sh /etc/rc.common $ZAPRET_ORIG_INITD start "$@"
	monitor_internet
}

function start {
	wait_for_internet
	init_before_start "$DAEMON_LOG_ENABLE"
	/bin/sh /etc/rc.common $ZAPRET_ORIG_INITD start "$@"
	monitor_internet
}

function restart {
	init_before_start "$DAEMON_LOG_ENABLE"
	/bin/sh /etc/rc.common $ZAPRET_ORIG_INITD restart "$@"
}
