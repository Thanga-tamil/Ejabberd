#!/bin/sh

# Path to ejabberdctl
EJABBERDCTL="/opt/ejabberd/sbin/ejabberdctl"

# Start ejabberd service
$EJABBERDCTL start

echo "$(hostname)"

# If this is the first pod (ejabberd-0), it's the seed node
if [ "$(hostname)" = "chatservice-headless-0" ]; then
  echo "This is the seed node. No need to join the cluster."
else
  # Join the cluster using the seed node (ejabberd-0)
  echo "Joining the cluster..."
  $EJABBERDCTL -no-timeout join_cluster ejabberd@chatservice-headless-0.chatservice-headless-hl.uikit-dev.svc.cluster.local
fi

#Define cleanup procedure
cleanup() {

  # Join the cluster using the seed node (ejabberd-0)
  echo "Container stopped, performing cleanup..."
  $EJABBERDCTL leave_cluster ejabberd@chatservice-headless-0.chatservice-headless-hl.uikit-dev.svc.cluster.local
  $EJABBERDCTL stop

}

#Trap SIGTERM
trap 'cleanup' SIGTERM

# Keep the container running
tail -f /dev/null

