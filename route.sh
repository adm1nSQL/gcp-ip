#!/bin/bash

set -e


echo "======================================"
echo " GCP Multi NIC Routing IPv4 + IPv6"
echo "======================================"


#################################
# Enable Forwarding
#################################

echo "[+] Enable IPv4 IPv6 Forwarding"


cat >/etc/sysctl.d/99-multi-nic.conf <<EOF
net.ipv4.ip_forward=1
net.ipv4.conf.all.forwarding=1
net.ipv4.conf.default.forwarding=1

net.ipv6.conf.all.forwarding=1
net.ipv6.conf.default.forwarding=1
EOF


sysctl --system >/dev/null



TABLE=100
PRIORITY=100



for IFACE in $(ls /sys/class/net | grep -E "ens|eth")
do


echo ""
echo "================================"
echo " NIC: $IFACE"
echo "================================"



#################################
# IPv4
#################################


IPV4=$(ip -4 addr show $IFACE | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)


if [ -n "$IPV4" ]
then

echo "IPv4: $IPV4"


GW4=$(echo $IPV4 | awk -F. '{print $1"."$2"."$3".1"}')


echo "GW4 : $GW4"
echo "TABLE: $TABLE"


grep -q "^$TABLE " /etc/iproute2/rt_tables || \
echo "$TABLE $IFACE" >> /etc/iproute2/rt_tables



ip route flush table $TABLE


ip route add default \
via $GW4 \
dev $IFACE \
table $TABLE



ip rule del \
from $IPV4 \
table $TABLE \
2>/dev/null || true



ip rule add \
from $IPV4 \
table $TABLE \
priority $PRIORITY



echo "IPv4 test:"

curl -4 \
--interface $IFACE \
--max-time 5 \
-s https://ifconfig.me \
&& echo " OK" \
|| echo " FAIL"



else

echo "IPv4: NONE"

fi




#################################
# IPv6
#################################


IPV6=$(ip -6 addr show $IFACE | awk '/inet6.*global/{print $2}' | cut -d/ -f1 | head -n1)



if [ -n "$IPV6" ]
then


echo "IPv6: $IPV6"



GW6=$(ip -6 route show dev $IFACE | awk '/default via/{print $3}' | head -n1)



if [ -n "$GW6" ]
then


echo "GW6: $GW6"



ip -6 route flush table $TABLE



ip -6 route add default \
via $GW6 \
dev $IFACE \
table $TABLE



ip -6 rule del \
from $IPV6 \
table $TABLE \
2>/dev/null || true



ip -6 rule add \
from $IPV6 \
table $TABLE \
priority $PRIORITY



echo "IPv6 test:"


curl -6 \
--interface $IFACE \
--max-time 5 \
-s https://ifconfig.co \
&& echo " OK" \
|| echo " FAIL"



else

echo "IPv6 gateway not found"

fi



else


echo "IPv6: NONE"


fi



TABLE=$((TABLE+1))
PRIORITY=$((PRIORITY+1))


done



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
echo "DONE"
