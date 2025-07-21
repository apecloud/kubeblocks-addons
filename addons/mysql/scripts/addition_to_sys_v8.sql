USE sys;

DELIMITER $$

CREATE FUNCTION my_id() RETURNS TEXT(36) DETERMINISTIC NO SQL RETURN (SELECT @@global.server_uuid as my_id);$$

-- previous obsolete function
-- CREATE FUNCTION gr_member_in_primary_partition()
-- RETURNS VARCHAR(3)
-- DETERMINISTIC
-- BEGIN
--  RETURN (SELECT IF( MEMBER_STATE='ONLINE' AND ((SELECT COUNT(*) FROM
--  performance_schema.replication_group_members WHERE MEMBER_STATE != 'ONLINE') >=
--  ((SELECT COUNT(*) FROM performance_schema.replication_group_members)/2) = 0),
--  'YES', 'NO' ) FROM performance_schema.replication_group_members JOIN
--  performance_schema.replication_group_member_stats USING(member_id) where member_id=my_id());
-- END$$

-- new function, contribution from Bruce DeFrang
CREATE FUNCTION gr_member_in_primary_partition()
    RETURNS VARCHAR(3)
    DETERMINISTIC
    BEGIN
     RETURN (SELECT IF( MEMBER_STATE='ONLINE' AND ((SELECT COUNT(*) FROM
    performance_schema.replication_group_members WHERE MEMBER_STATE NOT IN ('ONLINE', 'RECOVERING')) >=
    ((SELECT COUNT(*) FROM performance_schema.replication_group_members)/2) = 0),
    'YES', 'NO' ) FROM performance_schema.replication_group_members JOIN
    performance_schema.replication_group_member_stats USING(member_id) where member_id=my_id());
END$$

CREATE VIEW gr_member_routing_candidate_status AS SELECT
sys.gr_member_in_primary_partition() as viable_candidate,
IF( (SELECT (SELECT GROUP_CONCAT(variable_value) FROM
performance_schema.global_variables WHERE variable_name IN ('read_only',
'super_read_only')) != 'OFF,OFF'), 'YES', 'NO') as read_only,
Count_Transactions_Remote_In_Applier_Queue as transactions_behind, Count_Transactions_in_queue as 'transactions_to_cert'
from performance_schema.replication_group_member_stats where member_id=my_id();$$

DELIMITER ;