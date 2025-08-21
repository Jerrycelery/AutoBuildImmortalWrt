#!/bin/sh
# 99-custom.sh —— ImmortalWRT 首次启动脚本
# 位于 /etc/uci-defaults/99-custom.sh

LOGFILE="/etc/config/uci-defaults-log.txt"

log() {
    echo "[$(date '+%F %T')] $*" >>$LOGFILE
}

log "Starting 99-custom.sh"

# 设置默认防火墙规则，方便单网口虚拟机访问 WebUI
uci set firewall.@zone[1].input='ACCEPT'

# 设置主机名映射，解决安卓 TV 无法联网问题
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"

# 检查 PPPoE 配置
SETTINGS_FILE="/etc/config/pppoe-settings"
if [ -f "$SETTINGS_FILE" ]; then
    . "$SETTINGS_FILE"
else
    log "PPPoE settings file not found, using defaults."
fi

# 设置 PPPoE默认值
enable_pppoe=${enable_pppoe:-no}
pppoe_account=${pppoe_account:-""}
pppoe_password=${pppoe_password:-""}

# 固定网口分配
WAN_IF="eth3"
LAN_IFS="eth0 eth1 eth2"

# 设置 WAN 接口
uci set network.wan=interface
uci set network.wan.device="$WAN_IF"
uci set network.wan.proto='dhcp'

# 设置 WAN6
uci set network.wan6=interface
uci set network.wan6.device="$WAN_IF"

# 配置 LAN 接口
uci set network.lan.proto='static'
uci set network.lan.netmask='255.255.255.0'

IP_VALUE_FILE="/etc/config/custom_router_ip.txt"
if [ -f "$IP_VALUE_FILE" ]; then
    CUSTOM_IP=$(cat "$IP_VALUE_FILE")
    uci set network.lan.ipaddr="$CUSTOM_IP"
    log "Custom router IP is $CUSTOM_IP"
else
    uci set network.lan.ipaddr='192.168.100.1'
    log "Default router IP is 192.168.100.1"
fi

# 更新 LAN 端口列表
section=$(uci show network | awk -F '[.=]' '/\.@?device\[\d+\]\.name=.br-lan.$/ {print $2; exit}')
if [ -z "$section" ]; then
    log "Error: cannot find device 'br-lan'."
else
    uci -q delete "network.$section.ports"
    for port in $LAN_IFS; do
        uci add_list "network.$section.ports"="$port"
    done
    log "Ports of device 'br-lan' updated: $LAN_IFS"
fi

# 判断是否启用 PPPoE
log "enable_pppoe=$enable_pppoe"
if [ "$enable_pppoe" = "yes" ]; then
    log "PPPoE enabled, configuring..."
    uci set network.wan.proto='pppoe'
    uci set network.wan.username="$pppoe_account"
    uci set network.wan.password="$pppoe_password"
    uci set network.wan.peerdns='1'
    uci set network.wan.auto='1'
    uci set network.wan6.proto='none'
    log "PPPoE configuration completed."
else
    log "PPPoE not enabled, skipping."
fi

uci commit network

# Docker 防火墙配置
if command -v dockerd >/dev/null 2>&1; then
    log "Docker detected, configuring firewall..."
    uci -q delete firewall.docker

    # 删除涉及 docker 的 forwarding
    for idx in $(uci show firewall | grep "=forwarding" | cut -d[ -f2 | cut -d] -f1 | sort -rn); do
        src=$(uci get firewall.@forwarding[$idx].src 2>/dev/null)
        dest=$(uci get firewall.@forwarding[$idx].dest 2>/dev/null)
        if [ "$src" = "docker" ] || [ "$dest" = "docker" ]; then
            uci delete firewall.@forwarding[$idx]
        fi
    done

    uci commit firewall

    # 添加 docker zone 和转发
    cat <<EOF >>/etc/config/firewall

config zone 'docker'
    option name 'docker'
    option input 'ACCEPT'
    option output 'ACCEPT'
    option forward 'ACCEPT'
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

    log "Docker firewall configuration completed."
else
    log "Docker not detected, skipping firewall configuration."
fi

# 设置 TTYD 和 Dropbear
uci delete ttyd.@ttyd[0].interface
uci set dropbear.@dropbear[0].Interface=''
uci commit

# 修改编译作者信息
FILE_PATH="/etc/openwrt_release"
NEW_DESCRIPTION="Packaged by JerryLee"
sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"
sed -i "s/DISTRIB_PACKAGER='[^']*'/DISTRIB_PACKAGER='JerryLee'/" "$FILE_PATH" || \
    echo "DISTRIB_PACKAGER='JerryLee'" >> "$FILE_PATH"

# 去掉 zsh 调用（luci-app-advancedplus）
if opkg list-installed | grep -q '^luci-app-advancedplus '; then
    sed -i '/\/usr\/bin\/zsh/d' /etc/profile
    sed -i '/\/bin\/zsh/d' /etc/init.d/advancedplus
    sed -i '/\/usr\/bin\/zsh/d' /etc/init.d/advancedplus
fi

log "99-custom.sh completed."
exit 0
