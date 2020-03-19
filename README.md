# iptmon: Simple iptables bandwidth monitor

![graph](./graph.png)

`iptmon` is a script used to create and update `iptables` firewall rules to count transmit and recieve traffic to/from each host. It is intended to be triggered by dnsmasq using the `--dhcp-script` option, so that as new hosts are added and old leases expire, rules are updated dynamically.

Packet and byte counts can then be scraped by `collectd` using the `iptables` plugin. See `files/etc/collectd/conf.d/iptables.conf` for configuration.

Furthermore, `collectd` can push data to InfluxDB, which can in turn be used as a data source for [Grafana dashboards](https://github.com/oofnikj/docker-openwrt/tree/master/monitoring).

Inspired by [wrtbwmon](https://github.com/pyrovski/wrtbwmon).

---

To make use of `iptmon`, you should already be using `luci-app-statistics` and `collectd` to collect and process metrics.

A [patch](files/usr/lib/lua/luci/statistics/rrdtool/definitions/ip6tables.lua) is included for `luci_statistics` to enable IPv6 firewall time series. ([PR](https://github.com/openwrt/luci/pull/3763))

The `iptables` module can be used to collect per-host metrics.


## Installation on OpenWRT

### On host
Copy files:
```
$ cd files/ && scp -r . ${OPENWRT_HOST}:/
```

### On router

Configure `dnsmasq` to use a custom DHCP script file and load extra config files from a persistent directory (default is `/tmp/dnsmasq.d`). 

We need to do this because by default `--script-arp` is not enabled. 

This will hopefully be [fixed](https://github.com/openwrt/openwrt/pull/2842) but in the mean time:
```
# uci set dhcp.@dnsmasq[0].dhcpscript=/usr/sbin/iptmon
# uci set dhcp.@dnsmasq[0].confdir=/etc/dnsmasq.d/
# uci commit
# /etc/init.d/dnsmasq restart
```

Add init command to firewall startup:
```
# echo '/usr/sbin/iptmon init' >> /etc/firewall.user
```

Set include dir for `collectd`:
```
# uci set luci_statistics.collectd.Include='/etc/collectd/conf.d'
# uci commit
# service luci_statistics restart
```

## removal
To uninstall, run `iptmon remove`. This will restore your `mangle` table to the state it was in before you ran `iptmon init`. Then remove the configuration added above, and delete the files.