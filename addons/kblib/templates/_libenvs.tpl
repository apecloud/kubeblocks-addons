{{/*
Library of envs related functions implemented in Bash. Currently, the following functions are available:
- envExist: Check if a single environment variable exists in the system's environment variables.
- envsExist: Check if multiple environment variables exist in the system's environment variables.
*/}}

{{/*
This function is used to check if a single environment variable exists in the system's environment variables.

Usage:
    envExist "ENV_NAME"
Result:
    true if the provided environment variable exists in the system's environment variables, false otherwise
Example:
    if envExist "ENV1"; then
      echo "ENV1 exists"
    else
      echo "ENV1 does not exist"
    fi
*/}}
{{- define "kblib.envs.envExist" }}
envExist() {
  local envName="$1"

  if [[ -z "${!envName}" ]]; then
    echo "false, $envName does not exist"
    return 1
  fi

  echo "true, $envName exists"
  return 0
}
{{- end }}

{{/*
This function is used to check if multiple environment variables exist in the system's environment variables.

Usage:
    envsExist "ENV1" "ENV2" "ENV3"
Result:
    true if all the provided environment variables exist in the system's environment variables, false otherwise
Example:
    if envsExist "ENV1" "ENV2" "ENV3"; then
      echo "All environment variables exist"
    else
      echo "Some environment variables do not exist"
    fi
*/}}
{{- define "kblib.envs.envsExist" }}
envsExist() {
  local envList=("$@")
  local missingEnvs=()

  for env in "${envList[@]}"; do
    if [[ -z "${!env}" ]]; then
      missingEnvs+=("$env")
    fi
  done

  if [[ ${#missingEnvs[@]} -eq 0 ]]; then
    echo "true, all environment variables exist"
    return 0
  else
    echo "false, the following environment variables do not exist: ${missingEnvs[*]}"
    return 1
  fi
}
{{- end }}