# shellcheck shell=sh

Describe "MariaDB topology-specific ComponentVersions"

  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  template_dir() {
    printf "%s/addons/mariadb/templates" "$(repo_root)"
  }

  It "defines one ComponentVersion template per topology"
    The path "$(template_dir)/cpmv.yaml" should be exist
    The path "$(template_dir)/cpmv-replication.yaml" should be exist
    The path "$(template_dir)/cpmv-galera.yaml" should be exist
    The path "$(template_dir)/cmpv.yaml" should not be exist
  End

  It "binds each ComponentVersion to only its topology ComponentDefinition"
    The contents of file "$(template_dir)/cpmv.yaml" should include 'mariadb.standalone.cmpdRegexpPattern'
    The contents of file "$(template_dir)/cpmv.yaml" should not include 'mariadb.replication.cmpdRegexpPattern'
    The contents of file "$(template_dir)/cpmv.yaml" should not include 'mariadb.galera.cmpdRegexpPattern'

    The contents of file "$(template_dir)/cpmv-replication.yaml" should include 'mariadb.replication.cmpdRegexpPattern'
    The contents of file "$(template_dir)/cpmv-replication.yaml" should not include 'mariadb.standalone.cmpdRegexpPattern'
    The contents of file "$(template_dir)/cpmv-replication.yaml" should not include 'mariadb.galera.cmpdRegexpPattern'

    The contents of file "$(template_dir)/cpmv-galera.yaml" should include 'mariadb.galera.cmpdRegexpPattern'
    The contents of file "$(template_dir)/cpmv-galera.yaml" should not include 'mariadb.standalone.cmpdRegexpPattern'
    The contents of file "$(template_dir)/cpmv-galera.yaml" should not include 'mariadb.replication.cmpdRegexpPattern'
  End

  It "keeps init-syncer scoped to the replication topology"
    The contents of file "$(template_dir)/cpmv-replication.yaml" should include 'init-syncer:'
    The contents of file "$(template_dir)/cpmv.yaml" should not include 'init-syncer:'
    The contents of file "$(template_dir)/cpmv-galera.yaml" should not include 'init-syncer:'
  End

  It "keeps MariaDB 10.6 out of Galera while retaining it elsewhere"
    The contents of file "$(template_dir)/cpmv.yaml" should include '"10.6.15"'
    The contents of file "$(template_dir)/cpmv-replication.yaml" should include '"10.6.15"'
    The contents of file "$(template_dir)/cpmv-galera.yaml" should not include '"10.6.15"'
  End

End
