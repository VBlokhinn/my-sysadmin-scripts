#!/usr/bin/env bash
INTERVAL=5
LOG_FILE="monitor.log"

echo "Мониторинг запущен. Интервал: ${INTERVAL} сек. Вывод пишется в ${LOG_FILE}"

while true; do
    {
        echo "--- $(date '+%Y-%m-%d %H:%M:%S') ---"
        free -h
        echo ""
        df -h
        echo ""
        uptime
        echo ""
    } >> "$LOG_FILE"
    sleep "$INTERVAL"
done