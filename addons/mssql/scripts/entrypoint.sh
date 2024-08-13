#!/bin/bash
set -x
function conn_local {
  echo "[DEBUG] $1"
  /opt/mssql-tools18/bin/sqlcmd -S localhost -U SA -P $MSSQL_SA_PASSWORD -C -Q "$1"
}

# TODO: should generate dynamically
cer_base64="MIIDlzCCAf8CCDUHrsK764LGMA0GCSqGSIb3DQEBCwUAMA4xDDAKBgNVBAMMA2RibTAeFw0yNDA4MDcwMzAwMDFaFw0yNTA4MDcwMzAwMDFaMA4xDDAKBgNVBAMMA2RibTCCAaIwDQYJKoZIhvcNAQEBBQADggGPADCCAYoCggGBAK6kfT6055qqNFhm7D2XeCXr4j8T/LKcDjzfyCQY+vGMw0DD2UV3t76meiZ5eRQcpQCSWBfMSLo3i2boqi/AEpimNRieKtOxWHKsROm/XhvNdSUul+FYCGoRwn5suhwgQJOgEK8vMp5gLEbLsXR4r71ZfNJaTSuJbwxhIxmwgRkKTgurfyUKzbiZtGh0mEd6B8sBe2TS1ofQIBdu1kEeZuhkzVerOdyf018PWDGSwFfrJj1edP1gVMqf/E5KkhlqrJtujTNd86lMmjzJWDQIxC1FnkVm+v8xubK6VUoqpTM/UqAl8QxVTUHQOI0tjfy+FRGkE4TsXKo9nRcJzdRnGkf6faObKr3V1Sk5FN5e/c3fhcop399OywzLiAJ22EjfxoguzW84uiPylJLVwVP1ra4Giri/rnX1V7hDdNNeuePv1N/dfArIPJPVgpn2KLJGWZmPAwNiSk2SgdTAyYVpPrQneeyWIcUspCkKjVpZGSOFbDB6eSDn5k2iFB88+qi77QIDAQABMA0GCSqGSIb3DQEBCwUAA4IBgQBQ74zWGp1Ib5ylP5h0dq6Rz3p3xWYYFEVA4VvzDtMU28uimRUJSg4V7AoZ8XUsWPVq36xDOPZKEEBwDy6sK4Lun/Q7Zlfe48EGOVgPvpds2ecCUTs1c6YUtIuo9SsYVXRMciImcxq2CDGI9z8/Onu7pLalmKOFWMnS8G1QivglIIZZmZyLqGCAQ4NSHGzbzq0D4KptLJCdOVWMSek+pLudvflq1Xfhp11plDt0vDYViaa5IN1CPoDoD9UWSiATn7PSdkdEsSOv5sfoxJHkNLM6jPya3Pa8rekWFpfTL7k7rpQuUTnEihhGqCE+tRO5FaYTslYmXHqARALa4yPZp+Fzrb1IMGAVzDN0yn3Evm4xiZA/ebTK6DHNfxCkbSSJAOgtbAEBEkjlOSkp/W1SHjPTaJyTbABCx2WBOH1cXzrftHCii5muPlDrAXK0A/xhsdY4M/i+gyqgiGXhHXuIyHBUQN5xCsq/Q/2Kx0VhCUO/Sr5t01u466BEVwL07bzX5PE="
pvk_base64="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"
function create_certificate {
  # create certificate file
  echo $cer_base64 | base64 -d > /var/opt/mssql/data/dbm_certificate.cer
  echo $pvk_base64 | base64 -d > /var/opt/mssql/data/dbm_certificate.pvk
  # TODO: dynamic password
  create_certificate_sql=$(cat <<EOF
CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<Master_Key_Password>';
CREATE CERTIFICATE dbm_certificate
    FROM FILE = '/var/opt/mssql/data/dbm_certificate.cer'
    WITH PRIVATE KEY (
        FILE = '/var/opt/mssql/data/dbm_certificate.pvk',
        DECRYPTION BY PASSWORD = '<Private_Key_Password>'
    );
EOF
  )
  conn_local "$create_certificate_sql"
}

function create_mirroring_endpoint {
  create_mirroring_endpoint_sql=$(cat <<EOF
CREATE ENDPOINT [Hadr_endpoint]
    AS TCP (LISTENER_PORT = 5022)
    FOR DATABASE_MIRRORING (
        ROLE = ALL,
        AUTHENTICATION = CERTIFICATE dbm_certificate,
        ENCRYPTION = REQUIRED ALGORITHM AES
    );
ALTER ENDPOINT [Hadr_endpoint] STATE = STARTED;
EOF
  )
  conn_local "$create_mirroring_endpoint_sql"
}

function build_create_ag_sql {
  # TODO: ag name as configuration
  create_ag_sql=$(cat <<EOF
CREATE AVAILABILITY GROUP [ag1]
      WITH (DB_FAILOVER = ON, CLUSTER_TYPE = EXTERNAL)
      FOR REPLICA ON
EOF
  )
  IFS=',' read -ra pods <<< "$KB_POD_LIST"
  for i in "${!pods[@]}"; do
    pod_dns="${pods[$i]}.$KB_CLUSTER_COMP_NAME-headless"
    conf=$(cat <<EOF
         N'${pods[$i]}'
         WITH (
              ENDPOINT_URL = N'tcp://$pod_dns:5022',
              AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
              FAILOVER_MODE = EXTERNAL,
              SEEDING_MODE = AUTOMATIC
              )
EOF
    )
    create_ag_sql="$create_ag_sql $conf"
    if [[ $i -eq $((${#pods[@]} - 1)) ]]; then
      create_ag_sql="$create_ag_sql;"
    else
      create_ag_sql="$create_ag_sql,"
    fi
  done
  # TODO: ag1
  create_ag_sql="$create_ag_sql ALTER AVAILABILITY GROUP [ag1] GRANT CREATE ANY DATABASE;"
}
function create_ag {
  build_create_ag_sql
  conn_local "$create_ag_sql"
}

function wait_for_sqlservr_ready {
  while true; do
    conn_local "select 1"
    if [ $? -eq 0 ]; then
      break
    fi
    sleep 5
  done
}

function configure_ag {
  wait_for_sqlservr_ready
  create_certificate
  create_mirroring_endpoint
  create_ag
}

function wait_for_sqlservr_to_term {
  while true; do
    if [ -z "$(pidof sqlservr)" ]; then
      exit 1
    fi
    sleep 5
  done
}

/opt/mssql/bin/mssql-conf set hadr.hadrenabled 1

configure_ag | tee -a ag.log &

/opt/mssql/bin/sqlservr