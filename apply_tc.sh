#!/bin/sh
# Ждём, пока интерфейс wg0 появится (до 10 секунд)
for i in $(seq 1 10); do
  if ip link show wg0 >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

# Настройки лимитов (можно переопределить через переменные окружения в docker-compose.yml)
TC_MAX_CLIENTS=${TC_MAX_CLIENTS:-20}
TC_RATE_MBIT=${TC_RATE_MBIT:-10}
WG_DEFAULT_ADDRESS=${WG_DEFAULT_ADDRESS:-10.8.0.x}
BASE_NET=$(echo "$WG_DEFAULT_ADDRESS" | sed 's/\.x$//')

# Удаляем старые qdisc если есть
tc qdisc del dev wg0 root 2>/dev/null

# Корневой qdisc: HTB, весь неопознанный (сверх лимита клиентов) трафик идёт в default-класс
tc qdisc add dev wg0 root handle 1: htb default 999
tc class add dev wg0 parent 1: classid 1:999 htb rate ${TC_RATE_MBIT}mbit ceil ${TC_RATE_MBIT}mbit

# Отдельный класс на каждого клиента: BASE_NET.2 .. BASE_NET.(1+TC_MAX_CLIENTS)
# Каждому клиенту — свои TC_RATE_MBIT Мбит/с, не разделяемые с другими клиентами
i=2
classid=10
end=$((TC_MAX_CLIENTS + 1))
while [ $i -le $end ]; do
  tc class add dev wg0 parent 1: classid 1:$classid htb rate ${TC_RATE_MBIT}mbit ceil ${TC_RATE_MBIT}mbit
  tc filter add dev wg0 protocol ip parent 1: prio 1 u32 match ip dst ${BASE_NET}.${i}/32 flowid 1:$classid
  i=$((i + 1))
  classid=$((classid + 1))
done
