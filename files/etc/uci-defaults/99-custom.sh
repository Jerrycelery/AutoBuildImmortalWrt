#!/bin/sh
# 99-custom.sh 就是immortalwrt固件首次启动时运行的脚本 位于/etc/uci-defaults/99-custom.sh
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >>$LOGFILE

# 默认防火墙允许输入
uci set firewall.@zone[1].input='ACCEPT'

# 设置time.android.com域名解析
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"

# 加载PPPoE配置文件
SETTINGS_FILE="/etc/config/pppoe-settings"
if [ -f "$SETTINGS_FILE" ]; then
    . "$SETTINGS_FILE"
else
    echo "PPPoE settings file not found. Skipping." >>$LOGFILE
fi

# 检查物理网卡数量（仅用于日志）
count=0
ifnames=""
for iface in /sys/class/net/*; do
    iface_name=$(basename "$iface")
    if [ -e "$iface/device" ] && echo "$iface_name" | grep -Eq '^eth|^en'; then
        count=$((count + 1))
        ifnames="$ifnames $iface_name"
    fi
done
ifnames=$(echo "$ifnames" | awk '{$1=$1};1')
echo "Detected interfaces: $ifnames (count=$count)" >>$LOGFILE

# ========== 强制指定网卡接口映射 ==========
wan_ifname="eth3"
lan_ifnames="eth0 eth1 eth2"
echo "Manual override: WAN=$wan_ifname, LAN=$lan_ifnames" >>$LOGFILE
count=4

# 网络设置
if [ "$count" -eq 1 ]; then
    uci set network.lan.proto='dhcp'
    uci delete network.lan.ipaddr
    uci delete network.lan.netmask
    uci delete network.lan.gateway
    uci delete network.lan.dns
    uci commit network
elif [ "$count" -gt 1 ]; then
    # 设置 WAN 接口
    uci set network.wan=interface
    uci set network.wan.device="$wan_ifname"
    uci set network.wan.proto='dhcp'

    # 设置 WAN6（IPv6）接口
    uci set network.wan6=interface
    uci set network.wan6.device="$wan_ifname"

    # 配置 LAN 接口成员
    section=$(uci show network | awk -F '[.=]' '/\.@?device\[\d+\]\.name=.br-lan.$/ {print $2; exit}')
    if [ -z "$section" ]; then
        echo "error: cannot find device 'br-lan'." >>$LOGFILE
    else
        uci -q delete "network.$section.ports"
        for port in $lan_ifnames; do
            uci add_list "network.$section.ports"="$port"
        done
        echo "ports of device 'br-lan' updated to: $lan_ifnames" >>$LOGFILE
    fi

    # 设置LAN口静态IP
    uci set network.lan.proto='static'
    uci set network.lan.ipaddr='192.168.5.1'
    uci set network.lan.netmask='255.255.255.0'
    echo "set LAN IP to 192.168.5.1 at $(date)" >>$LOGFILE

    # 设置PPPoE（如果启用）
    echo "print enable_pppoe value === $enable_pppoe" >>$LOGFILE
    if [ "$enable_pppoe" = "yes" ]; then
        echo "PPPoE is enabled at $(date)" >>$LOGFILE
        uci set network.wan.proto='pppoe'
        uci set network.wan.username="$pppoe_account"
        uci set network.wan.password="$pppoe_password"
        uci set network.wan.peerdns='1'
        uci set network.wan.auto='1'
        uci set network.wan6.proto='none'
        echo "PPPoE configuration completed successfully." >>$LOGFILE
    else
        echo "PPPoE is not enabled. Skipping configuration." >>$LOGFILE
    fi
fi

# Docker防火墙规则
if command -v dockerd >/dev/null 2>&1; then
    echo "检测到 Docker，正在配置防火墙规则..." >>$LOGFILE
    FW_FILE="/etc/config/firewall"
    uci delete firewall.docker

    for idx in $(uci show firewall | grep "=forwarding" | cut -d[ -f2 | cut -d] -f1 | sort -rn); do
        src=$(uci get firewall.@forwarding[$idx].src 2>/dev/null)
        dest=$(uci get firewall.@forwarding[$idx].dest 2>/dev/null)
        if [ "$src" = "docker" ] || [ "$dest" = "docker" ]; then
            uci delete firewall.@forwarding[$idx]
        fi
    done
    uci commit firewall

    cat <<EOF >>"$FW_FILE"

config zone 'docker'
  option input 'ACCEPT'
  option output 'ACCEPT'
  option forward 'ACCEPT'
  option name 'docker'
  list subnet '172.16.0.0/12'

config forwarding
  option src 'docker'
  option dest 'lan'

config forwarding
  option src 'docker'
  option dest 'wan'

config forwarding
  option src 'lan'
  option dest 'docker'
EOF
else
    echo "未检测到 Docker，跳过防火墙配置。" >>$LOGFILE
fi

# 开放TTYD终端与SSH访问
uci delete ttyd.@ttyd[0].interface
uci set dropbear.@dropbear[0].Interface=''
uci commit

# 设置编译者信息
FILE_PATH="/etc/openwrt_release"
NEW_DESCRIPTION="Packaged by JerryLee"
sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"

exit 0

