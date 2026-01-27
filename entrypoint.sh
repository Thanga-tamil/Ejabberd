#!/bin/bash

# --- Set limits BEFORE ejabberd starts ---
ulimit -n 1000000
ulimit -u 2000000

echo "ULIMIT SETTINGS:"
echo "nofile: $(ulimit -n)"
echo "nproc:  $(ulimit -u)"

# --- Delegate to original cluster logic ---
exec /usr/local/bin/cluster-join-leave.sh