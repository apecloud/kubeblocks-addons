#!/bin/bash

current_member_index=${KB_AGENT_POD_NAME##*-}
zkCli.sh << EOF
    addauth digest $ZK_ADMIN_USER:$ZK_ADMIN_PASSWORD
    reconfig -remove ${current_member_index}
EOF