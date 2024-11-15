Describe 'update_pg_params.sh'
  Include ../reloader/update-parameter.sh

  # Mock psql command
  setup() {
    export POSTGRES_PASSWORD='test_pass'
    export POSTGRES_USER='test_user'
  }

  BeforeEach 'setup'

  Describe 'do_reload()'
    # Mock psql command
    Mock psql
      # Just echo the command for verification
      echo "psql called with: $*"
    End

    It 'calls psql with correct parameters'
      When call do_reload "max_connections" "100"
      The output should include "alter system set max_connections='100'"
      The output should include "select pg_reload_conf()"
      The output should include "-h localhost -U test_user"
    End

    It 'fails when param name is missing'
      When call do_reload
      The status should be failure
      The error should include "missing param name"
    End

    It 'fails when param value is missing'
      When call do_reload "max_connections"
      The status should be failure
      The error should include "missing value"
    End
  End
End