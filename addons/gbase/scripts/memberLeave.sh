#!/bin/bash   

JOIN_POD_IP=$1
IP_LIST=()

# get cluster running node ip and hostname
output=$(sudo -i -u gbase gs_om -t status --all)
if [[ $? -ne 0 ]]; then
  echo "Failed to execute 'gs_om -t status --all'"
  exit 1
fi
while IFS= read -r line; do
  if [[ "$line" =~ node_ip[[:space:]]*:[[:space:]]*(.*) ]]; then
    IP_LIST+=("${BASH_REMATCH[1]}")
  fi
done <<< "$output"
IP_LIST_COMMA=$(IFS=,; echo "${IP_LIST[*]}")

if [[ " ${IP_LIST[@]} " =~ " ${JOIN_POD_IP} " ]]; then
    expect <<EOF
set timeout 1800
spawn /home/gbase/gbase_package/script/gs_dropnode -U gbase -G gbase -h $JOIN_POD_IP

expect {
    "(yes/no)?" {
        send "yes\r"
        exp_continue
    }
    eof {
        puts "Interact completed successfully."
        wait
        exit
    }
    default {
        puts "Unexpected output: $expect_out(buffer)"
        wait
        exit
    }
}

if { [catch wait result] } {
    puts "Interact failed, process likely closed: $result"
} else {
    puts "Interact completed successfully: $result"
}
EOF

else
    exit 0
fi