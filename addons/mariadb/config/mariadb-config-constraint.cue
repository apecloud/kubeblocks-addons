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
// alpha.89 v1 commit 10 (Helen 2026-05-20, C3 path per weston
// 2026-05-20 00:08 msg `cb0afa37`) — extended with a
// `replicationMode` field whose CUE conditional blocks derive the
// four `rpl_semi_sync_*` engine variables when set. weston's
// precedence rule: if `replicationMode` is set, it overrides the
// four real variables; if the user ALSO sets one of the four with
// an inconsistent value, CUE unification fails and KB rejects the
// assignment at the controller parameter reconcile path. If
// `replicationMode` is unset, the user can freely set the four
// real variables (chart default is async via the four variables
// taking their CUE defaults of OFF).
//
// This makes both user-facing surfaces (a single logical
// `replicationMode` switch AND the four real engine variables)
// visible and changeable per weston's directive; CUE unification
// handles the consistency check natively and the four variables
// remain the ground-truth source rendered into my.cnf.
//
// Note that this CUE expression depends on KB's CUE renderer
// actually emitting derived field values into the rendered my.cnf
// (not only validating them). If KB's renderer only validates and
// does not derive (i.e. it ignores the conditional blocks for
// rendering), a thin addon-side mapper in reconfigureAction would
// fill the four variables when only `replicationMode` is set,
// while CUE unification continues to reject inconsistent explicit
// assignments. Jack's KB-validator behavioral test
// (pkg/parameters/validate/cue_util.go ValidateConfigWithCue) is
// scheduled to verify which path the runtime takes; until then this
// commit lays the schema only and the mapper question is deferred
// to commit 11+ based on Jack's findings.
//
// MariaDB accepts both "ON"/"OFF" and "1"/"0" for boolean variables
// in my.cnf and via SET GLOBAL. The schema constrains the my.cnf
// surface to "ON"/"OFF" for readability; runtime SET GLOBAL via
// reconfigureAction may continue to accept either form at the
// SQL layer (the engine normalizes).

#MariaDBParameter: {
	// alpha.89 v1 commit 10 (Helen 2026-05-20, C3 path) — logical
	// replication-mode switch. When set, the conditional blocks
	// below unify the two `rpl_semi_sync_*_enabled` fields with
	// the corresponding ON / OFF value. The user may also set the
	// two `*_enabled` fields explicitly; CUE unification fails if
	// the explicit value disagrees with the value derived from
	// `replicationMode`, and KB rejects the assignment via the
	// existing `ValidateConfigWithCue()` path that already binds
	// `#MariaDBParameter` to every INI section.
	//
	// `replicationMode` is intentionally NOT given a default. Per
	// weston 2026-05-20 00:08 msg `cb0afa37`: when the user does
	// not set `replicationMode`, the four real variables are
	// freely settable and the cluster defaults to async via the
	// `rpl_semi_sync_*_enabled` defaults of OFF below.
	replicationMode?: "async" | "semisync"

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

	// C3 precedence — `replicationMode` overrides the two
	// `*_enabled` fields. The conditional blocks unify those
	// fields with the derived value; if the user also sets one of
	// them with a conflicting literal, CUE unification fails and
	// KB rejects the assignment. The auxiliary `wait_for_slave_count`
	// and `master_timeout` fields are not constrained by
	// `replicationMode` — they remain user-tunable within their
	// declared int range whether the cluster runs async or
	// semisync (engine ignores the values when semisync is OFF).
	if replicationMode == "semisync" {
		rpl_semi_sync_master_enabled: "ON"
		rpl_semi_sync_slave_enabled:  "ON"
	}
	if replicationMode == "async" {
		rpl_semi_sync_master_enabled: "OFF"
		rpl_semi_sync_slave_enabled:  "OFF"
	}
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
