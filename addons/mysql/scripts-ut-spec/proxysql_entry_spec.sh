# shellcheck shell=bash
# shellcheck disable=SC2034


# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
# if ! validate_shell_type_and_version "bash" &>/dev/null; then
#   echo "mongodb replicaset_setup_spec.sh skip all cases because dependency bash is not installed."
#   exit 0
# fi

Describe "ProxySQL Entry Script Tests"

    init() {
        TEST_DATA_DIR="./test_data"
        export FRONTEND_TLS_ENABLED="false"
    }
    BeforeAll "init"

    cleanup() {
        rm -rf $TEST_DATA_DIR
    }
    AfterAll 'cleanup'

    Describe "Run proxysql-entry.sh with FRONTEND_TLS_ENABLED=false"
        It "runs successfully"
            replace_config_variables() {
                return 0
            }
            When run source ../scripts/proxysql-entry.sh
            The status should be failure
            The stdout should include "Configuring proxysql ..."
            The stderr should include "../scripts/proxysql-entry.sh"
        End
    End

    Describe "term_handler unit contract"
        # Include defines term_handler without running the main body, because
        # the script's __SOURCED__ guard returns early after the function decls.
        # term_handler ends with `exit 0`, so use `When run` (subshell) here.
        Include ../scripts/proxysql-entry.sh

        It "forwards SIGTERM to the captured proxysql pid and exits 0"
            kill() { echo "kill $*"; }
            wait() { echo "wait $*"; }
            pid=12345
            When run term_handler
            The status should be success
            The stdout should include "kill -TERM 12345"
        End

        It "is a no-op when no proxysql pid was captured (signal before spawn)"
            kill() { echo "kill $*"; }
            wait() { echo "wait $*"; }
            pid=0
            When run term_handler
            The status should be success
            The stdout should not include "kill"
        End

        It "terminates instead of falling through to a second wait (double-wait guard)"
            # If term_handler returned instead of exiting, control would fall
            # through to the main path's bottom `wait "$pid"`, which under set -e
            # would exit 127 ("not a child") after the handler already reaped it.
            kill() { :; }
            wait() { :; }
            pid=999
            probe() { term_handler; echo "FELL_THROUGH"; }
            When run probe
            The status should be success
            The output should not include "FELL_THROUGH"
        End

        It "installs a SIGTERM/SIGINT trap before spawning proxysql"
            When run cat ../scripts/proxysql-entry.sh
            The status should be success
            The output should include "trap 'term_handler' SIGTERM SIGINT"
            # trap line must appear before the proxysql spawn line
            trap_ln=$(grep -n "trap 'term_handler'" ../scripts/proxysql-entry.sh | head -1 | cut -d: -f1)
            spawn_ln=$(grep -n "^proxysql -c" ../scripts/proxysql-entry.sh | head -1 | cut -d: -f1)
            The variable trap_ln should satisfy test "$trap_ln" -lt "$spawn_ln"
        End
    End

    Describe "end-to-end SIGTERM forwarding to a real proxysql child"
        run_signal_test() {
            tmpdir=$(mktemp -d)
            marker="${tmpdir}/term-received"
            ready="${tmpdir}/proxysql-up"

            # stub proxysql: signal readiness, record SIGTERM, exit cleanly.
            cat > "${tmpdir}/proxysql" <<STUB
#!/usr/bin/env bash
trap 'echo received > "${marker}"; exit 0' TERM
echo up > "${ready}"
while true; do sleep 0.05; done
STUB
            chmod +x "${tmpdir}/proxysql"

            # stub configure helper and sed: succeed immediately (sed stub avoids
            # BSD/GNU -i differences on the test host).
            printf '#!/usr/bin/env bash\nexit 0\n' > "${tmpdir}/configure.sh"
            chmod +x "${tmpdir}/configure.sh"
            printf '#!/usr/bin/env bash\nexit 0\n' > "${tmpdir}/sed"
            chmod +x "${tmpdir}/sed"

            PATH="${tmpdir}:${PATH}" \
                PROXYSQL_CONFIGURE_SCRIPT="${tmpdir}/configure.sh" \
                PROXYSQL_CONFIG_TPL="/dev/null" \
                PROXYSQL_CONFIG_OUT="${tmpdir}/proxysql.cnf" \
                FRONTEND_TLS_ENABLED=false \
                bash ../scripts/proxysql-entry.sh >/dev/null 2>&1 &
            wrapper_pid=$!

            # deterministically wait until proxysql is up (configure is instant,
            # so the wrapper is then parked at the bottom `wait`), then send TERM.
            i=0
            while [ ! -f "${ready}" ] && [ ${i} -lt 100 ]; do sleep 0.05; i=$((i + 1)); done
            sleep 0.1
            kill -TERM "${wrapper_pid}" 2>/dev/null

            wait "${wrapper_pid}"
            rc=$?

            if [ -f "${marker}" ]; then term="yes"; else term="no"; fi
            rm -rf "${tmpdir}"
            echo "child_term=${term} wrapper_rc=${rc}"
        }

        It "delivers SIGTERM to the proxysql child and the wrapper exits 0"
            When call run_signal_test
            The output should equal "child_term=yes wrapper_rc=0"
        End
    End

End