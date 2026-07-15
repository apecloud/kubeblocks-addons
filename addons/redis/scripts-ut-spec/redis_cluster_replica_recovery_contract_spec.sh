# shellcheck shell=bash

Describe "Redis Cluster replica recovery compatibility contract"
  common_script="../redis-cluster-scripts/redis-cluster-common.sh"
  redis5_script="../redis-cluster-scripts/redis-cluster5-server-start.sh"
  redis6_script="../redis-cluster-scripts/redis-cluster6-server-start.sh"
  redis78_script="../redis-cluster-scripts/redis-cluster-server-start.sh"
  chart_template="../templates/cmpd-redis-cluster.yaml"

  assert_membership_closure_order() {
    awk '
      /^scale_redis_cluster_replica\(\)/ { in_scale = 1 }
      in_scale && /check_node_in_cluster_with_retry/ && !membership_check { membership_check = NR }
      in_scale && membership_check && /^[[:space:]]+ensure_current_node_replication[[:space:]]/ && !closure { closure = NR }
      in_scale && membership_check && /^[[:space:]]+exit 0[[:space:]]*$/ && !membership_exit { membership_exit = NR }
      in_scale && /^}/ { in_scale = 0 }
      END {
        if (membership_check && closure && membership_exit && membership_check < closure && closure < membership_exit) {
          print "membership-check<shared-closure<exit"
          exit 0
        }
        exit 1
      }
    ' "$1"
  }

  It "defines the shared dual-view convergence helpers"
    The contents of file "$common_script" should include "get_consistent_current_node_replication_state()"
    The contents of file "$common_script" should include "repair_current_node_replication()"
    The contents of file "$common_script" should include "verify_current_node_replication()"
    The contents of file "$common_script" should include "ensure_current_node_replication()"
  End

  It "routes Redis 5 through the shared positive closure"
    When call assert_membership_closure_order "$redis5_script"
    The status should be success
    The output should equal "membership-check<shared-closure<exit"
  End

  It "routes Redis 6 through the shared positive closure"
    When call assert_membership_closure_order "$redis6_script"
    The status should be success
    The output should equal "membership-check<shared-closure<exit"
  End

  It "routes Redis 7 and 8 through the shared positive closure"
    When call assert_membership_closure_order "$redis78_script"
    The status should be success
    The output should equal "membership-check<shared-closure<exit"
  End

  It "keeps the chart major-version routing explicit"
    The contents of file "$chart_template" should include 'redis-cluster5-server-start.sh'
    The contents of file "$chart_template" should include 'redis-cluster6-server-start.sh'
    The contents of file "$chart_template" should include 'redis-cluster-server-start.sh'
  End
End
