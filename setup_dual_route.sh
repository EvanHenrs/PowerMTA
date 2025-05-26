#!/bin/bash

# 校验 IPv4 地址格式
function is_valid_ip() {
    [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] &&
    for octet in $(echo $1 | tr '.' ' '); do
        [[ $octet -ge 0 && $octet -le 255 ]] || return 1
    done
}

# 校验 CIDR 网段格式（IP/掩码）
function is_valid_cidr() {
    [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] &&
    is_valid_ip "${1%/*}" &&
    [[ ${1#*/} -ge 1 && ${1#*/} -le 32 ]]
}
# 自动获取 eth0 和 eth1 IP
ETH0_IP=$(ip -4 addr show dev eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
ETH1_IP=$(ip -4 addr show dev eth1 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
GATEWAY=$(ip route | grep '^default' | head -n1 | awk '{print $3}')

# 若失败则手动输入，直到格式合法
while ! is_valid_ip "$ETH0_IP"; do
    read -p "❓ 请输入 eth0 IP（如 172.30.174.243）: " ETH0_IP
done

while ! is_valid_ip "$ETH1_IP"; do
    read -p "❓ 请输入 eth1 IP（如 172.30.174.244）: " ETH1_IP
done

while ! is_valid_ip "$GATEWAY"; do
    read -p "❓ 请输入默认网关（如 172.30.175.253）: " GATEWAY
done

# 获取网段
NET0_SUBNET=$(ip route | grep eth0 | grep 'proto kernel' | awk '{print $1}' | head -n1)
NET1_SUBNET=$(ip route | grep eth1 | grep 'proto kernel' | awk '{print $1}' | head -n1)

while ! is_valid_cidr "$NET0_SUBNET"; do
    read -p "❓ 请输入 eth0 网段（如 172.30.160.0/20）: " NET0_SUBNET
done

while ! is_valid_cidr "$NET1_SUBNET"; do
    read -p "❓ 请输入 eth1 网段（如 172.30.160.0/20）: " NET1_SUBNET
done


echo "✅ eth0 IP: $ETH0_IP"
echo "✅ eth1 IP: $ETH1_IP"
echo "✅ 默认网关: $GATEWAY"
echo "✅ eth0 网段: $NET0_SUBNET"
echo "✅ eth1 网段: $NET1_SUBNET"
echo ""
read -p "❓ 请确认以上信息是否正确？输入 y 确认，n 取消并退出: " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "❌ 操作已取消。退出脚本。"
    exit 0
fi
# 设置 rt_tables
echo "配置 /etc/iproute2/rt_tables ..."
cat <<EOF > /etc/iproute2/rt_tables
# added for dual net
250     net0
251     net1
EOF

# 生成策略路由段内容
ROUTE_SCRIPT="
# === Dual NIC routing setup ===
sleep 5

ip route flush table net0
ip route add default via $GATEWAY dev eth0 table net0
ip route add $NET0_SUBNET dev eth0 table net0
ip rule add from $ETH0_IP table net0

ip route flush table net1
ip route add default via $GATEWAY dev eth1 table net1
ip route add $NET1_SUBNET dev eth1 table net1
ip rule add from $ETH1_IP table net1
# === End of Dual NIC routing ===
"

# 检查 rc.local 是否已包含该段，避免重复追加
if ! grep -q "Dual NIC routing setup" /etc/rc.local; then
    echo "🔧 向 /etc/rc.local 追加路由规则..."
    echo "$ROUTE_SCRIPT" >> /etc/rc.local
else
    echo "✅ /etc/rc.local 已包含路由规则，无需重复添加。"
fi

chmod +x /etc/rc.local

echo "🎉 配置完成。策略路由将在下次启动时自动应用。"
