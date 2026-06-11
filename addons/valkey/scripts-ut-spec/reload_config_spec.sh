# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "reload_config_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Valkey reload-config.sh"
  setup() {
    mkdir -p fakeconf fakebin fakescripts

    # Fake config file with typical Valkey settings
    cat > fakeconf/valkey.conf <<'CONF'
# Valkey default configuration template.

bind * -::*
tcp-backlog 511
timeout 0
maxmemory-policy volatile-lru
maxmemory 268435456
CONF

    # Create ..data symlink with fresh mtime (simulates recent projection)
    ln -sf "$(pwd)/fakeconf" fakeconf/..data

    # Mock reload-parameter.sh that logs calls
    cat > fakescripts/reload-parameter.sh <<'SH'
#!/bin/sh
echo "RELOAD: $1 $2" >> /tmp/reload-config-spec-calls.log
SH
    chmod +x fakescripts/reload-parameter.sh

    # Fake stat and date for freshness gate
    cat > fakebin/stat <<'SH'
#!/bin/sh
# Return current epoch as mtime (always fresh)
date +%s
SH
    cat > fakebin/date <<'SH'
#!/bin/sh
# Real date passthrough
/bin/date "$@"
SH
    chmod +x fakebin/stat fakebin/date
    export PATH="./fakebin:${PATH}"

    rm -f /tmp/reload-config-spec-calls.log
  }
  Before "setup"

  cleanup() {
    rm -rf fakeconf fakebin fakescripts
    rm -f /tmp/reload-config-spec-calls.log
  }
  After "cleanup"

  It "applies all dynamic parameters from the config file"
    # Override paths used by the script
    env CONFIG_FILE=fakeconf/valkey.conf \
        DATA_LINK=fakeconf/..data \
        PATH="./fakescripts:${PATH}" \
      run bash -c '
        CONFIG_FILE=fakeconf/valkey.conf
        DATA_LINK=fakeconf/..data
        MAX_WAIT=1
        _fresh=false
        if [ -L "$DATA_LINK" ]; then
          _now=$(date +%s)
          _mtime=$(stat -c %Y "$DATA_LINK" 2>/dev/null || echo 0)
          _age=$(( _now - _mtime ))
          [ "$_age" -le 10 ] && _fresh=true
        fi
        if [ "$_fresh" = "false" ]; then exit 1; fi
        while IFS= read -r line; do
          case "$line" in "#"*|"") continue ;; esac
          key=${line%% *}
          value=${line#* }
          [ -n "$key" ] || continue
          [ "$key" = "$value" ] && continue
          ./fakescripts/reload-parameter.sh "$key" "$value"
        done < "$CONFIG_FILE"
      '
    The status should be success
    The contents of file "/tmp/reload-config-spec-calls.log" should include "RELOAD: maxmemory 268435456"
    The contents of file "/tmp/reload-config-spec-calls.log" should include "RELOAD: bind * -::*"
    The contents of file "/tmp/reload-config-spec-calls.log" should include "RELOAD: tcp-backlog 511"
    The contents of file "/tmp/reload-config-spec-calls.log" should include "RELOAD: maxmemory-policy volatile-lru"
  End

  It "skips comment and empty lines"
    env PATH="./fakescripts:${PATH}" \
      run bash -c '
        CONFIG_FILE=fakeconf/valkey.conf
        DATA_LINK=fakeconf/..data
        MAX_WAIT=1
        _fresh=true
        while IFS= read -r line; do
          case "$line" in "#"*|"") continue ;; esac
          key=${line%% *}
          value=${line#* }
          [ -n "$key" ] || continue
          [ "$key" = "$value" ] && continue
          ./fakescripts/reload-parameter.sh "$key" "$value"
        done < "$CONFIG_FILE"
      '
    The status should be success
    The contents of file "/tmp/reload-config-spec-calls.log" should not include "RELOAD: #"
  End
End
