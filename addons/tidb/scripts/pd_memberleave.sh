#!/bin/bash

set -exo pipefail

echo "$KB_LEAVE_MEMBER_POD_NAME"
res=$(/pd-ctl member delete name "$KB_LEAVE_MEMBER_POD_NAME")
echo "$res"
not_found_pattern="Failed to delete member.*not found"
# this redirect_not_leader_pattern is a workaround when scaling in multiple pd instances,
# pd cluster may fail to create a new leader until the deleted members' pod is stopped.
# See: https://github.com/apecloud/apecloud/issues/13893#issuecomment-3574029284
# In the future, when scale in is implemented in instanceset controller, we can have a better
# solution that does memberLeave one by one. 
redirect_not_leader_pattern="redirect to not leader"
if [[ $res != "Success!" && ! $res =~ $not_found_pattern && ! $res =~ $redirect_not_leader_pattern ]]; then
    exit 1
fi
echo "member leave success"
