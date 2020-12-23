#!/usr/bin/env bash
set -x

##                                              ##
# Usage: ./test.sh run                           #
# test script does several things:               #
# 1. launch OpenWRT in Docker                    #
# 2. install iptmon                              #
# 3. launch udhcpc in a separate container       #
# 4. check for presence of iptmon rules          #
##                                              ##

TAG=x86-64-19.07.5
IP4_ADDR=172.22.0.22
IP4_GW=172.22.0.1
IP4_CIDR=172.22.0.0/24
IP6_ADDR=fc22::22
IP6_CIDR=fc22::/64

run_openwrt() {
	docker network create iptmon-net --subnet $IP4_CIDR --ipv6 --subnet $IP6_CIDR
	OPENWRT=$(docker run --rm -it -d -v `pwd`:/root/iptmon:ro \
		--ip $IP4_ADDR \
		--ip6 $IP6_ADDR \
		-p 8080:80 \
		--name test_iptmon \
		--hostname openwrt \
		--network iptmon-net \
		--cap-add net_admin \
		--sysctl net.ipv6.conf.all.disable_ipv6=0 \
		openwrtorg/rootfs:$TAG)
}

_set_network() {
	cat <<-EOF | uci batch
		del network.wan
		del network.wan6
		set network.lan=interface
		set network.lan.ifname=eth0
		set network.lan.proto=static
		set network.lan.ipaddr=${IP4_ADDR}/24
		set network.lan.ip6addr=${IP6_ADDR}/64
		set network.default=route
		set network.default.interface=lan
		set network.default.target=0.0.0.0
		set network.default.netmask=0.0.0.0
		set network.default.gateway=$IP4_GW
		add_list dhcp.@dnsmasq[0].server=208.67.222.222
		commit
	EOF
	/etc/init.d/network restart
}

_install_iptmon() {
	until opkg update ; do sleep 1; done
	opkg install dnsmasq \
		luci-app-statistics \
		collectd-mod-iptables \
		/root/iptmon/build/packages/x86_64/iptmon/iptmon*.ipk
}

run_busybox() {
	docker run --rm -d \
	--network iptmon-net \
	--name busybox \
	busybox sh -c "
		udhcpc -x hostname:dhcp-host
		ping $IP4_ADDR &
		ping $IP6_ADDR"
}

restart_dnsmasq() {
	docker exec -it $OPENWRT sh -c '
		/etc/init.d/dnsmasq restart'
}

check_iptables() {
	docker exec -it $OPENWRT sh -c '
		i=1
		interval=5
		tries=3
		while [[ $i -le $tries ]]; do
			echo "############################# $i/$tries"
			for IPTABLES in iptables ip6tables; do
				$IPTABLES -t mangle -nvL iptmon_rx
				$IPTABLES -t mangle -nvL iptmon_tx
			done
			let i+=1
			if [[ $i -gt $tries ]]; then break; fi
			sleep $interval
		done
	'
}

main() {
	run_openwrt
	docker exec -it $OPENWRT sh -c '
		. /root/iptmon/test.sh
		_set_network
		echo -e "# a comment and some newlines\n\n" >> /etc/hosts
		echo "1.2.3.4 static-host" >> /etc/hosts
		_install_iptmon'

	run_busybox
	sleep 5
	restart_dnsmasq
	check_iptables
}

cleanup() {
	docker kill test_iptmon busybox
	docker network rm iptmon-net
}

case $1 in
run)
	trap cleanup EXIT
	main
;;
esac