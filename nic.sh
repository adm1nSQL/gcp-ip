#!/bin/bash

set -e


echo "======================================"
echo " GCP Multi NIC IPv4 + IPv6 Routing"
echo "======================================"


####################################
# 初始化
####################################

mkdir -p /etc/iproute2


cat >/etc/iproute2/rt_tables <<EOF
#
255 local
254 main
253 default
0 unspec
EOF



####################################
# 开启转发
####################################

echo "[+] Enable Forwarding"


cat >/etc/sysctl.d/99-gcp-multi-nic.conf <<EOF

net.ipv4.ip_forward=1
net.ipv4.conf.all.forwarding=1
net.ipv4.conf.default.forwarding=1

net.ipv6.conf.all.forwarding=1
net.ipv6.conf.default.forwarding=1

EOF


sysctl --system >/dev/null 2>&1



####################################
# 清理旧规则
####################################

echo "[+] Cleanup old rules"


for P in $(seq 100 300)
do

ip rule del priority $P 2>/dev/null || true

ip -6 rule del priority $P 2>/dev/null || true

done



####################################
# 变量
####################################

V4_TABLE=100
V6_TABLE=200

PRIORITY4=100
PRIORITY6=200



####################################
# 网卡循环
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


TABLE=$V4_TABLE


GW4=$(echo $IPV4 \
| awk -F. '{print $1"."$2"."$3".1"}')



echo "[IPv4]"
echo "IP    : $IPV4"
echo "GW    : $GW4"
echo "TABLE : $TABLE"



echo "$TABLE ${IFACE}-v4" >> /etc/iproute2/rt_tables



ip route flush table $TABLE 2>/dev/null || true



ip route add default \
via $GW4 \
dev $IFACE \
table $TABLE \
2>/dev/null || true



ip rule add \
from $IPV4 \
table $TABLE \
priority $PRIORITY4 \
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


IPV6=$(ip -6 addr show $IFACE \
| awk '/scope global/ && !/temporary/ {print $2}' \
| cut -d/ -f1 \
| head -n1)



if [ -n "$IPV6" ]
then


TABLE=$V6_TABLE



echo ""
echo "[IPv6]"
echo "IP    : $IPV6"
echo "TABLE : $TABLE"



echo "$TABLE ${IFACE}-v6" >> /etc/iproute2/rt_tables



####################################
# 获取IPv6网关
####################################


GW6=$(ip -6 route show dev $IFACE \
| grep "default" \
| grep -oP '(?<=via ).*?(?= dev)' \
| head -n1)



if [ -z "$GW6" ]
then


GW6=$(ip -6 route show dev $IFACE \
| grep "^default" \
| grep -oP '(?<=via ).*?(?= dev)' \
| head -n1)


fi



if [ -z "$GW6" ]
then

echo "IPv6 Gateway NOT FOUND"

else


echo "GW6   : $GW6"



####################################
# 获取GCP RA prefix
####################################


PREFIX6=$(ip -6 route show dev $IFACE proto ra \
| grep "^2" \
| awk '{print $1}' \
| head -n1)



echo "PREFIX: $PREFIX6"



ip -6 route flush table $TABLE 2>/dev/null || true



####################################
# /128 地址
####################################


ip -6 route add \
$IPV6/128 \
dev $IFACE \
table $TABLE \
2>/dev/null || true



####################################
# GCP RA prefix
####################################


if [ -n "$PREFIX6" ]
then


ip -6 route add \
$PREFIX6 \
via $GW6 \
dev $IFACE \
table $TABLE \
2>/dev/null || true


fi



####################################
# 默认IPv6
####################################


ip -6 route add default \
via $GW6 \
dev $IFACE \
onlink \
table $TABLE \
2>/dev/null || true




####################################
# IPv6 rule
####################################


ip -6 rule add \
from $IPV6 \
table $TABLE \
priority $PRIORITY6 \
2>/dev/null || true



echo "IPv6 Test:"


curl -6 \
--interface $IPV6 \
--max-time 5 \
-s https://ifconfig.co \
&& echo " OK" \
|| echo " FAIL"



fi


else


echo "IPv6 NONE"


fi




V4_TABLE=$((V4_TABLE+1))
V6_TABLE=$((V6_TABLE+1))

PRIORITY4=$((PRIORITY4+1))
PRIORITY6=$((PRIORITY6+1))


done





echo ""
echo "======================================"
echo " IPv4 RULE"
echo "======================================"

ip rule



echo ""
echo "======================================"
echo " IPv6 RULE"
echo "======================================"

ip -6 rule



echo ""
echo "======================================"
echo " IPv6 ROUTE"
echo "======================================"

ip -6 route show table all



echo ""
echo "======================================"
echo " DONE"
echo "======================================"
