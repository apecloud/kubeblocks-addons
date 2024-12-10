#!/bin/bash
set -euo pipefail
# only manage version in chart.yaml
# CR api version annotation please check kblib

bump_chart_version() {
  local chart="$1"
  local chart_version="$2"
  echo "Updating version for chart to $chart_version"
  sed -i.bak "s/^version:.*/version: ${chart_version}/g" "$chart" && rm "$chart.bak"
}

bump_chart_annotation_kb_version() {
  local chart="$1"
  local chart_annotation_kb_version="$2"
  echo "Updating kb version annotation for $chart to $chart_annotation_kb_version"
  sed -i.bak "s/^  addon.kubeblocks.io\/kubeblocks-version:.*/  addon.kubeblocks.io\/kubeblocks-version: \"${chart_annotation_kb_version}\"/g" "$chart" && rm "$chart.bak"
}

main() {
  local parent_dir="$1"
  local option="$2"
  local version="$3"
  if [ -z "$option" ] || [[ "$option" != "chart-ver" && "$option" != "chart-anno-kb-ver" ]]; then
    echo "Invalid or missing option. Exiting."
    exit 1
  fi

  find "$parent_dir" -type d -not -name "kblib" | while read -r chart_dir; do
    echo "$chart_dir"
    local chart="$chart_dir/Chart.yaml"
    if [ -f "$chart" ]; then
      if [ "$option" == "chart-ver" ]; then
        bump_chart_version "$chart" "$version"
      elif [ "$option" == "chart-anno-kb-ver" ]; then
        bump_chart_annotation_kb_version "$chart" "$version"
      else
        echo "Invalid option. Exiting."
        exit 1
      fi
    fi
  done
}

main "$@"
# hack/bump-chart-versions.sh addons chart-ver 1.0.0-alpha.0
# hack/bump-chart-versions.sh addons-cluster chart-ver 1.0.0-alpha.0
# hack/bump-chart-versions.sh addons chart-anno-kb-ver ">=1.0.0"