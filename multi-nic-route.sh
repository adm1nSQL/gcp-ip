#!/bin/bash

set -e

echo "=============================="
echo " Multi NIC Routing (DIAG MODE)"
echo "=============================="

TABLE=100

for IFACE in $(ls /sys/class/net | grep -E "ens|eth"); do

  IP=$(ip -4 addr show $IFACE | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)

  if [ -z "$IP" ]; then
    echo "[SKIP] $IFACE no IPv4"
    continue
  fi

  GW=$(echo $IP | awk -F. '{print $1"."$2"."$3".1"}')

  echo ""
  echo "[IFACE] $IFACE"
  echo "  IP      : $IP"
  echo "  GW      : $GW"
  echo "  TABLE   : $TABLE"

  # route
  ip route replace default via $GW dev $IFACE table $TABLE
  ip rule add from $IP table $TABLE priority $TABLE 2>/dev/null || true

  echo "  ROUTE   : OK"

  TABLE=$((TABLE+1))

done

echo ""
echo "=============================="
echo " ROUTING TABLE CHECK"
echo "=============================="

ip rule show
echo ""
ip route show table all

echo ""
echo "=============================="
echo " OUTBOUND TEST PER NIC"
echo "=============================="

for IFACE in $(ls /sys/class/net | grep -E "ens|eth"); do

  IP=$(ip -4 addr show $IFACE | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)

  if [ -z "$IP" ]; then
    continue
  fi

  echo ""
  echo "[TEST] $IFACE ($IP)"

  curl -s --max-time 3 --interface $IFACE ifconfig.me && echo "  <- OK" || echo "  <- FAIL"

done

echo ""
echo "DONE"
