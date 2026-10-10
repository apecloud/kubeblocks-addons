# shellcheck shell=sh

Describe "RabbitMQ startup account boundary"
  startup_script="../scripts/startup.sh"

  It "leaves runtime password rotation to the managed accountProvision action"
    When call grep -E "sync_default_user_password|start_default_user_password_sync|change_password" "${startup_script}"
    The status should be failure
    The output should equal ""
  End

  It "still renders the generated root credential for first bootstrap"
    When call grep -F "default_pass = \${RABBITMQ_DEFAULT_PASS}" "${startup_script}"
    The status should be success
    The output should include "default_pass = \${RABBITMQ_DEFAULT_PASS}"
  End
End
