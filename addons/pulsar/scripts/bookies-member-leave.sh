#!/bin/bash

bookies_member_leave() {
  if [[ "$KB_LEAVE_MEMBER_POD_NAME" != "$CURRENT_POD_NAME" ]]; then
    echo "Member to leave is not current pod, skipping Bookie formatting"
    return 1
  fi

  # TODO: consider using decommissionbookie? But decommissionbookie needs bookie to stop first, kb doesn't support a "postMemberLeave" hook.
  echo "Formatting Bookie..."
  export BOOKIE_CONF=/opt/pulsar/conf/bookkeeper.conf
  bin/bookkeeper shell bookieformat -nonInteractive -force -deleteCookie
  echo "Bookie formatted"
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
bookies_member_leave