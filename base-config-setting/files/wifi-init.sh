#!/bin/sh

wifi_setup_radio()
{
	local radio=$1

	if uci get wireless.${radio} >/dev/null 2>&1; then
		#FIXME hack
		local path htmode
		if [ "${radio}" = "radio0" ] || [ "${radio}" = "radio1" ]; then
		if test -e /sys/kernel/debug/ieee80211/phy0/mt76 &&
		   [ "$(readlink /sys/class/ieee80211/phy0/device)" = "$(readlink /sys/class/ieee80211/phy1/device)" ]; then
			htmode="$(uci get wireless.${radio}.htmode)"
			path="$(uci get wireless.${radio}.path)"
			if test -z "${htmode##HE*}"; then
				htmode=HE
			else
				htmode=
			fi
			if test -z "${path#*+1}"; then
				uci set wireless.${radio}.phy='phy1'
				uci set wireless.${radio}.htmode="${htmode:-VHT}80"
				uci set wireless.${radio}.hwmode='11be'
				uci set wireless.${radio}.band='5g'
			else
				uci set wireless.${radio}.phy='phy0'
				uci set wireless.${radio}.htmode="${htmode:-HT}20"
				uci set wireless.${radio}.hwmode='11be'
				uci set wireless.${radio}.band='2g'
			fi
			uci delete wireless.${radio}.path
		fi
		fi # radio0/radio1

		uci -q batch <<-EOT
			set wireless.${radio}.disabled='0'
			set wireless.${radio}.country='US'
			set wireless.${radio}.hwmode='11be'
			set wireless.${radio}.cell_density='0'
		EOT

		# Configuración por banda
		if [ "$(uci get wireless.${radio}.band 2>/dev/null)" = "2g" ]; then
			# BANDA 2.4GHz: Canal 6
			uci set wireless.${radio}.channel='6'
			
		elif [ "$(uci get wireless.${radio}.band 2>/dev/null)" = "5g" ]; then
			# BANDA 5GHz: Canal 100
			uci set wireless.${radio}.channel='100'
			
		elif uci get wireless.${radio}.htmode 2>/dev/null | grep -q EHT; then
			# BANDA 6GHz: Canal 36
			uci set wireless.${radio}.channel='36'
			uci set wireless.${radio}.band='6g'
		else
			# Fallback para otras bandas
			uci set wireless.${radio}.channel='auto'
		fi

		# Crear interfaz WiFi
		obj=$(uci add wireless wifi-iface)
		if test -n "$obj"; then
			uci set wireless.$obj.device="${radio}"
			uci set wireless.$obj.network='lan'
			uci set wireless.$obj.mode='ap'
			uci set wireless.$obj.encryption='sae'
			uci set wireless.$obj.key='12345678'
			
			# SSID según banda
			if [ "$(uci get wireless.${radio}.band 2>/dev/null)" = "6g" ]; then
				uci set wireless.$obj.ssid="BANANA_6G"
				uci set wireless.$obj.ocv='0'
				
			elif [ "$(uci get wireless.${radio}.band 2>/dev/null)" = "5g" ]; then
				uci set wireless.$obj.ssid="BANANA_5G"
				
			elif [ "$(uci get wireless.${radio}.band 2>/dev/null)" = "2g" ]; then
				uci set wireless.$obj.ssid="BANANA_2G"
			else
				uci set wireless.$obj.ssid="BANANA"
			fi
			
			# IEEE 802.11r (Fast Roaming) - Solo si no es bcma o Cypress
			if uci get wireless.${radio}.path | grep -q bcma || iwinfo wlan${radio:5} info | grep -qi Cypress; then
				:
			else
				uci set wireless.$obj.ieee80211r='1'
				uci set wireless.$obj.ft_over_ds='0'
				uci set wireless.$obj.ft_psk_generate_local='1'
			fi
			
			# Eliminar ft_psk_generate_local en 6GHz (incompatible con SAE)
			if [ "$(uci get wireless.${radio}.band 2>/dev/null)" = "6g" ]; then
				uci delete wireless.$obj.ft_psk_generate_local 2>/dev/null
			fi
		fi
	fi
}

wifi_first_init()
{
	while uci delete wireless.@wifi-iface[0] >/dev/null 2>&1; do :; done
	for radio in radio0 radio1 radio2 radio3 wifi0 wifi1 wifi2 wifi3; do
		wifi_setup_radio ${radio}
	done
	uci commit wireless

	# wireless migration
	local widx=0
	local change=0
	while uci rename wireless.@wifi-iface[$widx]=wifinet$widx >/dev/null 2>&1; do widx=$((widx+1)); done
	uci changes wireless | tr ".='" "   " | while read _ a b; do
		if [ "x$a" != "x$b" ]; then
			uci commit wireless
			change=1
			break
		fi
	done
	[ "x$change" = "x0" ] && uci revert wireless
}
