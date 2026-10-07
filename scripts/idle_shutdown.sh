#!/usr/bin/env bash
# Stops the EC2 instance after IDLE_MINUTES without requests (stopped = no GPU billing).
# Install in ROOT's crontab:  */5 * * * * /home/ubuntu/agentic-ide/scripts/idle_shutdown.sh
LIMIT=${IDLE_MINUTES:-30}
F=${ACTIVITY_FILE:-/tmp/ide_last_activity}
[ -f "$F" ] || touch "$F"
if [ -n "$(find "$F" -mmin +"$LIMIT")" ]; then shutdown -h now; fi
