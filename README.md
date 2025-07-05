# Kubernetes Kubeadm Bootstrap Script with Multus

This script provides a powerful, automated way to bootstrap a multi-node, multi-network Kubernetes cluster on Ubuntu virtual machines. It uses `kubeadm` for the core cluster setup and can optionally integrate `Multus CNI` to allow pods to connect to multiple physical networks.

The entire process is interactive, guiding you through the configuration of your master nodes, worker nodes, and any additional networks you require.

## Key Features

* **Interactive Setup:** No need to edit configuration files. The script asks for all required information.
* **Multi-Master Ready:** Easily create a High-Availability (HA) control plane by specifying more than one master node.
* **Multi-Network Pods:** Optional integration with **Multus CNI** and **macvlan** allows you to create pods with multiple network interfaces, connecting them directly to secondary physical networks.
* **Automated Prerequisite Installation:** Installs and configures all necessary components on each node, including `containerd`, `kubelet`, `kubeadm`, and `kubectl`.
* **Standard CNI Deployment:** Deploys Calico as the primary networking plugin for cluster-aware communication.
* **Automatic `NetworkAttachmentDefinition` Creation:** When using Multus, the script automatically generates the required Custom Resource Definitions for your secondary networks.

## How It Works: A Step-by-Step Breakdown

The script follows a logical sequence to build your cluster from the ground up. Here is a detailed look at each step:

### Step 1: Gathering Cluster Specifications

The script begins by interactively prompting you for all the necessary details about your cluster.

1.  **Cluster Name:** A unique name for your cluster.
2.  **Master Nodes:** The number of master nodes, followed by the IP address, hostname, admin username, and optional SSH key path for each one. The IP address provided here is used for primary cluster communication.
3.  **Worker Nodes:** The number of worker nodes and their corresponding details (IP, hostname, user, key).
4.  **Secondary Networks (Optional):** The script will ask if you want to configure secondary networks. If you answer 'yes', it will ask for:
    * The number of secondary networks.
    * For each network: a unique name (e.g., `storage-net`), the name of the physical network interface on the nodes (e.g., `eth1`), and the subnet in CIDR format (e.g., `192.168.100.0/24`).

### Step 2: Preparing the Node Installation Script

A temporary shell script (`/tmp/k8s_node_setup.sh`) is generated locally. This script contains all the commands needed to prepare a single Ubuntu node for Kubernetes. When executed on a target node, it will:

* Disable swap memory.
* Load necessary kernel modules (`overlay`, `br_netfilter`).
* Configure `sysctl` for Kubernetes networking.
* Install and configure `containerd` as the container runtime.
* Add the official Kubernetes `apt` repository.
* Install `kubeadm`, `kubelet`, and `kubectl`, and pin their versions.

### Step 3: Provisioning All Nodes

The script iterates through every master and worker node you defined. For each node, it performs the following over SSH:

1.  Sets the node's hostname to what you specified.
2.  Copies the `k8s_node_setup.sh` script to the node's `/tmp` directory.
3.  Executes the script with `sudo` privileges to run the prerequisite installations from Step 2.

### Step 4: Initializing the Control Plane

1.  The script executes `sudo kubeadm init` on the **first master node**. This command bootstraps the Kubernetes control plane.
2.  After initialization, it copies the `admin.conf` file to the admin user's home directory (`~/.kube/config`). This file contains the credentials to manage the cluster with `kubectl`.

### Step 5: Joining Nodes to the Cluster

1.  The script securely retrieves the unique join commands from the first master node.
2.  If you specified additional master nodes, it connects to each one and runs the join command with the `--control-plane` flag to create an HA control plane.
3.  It then connects to every specified worker node and runs the standard join command to add them to the cluster.

### Step 6: Deploying Network Plugins (CNI)

With the nodes joined, the networking is configured:

1.  **Primary CNI:** The script first applies the **Calico** CNI manifest. This creates the primary pod-to-pod network (`192.168.0.0/16` by default).
2.  **Multus Meta-Plugin (Optional):** If you opted-in, the script then applies the **Multus CNI** daemonset. Multus acts as a dispatcher, allowing other CNI plugins to be used simultaneously.

### Step 7: Configuring Secondary Networks (Optional)

If you are using Multus, the script does the following for each secondary network you defined:

1.  It creates a `NetworkAttachmentDefinition` YAML file locally. This custom resource tells Multus how to configure the secondary interface, specifying the use of the `macvlan` plugin, the target physical interface (`master`), and the subnet for IP address management (`ipam`).
2.  It copies this YAML file to the first master node.
3.  It uses `kubectl apply` on the master node to create the resource in the cluster.
4.  It cleans up the temporary YAML files from the local machine and the master node.

### Step 8: Finalization

Finally, the script cleans up the main temporary file (`/tmp/k8s_node_setup.sh`) and displays a success message, including the SSH command needed to access your new cluster's master node. If you configured Multus, it also provides a sample pod manifest to show you how to attach a pod to a secondary network.

## Prerequisites

* **Local Machine:** A Bash-compatible shell, an SSH client, and network access to all target nodes.
* **Target Ubuntu Nodes:** A fresh Ubuntu LTS installation (22.04/20.04 recommended), a unique hostname, a static IP, an admin user with `sudo`, and a running `sshd` service.

## Usage

1.  **Save the Script:** Save the code to a file named `bootstrap_k8s.sh`.
2.  **Make it Executable:** `chmod +x bootstrap_k8s.sh`
3.  **Run it:** `./bootstrap_k8s.sh` and follow the on-screen prompts.

## Using the Secondary Networks

To attach a pod to one of the secondary networks you created, you need to add an annotation to its metadata. The script provides an example upon completion.

**Example:** If you created a network named `storage-net`, your pod YAML would look like this:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: sample-pod-on-storage
  annotations:
    k8s.v1.cni.cncf.io/networks: storage-net
spec:
  containers:
  - name: sample-container
    image: busybox
    command: ['/bin/sh', '-c', 'ip a && sleep 3600']
