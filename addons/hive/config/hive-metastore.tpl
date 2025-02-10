<?xml version="1.0" encoding="utf-8"?>

<configuration>
    <property>
        <name>javax.jdo.option.ConnectionURL</name>
        <value>jdbc:mysql://{{- .METADB_MYSQL_ENDPOINTS }}:3306/hive_metadata?allowPublicKeyRetrieval=true&amp;createDatabaseIfNotExist=true&amp;useSSL=false</value>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionDriverName</name>
        <value>com.mysql.jdbc.Driver</value>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionUserName</name>
        <value>{{ getEnvByName ( getContainerByName $.podSpec.containers "hive-metastore" ) "METADB_MYSQL_USERNAME" }}</value>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionPassword</name>
        <value>{{ getEnvByName ( getContainerByName $.podSpec.containers "hive-metastore" ) "METADB_MYSQL_PASSWORD" }}</value>
    </property>
    <property>
        <name>hive.metastore.warehouse.dir</name>
        <value>/warehouse/hive</value>
    </property>
    <property>
        <name>spark.sql.warehouse.dir</name>
        <value>/warehouse/spark</value>
    </property>
    <property>
        <name>hive.metastore.schema.verification</name>
        <value>false</value>
    </property>
    <property>
        <name>hive.metastore.event.db.notification.api.auth</name>
        <value>false</value>
    </property>
    <property>
        <name>hive.cli.print.header</name>
        <value>true</value>
    </property>
    <property>
        <name>hive.cli.print.current.db</name>
        <value>true</value>
    </property>
</configuration>
