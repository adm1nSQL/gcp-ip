#!/bin/bash

set -e


echo "======================================"
echo " GCP Multi NIC IPv4 + IPv6 Routing"
echo "======================================"


####################################
# 初始化
####################################

mkdir -p /etc/iproute2
touch /etc/iproute2/rt_tables


####################################
# 开启转发
####################################

echo "[+] Enable Forwarding"


cat >/etc/sysctl.d/99-multi-nic.conf <<EOF
net.ipv4.ip_forward=1
net.ipv4.conf.all.forwarding=1
net.ipv4.conf.default.forwarding=1

net.ipv6.conf.all.forwarding=1
net.ipv6.conf.default.forwarding=1
EOF


sysctl --system >/dev/null



####################################
# 表编号
####################################

V4_TABLE=100
V6_TABLE=200

PRIORITY=100



####################################
# 遍历网卡
####################################

for IFACE in $(ls /sys/class/net | grep -E "ens|eth")
do


echo ""
echo "================================"
echo " NIC : $IFACE"
echo "================================"



####################################
# IPv4
####################################


IPV4=$(ip -4 addr show $IFACE \
| awk '/inet /{print $2}' \
| cut -d/ -f1 \
| head -n1)



if [ -n "$IPV4" ]
then


GW4=$(echo $IPV4 | awk -F. '{print $1"."$2"."$3".1"}')


TABLE=$V4_TABLE


echo "[IPv4]"
echo "IP   : $IPV4"
echo "GW   : $GW4"
echo "TABLE: $TABLE"



grep -q "^$TABLE " /etc/iproute2/rt_tables || \
echo "$TABLE ${IFACE}-v4" >> /etc/iproute2/rt_tables



# 清理旧表

ip route flush table $TABLE 2>/dev/null || true



# 默认路由

ip route add default \
via $GW4 \
dev $IFACE \
table $TABLE \
2>/dev/null || true



# 删除旧rule

ip rule del \
from $IPV4 \
table $TABLE \
2>/dev/null || true



# 添加rule

ip rule add \
from $IPV4 \
table $TABLE \
priority $PRIORITY \
2>/dev/null || true



echo "IPv4 Test:"


curl -4 \
--interface $IFACE \
--max-time 5 \
-s https://ifconfig.me \
&& echo " OK" \
|| echo " FAIL"



else


echo "IPv4 NONE"


fi





####################################
# IPv6
####################################


V6INFO=$(ip -6 addr show $IFACE \
| awk '/scope global/ && !/temporary/ {print $2}' \
| head -n1)



if [ -n "$V6INFO" ]
then


IPV6=$(echo $V6INFO | cut -d/ -f1)

PREFIX=$(echo $V6INFO | cut -d/ -f2)


TABLE=$V6_TABLE



echo ""
echo "[IPv6]"
echo "IP   : $IPV6/$PREFIX"
echo "TABLE: $TABLE"



grep -q "^$TABLE " /etc/iproute2/rt_tables || \
echo "$TABLE ${IFACE}-v6" >> /etc/iproute2/rt_tables





####################################
# 自动获取IPv6网关
####################################


GW6=$(ip -6 route show dev $IFACE \
| grep default \
| grep -oP '(?<=via ).*?(?= dev)' \
| head -n1)



if [ -z "$GW6" ]
then

GW6=$(ip -6 route show \
| grep default \
| grep "$IFACE" \
| grep -oP '(?<=via ).*?(?= dev)' \
| head -n1)

fi



if [ -n "$GW6" ]
then


echo "GW6  : $GW6"



# 清理IPv6表

ip -6 route flush table $TABLE 2>/dev/null || true



####################################
# 添加IPv6默认路由
####################################


ip -6 route add default \
via $GW6 \
dev $IFACE \
table $TABLE \
2>/dev/null || true




####################################
# 添加本地IPv6地址
####################################


ip -6 route add \
$IPV6/$PREFIX \
dev $IFACE \
table $TABLE \
2>/dev/null || true




####################################
# IPv6 rule
####################################


ip -6 rule del \
from $IPV6 \
table $TABLE \
2>/dev/null || true



ip -6 rule add \
from $IPV6 \
table $TABLE \
priority $PRIORITY \
2>/dev/null || true




echo "IPv6 Test:"


curl -6 \
--interface $IFACE \
--max-time 5 \
-s https://ifconfig.co \
&& echo " OK" \
|| echo " FAIL"



else


echo "IPv6 Gateway NOT FOUND"



fi



else


echo "IPv6 NONE"



fi




V4_TABLE=$((V4_TABLE+1))
V6_TABLE=$((V6_TABLE+1))
PRIORITY=$((PRIORITY+1))


done





####################################
# 输出
####################################


echo ""
echo "======================================"
echo " IPv4 RULE"
echo "======================================"

ip rule show



echo ""
echo "======================================"
echo " IPv6 RULE"
echo "======================================"

ip -6 rule show



echo ""
echo "======================================"
echo " IPv4 ROUTE"
echo "======================================"

ip route show table all



echo ""
echo "======================================"
echo " IPv6 ROUTE"
echo "======================================"

ip -6 route show table all



echo ""
echo "======================================"
echo " DONE"
echo "======================================"
