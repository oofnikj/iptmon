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

run_openwrt() {
	docker network create iptmon-net --subnet 172.22.0.0/24 --ipv6 --subnet fc22::/64
	OPENWRT=$(docker run --rm -it -d -v `pwd`:/root/iptmon:ro \
		--ip 172.22.0.22 \
		--ip6 fc22::22 \
		-p 8080:80 \
		--name test_iptmon \
		--network iptmon-net \
		--cap-add net_admin \
		--sysctl net.ipv6.conf.all.forwarding=1 \
		openwrtorg/rootfs:x86-64-19.07.1)
}

_set_network() {
	cat <<-EOF | uci batch
	set network.lan=interface
	set network.lan.ifname=eth0
	set network.lan.proto=static
	set network.lan.ipaddr=172.22.0.22/24
	set network.lan.ip6addr=fc22::22/64
	set network.default=route
	set network.default.interface=lan
	set network.default.target=0.0.0.0
	set network.default.netmask=0.0.0.0
	set network.default.gateway=172.22.0.1
	commit
	EOF
	/etc/init.d/network restart
}

_install_iptmon() {
	opkg update
	opkg install /root/iptmon/build/packages/x86_64/iptmon/iptmon*.ipk
	/etc/init.d/dnsmasq restart
}

launch_busybox() {
	docker run --rm -it \
	--network iptmon-net \
	busybox sh -c '
		udhcpc -v -x hostname:abcdef
		udhcpc6
		ping -c4 fc22::22'
}

check_iptables() {
	docker exec -it $OPENWRT sh -c '
		iptables -t mangle -nvL iptmon_rx
		iptables -t mangle -nvL iptmon_tx
		ip6tables -t mangle -nvL iptmon_rx
		ip6tables -t mangle -nvL iptmon_tx'
}

main() {
	docker exec -it $OPENWRT sh -c '
		. /root/iptmon/test.sh
		_set_network
		sleep 3
		_install_iptmon'
}

cleanup() {
	docker kill test_iptmon
	docker network rm iptmon-net
}

case $1 in
run)
	run_openwrt
	main
	launch_busybox
	check_iptables
;;
cleanup)
	cleanup
;;
esac