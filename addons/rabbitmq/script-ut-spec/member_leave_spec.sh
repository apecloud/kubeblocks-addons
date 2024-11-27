# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "RabbitMQ Member Leave Script Tests"
  Include ../scripts/member_leave.sh

  Describe "is_node_deleted tests"

    It "it is true when node is in disk nodes list"
      KB_LEAVE_MEMBER_POD_NAME="rabbitmq-1"
      input="Disk Nodes
rabbit@rabbitmq-0
rabbit@rabbitmq-1
rabbit@rabbitmq-2

Running Nodes
rabbit@rabbitmq-0
rabbit@rabbitmq-1
rabbit@rabbitmq-2"

      When call is_node_deleted "$input"
      The status should be failure  # return 1 to indicate the node is not deleted
    End

    It "false when node is not in disk nodes list"
        KB_LEAVE_MEMBER_POD_NAME="rabbitmq-3"
        input="Disk Nodes
rabbit@rabbitmq-0
rabbit@rabbitmq-1
rabbit@rabbitmq-2

Running Nodes
rabbit@rabbitmq-0
rabbit@rabbitmq-1
rabbit@rabbitmq-2"

      When call is_node_deleted "$input"
      The status should be success  # return 0 to indicate the node is deleted
    End
  End

   Describe "get_target_node tests"
 
     It "return the first node that is not the leave node"
       LEAVE_NODE="rabbit@rabbitmq-1"
       input="Running Nodes
 rabbit@rabbitmq-0
 rabbit@rabbitmq-1
 rabbit@rabbitmq-2"
 
       When call get_target_node "$input"
       The output should be present
       The status should be success
     End
 
     It "false when no target node found"
       LEAVE_NODE="rabbit@rabbitmq-0"
       input="Running Nodes
 rabbit@rabbitmq-0"
 
       When call get_target_node "$input"
       The output should include "no target node found to execute forget_cluster_node."
       The status should be failure
     End
   End

   Describe "cleanup tests"

     It "rm lock file"
       rm() {
         echo "rm $*"
       }
       When call cleanup
       The output should include "Cleaning up..."
       The output should include "rm -f /tmp/member_leave.lock"
       The status should be success
     End
   End

  Describe "execute member_leave.sh tests"

    It "exit when KB_LEAVE_MEMBER_POD_NAME is not set"
      unset KB_LEAVE_MEMBER_POD_NAME

      When run source ../scripts/member_leave.sh
      The output should include "no leave member name provided"
      The stderr should be present
      The status should be failure
    End

    It "exit when member_leave.sh is already running"
      setup() {
        KB_LEAVE_MEMBER_POD_NAME="rabbitmq-1"
        touch /tmp/member_leave.lock
      }
      setup

      When run source ../scripts/member_leave.sh
      The output should include "member_leave.sh is already running"
      The stderr should be present
      The status should be failure

      rm -f /tmp/member_leave.lock
    End
  End
End

  # The tests need to be executed in linux environment
  #  It "exit when leave success file exists and current pod is the leave member pod"
  #    setup() {
  #      KB_LEAVE_MEMBER_POD_NAME="rabbitmq-1"
  #      RABBITMQ_NODENAME="rabbit@rabbitmq-1.example.com"
  #      touch "/tmp/${KB_LEAVE_MEMBER_POD_NAME}_leave.success"
  #    }
  #    setup

  #    When run source ../scripts/member_leave.sh
  #    The output should include "member_leave.sh is already leave success"
  #    The status should be success
  #    The file "/tmp/rabbitmq-1_leave.success" should be exist
  #    rm -f /tmp/rabbitmq-1_leave.success
  #  End

  #  It "当离开成功文件存在且当前节点不是离开节点时，删除成功文件并退出"
  #    setup() {
  #      KB_LEAVE_MEMBER_POD_NAME="rabbitmq-1"
  #      RABBITMQ_NODENAME="rabbit@rabbitmq-0.example.com"
  #      touch "/tmp/${KB_LEAVE_MEMBER_POD_NAME}_leave.success"
  #    }
  #    Before "setup"
  #    After "rm -f /tmp/rabbitmq-1_leave.success"

  #    When run source ../scripts/member_leave.sh
  #    The output should include "member_leave.sh is already leave success"
  #    The output should not include "exit 0"
  #    The status should be success
  #  End