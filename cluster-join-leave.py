import time
import subprocess
import os
from kubernetes import client, config

# Load Kubernetes config (default for in-cluster use)
config.load_kube_config()  # Use load_incluster_config() if inside a pod

v1 = client.CoreV1Api()

# Replace with the actual ejabberd pod label selector and namespace
POD_LABEL_SELECTOR = 'app=ejabberd'
NAMESPACE = 'default'  # Replace with your namespace
CLUSTER_COMMAND = '/opt/ejabberd/bin/ejabberdctl'

def get_ejabberd_status():
    """Check if ejabberd pod is running."""
    try:
        pods = v1.list_namespaced_pod(namespace=NAMESPACE, label_selector=POD_LABEL_SELECTOR)
        for pod in pods.items:
            if pod.status.phase == "Running":
                return True
        return False
    except Exception as e:
        print(f"Error fetching ejabberd pod status: {e}")
        return False

def leave_cluster():
    """Execute the leave cluster command."""
    try:
        result = subprocess.run([CLUSTER_COMMAND, "leave_cluster"], check=True, text=True, capture_output=True)
        print(f"Left cluster successfully: {result.stdout}")
    except subprocess.CalledProcessError as e:
        print(f"Error leaving cluster: {e.stderr}")

def join_cluster():
    """Execute the join cluster command."""
    try:
        # Replace 'node' with the actual target node to join the cluster
        target_node = 'ejabberd@node_name'
        result = subprocess.run([CLUSTER_COMMAND, "join_cluster", target_node], check=True, text=True, capture_output=True)
        print(f"Joined cluster successfully: {result.stdout}")
    except subprocess.CalledProcessError as e:
        print(f"Error joining cluster: {e.stderr}")

def get_pod_name():
    """Retrieve the current pod name from the environment or Kubernetes metadata."""
    return os.getenv('POD_NAME')  # Kubernetes injects POD_NAME in StatefulSet pods

def monitor_ejabberd():
    """Monitor ejabberd pod status and manage cluster membership."""
    previous_status = None
    pod_name = get_pod_name()

    print(f"Current pod: {pod_name}")

    if pod_name == 'ejabberd-0':
        print("This is the headless/primary node, no need to join the cluster.")
        return  # Exit the script if the node is headless

    while True:
        is_running = get_ejabberd_status()
        print(f"ejabberd running status: {is_running}")

        # Handle ejabberd stop scenario
        if not is_running and previous_status == True:
            print("ejabberd stopped, leaving cluster...")
            leave_cluster()

        # Handle ejabberd start scenario
        if is_running and previous_status == False:
            print("ejabberd started, joining cluster...")
            join_cluster()

        previous_status = is_running
        time.sleep(30)  # Check every 30 seconds

if __name__ == '__main__':
    monitor_ejabberd()
