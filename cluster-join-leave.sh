#!/bin/bash

EJABBERDCTL=/opt/ejabberd/sbin/ejabberdctl
HOSTNAME_S=$(hostname -s) # ejabberd-0
HOSTNAME_F=$(hostname -f) # ejabberd-0.ejabberd.default.svc.cluster.local
HEADLESS_SERVICE="${HOSTNAME_F/$HOSTNAME_S./}" # ejabberd.default.svc.cluster.local
ERLANG_NODE_ARG="ejabberd@$HOSTNAME_F" # ejabberd@ejabberd-0.ejabberd.default.svc.cluster.local
ERLANG_NODE=$ERLANG_NODE_ARG

echo $EJABBERDCTL
echo $HEADLESS_SERVICE
echo $ERLANG_NODE_ARG
# Check if the node is already running
NODE_STATUS=$($EJABBERDCTL -n $ERLANG_NODE_ARG status | grep "Failed RPC connection to the node")
if [[ -z "$NODE_STATUS" ]]; then
# If the node is not running, start it
  echo "Node ejabberd@$ERLANG_NODE_ARG is already running."
else
 echo "Node ejabberd@$ERLANG_NODE_ARG is not running. Starting it..."
  # # echo "launching in foreground"
 $EJABBERDCTL -n $ERLANG_NODE_ARG foreground 
 sleep 10
fi

while true; do

Cluster_STATUS=$($EJABBERDCTL -n $ERLANG_NODE_ARG status | grep "Failed RPC connection to the node")
if [ $HOSTNAME_S == "chatservice-headless-0" ]; then
 echo "This is the seed node. No need to join the cluster."
else

    if [[ -z "$Cluster_STATUS" ]]; then
    # If the node is not running, start it
    
     echo "Already clustered"
    else
    echo "CLuster need to join"
     $EJABBERDCTL -n $ERLANG_NODE_ARG join_cluster "ejabberd@chatservice-headless-0.$HEADLESS_SERVICE"
    echo "cluster Joined"
    fi
fi

sleep 30
done
#Define cleanup procedure
cleanup() {
    echo "Container stopped, performing cleanup..."
    $EJABBERDCTL -n $ERLANG_NODE_ARG leave_cluster "$ERLANG_NODE_ARG"
    $EJABBERDCTL -n $ERLANG_NODE_ARG stop
}

#Trap SIGTERM
trap 'cleanup' SIGTERM

# # echo "launching in foreground"
# $EJABBERDCTL -n $ERLANG_NODE_ARG foreground &

# #Wait
# wait $!
