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

TAG=x86-64-19.07.1
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
		--network iptmon-net \
		--cap-add net_admin \
		--sysctl net.ipv6.conf.all.forwarding=1 \
		--sysctl net.ipv6.conf.all.disable_ipv6=0 \
		openwrtorg/rootfs:$TAG)
}

_set_network() {
	cat <<-EOF | uci batch
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
	commit
	EOF
	/etc/init.d/network restart
}

_install_iptmon() {
	opkg update
	opkg install /root/iptmon/build/packages/x86_64/iptmon/iptmon*.ipk
}

launch_busybox() {
	docker run --rm -it \
	--network iptmon-net \
	busybox sh -c "
		udhcpc -x hostname:abcdef
		udhcpc6
	"
}

check_iptables() {
	docker exec -it $OPENWRT sh -c '
		kill -HUP $(pgrep dnsmasq | head -n1)
		sleep 1
		iptables -t mangle -nvL iptmon_rx
		iptables -t mangle -nvL iptmon_tx
		ip6tables -t mangle -nvL iptmon_rx
		ip6tables -t mangle -nvL iptmon_tx
		logread -l1000 -e iptmon
	'
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