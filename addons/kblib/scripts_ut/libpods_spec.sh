#shellcheck shell=bash

source kblib/scripts_ut/utils.sh

libpods_tpl_file="kblib/templates/_libpods.tpl"
libpods_file="kblib/scripts_ut/libpods.sh"

convert_tpl_to_bash $libpods_tpl_file $libpods_file

Describe 'kubeblocks pods library tests'
  cleanup() { rm -f $libpods_file; }
  AfterAll 'cleanup'

  Describe 'getPodListFromEnv without setting TEST_POD_LIST and KB_POD_LIST env variables'
    Include $libpods_file

    It 'getPodListFromEnv should return TEST_POD_LIST'
      When call getPodListFromEnv "TEST_POD_LIST"
      The output should eq ""
      The status should be failure
      The stderr should include "'TEST_POD_LIST' does not exist"
    End

    It 'getPodListFromEnv should return KB_POD_LIST'
      When call getPodListFromEnv ""
      The output should eq ""
      The stderr should include "'KB_POD_LIST' does not exist"
      The status should be failure
    End
  End

  Describe 'getPodListFromEnv with setting TEST_POD_LIST and KB_POD_LIST env variables'
    Include $libpods_file

    setup() {
      export TEST_POD_LIST="pod1,pod2,pod3"
      export KB_POD_LIST="kb_pod1,kb_pod2,kb_pod3"
    }
    Before 'setup'

    It 'getPodListFromEnv should return TEST_POD_LIST'
      When call getPodListFromEnv "TEST_POD_LIST"
      The output should eq "pod1 pod2 pod3"
    End

    It 'getPodListFromEnv should return KB_POD_LIST'
      When call getPodListFromEnv ""
      The output should eq "kb_pod1 kb_pod2 kb_pod3"
    End
  End

  Describe 'minLexicographicalOrderPod without setting KB_POD_LIST env variable'
    Include $libpods_file

    It 'minLexicographicalOrderPod should return empty string'
      When call minLexicographicalOrderPod ""
      The output should eq ""
    End

    It 'minLexicographicalOrderPod should return pod-1'
      When call minLexicographicalOrderPod "pod-pod-0,pod-1,pod-pod-1"
      The output should eq "pod-1"
    End
  End

  Describe 'minLexicographicalOrderPod with setting KB_POD_LIST env variable'
    Include $libpods_file

    setup() {
      export KB_POD_LIST="pod3,pod2,pod1"
    }
    Before 'setup'

    It 'minLexicographicalOrderPod should return pod1'
      When call minLexicographicalOrderPod ""
      The output should eq "pod1"
    End

    It 'minLexicographicalOrderPod should return pod1'
      When call minLexicographicalOrderPod "pod2,pod1,pod3"
      The output should eq "pod1"
    End

    It 'minLexicographicalOrderPod should return pod-1'
      When call minLexicographicalOrderPod "pod-0,pod-0-0,pod-1-0"
      The output should eq "pod-0"
    End

    It 'minLexicographicalOrderPod should return pod-1'
      When call minLexicographicalOrderPod "pod-pod-0,pod-1,pod-pod-1"
      The output should eq "pod-1"
    End
  End
End