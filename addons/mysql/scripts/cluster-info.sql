
CREATE TABLE IF NOT EXISTS kb_orc_meta_cluster.kb_orc_meta_cluster (
    `anchor` tinyint(4) NOT NULL,
    `host_name` varchar(128) NOT NULL DEFAULT '',
    `cluster_name` varchar(128) NOT NULL DEFAULT '',
    `cluster_domain` varchar(128) NOT NULL DEFAULT '',
    `data_center` varchar(128) NOT NULL,
    PRIMARY KEY (`anchor`)
    );
