{{/*
Library of pods related functions implemented in Bash. Currently, the following functions are available:
- getPodListFromEnv: Get the list of pods from the provided environment variable or the default KB_POD_LIST environment variable.
- minLexicographicalOrderPod: Get the minimum lexicographically pod name from the given pod list or the default KB_POD_LIST environment variable.
*/}}

{{/*
This function is used to get the list of pods from the provided environment variable.
If the environment variable does not exist, an error is returned.
If no environment variable name is provided, it defaults to KB_POD_LIST.

Usage:
    getPodListFromEnv "ENV_VAR_NAME"
    getPodListFromEnv ""
Result:
    An array of pod names
Example:
    pods=$(getPodListFromEnv "MY_POD_LIST")
    pods=$(getPodListFromEnv "")
*/}}
{{- define "kblib.pods.getPodListFromEnv" }}
getPodListFromEnv() {
  local envName="${1:-KB_POD_LIST}"

  if [[ -z "${!envName}" ]]; then
    echo "failed to get pod list cause environment variable '$envName' does not exist" >&2
    return 1
  fi

  local podListStr="${!envName}"
  local podList=()

  IFS=',' read -ra podList <<< "$podListStr"

  echo "${podList[@]}"
}
{{- end }}

{{/*
This function is used to get the minimum lexicographically pod name from the pod list.
if the parameter is not provided, it will use the default pod list from KB_POD_LIST environment variable.

Usage:
    minLexicographicalOrderPod "pod1,pod2,pod3"
    minLexicographicalOrderPod ""
Result:
    The minimum lexicographically order pod name
Example:
    minimumPod=$(minLexicographicalOrderPod "pod-0,pod-1,pod-2") # pod1
    minimumPod=$(minLexicographicalOrderPod "") # use the default KB_POD_LIST env variable
*/}}
{{- define "kblib.pods.minLexicographicalOrderPod" }}
minLexicographicalOrderPod() {
  local podListStr="${1:-${KB_POD_LIST}}"
  local podList=()

  IFS=',' read -ra podList <<< "$podListStr"

  local minimumPod="${podList[0]}"
  for pod in "${podList[@]}"; do
    if [[ "$pod" < "$minimumPod" ]]; then
      minimumPod="$pod"
    fi
  done

  echo "$minimumPod"
}
{{- end }}