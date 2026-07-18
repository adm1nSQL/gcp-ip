#!/bin/bash

set -e

echo "======================================"
echo " GCP Multi NIC Routing IPv4 + IPv6"
echo "======================================"



############################
# Enable Forward
############################

echo "[+] Enable IPv4 IPv6 Forwarding"


cat >/etc/sysctl.d/99-multi-nic-routing.conf <<EOF
net.ipv4.ip_forward=1
net.ipv4.conf.all.forwarding=1
net.ipv4.conf.default.forwarding=1

net.ipv6.conf.all.forwarding=1
net.ipv6.conf.default.forwarding=1
EOF


sysctl --system >/dev/null



############################
# Prepare
############################


TABLE=100
PRIORITY=100


NIC_LIST=$(ls /sys/class/net | grep -E "ens|eth")



for IFACE in $NIC_LIST
do


echo ""
echo "======================================"
echo "[ NIC ] $IFACE"
echo "======================================"



############################
# IPv4
############################


IPV4=$(ip -4 addr show $IFACE \
| awk '/inet /{print $2}' \
| cut -d/ -f1 \
| head -n1)



if [ -n "$IPV4" ]
then


echo ""
echo "[IPv4]"
echo "IP : $IPV4"


GW4=$(echo $IPV4 \
| awk -F. '{print $1"."$2"."$3".1"}')


echo "GW : $GW4"

echo "TABLE : $TABLE"



# 写入路由表名称

grep -q "^$TABLE " /etc/iproute2/rt_tables \
|| echo "$TABLE $IFACE" >> /etc/iproute2/rt_tables



# 清理旧规则

ip route flush table $TABLE



# 添加IPv4默认路由

ip route add default \
via $GW4 \
dev $IFACE \
table $TABLE



# 添加本地网段

LOCAL_ROUTE=$(ip route show dev $IFACE \
| grep proto \
| grep -v default \
| head -n1)


if [ -n "$LOCAL_ROUTE" ]
then

NETWORK=$(echo "$LOCAL_ROUTE" | awk '{print $1}')


ip route add $NETWORK \
dev $IFACE \
table $TABLE \
2>/dev/null || true


fi



# 删除旧rule

ip rule del \
from $IPV4 \
table $TABLE \
2>/dev/null || true



# 添加rule

ip rule add \
from $IPV4 \
table $TABLE \
priority $PRIORITY



echo ""
echo "IPv4 Test:"

curl -4 \
--interface $IFACE \
--max-time 5 \
-s https://ifconfig.me \
&& echo " OK" \
|| echo " FAIL"



else

echo "[IPv4] NONE"


fi





############################
# IPv6
############################


IPV6=$(ip -6 addr show $IFACE \
| awk '/inet6.*global/ {print $2}' \
| cut -d/ -f1 \
| head -n1)



if [ -n "$IPV6" ]
then


echo ""
echo "[IPv6]"
echo "IP : $IPV6"



# 获取GCP IPv6 gateway

GW6=$(ip -6 route show dev $IFACE \
| awk '/default via/ {print $3}' \
| head -n1)



if [ -n "$GW6" ]
then


echo "GW : $GW6"



# IPv6 清理

ip -6 route flush table $TABLE



# 添加IPv6默认路由

ip -6 route add default \
via $GW6 \
dev $IFACE \
table $TABLE



# 添加IPv6前缀

V6NET=$(ip -6 route show dev $IFACE \
| grep proto \
| grep -v default \
| head -n1 \
| awk '{print $1}')



if [ -n "$V6NET" ]
then

ip -6 route add $V6NET \
dev $IFACE \
table $TABLE \
2>/dev/null || true

fi




# 删除旧IPv6 rule

ip -6 rule del \
from $IPV6 \
table $TABLE \
2>/dev/null || true



# 添加IPv6 rule

ip -6 rule add \
from $IPV6 \
table $TABLE \
priority $PRIORITY




echo ""
echo "IPv6 Test:"


curl -6 \
--interface $IFACE \
--max-time 5 \
-s https://ifconfig.co \
&& echo " OK" \
|| echo " FAIL"



else


echo "[IPv6] NONE"



fi



TABLE=$((TABLE+1))

PRIORITY=$((PRIORITY+1))


done





############################
# Result
############################


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
echo " FINISHED"
echo "======================================"
