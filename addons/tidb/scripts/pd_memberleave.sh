#!/bin/bash

set -exo pipefail

echo "$KB_LEAVE_MEMBER_POD_NAME"
res=$(/pd-ctl member delete name "$KB_LEAVE_MEMBER_POD_NAME")
echo "$res"
not_found_pattern="Failed to delete member.*not found"
if [[ $res != "Success!" && ! $res =~ $not_found_pattern ]]; then
    exit 1
fi
