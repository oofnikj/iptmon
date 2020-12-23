#!/bin/bash

##                                                                ##
# Usage: ./docker-build.sh                                         #
# Package will be built in                                         #
#   ./build/packages/x86_64/iptmon/iptmon_$VERSION_all.ipk         #
##                                                                ##

run_sdk() {
	mkdir -p build
	chmod a+rwx build
	docker run --rm -it \
		-v $(pwd)/build:/home/build/openwrt/bin \
		-v $(pwd):/home/build/iptmon \
		openwrtorg/sdk /home/build/iptmon/$0 build_ipk
}

build_ipk() {
	echo src-link iptmon /home/build/iptmon > feeds.conf
	./scripts/feeds update
	./scripts/feeds install iptmon
	make defconfig
	make package/iptmon/compile V=s
}

case $1 in
build_ipk)
	build_ipk
;;
*)
	run_sdk
;;
esac