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
	OPENWRT=$(docker run --rm -it -d -v `pwd`:/root/iptmon:ro \
		--cap-add net_admin \
		--sysctl net.ipv6.conf.all.disable_ipv6=0 \
		--sysctl net.ipv6.conf.all.forwarding=1 \
		--ip 172.17.0.42/16 \
    -p 8080:80 \
		openwrtorg/rootfs:x86-64-19.07.1)
}

_set_network() {
	cat <<-EOF | uci batch
	set network.lan=interface
	set network.lan.ifname=eth0
	set network.lan.proto=static
	set network.lan.ipaddr=172.17.0.42/16
	set network.default=route
	set network.default.interface=lan
	set network.default.target=0.0.0.0
	set network.default.netmask=0.0.0.0
	set network.default.gateway=172.17.0.1
	commit
	EOF
	/etc/init.d/network restart
}

_install_iptmon() {
	opkg update
	opkg install /root/iptmon/build/packages/x86_64/iptmon/iptmon*.ipk
}

launch_busybox() {
	docker run --rm -it busybox udhcpc
}

check_iptables() {
  docker exec -it $OPENWRT sh -c '
    iptables -t mangle -nvL iptmon_rx
    iptables -t mangle -nvL iptmon_tx'
}

main() {
  docker exec -it $OPENWRT sh -c '
    . /root/iptmon/test.sh
    _set_network
    sleep 3
    _install_iptmon'
}

cleanup() {
  docker kill $OPENWRT
}

case $1 in
run)
  run_openwrt
  main
  launch_busybox
  check_iptables
  cleanup
;;
esac