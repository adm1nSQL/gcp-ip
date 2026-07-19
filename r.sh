#!/bin/bash

set -e


echo "======================================"
echo " GCP Multi NIC IPv4 + IPv6 Routing"
echo "======================================"


# ===============================
# rt_tables
# ===============================

mkdir -p /etc/iproute2
touch /etc/iproute2/rt_tables


add_table(){

    ID=$1
    NAME=$2

    sed -i "/[[:space:]]$NAME$/d" /etc/iproute2/rt_tables

    echo "$ID $NAME" >> /etc/iproute2/rt_tables
}



# ===============================
# sysctl
# ===============================

cat >/etc/sysctl.d/99-gcp-route.conf <<EOF

net.ipv4.ip_forward=1
net.ipv4.conf.all.forwarding=1
net.ipv4.conf.default.forwarding=1

net.ipv6.conf.all.forwarding=1
net.ipv6.conf.default.forwarding=1

net.ipv6.conf.all.accept_ra=2
net.ipv6.conf.default.accept_ra=2

EOF


sysctl --system >/dev/null 2>&1 || true



# ===============================
# cleanup
# ===============================

echo "[+] Cleanup rules"


for i in $(seq 100 500)
do
    ip rule del priority $i 2>/dev/null || true
    ip -6 rule del priority $i 2>/dev/null || true
done



INDEX=0



for IFACE in $(ls /sys/class/net | grep -E "^(ens|eth)")
do


V4_TABLE=$((100+INDEX))
V6_TABLE=$((300+INDEX))

V4_PRIORITY=$((100+INDEX))
V6_PRIORITY=$((300+INDEX))


echo ""
echo "======================================"
echo " NIC : $IFACE"
echo "======================================"



# =================================================
# IPv4
# =================================================


IPV4=$(ip -4 addr show $IFACE \
| awk '/inet /{print $2}' \
| cut -d/ -f1 \
| head -n1)



if [ -n "$IPV4" ]
then


GW4=$(echo $IPV4 | awk -F. '{print $1"."$2"."$3".1"}')


echo ""
echo "[IPv4]"
echo "IP   : $IPV4"
echo "GW   : $GW4"
echo "TABLE: $V4_TABLE"


add_table $V4_TABLE "${IFACE}-v4"


ip route flush table $V4_TABLE 2>/dev/null || true



ip route add default \
via $GW4 \
dev $IFACE \
table $V4_TABLE \
2>/dev/null || true



ip rule add \
from $IPV4 \
table $V4_TABLE \
priority $V4_PRIORITY \
2>/dev/null || true



curl -4 \
--interface $IFACE \
--max-time 5 \
-s https://ifconfig.me \
&& echo " IPv4 OK" \
|| echo " IPv4 FAIL"


fi




# =================================================
# IPv6
# =================================================


IPV6_FULL=$(ip -6 addr show $IFACE \
| awk '/scope global/ && !/temporary/ {print $2}' \
| head -n1)



if [ -n "$IPV6_FULL" ]
then


IPV6=$(echo $IPV6_FULL | cut -d/ -f1)

MASK=$(echo $IPV6_FULL | cut -d/ -f2)



echo ""
echo "[IPv6]"
echo "IP   : $IPV6"
echo "MASK : /$MASK"
echo "TABLE: $V6_TABLE"



add_table $V6_TABLE "${IFACE}-v6"



# =================================================
# GCP IPv6 Gateway
# 支持:
# default via xxx
# prefix nhid xxx via xxx
# =================================================


GW6=$(ip -6 route show dev $IFACE \
| awk '
/via/ {
    for(i=1;i<=NF;i++)
    {
        if($i=="via")
        {
            print $(i+1)
            exit
        }
    }
}')



echo "GW6  : ${GW6:-NONE}"



if [ -n "$GW6" ]
then



# =================================================
# IPv6 Prefix
# =================================================


PREFIX6=$(ip -6 route show dev $IFACE proto ra \
| awk '
$1!="default" && /via/ {print $1}
' \
| head -n1)



echo "PREFIX: ${PREFIX6:-NONE}"



ip -6 route flush table $V6_TABLE 2>/dev/null || true



# 本机地址

ip -6 route add \
$IPV6/$MASK \
dev $IFACE \
table $V6_TABLE \
2>/dev/null || true



# IPv6 Prefix

if [ -n "$PREFIX6" ]
then

ip -6 route add \
$PREFIX6 \
dev $IFACE \
table $V6_TABLE \
2>/dev/null || true

fi



# 默认IPv6出口


ip -6 route add default \
via $GW6 \
dev $IFACE \
table $V6_TABLE \
2>/dev/null || true



# policy routing


ip -6 rule add \
from $IPV6 \
table $V6_TABLE \
priority $V6_PRIORITY \
2>/dev/null || true



curl -6 \
--interface $IFACE \
--max-time 5 \
-s https://ifconfig.co \
&& echo " IPv6 OK" \
|| echo " IPv6 FAIL"



else

echo "IPv6 Gateway NONE"

fi



else

echo "IPv6 NONE"

fi



INDEX=$((INDEX+1))


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
echo " ROUTE TABLES"
echo "======================================"

ip -6 route show table all



echo ""
echo "======================================"
echo " DONE"
echo "======================================"
