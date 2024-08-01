#shellcheck shell=bash

source kblib/scripts_ut/utils.sh

libenvs_tpl_file="kblib/templates/_libenvs.tpl"
libenvs_file="kblib/scripts_ut/libenvs.sh"

convert_tpl_to_bash $libenvs_tpl_file $libenvs_file

Describe 'kubeblocks envs library tests'
  cleanup() { rm -f $libenvs_file; }
  AfterAll 'cleanup'

  Describe 'envExist'
    Include $libenvs_file

    Context 'when the environment variable does not exist'
      It 'should return false'
        When call envExist "NON_EXISTENT_ENV"
        The output should eq "false, NON_EXISTENT_ENV does not exist"
        The status should be failure
      End
    End

    Context 'when the environment variable exists'
      setup() {
        export EXISTENT_ENV="value"
      }
      Before 'setup'

      It 'should return true'
        When call envExist "EXISTENT_ENV"
        The output should eq "true, EXISTENT_ENV exists"
        The status should be success
      End
    End
  End

  Describe 'envsExist'
    Include $libenvs_file

    Context 'when all environment variables exist'
      setup() {
        export ENV1="value1"
        export ENV2="value2"
        export ENV3="value3"
      }
      Before 'setup'

      It 'should return true'
        When call envsExist "ENV1" "ENV2" "ENV3"
        The output should eq "true, all environment variables exist"
        The status should be success
      End
    End

    Context 'when some environment variables do not exist'
      setup() {
        export ENV1="value1"
        export ENV3="value3"
      }
      Before 'setup'

      It 'should return false'
        When call envsExist "ENV1" "ENV2" "ENV3"
        The output should eq "false, the following environment variables do not exist: ENV2"
        The status should be failure
      End
    End

    Context 'when all environment variables do not exist'
      It 'should return false'
        When call envsExist "ENV1" "ENV2" "ENV3"
        The output should eq "false, the following environment variables do not exist: ENV1 ENV2 ENV3"
        The status should be failure
      End
    End
  End
End