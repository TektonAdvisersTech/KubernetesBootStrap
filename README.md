# KubernetesBootStrap
Bash Cript to automate the bootstrapping of the creation of a K8s cluster using kubeadm

Kubernetes Kubeadm Bootstrap Script
This script automates the process of bootstrapping a multi-node Kubernetes cluster on Ubuntu virtual machines using kubeadm. It interactively collects information about your desired cluster topology (master and worker nodes) and then remotely configures each node accordingly.
Overview
The script performs the following actions:
Gathers Cluster Details: Prompts the user for the cluster name, the number of master and worker nodes, and the connection details (IP address, hostname, admin user, and optional SSH key) for each node.
Prepares Nodes: Connects to each specified node via SSH to perform prerequisite setup, including:
Disabling swap memory.
Configuring required kernel modules (overlay, br_netfilter).
Setting necessary sysctl parameters for Kubernetes networking.
Installing containerd as the container runtime.
Installing Kubernetes components: kubeadm, kubelet, and kubectl.
Setting the hostname for each node.
Initializes the Control Plane: Runs kubeadm init on the first master node to bootstrap the cluster's control plane.
Configures kubectl: Sets up the kubeconfig file for the administrative user on the first master node, allowing immediate cluster management via kubectl.
Joins Nodes:
Joins any additional master nodes to the control plane for a high-availability (HA) setup.
Joins all specified worker nodes to the cluster.
Deploys a CNI: Automatically applies the Calico network plugin (CNI) to enable pod-to-pod communication.
Provides Confirmation: Notifies the user upon successful cluster creation and provides the command to access the cluster.
Prerequisites
Local Machine
A Bash-compatible shell (tested on Linux and macOS).
SSH client installed.
Network connectivity to all target Ubuntu nodes.
If using SSH keys, the private key must be available on the local machine.
Target Ubuntu Nodes
A fresh installation of Ubuntu LTS (22.04 or 20.04 is recommended).
Each node must have a unique hostname and a static IP address.
Full network connectivity between all nodes in the cluster.
An administrative user account with sudo privileges on all nodes.
The sshd service must be running and configured to allow login for the specified administrative user (either via password or SSH key).
How to Use
Save the Script: Save the script content to a file named bootstrap_k8s.sh.
Make it Executable: Open your terminal and grant execute permissions to the script.
chmod +x bootstrap_k8s.sh


Run the Script: Execute the script from your local machine.
./bootstrap_k8s.sh


Follow the Prompts: The script will guide you through the configuration process. You will be asked to provide the following information:
Cluster Name: A descriptive name for your cluster.
Master Nodes: The number of master nodes and for each one:
IP Address
Hostname
Administrative Username
Path to SSH Private Key (optional; leave empty for password authentication or if using an SSH agent).
Worker Nodes: The number of worker nodes and their corresponding details (IP, hostname, user, key).
The script will then proceed with the automated setup, displaying its progress in the terminal.
Post-Installation
Once the script completes, you will see a success message with instructions on how to access your new Kubernetes cluster.
SSH into the Master Node: Use the provided command to log into your first master node.
# The script will output the exact command to use, for example:
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null your-admin-user@your-master-ip


Verify the Cluster: Once logged in, you can verify that all nodes have joined the cluster successfully by running:
kubectl get nodes

You should see all your master and worker nodes listed with a Ready status. It may take a minute or two for all nodes to become fully ready after the CNI is applied.
Customization
Changing the CNI
The script defaults to using Calico as the Container Network Interface (CNI). If you wish to use a different CNI, such as Flannel or Weave Net, you can modify the following line near the end of the script:
# --- Final Steps ---
print_color "blue" "\n--- Applying CNI (Calico) ---"
# Note: You can replace this with Flannel or another CNI if you prefer.
$SSH_CMD_FIRST_MASTER "kubectl apply -f [https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml](https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml)"


Replace the URL with the manifest URL for your desired CNI plugin. Make sure the --pod-network-cidr value used in the kubeadm init command is compatible with your chosen CNI.

