<clickhouse>
  <!--
    Read-only replica overrides.
    Sets the default connection profile to 'readonly' so that all non-admin
    connections are restricted to SELECT queries only.
    Admin connections (via the admin user profile) remain fully privileged.
  -->
  <profiles>
    <!-- Override the default profile to enforce read-only mode -->
    <default>
      <!-- 1 = allow SELECT; 0 = also allow DDL/DML.
           2 = allow SELECT + SET (settings changes) -->
      <readonly>1</readonly>
    </default>
  </profiles>
</clickhouse>
