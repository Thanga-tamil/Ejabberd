#!/bin/bash

EJABBERDCTL=/opt/ejabberd/sbin/ejabberdctl
HOSTNAME_S=$(hostname -s)  # ejabberd-0
HOSTNAME_F=$(hostname -f)  # ejabberd-0.ejabberd.default.svc.cluster.local
HEADLESS_SERVICE="${HOSTNAME_F/$HOSTNAME_S./}"  # ejabberd.default.svc.cluster.local
ERLANG_NODE_ARG="ejabberd@$HOSTNAME_F"  # ejabberd@ejabberd-0.ejabberd.default.svc.cluster.local

echo "Ejabberd Control: $EJABBERDCTL"
echo "Headless Service: $HEADLESS_SERVICE"
echo "Erlang Node: $ERLANG_NODE_ARG"
$EJABBERDCTL -n $ERLANG_NODE_ARG list_cluster

# Check if the node is already running
NODE_STATUS=$($EJABBERDCTL -n $ERLANG_NODE_ARG status | grep "Failed RPC connection to the node")

if [[ -z "$NODE_STATUS" ]]; then
    echo "Node ejabberd@$ERLANG_NODE_ARG is already running."
else
    echo "Node ejabberd@$ERLANG_NODE_ARG is not running. Starting it..."
    # $EJABBERDCTL -n $ERLANG_NODE_ARG start
    # sleep 10
fi


(
while true; do
    Cluster_STATUS=$($EJABBERDCTL -n $ERLANG_NODE_ARG list_cluster | grep "ejabberd@chatservice-headless-0.$HEADLESS_SERVICE")

    if [[ "$HOSTNAME_S" == "chatservice-headless-0" ]]; then
        echo "This is the seed node. No need to join the cluster."
    else
        if [[ -z "$Cluster_STATUS" ]]; then
        echo "Cluster needs to join"
            $EJABBERDCTL -n $ERLANG_NODE_ARG join_cluster "ejabberd@chatservice-headless-0.$HEADLESS_SERVICE"
            echo "Cluster joined"
            
        else
            echo "Already clustered"
        fi
    fi
    #$EJABBERDCTL -n $ERLANG_NODE_ARG list_cluster
    sleep 30  # Wait before checking again
done ) &

#Define cleanup procedure
cleanup() {
    echo "Container stopped, performing cleanup..."
    $EJABBERDCTL -n $ERLANG_NODE_ARG leave_cluster "ejabberd@chatservice-headless-0.$HEADLESS_SERVICE"
    $EJABBERDCTL -n $ERLANG_NODE_ARG stop
}

# Trap SIGTERM to cleanup properly on container stop
trap 'cleanup' SIGTERM

exec $EJABBERDCTL -n $ERLANG_NODE_ARG foreground