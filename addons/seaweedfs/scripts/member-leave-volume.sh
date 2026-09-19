#!/bin/sh
# Removing a data-bearing volume server without evacuation can lose objects.
printf '%s\n' 'SeaweedFS volume scale-in is unsupported: migrate and verify all data before removing a volume server.' >&2
exit 1
