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
$EJABBERDCTL -n $ERLANG_NODE_ARG status 
# Check if the node is already running
NODE_STATUS=$($EJABBERDCTL -n $ERLANG_NODE_ARG status | grep "Failed RPC connection to the node")
Cluster_STATUS=$($EJABBERDCTL -n $ERLANG_NODE_ARG status | grep "Failed RPC connection to the node")

if [[ -z "$NODE_STATUS" ]]; then
# If the node is not running, start it
  echo "Node ejabberd@$ERLANG_NODE_ARG is not running. Starting it..."
  $EJABBERDCTL -n $ERLANG_NODE_ARG start 
  $EJABBERDCTL -n $ERLANG_NODE_ARG started
else
  echo "Node ejabberd@$ERLANG_NODE_ARG is already running."
fi

if [ $HOSTNAME_S == "chatservice-headless-0" ]; then
 echo "This is the seed node. No need to join the cluster."
else
    if [[ -z "$Cluster_STATUS" ]]; then
    # If the node is not running, start it
    echo "CLuster need to join"

    else
    echo "Already clustered"
    fi
   
fi

#Define cleanup procedure
cleanup() {
    echo "Container stopped, performing cleanup..."
    $EJABBERDCTL -n $ERLANG_NODE_ARG leave_cluster "$ERLANG_NODE_ARG"
    $EJABBERDCTL -n $ERLANG_NODE_ARG stop
}

#Trap SIGTERM
trap 'cleanup' SIGTERM

# echo "launching in foreground"
# $EJABBERDCTL -n $ERLANG_NODE_ARG foreground &

#Wait
#wait $!
