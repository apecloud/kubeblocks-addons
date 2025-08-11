#!/bin/bash

calculate_signature_with_openssl() {
    local data="$1"
    local sk="$2"

    printf "%s" "$data" | openssl dgst -sha1 -hmac "$sk" -binary | base64
}

BINARY_DATA=""
if [ "$ENABLE_ACL" = "true" ]; then
    # 26 is request code of GET_BROKER_CONFIG
    sig=$(calculate_signature_with_openssl "$ROCKETMQ_USER" "$ROCKETMQ_PASSWORD")

    JSON_HEADER='{"code":26,"language":"GO","version":317,"opaque":1,"flag":0,"remark":"","extFields":{"Signature":"'$sig'","AccessKey":"'$ROCKETMQ_USER'"}}'
    HEADER_LEN=${#JSON_HEADER}
    BODY_LEN=0
    FRAME_SIZE=$((4 + HEADER_LEN + BODY_LEN))
    CODEC_TYPE=0

    BINARY_DATA+="\\x$(printf %08x $FRAME_SIZE | cut -c1-2)"
    BINARY_DATA+="\\x$(printf %08x $FRAME_SIZE | cut -c3-4)"
    BINARY_DATA+="\\x$(printf %08x $FRAME_SIZE | cut -c5-6)"
    BINARY_DATA+="\\x$(printf %08x $FRAME_SIZE | cut -c7-8)"

    BINARY_DATA+="\\x$(printf %02x $CODEC_TYPE)"

    BINARY_DATA+="\\x$(printf %06x "$HEADER_LEN" | cut -c1-2)"
    BINARY_DATA+="\\x$(printf %06x "$HEADER_LEN" | cut -c3-4)"
    BINARY_DATA+="\\x$(printf %06x "$HEADER_LEN" | cut -c5-6)"

    for (( i=0; i<${#JSON_HEADER}; i++ )); do
        CHAR="${JSON_HEADER:$i:1}"
        ASCII_CODE=$(printf "%d" "'$CHAR")
        BINARY_DATA+="\\x$(printf %02x "$ASCII_CODE")"
    done
else
    # Since the JSON_HEADER format is fixed and the calculation process is also fixed,
    # it can directly provide the BINARY_DATA.
    BINARY_DATA='\x00\x00\x00\x5c\x00\x00\x00\x58\x7b\x22\x63\x6f\x64\x65\x22\x3a\x32\x36\x2c\x22\x6c\x61\x6e\x67\x75\x61\x67\x65\x22\x3a\x22\x47\x4f\x22\x2c\x22\x76\x65\x72\x73\x69\x6f\x6e\x22\x3a\x33\x31\x37\x2c\x22\x6f\x70\x61\x71\x75\x65\x22\x3a\x31\x2c\x22\x66\x6c\x61\x67\x22\x3a\x30\x2c\x22\x72\x65\x6d\x61\x72\x6b\x22\x3a\x22\x22\x2c\x22\x65\x78\x74\x46\x69\x65\x6c\x64\x73\x22\x3a\x7b\x7d\x7d'
fi

brokerConfig=$(echo -e "$BINARY_DATA" | curl telnet://127.0.0.1:"$BROKER_PORT" --no-buffer --max-time 0.5 | tr -d '\0')
role=$(echo "$brokerConfig" | grep -o 'brokerRole=[^ ]*' | cut -d= -f2)
if [ "$role" == "SLAVE" ]; then
    echo -n "slave"
else
    echo -n "master"
fi
