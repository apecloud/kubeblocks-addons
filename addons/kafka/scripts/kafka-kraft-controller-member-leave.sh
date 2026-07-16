#!/bin/sh

printf '%s\n' 'Kafka KRaft controller scale-in is unsupported: this addon uses static controller.quorum.voters; keep controller replicas unchanged and scale only brokers in separated topology' >&2
exit 1
