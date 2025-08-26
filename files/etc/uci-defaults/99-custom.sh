#!/bin/sh
# 99-custom.sh 就是 immortalwrt 固件首次启动时运行的脚本
# 位于固件内的 /etc/uci-defaults/99-custom.sh

# Log file for debugging
LOGFILE="/etc/config/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >>$LOGFILE

# 1. 扫描物理网卡
ifnames=""
for iface in /sys/class/net/*; do
    iface_name=$(basename "$iface")
    if [ -e "$iface/device" ] && echo "$iface_name" | grep -Eq '^eth|^en'; then
        ifnames="$ifnames $iface_name"
    fi
done
ifnames=$(echo "$ifnames" | awk '{$1=$1};1')   # 去掉多余空格

count=$(echo "$ifnames" | wc -w)
echo "Detected physical interfaces: $ifnames" >>$LOGFILE
echo "Interface count: $count" >>$LOGFILE

# 2. 按需分配 WAN / LAN
if [ "$count" -eq 1 ]; then
    # 单网口设备直接做 LAN DHCP
    wan_ifname=""
    lan_ifnames="$ifnames"
    echo "Single interface, using DHCP LAN: $lan_ifnames" >>$LOGFILE
else
    # 多网口：最后一个是 WAN，其余是 LAN
    wan_ifname=$(echo "$ifnames" | awk '{print $NF}')
    lan_ifnames=$(echo "$ifnames" | awk '{$NF=""; print $0}')
    echo "Using last interface as WAN=$wan_ifname, LAN=$lan_ifnames" >>$LOGFILE
fi

# -------------------
# 网络配置
# -------------------

# 清理旧配置
uci -q delete network.lan.ipaddr
uci -q delete network.lan.netmask
uci -q delete network.lan.type
uci -q delete network.lan.ifname
uci -q delete network.wan.ifname
uci -q delete network.wan.proto

# 配置 LAN
uci set network.lan=interface
uci set network.lan.proto='static'
uci set network.lan.ipaddr='192.168.5.1'
uci set network.lan.netmask='255.255.255.0'
uci set network.lan.device="$lan_ifnames"

# 配置 WAN (仅当存在)
if [ -n "$wan_ifname" ]; then
    uci set network.wan=interface
    uci set network.wan.proto='dhcp'
    uci set network.wan.device="$wan_ifname"
fi

# 防火墙设置
uci set firewall.@zone[0].network='lan'
uci set firewall.@zone[1].network='wan'

# 提交配置
uci commit network
uci commit firewall

echo "Finished 99-custom.sh at $(date)" >>$LOGFILE
exit 0
