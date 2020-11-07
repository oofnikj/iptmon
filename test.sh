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

TAG=x86-64-19.07.4
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
	opkg install dnsmasq \
		luci-app-statistics \
		collectd-mod-iptables \
		/root/iptmon/build/packages/x86_64/iptmon/iptmon*.ipk
}

launch_busybox() {
	docker run --rm -it -d \
	--network iptmon-net \
	--name busybox \
	busybox sh -c "
		udhcpc -x hostname:abcdef
		udhcpc6
		ping $IP6_ADDR
	"
}

restart_dnsmasq() {
	docker exec -it $OPENWRT sh -c '
		/etc/init.d/dnsmasq restart'
}

check_iptables() {
	docker exec -it $OPENWRT sh -c '
		iptables -t mangle -nvL iptmon_rx
		iptables -t mangle -nvL iptmon_tx
		ip6tables -t mangle -nvL iptmon_rx
		ip6tables -t mangle -nvL iptmon_tx
	'
}

main() {
	docker exec -it $OPENWRT sh -c '
		. /root/iptmon/test.sh
		_set_network
		sleep 3
		echo "# a comment" >> /etc/hosts
		_install_iptmon'
}

cleanup() {
	docker kill test_iptmon busybox
	docker network rm iptmon-net
}

case $1 in
run)
	run_openwrt
	main
	launch_busybox
	sleep 5
	restart_dnsmasq
	sleep 5
	check_iptables
;;
cleanup)
	cleanup
;;
esac