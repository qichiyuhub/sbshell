#!/bin/sh

# 读取当前模式
MODE=$(grep -oP '(?<=^MODE=).*' /etc/sing-box/mode.conf)

# 仅在 TProxy 模式下应用防火墙规则
if [ "$MODE" = "TProxy" ]; then
    echo "应用 TProxy 模式下的防火墙规则..."
    
    # 确保目录存在
    sudo mkdir -p /etc/sing-box/nft

    # 检查并创建表和链
    nft list table inet sing-box >/dev/null 2>&1 || nft add table inet sing-box >/dev/null 2>&1
    nft list chain inet sing-box prerouting_tproxy >/dev/null 2>&1 || nft add chain inet sing-box prerouting_tproxy { type filter hook prerouting priority mangle \; } >/dev/null 2>&1
    nft list chain inet sing-box output_tproxy >/dev/null 2>&1 || nft add chain inet sing-box output_tproxy { type route hook output priority mangle \; } >/dev/null 2>&1

    # 清理旧的规则
    nft flush chain inet sing-box prerouting_tproxy >/dev/null 2>&1
    nft flush chain inet sing-box output_tproxy >/dev/null 2>&1

    # 设置 TProxy 模式下的 nftables 规则和 IP 路由
    cat > /etc/sing-box/nft/nftables.conf <<EOF
table inet sing-box {
    chain prerouting_tproxy {
        type filter hook prerouting priority mangle; policy accept;
        meta l4proto { tcp, udp } th dport 53 tproxy to :7895 accept
        fib daddr type local meta l4proto { tcp, udp } th dport 7895 reject with icmpx type host-unreachable
        fib daddr type local accept
        ip daddr { 127.0.0.0/8, 10.0.0.0/16, 192.168.0.0/16, 100.64.0.0/10, 169.254.0.0/16, 172.16.0.0/12, 224.0.0.0/4, 240.0.0.0/4, 255.255.255.255/32 } accept
        meta l4proto { tcp, udp } tproxy to :7895 meta mark set 1
    }

    chain output_tproxy {
        type route hook output priority mangle; policy accept;
        oifname != "lo" accept
        meta mark 1 accept
        meta l4proto { tcp, udp } th dport 53 meta mark set 1
        ip daddr { 127.0.0.0/8, 10.0.0.0/16, 192.168.0.0/16, 100.64.0.0/10, 169.254.0.0/16, 172.16.0.0/12, 224.0.0.0/4, 240.0.0.0/4, 255.255.255.255/32 } accept
        meta l4proto { tcp, udp } meta mark set 1
    }
}
EOF

    # 应用防火墙规则和 IP 路由
    nft -f /etc/sing-box/nft/nftables.conf >/dev/null 2>&1
    ip rule delete fwmark 1 table 100 2>/dev/null
    ip route delete local default dev lo table 100 2>/dev/null
    ip rule add fwmark 1 table 100 >/dev/null 2>&1
    ip route add local default dev lo table 100 >/dev/null 2>&1

    # 持久化防火墙规则
    nft list ruleset > /etc/nftables.conf

    echo "TProxy 模式的防火墙规则已应用。"
else
    echo "当前模式为 TUN 模式，不需要应用防火墙规则。" >/dev/null 2>&1
fi
