# shellcheck shell=sh

validate_rendered_container_memory_refs() {
  chart_dir=$(cd .. && pwd)
  addons_dir=$(cd ../.. && pwd)
  render_root=$(mktemp -d)
  render_chart="$render_root/kafka"
  render_kblib="$render_root/kblib"
  rendered="$render_root/rendered.yaml"
  status=0

  cp -R "$chart_dir" "$render_chart" || status=1
  cp -R "$addons_dir/kblib" "$render_kblib" || status=1
  if [ "$status" -eq 0 ]; then
    rm -rf "$render_chart/charts"
    helm dependency build "$render_chart" >/dev/null 2>&1 || status=1
  fi
  if [ "$status" -eq 0 ]; then
    helm template kafka "$render_chart" >"$rendered" || status=1
  fi
  if [ "$status" -eq 0 ]; then
    ruby ./container_memory_ref_render_check.rb "$rendered" || status=1
  fi
  rm -rf "$render_root"
  return "$status"
}

Describe "Kafka container memory resource reference"
  It "resolves against whichever container executes the action"
    When call validate_rendered_container_memory_refs
    The status should be success
    The output should be blank
  End
End
