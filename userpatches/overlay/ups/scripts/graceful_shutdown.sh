#!/bin/bash

LOG_FILE="/opt/web3pi/logs/ups-events.log"
echo "[$(date)] UPS battery critical – initiating graceful shutdown" >> "$LOG_FILE"

# Lista procesów do zatrzymania
APPS=("geth" "nimbus_beacon_node" "nimbus_validator_client" "lighthouse")

for APP in "${APPS[@]}"; do
  PID=$(pidof "$APP")
  if [ -n "$PID" ]; then
    echo "[$(date)] Stopping $APP (PID $PID)" >> "$LOG_FILE"
    kill -SIGTERM "$PID"

    # Czekamy aż proces się zakończy
    for i in {1..30}; do
      sleep 1
      if ! pidof "$APP" >/dev/null; then
        echo "[$(date)] $APP stopped successfully" >> "$LOG_FILE"
        break
      fi
    done

    # Jeśli nadal żyje – SIGKILL
    if pidof "$APP" >/dev/null; then
      echo "[$(date)] $APP did not stop in time, forcing kill" >> "$LOG_FILE"
      kill -9 "$PID"
    fi
  else
    echo "[$(date)] $APP not running" >> "$LOG_FILE"
  fi
done

echo "[$(date)] All apps stopped, shutting down system..." >> "$LOG_FILE"
shutdown -h now
