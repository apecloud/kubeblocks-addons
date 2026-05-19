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
// This schema only declares the four `rpl_semi_sync_*` engine
// variables that are the real source-of-truth for replication mode
// (per Jack's enum-research conclusion). It does not declare a
// `replicationMode` synthetic key — KB has no transform from a
// synthetic key to multiple engine variables (ParamConfigRenderer
// has no transform hook); declaring `replicationMode` here would
// either be ignored or, if KB treats it as a managed key, write
// `replicationMode = semisync` into my.cnf, which mariadbd does
// not recognize. The unified-switch UX is provided by addon-side
// docs and (future) helper scripts that emit the four-parameter
// block from a single user-facing choice.
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
