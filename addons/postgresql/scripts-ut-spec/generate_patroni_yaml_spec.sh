# shellcheck shell=bash

Describe "scripts/generate_patroni_yaml.py"

  setup() {
    tmpdir=$(mktemp -d -t pg-generate-patroni-XXXXXX)
    conf_dir="${tmpdir}/conf"
    pgdata_dir="${tmpdir}/pgdata"
    restore_dir="${pgdata_dir}/kb_restore"
    out="${tmpdir}/patroni.yaml"
    mkdir -p "${conf_dir}" "${pgdata_dir}/conf" "${restore_dir}"

    cat > "${conf_dir}/pg_hba.conf" <<'EOF'
host all all 0.0.0.0/0 md5
EOF
    cat > "${conf_dir}/replica_restore.conf" <<'EOF'
create_replica_methods:
- restore_data
- basebackup
restore_data:
  command: bash /home/postgres/pgdata/kb_restore/kb_restore.sh --replica
EOF
    cat > "${conf_dir}/patroni.yaml" <<'EOF'
postgresql:
  use_pg_rewind: true
EOF
    cat > "${conf_dir}/kb_pitr.conf" <<'EOF'
method: kb_restore_from_time
kb_restore_from_time:
  command: bash /home/postgres/pgdata/kb_restore/kb_restore.sh
  keep_existing_recovery_conf: false
  recovery_conf: {}
EOF

    export POSTGRES_CONF_DIR="${conf_dir}"
    export POSTGRES_PGDATA_DIR="${pgdata_dir}"
    export RESTORE_DATA_DIR="${restore_dir}"
    export SPILO_CONFIGURATION='bootstrap:
  initdb:
  - auth-host: md5
postgresql: {}'
  }

  cleanup() {
    rm -rf "${tmpdir}"
    unset POSTGRES_CONF_DIR POSTGRES_PGDATA_DIR RESTORE_DATA_DIR SPILO_CONFIGURATION
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  It "adds primary bootstrap and follower replica restore methods when restore signal exists"
    touch "${restore_dir}/kb_restore.signal"
    When run python3 ../scripts/generate_patroni_yaml.py "${out}"
    The status should eq 0
    The path "${out}" should be exist
    The contents of file "${out}" should include "method: kb_restore"
    The contents of file "${out}" should include "kb_restore:"
    The contents of file "${out}" should include "command: bash ${restore_dir}/kb_restore.sh"
    The contents of file "${out}" should include "keep_existing_recovery_conf: false"
    The contents of file "${out}" should include "create_replica_methods:"
    The contents of file "${out}" should include "restore_data"
    The contents of file "${out}" should include "kb_restore.sh --replica"
  End

  It "does not add restore bootstrap when the restore signal is absent"
    When run python3 ../scripts/generate_patroni_yaml.py "${out}"
    The status should eq 0
    The contents of file "${out}" should not include "method: kb_restore"
    The contents of file "${out}" should not include "create_replica_methods:"
  End
End
