#!/bin/bash
source /scripts/common.sh

function get_keeper_role() {
	local mode=$(get_mode 127.0.0.1)
	if [ "$mode" == "standalone" ]; then
		printf "leader"
	elif [ "$mode" == "follower" ] || [ "$mode" == "leader" ] || [ "$mode" == "observer" ]; then
		printf "%s" "$mode"
	fi
}

get_keeper_role
