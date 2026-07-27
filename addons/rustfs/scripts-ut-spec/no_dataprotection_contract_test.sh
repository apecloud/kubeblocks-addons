#!/bin/sh

set -eu

spec_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
chart_dir=$(CDPATH= cd -- "$spec_dir/.." && pwd)
rendered=$(mktemp)
trap 'rm -f "$rendered"' EXIT HUP INT TERM

helm template rustfs "$chart_dir" >"$rendered"

assert_absent() {
  pattern=$1
  description=$2
  if grep -Eq "$pattern" "$rendered"; then
    echo "RustFS must not render $description" >&2
    exit 1
  fi
}

assert_kind_count() {
  kind=$1
  expected=$2
  actual=$(grep -Ec "^kind: ${kind}$" "$rendered" || true)
  if [ "$actual" -ne "$expected" ]; then
    echo "expected ${expected} rendered ${kind} resource(s), got ${actual}" >&2
    exit 1
  fi
}

assert_absent '^kind: BackupPolicyTemplate$' 'a BackupPolicyTemplate'
assert_absent '^kind: ActionSet$' 'an ActionSet'
assert_absent '^[[:space:]]*backupMethods:' 'backup methods'
assert_absent '^[[:space:]]*actionSetName:' 'an ActionSet reference'

for path in \
  "$chart_dir/templates/backuppolicytemplate.yaml" \
  "$chart_dir/templates/actionset.yaml"; do
  if [ -e "$path" ]; then
    echo "RustFS dataprotection source remains at $path" >&2
    exit 1
  fi
done

if [ -d "$chart_dir/dataprotection" ] &&
  find "$chart_dir/dataprotection" -type f -print -quit | grep -q .; then
  echo "RustFS dataprotection source remains under $chart_dir/dataprotection" >&2
  exit 1
fi

assert_kind_count ComponentDefinition 1
assert_kind_count ComponentVersion 1
assert_kind_count ConfigMap 2

role_probe_block=$(
  awk '
    /^    roleProbe:$/ { in_role_probe = 1; next }
    in_role_probe && /^    [^ ]/ { exit }
    in_role_probe { print }
  ' "$rendered"
)

for expected in \
  '      periodSeconds: 1' \
  '      timeoutSeconds: 3'; do
  if ! printf '%s\n' "$role_probe_block" | grep -Fxq "$expected"; then
    echo "RustFS must preserve roleProbe timing: $expected" >&2
    exit 1
  fi
done

echo "rustfs no-dataprotection contract test passed"
