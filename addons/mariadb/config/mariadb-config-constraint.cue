// MariaDB parameter schema for the merged replication CmpD.
//
// alpha.89 v1 commit 3 (Helen 2026-05-19, C1 path) — defines the
// CUE schema KB ParametersDefinition uses to validate parameter
// assignments. Per Jack design review (15:50) Class 4 sentinel
// requirement: invalid values for `replicationMode` semisync
// engine variables must fail-closed at the controller parameter
// reconcile path before reaching the engine. KB's parameter
// validator (#10254 once merged) reads `schemaInJSON` generated
// from this CUE file and rejects unknown / out-of-range / non-enum
// assignments at `ValidateComponentParameterAssignments()`. On
// current main without #10254, validation still happens at the
// `ClassifyComponentParameters()` / `DoMerge()` boundary, before
// engine config is rendered.
//
// alpha.89 v1 commit 11 (Helen 2026-05-20, C3 path correction
// after Jack KB-validator behavioral test 2026-05-20 00:16 msg
// `ea50aa12`): revert the conditional `replicationMode`-derivation
// blocks introduced in commit 10 and fix a separate closed-section
// bug that has been silently present since commit 3 v2.
//
// Jack's behavioral test against KB `pkg/parameters/validate
// /cue_util.go ValidateConfigWithCue()` + `DoMerge()` proved:
//
// 1. KB does NOT emit CUE-derived field values into the rendered
//    my.cnf. A user setting only `replicationMode=semisync` would
//    get a my.cnf containing `replicationmode=semisync` (which
//    mariadbd rejects as an unknown variable) and no derived
//    `rpl_semi_sync_master_enabled=ON`. So the C3 single-source-of
//    -truth cannot be CUE alone; an addon-side mapper inside
//    reconfigureAction must consume `replicationMode` BEFORE the
//    my.cnf render and write the four real variables explicitly.
// 2. KB's INI parser lowercases all keys, so a camelCase CUE field
//    `replicationMode` does not match the parsed key
//    `replicationmode` — even validation fails on this.
// 3. The `[SectionName=_]: #MariaDBParameter` binding from
//    commit 3 v2 is a CLOSED CUE struct. Any key in the rendered
//    base my.cnf that is not declared in `#MariaDBParameter` (e.g.
//    `binlog_format`, `max_connections`, `slow_query_log`) is
//    rejected by `ValidateConfigWithCue()` as "field not allowed".
//    Commit 3 v2's ShellSpec used a narrow fixture (only the four
//    `rpl_semi_sync_*` keys) so this bug never surfaced; a real
//    cluster's full base my.cnf merge would fail.
//
// Fix in this commit:
//
// - `replicationMode` is REMOVED from the CUE schema. It will be
//   re-introduced in a follow-up commit as a ComponentSpec parameter
//   consumed by an addon-side mapper in reconfigureAction (the
//   mapper validates consistency against the four real variables
//   and writes the derived values into my.cnf via the alpha.88
//   persistence path; the four real variables remain the only
//   keys that land in the rendered ConfigMap).
// - The two `if replicationMode == ...` conditional blocks are
//   REMOVED. CUE unification is no longer used to express
//   precedence; the mapper handles it.
// - The struct is now OPEN (`[string]: _`), so base my.cnf keys
//   not declared in this schema pass through unchallenged. This
//   retroactively fixes the commit 3 v2 closed-section bug; the
//   four `rpl_semi_sync_*` fields still take their declared
//   constraints because CUE unifies any matching key with the
//   field constraint and lets unknown keys flow through.
//
// The four `rpl_semi_sync_*` field declarations and the
// `[SectionName=_]: #MariaDBParameter` section binding are
// unchanged from commit 3 v2.
//
// MariaDB accepts both "ON"/"OFF" and "1"/"0" for boolean variables
// in my.cnf and via SET GLOBAL. The schema constrains the my.cnf
// surface to "ON"/"OFF" for readability; runtime SET GLOBAL via
// reconfigureAction may continue to accept either form at the
// SQL layer (the engine normalizes).

#MariaDBParameter: {
	// Enables semisync replication on the primary. When ON, the
	// primary waits for at least
	// rpl_semi_sync_master_wait_for_slave_count secondaries to
	// acknowledge each transaction's binlog event (or for
	// rpl_semi_sync_master_timeout milliseconds) before returning
	// OK to the client. Default OFF — async replication.
	rpl_semi_sync_master_enabled?: string & "ON" | "OFF" | *"OFF"

	// Enables semisync replication on the secondary. Must be ON on
	// the secondary side for semisync to actually take effect on
	// the primary side. Default OFF — async replication.
	rpl_semi_sync_slave_enabled?: string & "ON" | "OFF" | *"OFF"

	// Number of secondaries that must acknowledge a binlog event
	// before the primary commits in semisync mode. Only meaningful
	// when rpl_semi_sync_master_enabled = ON. MariaDB hard minimum
	// is 1; upper bound matches the maximum allowable replica
	// count.
	rpl_semi_sync_master_wait_for_slave_count?: int & >=1 & <=65535 | *1

	// (ms) Timeout in milliseconds for the primary to wait for
	// secondary acknowledgement in semisync mode before falling
	// back to async for that transaction. Only meaningful when
	// rpl_semi_sync_master_enabled = ON. MariaDB default 10000ms
	// (10s); 0 disables timeout (wait forever, which is unsafe and
	// not recommended).
	rpl_semi_sync_master_timeout?: int & >=1 & <=2147483647 | *10000 @timeDurationResource(1ms)

	// alpha.89 v1 commit 11 v2 (Helen 2026-05-20, Jack B1 fix):
	// explicitly forbid the synthetic key `replicationmode` from
	// landing in my.cnf. KB's INI parser lowercases every key, so
	// user input `replicationMode`, `replicationmode`, or any other
	// case variant normalizes to `replicationmode` before CUE
	// validation runs. The C3 design places `replicationMode` at
	// the ComponentSpec-parameter layer (consumed by an addon
	// mapper in reconfigureAction BEFORE my.cnf render) — under no
	// path should `replicationmode` appear as a my.cnf key, because
	// mariadbd does not recognize it and would log an unknown-
	// variable warning at startup. The `_|_` (CUE bottom value)
	// forbids the field outright: any ConfigMap merge that includes
	// this key fails `ValidateConfigWithCue()` with a clear CUE
	// conflict, before the merged config reaches the engine.
	//
	// More-specific field declarations take precedence over the
	// `[string]: _` open pattern below, so this forbid rule still
	// fires even though the open pattern accepts arbitrary string
	// keys.
	replicationmode?: _|_

	// Open the struct so KB's `ValidateConfigWithCue()` accepts any
	// other key the rendered base my.cnf may contain (e.g.
	// `binlog_format`, `max_connections`, `slow_query_log`) without
	// requiring this schema to enumerate every MariaDB engine
	// variable. The four `rpl_semi_sync_*` fields above still
	// constrain those specific keys when they are present; the
	// `replicationmode` forbid above still rejects that specific
	// key; all other unknown keys pass through unchallenged.
	//
	// alpha.89 v1 commit 11 (Helen 2026-05-20) — retroactive fix
	// for the commit 3 v2 closed-section bug Jack surfaced via
	// KB-validator behavioral test (msg `ea50aa12`). Without this
	// open marker, a real cluster's full base my.cnf merge fails
	// with "field not allowed" on any key not in this schema.
	[string]: _
}

// Bind #MariaDBParameter to every INI section in the parsed my.cnf.
//
// alpha.89 v1 commit 3 v2 (Helen 2026-05-19, Jack design review
// Class 4 blocker B1) — KB's CUE validator (pkg/parameters/validate
// /cue_util.go ValidateConfigWithCue) does NOT use a top-level
// definition unless the CUE file binds it to the parsed config
// structure. Without this binding, the four constrained variables
// declared above are just unreferenced definitions; an invalid
// value such as rpl_semi_sync_master_enabled = MAYBE is silently
// accepted by the validator, defeating the fail-closed contract
// for Class 4.
//
// The MySQL / ApeCloud MySQL addons use the same pattern
// ([SectionName=_]: #MysqlParameter) to bind their schema across
// all sections of the rendered INI; reuse it here so the
// constraints take effect on the [mysqld] section (and any other
// section the chart may render) without hard-coding the section
// name. KB's INI parser walks every section and validates its
// key-value pairs against the bound schema, returning a
// CUE-conflict error on the first violation.
[SectionName=_]: #MariaDBParameter
