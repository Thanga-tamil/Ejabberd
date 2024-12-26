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

if [[ -z "$NODE_STATUS" ]]; then
 echo "Node ejabberd@$ERLANG_NODE_ARG is already running."
 
else
  # If the node is not running, start it
  echo "Node ejabberd@$ERLANG_NODE_ARG is not running. Starting it..."
  $EJABBERDCTL -n $ERLANG_NODE_ARG start 
  $EJABBERDCTL -n $ERLANG_NODE_ARG started
fi

if [ $HOSTNAME_S == "chatservice-headless-0" ]; then
 echo "This is the seed node. No need to join the cluster."
else
Cluster_STATUS=$($EJABBERDCTL -n $ERLANG_NODE_ARG list_cluster | grep "Failed RPC connection to the node")

if [[ -z "$Cluster_STATUS" ]]; then
  echo "already in cluster"
  
else
  echo "Clusert Not added"
  IPS=$(nslookup $HEADLESS_SERVICE | tail -n +3 | grep "Address:" | sed -E 's/^Address: (.*)$/\1/')
echo "IPS: $IPS"

for IP in ${IPS}
do
    echo "looking up hostname for: $IP"
    HOSTNAMES=$(nslookup $IP | grep 'name =' | awk '{print $4}' | sed 's/\.$//' | awk -F '.' '{print $1}')
    echo "Resolved Hostname: $HOSTNAMES"
     echo "HOSTNAME: $HOSTNAME"
    echo "HOSTNAME_F: $HOSTNAME_F"
    echo "HOSTNAME_S: $HOSTNAME_S"
   if [[ "$HOSTNAME_S" == "$HOSTNAMES" ]] ; then
        echo "found own hostname, skipping"
        continue
    fi
    echo "HOSTNAME: $HOSTNAME"
    echo "HOSTNAME_F: $HOSTNAME_F"
    echo "HOSTNAME_S: $HOSTNAME_S"
    
    echo "trying to connect to node with hostname $HOSTNAME_S.$HEADLESS_SERVICE"
    $EJABBERDCTL -n $ERLANG_NODE_ARG join_cluster "ejabberd@$HOSTNAME_S.$HEADLESS_SERVICE"
    CLUSTERING_RESULT=$?
    $EJABBERDCTL -n $ERLANG_NODE_ARG list_cluster
    $EJABBERDCTL -n $ERLANG_NODE_ARG stop
    $EJABBERDCTL -n $ERLANG_NODE_ARG stopped
    if [[ $? -eq 0 ]] ; then
        echo "successfully joined";
        break
    else
        echo "failed to join, trying next";
    fi
done
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
wait $!
