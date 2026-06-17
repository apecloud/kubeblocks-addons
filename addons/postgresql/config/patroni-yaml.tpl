ttl: 30
loop_wait: 10
retry_timeout: 10
maximum_lag_on_failover: 1048576
max_timelines_history: 0
check_timeline: true
postgresql:
  remove_data_directory_on_rewind_failure: true
  remove_data_directory_on_diverged_timelines: true