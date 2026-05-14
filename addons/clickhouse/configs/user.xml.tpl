<clickhouse>
  <!-- Settings profiles -->
  <profiles>
    <!-- Admin user settings -->
    <default>
      <!-- The maximum number of threads when running a single query, which is used for admin user -->
      <max_threads>8</max_threads>
      <log_queries>1</log_queries>
      <log_queries_min_query_duration_ms>2000</log_queries_min_query_duration_ms>
      {{- if eq (index . "CLICKHOUSE_READONLY_MODE") "true" }}
      <!-- Readonly mode enforced by read-only replica component.
           readonly=2: SELECT and setting changes allowed, but no DDL/DML (INSERT/CREATE/ALTER).
           Using 2 instead of 1 so connection-level settings (e.g. connect_timeout) still work. -->
      <readonly>2</readonly>
      {{- end }}
    </default>

    <!-- Settings for queries from the user interface, this is a example profile for day-2-create user or special sessions -->
    <web>
      <max_rows_to_read>1000000000</max_rows_to_read>
      <max_bytes_to_read>100000000000</max_bytes_to_read>

      <max_rows_to_group_by>1000000</max_rows_to_group_by>
      <group_by_overflow_mode>any</group_by_overflow_mode>

      <max_rows_to_sort>1000000</max_rows_to_sort>
      <max_bytes_to_sort>1000000000</max_bytes_to_sort>

      <max_result_rows>100000</max_result_rows>
      <max_result_bytes>100000000</max_result_bytes>
      <result_overflow_mode>break</result_overflow_mode>

      <max_execution_time>600</max_execution_time>
      <min_execution_speed>1000000</min_execution_speed>
      <timeout_before_checking_execution_speed>15</timeout_before_checking_execution_speed>

      <max_columns_to_read>25</max_columns_to_read>
      <max_temporary_columns>100</max_temporary_columns>
      <max_temporary_non_const_columns>50</max_temporary_non_const_columns>

      <max_subquery_depth>2</max_subquery_depth>
      <max_pipeline_depth>25</max_pipeline_depth>
      <max_ast_depth>50</max_ast_depth>
      <max_ast_elements>100</max_ast_elements>

      <readonly>1</readonly>
    </web>

    <!-- Read-only analytics profile: SELECT only, no DDL/DML -->
    <readonly>
      <readonly>1</readonly>
      <log_queries>1</log_queries>
      <max_execution_time>120</max_execution_time>
    </readonly>

    <!-- Monitoring profile: read system.* tables only -->
    <monitoring>
      <readonly>1</readonly>
      <log_queries>0</log_queries>
    </monitoring>

    <!-- Ingest profile: INSERT only, no SELECT on user tables -->
    <ingest>
      <readonly>0</readonly>
      <log_queries>1</log_queries>
    </ingest>
  </profiles>

  <!-- Resource usage limits enforced per 1-hour time window -->
  <quotas>
    <default>
      <interval>
        <duration>3600</duration>
        <queries>0</queries>
        <errors>0</errors>
        <result_rows>0</result_rows>
        <read_rows>0</read_rows>
        <execution_time>0</execution_time>
      </interval>
    </default>
  </quotas>

  <!-- Users and roles -->
  <users>
    <!-- Admin user with full access -->
    <admin replace="replace">
      <password from_env="CLICKHOUSE_ADMIN_PASSWORD"/>
      <access_management>1</access_management>
      <named_collection_control>1</named_collection_control>
      <show_named_collections>1</show_named_collections>
      <show_named_collections_secrets>1</show_named_collections_secrets>

      <networks replace="replace">
        <!-- Loopback always allowed (required for pod-local health checks and interserver communication) -->
        <ip>127.0.0.1</ip>
        <ip>::1</ip>
        {{- if index . "ALLOWED_NETWORKS" }}
        {{- range $_, $cidr := splitList "," (index . "ALLOWED_NETWORKS") }}
        <ip>{{ $cidr }}</ip>
        {{- end }}
        {{- else }}
        <ip>::/0</ip>
        {{- end }}
      </networks>

      <profile>default</profile>
      <quota>default</quota>
    </admin>
  </users>

  <!-- Role definitions for day-2 user management.
       Roles with grants must be created via SQL after cluster provisioning.
       Example:
         CREATE ROLE readonly;
         GRANT SELECT ON *.* TO readonly;
         CREATE USER analyst IDENTIFIED BY 'password';
         GRANT readonly TO analyst;

         CREATE ROLE monitoring;
         GRANT SELECT ON system.* TO monitoring;

         CREATE ROLE ingest;
         GRANT INSERT ON *.* TO ingest;
  -->
</clickhouse>
