#!/bin/bash
# Create the Thread network "SoilNet" on the border router and print what the
# plant-side board needs: the active dataset (hex) and the Pi's mesh-local address.
set -e
C="sudo ot-ctl"
$C dataset init new
$C dataset networkname SoilNet
$C dataset commit active
$C ifconfig up
$C thread start
for i in $(seq 1 30); do
  s=$($C state | head -1)
  [ "$s" = leader ] && break
  sleep 2
done
echo "state: $($C state | head -1)"
echo "channel: $($C channel | head -1)"
echo "--- DATASET (paste into app.rb) ---"
$C dataset active -x | head -1
echo "--- DEST (Raspberry Pi mesh-local EID, paste into app.rb) ---"
$C ipaddr mleid | head -1
