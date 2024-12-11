#!/bin/bash

NAMESPACE="default"  # Set your Kubernetes namespace here
POD_LABEL_SELECTOR="app=ejabberd"  # Adjust this to your ejabberd pod label
EJABBERDCTL="/opt/ejabberd/bin/ejabberdctl"
POD_NAME=$(hostname)  # Use the hostname as the pod name in StatefulSet
SLEEP_INTERVAL=30  # Interval in seconds to check the status

# Function to check ejabberd pod status
check_ejabberd_status() {
    PODS_RUNNING=$(kubectl get pods -n $NAMESPACE -l $POD_LABEL_SELECTOR --field-selector=status.phase=Running --no-headers | wc -l)
    if [ "$PODS_RUNNING" -gt 0 ]; then
        return 0  # ejabberd is running
    else
        return 1  # ejabberd is not running
    fi
}

# Function to leave the ejabberd cluster
leave_cluster() {
    echo "Attempting to leave the cluster..."
    $EJABBERDCTL leave_cluster
    if [ $? -eq 0 ]; then
        echo "Left the cluster successfully."
    else
        echo "Failed to leave the cluster."
    fi
}

# Function to join the ejabberd cluster
join_cluster() {
    TARGET_NODE="ejabberd@node_name"  # Replace with the actual cluster node name
    echo "Attempting to join the cluster at $TARGET_NODE..."
    $EJABBERDCTL join_cluster $TARGET_NODE
    if [ $? -eq 0 ]; then
        echo "Joined the cluster successfully."
    else
        echo "Failed to join the cluster."
    fi
}

# Main loop to monitor ejabberd status
monitor_ejabberd() {
    PREVIOUS_STATUS="unknown"

    echo "Current pod: $POD_NAME"

    # If this is the headless pod (ejabberd-0), no need to join the cluster
    if [[ "$POD_NAME" == "ejabberd-0" ]]; then
        echo "This is the headless/primary node, no need to join the cluster."
        exit 0
    fi

    while true; do
        check_ejabberd_status
        CURRENT_STATUS=$?

        # If ejabberd has stopped running, leave the cluster
        if [[ $CURRENT_STATUS -eq 1 && "$PREVIOUS_STATUS" == "0" ]]; then
            echo "ejabberd stopped, leaving the cluster..."
            leave_cluster
        fi

        # If ejabberd has started running, join the cluster
        if [[ $CURRENT_STATUS -eq 0 && "$PREVIOUS_STATUS" == "1" ]]; then
            echo "ejabberd started, joining the cluster..."
            join_cluster
        fi

        # Update the previous status
        PREVIOUS_STATUS=$CURRENT_STATUS

        # Sleep for the defined interval
        sleep $SLEEP_INTERVAL
    done
}

# Start monitoring ejabberd
monitor_ejabberd
