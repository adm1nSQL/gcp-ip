#!/bin/bash

set -e

echo "=================================="
echo " Multi NIC Routing (IPv4 + IPv6)"
echo "=================================="

TABLE=100

for IFACE in $(ls /sys/class/net | grep -E "ens|eth"); do

  echo ""
  echo "[IFACE] $IFACE"

  ########################
  # IPv4
  ########################
  IPV4=$(ip -4 addr show $IFACE | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)

  if [ ! -z "$IPV4" ]; then

    GW4=$(echo $IPV4 | awk -F. '{print $1"."$2"."$3".1"}')

    echo "  IPv4: $IPV4"
    echo "  GW4 : $GW4"
    echo "  TAB4: $TABLE"

    ip route replace default via $GW4 dev $IFACE table $TABLE 2>/dev/null || true
    ip rule add from $IPV4 table $TABLE priority $TABLE 2>/dev/null || true

    # IPv4 test
    echo "  TEST IPv4:"
    curl -4 -s --max-time 3 --interface $IFACE ifconfig.me && echo " OK" || echo " FAIL"

  else
    echo "  IPv4: NONE"
  fi

  ########################
  # IPv6
  ########################
  IPV6=$(ip -6 addr show $IFACE | awk '/inet6.*global/ {print $2}' | cut -d/ -f1 | head -n1)

  if [ ! -z "$IPV6" ]; then

    echo "  IPv6: $IPV6"

    # IPv6 默认路由（GCP通常自动）
    ip -6 route replace default dev $IFACE table $TABLE 2>/dev/null || true
    ip -6 rule add from $IPV6 table $TABLE priority $TABLE 2>/dev/null || true

    # IPv6 test
    echo "  TEST IPv6:"
    curl -6 -s --max-time 3 --interface $IFACE ifconfig.co && echo " OK" || echo " FAIL"

  else
    echo "  IPv6: NONE"
  fi

  TABLE=$((TABLE+1))

done

echo ""
echo "=================================="
echo " FINAL RULES"
echo "=================================="

ip rule show
echo ""
ip route show table all

echo ""
echo "DONE"
