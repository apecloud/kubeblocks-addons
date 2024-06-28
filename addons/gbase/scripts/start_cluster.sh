#!/bin/bash

TARGET_USER="gbase"

echo "strat gbase..."
 
output=$(sudo -i -u $TARGET_USER gha_ctl start all -l http://127.0.0.1:2379 2>&1)

echo "gha_ctl start node log:"
echo "$output"

