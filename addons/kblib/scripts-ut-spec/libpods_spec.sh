#shellcheck shell=bash

source ./utils.sh

libpods_tpl_file="../templates/_libpods.tpl"
libpods_file="./libpods.sh"

convert_tpl_to_bash $libpods_tpl_file $libpods_file

Describe 'kubeblocks pods library tests'
  cleanup() { rm -f $libpods_file; }
  AfterAll 'cleanup'

  Describe 'get_pod_list_from_env without setting TEST_POD_LIST and KB_POD_LIST env variables'
    Include $libpods_file

    It 'get_pod_list_from_env should return TEST_POD_LIST'
      When call get_pod_list_from_env "TEST_POD_LIST"
      The output should eq ""
      The status should be failure
      The stderr should include "'TEST_POD_LIST' does not exist"
    End

    It 'get_pod_list_from_env should return KB_POD_LIST'
      When call get_pod_list_from_env ""
      The output should eq ""
      The stderr should include "'KB_POD_LIST' does not exist"
      The status should be failure
    End
  End

  Describe 'get_pod_list_from_env with setting TEST_POD_LIST and KB_POD_LIST env variables'
    Include $libpods_file

    setup() {
      export TEST_POD_LIST="pod1,pod2,pod3"
      export KB_POD_LIST="kb_pod1,kb_pod2,kb_pod3"
    }
    Before 'setup'

    It 'get_pod_list_from_env should return TEST_POD_LIST'
      When call get_pod_list_from_env "TEST_POD_LIST"
      The output should eq "pod1 pod2 pod3"
    End

    It 'get_pod_list_from_env should return KB_POD_LIST'
      When call get_pod_list_from_env ""
      The output should eq "kb_pod1 kb_pod2 kb_pod3"
    End
  End

  Describe 'min_lexicographical_order_pod without setting KB_POD_LIST env variable'
    Include $libpods_file

    It 'min_lexicographical_order_pod should return empty string'
      When call min_lexicographical_order_pod ""
      The output should eq ""
    End

    It 'min_lexicographical_order_pod should return pod-1'
      When call min_lexicographical_order_pod "pod-pod-0,pod-1,pod-pod-1"
      The output should eq "pod-1"
    End
  End

  Describe 'min_lexicographical_order_pod with setting KB_POD_LIST env variable'
    Include $libpods_file

    setup() {
      export KB_POD_LIST="pod3,pod2,pod1"
    }
    Before 'setup'

    It 'min_lexicographical_order_pod should return pod1'
      When call min_lexicographical_order_pod ""
      The output should eq "pod1"
    End

    It 'min_lexicographical_order_pod should return pod1'
      When call min_lexicographical_order_pod "pod2,pod1,pod3"
      The output should eq "pod1"
    End

    It 'min_lexicographical_order_pod should return pod-1'
      When call min_lexicographical_order_pod "pod-0,pod-0-0,pod-1-0"
      The output should eq "pod-0"
    End

    It 'min_lexicographical_order_pod should return pod-1'
      When call min_lexicographical_order_pod "pod-pod-0,pod-1,pod-pod-1"
      The output should eq "pod-1"
    End
  End
End