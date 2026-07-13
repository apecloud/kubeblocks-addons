# shellcheck shell=sh

Describe "MySQL xtrabackup action image contract"
  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  chart_path() {
    printf "%s/addons/mysql" "$(repo_root)"
  }

  helm_not_available() { ! command -v helm >/dev/null 2>&1; }
  Skip if "helm not available" helm_not_available

  render_template() {
    template=$1
    shift
    helm template test "$(chart_path)" --show-only "templates/${template}" "$@"
  }

  mapped_xtrabackup_image() {
    template=$1
    method=$2
    service_version=$3
    shift 3

    render_template "$template" "$@" | awk \
      -v method="$method" \
      -v service_version="$service_version" '
        /^  - name: / {
          current_method = $3
          in_method = (current_method == method)
          in_image_mapping = 0
          candidate = 0
        }
        in_method && /- name: XTRABACKUP_IMAGE$/ {
          in_image_mapping = 1
          next
        }
        in_image_mapping && /- serviceVersions:$/ {
          candidate = 0
          next
        }
        in_image_mapping && $1 == "-" {
          series = $2
          gsub(/"/, "", series)
          candidate = (index(service_version, series) == 1)
          next
        }
        in_image_mapping && candidate && $1 == "mappedValue:" {
          image = $2
          gsub(/"/, "", image)
          print image
          found = 1
          exit
        }
        END { if (!found) exit 1 }
      '
  }

  resolve_action_image() {
    policy_template=$1
    method=$2
    action_template=$3
    service_version=$4
    shift 4

    action_image=$(render_template "$action_template" "$@" |
      awk '/^      image: / { sub(/^      image: /, ""); print; exit }') || return 1
    [ "$action_image" = '$(XTRABACKUP_IMAGE)' ] || return 1
    mapped_xtrabackup_image "$policy_template" "$method" "$service_version" "$@"
  }

  It "resolves the exact MySQL 5.7 full-backup Job image"
    When call resolve_action_image backuppolicytemplate.yaml xtrabackup actionset-xtrabackup.yaml 5.7.44
    The status should be success
    The output should equal "docker.io/apecloud/percona-xtrabackup:2.4"
  End

  It "resolves the exact MySQL 8.0 full-backup Job image"
    When call resolve_action_image backuppolicytemplate.yaml xtrabackup actionset-xtrabackup.yaml 8.0.46
    The status should be success
    The output should equal "docker.io/apecloud/xtrabackup-minimal:8.0.35"
  End

  It "resolves the exact MySQL 8.4 full-backup Job image"
    When call resolve_action_image backuppolicytemplate.yaml xtrabackup actionset-xtrabackup.yaml 8.4.10
    The status should be success
    The output should equal "docker.io/apecloud/xtrabackup-minimal:8.4.0"
  End

  It "uses the exact MySQL 8.0 image for incremental backup Jobs"
    When call resolve_action_image backuppolicytemplate.yaml xtrabackup-inc actionset-xtrabackup-inc.yaml 8.0.46
    The status should be success
    The output should equal "docker.io/apecloud/xtrabackup-minimal:8.0.35"
  End

  It "uses the exact MySQL 8.4 image for ORC full-backup Jobs"
    When call resolve_action_image backuppolicytemplate-orc.yaml xtrabackup actionset-xtrabackup.yaml 8.4.10
    The status should be success
    The output should equal "docker.io/apecloud/xtrabackup-minimal:8.4.0"
  End

  It "uses the exact MySQL 5.7 image for ORC incremental backup Jobs"
    When call resolve_action_image backuppolicytemplate-orc.yaml xtrabackup-inc actionset-xtrabackup-inc.yaml 5.7.44
    The status should be success
    The output should equal "docker.io/apecloud/percona-xtrabackup:2.4"
  End

  It "preserves the minimal-image override in the final MySQL 8.0 Job image"
    When call resolve_action_image backuppolicytemplate.yaml xtrabackup actionset-xtrabackup.yaml 8.0.46 \
      --set image.xtraBackup.registry=registry.example.com \
      --set image.xtraBackup.minimalRepository=team/xtrabackup-minimal
    The status should be success
    The output should equal "registry.example.com/team/xtrabackup-minimal:8.0.35"
  End

  It "preserves the legacy-image override in the final MySQL 5.7 Job image"
    When call resolve_action_image backuppolicytemplate.yaml xtrabackup actionset-xtrabackup.yaml 5.7.44 \
      --set image.xtraBackup.registry=registry.example.com \
      --set image.xtraBackup.repository=team/xtrabackup
    The status should be success
    The output should equal "registry.example.com/team/xtrabackup:2.4"
  End

  It "fails closed when the service version has no xtrabackup image mapping"
    When call resolve_action_image backuppolicytemplate.yaml xtrabackup actionset-xtrabackup.yaml 9.0.0
    The status should be failure
    The output should be blank
  End

  It "leaves no ActionSet-level fallback image for an unmapped service version"
    When call sh -c '
      set -e
      output=$(helm template test "$1" \
        --show-only templates/actionset-xtrabackup.yaml \
        --show-only templates/actionset-xtrabackup-inc.yaml)
      [ "$(printf "%s\n" "$output" | grep -c "image: \$(XTRABACKUP_IMAGE)")" -eq 4 ]
      ! printf "%s\n" "$output" | grep -q "name: IMAGE_TAG"
      ! printf "%s\n" "$output" | grep -q "name: XTRABACKUP_IMAGE"
    ' sh "$(chart_path)"
    The status should be success
  End
End
