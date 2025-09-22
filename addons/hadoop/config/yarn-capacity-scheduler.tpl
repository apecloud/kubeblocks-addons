<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>

  <property>
    <name>yarn.scheduler.capacity.maximum-applications</name>
    <value>10000</value>
  </property>

  <property>
    <name>yarn.scheduler.capacity.maximum-am-resource-percent</name>
    <value>0.1</value>
  </property>

  <property>
    <name>yarn.scheduler.capacity.resource-calculator</name>
    <value>org.apache.hadoop.yarn.util.resource.DefaultResourceCalculator</value>
  </property>

  <property>
    <name>yarn.scheduler.capacity.root.queues</name>
    <value>default</value>
  </property>

  <property>
    <name>yarn.scheduler.capacity.root.default.capacity</name>
    <value>100</value>
  </property>

  <property>
    <name>yarn.scheduler.capacity.root.default.user-limit-factor</name>
    <value>1</value>
  </property>

  <property>
    <name>yarn.scheduler.capacity.root.default.maximum-capacity</name>
    <value>100</value>
  </property>

  <property>
    <name>yarn.scheduler.capacity.root.default.state</name>
    <value>RUNNING</value>
  </property>

  <property>
    <name>yarn.scheduler.capacity.root.default.acl_submit_applications</name>
    <value>*</value>
  </property>

  <property>
    <name>yarn.scheduler.capacity.root.default.acl_administer_queue</name>
    <value>*</value>
  </property>

  <property>
    <name>yarn.scheduler.capacity.root.default.acl_application_max_priority</name>
    <value>*</value>
  </property>

   <property>
     <name>yarn.scheduler.capacity.root.default.maximum-application-lifetime
     </name>
     <value>-1</value>
   </property>

   <property>
     <name>yarn.scheduler.capacity.root.default.default-application-lifetime
     </name>
     <value>-1</value>
   </property>

  <property>
    <name>yarn.scheduler.capacity.node-locality-delay</name>
    <value>40</value>
  </property>

  <property>
    <name>yarn.scheduler.capacity.rack-locality-additional-delay</name>
    <value>-1</value>
  </property>

  <property>
    <name>yarn.scheduler.capacity.queue-mappings</name>
    <value></value>
  </property>

  <property>
    <name>yarn.scheduler.capacity.queue-mappings-override.enable</name>
    <value>false</value>
  </property>

  <property>
    <name>yarn.scheduler.capacity.per-node-heartbeat.maximum-offswitch-assignments</name>
    <value>1</value>
  </property>


  <property>
    <name>yarn.scheduler.capacity.application.fail-fast</name>
    <value>false</value>
  </property>

  <property>
    <name>yarn.scheduler.capacity.workflow-priority-mappings</name>
    <value></value>
  </property>

  <property>
    <name>yarn.scheduler.capacity.workflow-priority-mappings-override.enable</name>
    <value>false</value>
  </property>

</configuration>