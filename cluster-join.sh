#!/bin/sh

# Path to ejabberdctl
EJABBERDCTL="/opt/ejabberd/bin/ejabberdctl"

# Start ejabberd service
$EJABBERDCTL start

# If this is the first pod (ejabberd-0), it's the seed node
if [ "$(hostname)" = "ejabberd-0" ]; then
  echo "This is the seed node. No need to join the cluster."
else
  # Join the cluster using the seed node (ejabberd-0)
  echo "Joining the cluster..."
  $EJABBERDCTL join ejabberd@ejabberd-0.ejabberd.default.svc.cluster.local
fi

#Define cleanup procedure
cleanup() {
  # If this is the first pod (ejabberd-0), it's the seed node
if [ "$(hostname)" = "ejabberd-0" ]; then
  echo "This is the seed node. No need to join the cluster."
else
  # Join the cluster using the seed node (ejabberd-0)
  echo "Joining the cluster..."
  $EJABBERDCTL leave_cluster ejabberd@ejabberd-0.ejabberd.default.svc.cluster.local
fi
    echo "Container stopped, performing cleanup..."
    $EJABBERDCTL -n $ERLANG_NODE_ARG leave_cluster "$ERLANG_NODE_ARG"
    $EJABBERDCTL -n $ERLANG_NODE_ARG stop
}

#Trap SIGTERM
trap 'cleanup' SIGTERM

# Keep the container running
tail -f /dev/null

