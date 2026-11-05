#!/bin/sh
# Small JSON status report for the demo page.
echo "Content-Type: application/json"
echo "Cache-Control: no-store"
echo

up=$(cut -d. -f1 /proc/uptime)
load=$(cut -d' ' -f1-3 /proc/loadavg)
mem_total=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
mem_avail=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
set -- $(df -k / | awk 'NR==2 {print $2, $3}')
disk_total=${1:-0}; disk_used=${2:-0}
ip=$(ip -4 -o addr show eth0 2>/dev/null | awk '{print $4}')
temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "")

printf '{"hostname":"%s","kernel":"%s","uptime":%s,"load":"%s",' "$(hostname)" "$(uname -r)" "${up:-0}" "$load"
printf '"mem_total_kb":%s,"mem_avail_kb":%s,"disk_total_kb":%s,"disk_used_kb":%s,' \
    "${mem_total:-0}" "${mem_avail:-0}" "$disk_total" "$disk_used"
printf '"ip":"%s","temp_mc":%s}\n' "$ip" "${temp:-null}"
