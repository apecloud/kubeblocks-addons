{{/*
Library of common utility functions implemented in Bash. Currently, the following functions are available:
- execute_cmd_with_retry: Execute a Bash function with retry capability.
*/}}

{{/*
This function is used to execute a Bash function with retry capability.

Usage:
    execute_cmd_with_retry <function_name> <max_retries> <retry_interval>
Arguments:
    - function_name: The name of the Bash function to execute. The function can accept any number of arguments.
    - max_retries: The maximum number of retries if the function fails.
    - retry_interval: The interval (in seconds) between each retry attempt.
Result:
    The result of the executed Bash function.
Example:
    execute_cmd_with_retry "my_function" 3 5
    execute_cmd_with_retry "my_function" 3 5 arg1 arg2 arg3
*/}}
{{- define "kblib.commons.execute_cmd_with_retry" }}
execute_cmd_with_retry() {
  local function_name="$1"
  local max_retries="$2"
  local retry_interval="$3"
  shift 3

  local retries=0
  while true; do
    if "$function_name" "$@"; then
      return 0
    else
      retries=$((retries + 1))
      if [[ $retries -eq $max_retries ]]; then
        echo "Function '$function_name' failed after $max_retries retries."
        return 1
      fi
      echo "Function '$function_name' failed. Retrying in $retry_interval seconds..."
      sleep $retry_interval
    fi
  done
}
{{- end }}