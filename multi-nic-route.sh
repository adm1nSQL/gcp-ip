#!/bin/bash

set -e

echo "[START] Multi NIC policy routing"

TABLE=100

for IFACE in $(ls /sys/class/net | grep -E "ens|eth"); do

  IP=$(ip -4 addr show $IFACE | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)

  if [ -z "$IP" ]; then
    continue
  fi

  GW=$(echo $IP | awk -F. '{print $1"."$2"."$3".1"}')

  echo "IFACE=$IFACE IP=$IP GW=$GW TABLE=$TABLE"

  ip route replace default via $GW dev $IFACE table $TABLE
  ip rule add from $IP table $TABLE priority $TABLE 2>/dev/null || true

  TABLE=$((TABLE+1))

done

echo "[DONE]"
ip rule show
