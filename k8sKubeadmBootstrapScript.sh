#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Functions ---

# Function to display colored output
function print_color {
    case "$1" in
        "green") echo -e "\n\e[32m$2\e[0m" ;;
        "red") echo -e "\n\e[31m$2\e[0m" ;;
        "blue") echo -e "\n\e[34m$2\e[0m" ;;
        *) echo "$2" ;;
    esac
}

# Function to validate if input is a positive integer
function validate_integer {
    if ! [[ "$1" =~ ^[1-9][0-9]*$ ]]; then
        print_color "red" "Error: Please enter a valid positive number."
        exit 1
    fi
}

# Function to validate IP address format
function validate_ip {
    if ! [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_color "red" "Error: Invalid IP address format."
        exit 1
    fi
}

# --- Collect User Input ---

print_color "blue" "--- Kubernetes Cluster Configuration ---"

# Get Cluster Name
read -p "Enter a name for your Kubernetes cluster: " CLUSTER_NAME
if [ -z "$CLUSTER_NAME" ]; then
    print_color "red" "Error: Cluster name cannot be empty."
    exit 1
fi

# --- Master Node Configuration ---
print_color "blue" "\n--- Master Node Details ---"
read -p "How many master nodes will you have? " MASTER_COUNT
validate_integer "$MASTER_COUNT"

declare -a MASTER_IPS
declare -a MASTER_HOSTNAMES
declare -a MASTER_SSH_KEYS
declare -a MASTER_ADMIN_USERS

for (( i=1; i<=MASTER_COUNT; i++ )); do
    print_color "green" "\nEnter details for Master Node #$i:"
    read -p "  IP Address: " ip
    validate_ip "$ip"
    MASTER_IPS+=("$ip")

    read -p "  Hostname: " hostname
    MASTER_HOSTNAMES+=("$hostname")

    read -p "  SSH Private Key Path (leave empty for password auth or agent): " key
    MASTER_SSH_KEYS+=("$key")

    read -p "  Administrative Username: " user
    MASTER_ADMIN_USERS+=("$user")
done

# --- Worker Node Configuration ---
print_color "blue" "\n--- Worker Node Details ---"
read -p "How many worker nodes will you have? " WORKER_COUNT
validate_integer "$WORKER_COUNT"

declare -a WORKER_IPS
declare -a WORKER_HOSTNAMES
declare -a WORKER_SSH_KEYS
declare -a WORKER_ADMIN_USERS

for (( i=1; i<=WORKER_COUNT; i++ )); do
    print_color "green" "\nEnter details for Worker Node #$i:"
    read -p "  IP Address: " ip
    validate_ip "$ip"
    WORKER_IPS+=("$ip")

    read -p "  Hostname: " hostname
    WORKER_HOSTNAMES+=("$hostname")

    read -p "  SSH Private Key Path (leave empty for password auth or agent): " key
    WORKER_SSH_KEYS+=("$key")

    read -p "  Administrative Username: " user
    WORKER_ADMIN_USERS+=("$user")
done

# --- Installation Script ---

# This script will be copied and executed on each node.
cat << 'EOF' > /tmp/k8s_node_setup.sh
#!/bin/bash
set -e # Exit on error

echo "--- [NODE] Starting Kubernetes prerequisite installation ---"

# Disable swap
sudo swapoff -a
# And comment out the swap line in /etc/fstab
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Load required kernel modules
sudo modprobe overlay
sudo modprobe br_netfilter

# Configure sysctl settings for Kubernetes networking
cat <<EOT | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOT
sudo sysctl --system

echo "--- [NODE] Installing containerd ---"
# Install containerd
sudo apt-get update
sudo apt-get install -y containerd

# Configure containerd
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml
# Set the cgroup driver to systemd
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd

echo "--- [NODE] Installing kubeadm, kubelet, and kubectl ---"
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# Add Kubernetes GPG key
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add Kubernetes apt repository
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

echo "--- [NODE] Prerequisite installation complete ---"
EOF

# --- Function to build SSH command ---
function get_ssh_cmd {
    local user=$1
    local ip=$2
    local key=$3
    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

    if [ -n "$key" ]; then
        echo "ssh ${ssh_opts} -i ${key} ${user}@${ip}"
    else
        echo "ssh ${ssh_opts} ${user}@${ip}"
    fi
}

# --- Function to build SCP command ---
function get_scp_cmd {
    local user=$1
    local ip=$2
    local key=$3
    local scp_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

    if [ -n "$key" ]; then
        echo "scp ${scp_opts} -i ${key}"
    else
        echo "scp ${scp_opts}"
    fi
}


# --- Provision Master Nodes ---
print_color "blue" "\n--- Provisioning Master Nodes ---"
FIRST_MASTER_IP=${MASTER_IPS[0]}
FIRST_MASTER_USER=${MASTER_ADMIN_USERS[0]}
FIRST_MASTER_KEY=${MASTER_SSH_KEYS[0]}

for (( i=0; i<MASTER_COUNT; i++ )); do
    IP=${MASTER_IPS[$i]}
    USER=${MASTER_ADMIN_USERS[$i]}
    KEY=${MASTER_SSH_KEYS[$i]}
    HOSTNAME=${MASTER_HOSTNAMES[$i]}

    print_color "green" "Provisioning Master Node: ${HOSTNAME} (${IP})"
    SSH_CMD=$(get_ssh_cmd "$USER" "$IP" "$KEY")
    SCP_CMD=$(get_scp_cmd "$USER" "$IP" "$KEY")

    # Set hostname
    $SSH_CMD "sudo hostnamectl set-hostname ${HOSTNAME}"

    # Copy and execute setup script
    $SCP_CMD /tmp/k8s_node_setup.sh ${USER}@${IP}:/tmp/k8s_node_setup.sh
    $SSH_CMD "chmod +x /tmp/k8s_node_setup.sh && /tmp/k8s_node_setup.sh"
done

# --- Initialize Cluster on the First Master ---
print_color "blue" "\n--- Initializing Kubernetes Cluster on ${MASTER_HOSTNAMES[0]} ---"
SSH_CMD_FIRST_MASTER=$(get_ssh_cmd "$FIRST_MASTER_USER" "$FIRST_MASTER_IP" "$FIRST_MASTER_KEY")

# Initialize the cluster
# We use --pod-network-cidr required for most CNI plugins like Calico or Flannel
INIT_CMD="sudo kubeadm init --pod-network-cidr=192.168.0.0/16 --apiserver-advertise-address=${FIRST_MASTER_IP} --node-name=${MASTER_HOSTNAMES[0]} --v=5"
$SSH_CMD_FIRST_MASTER "$INIT_CMD"

# Setup kubeconfig for the admin user on the master
print_color "blue" "Configuring kubectl for user ${FIRST_MASTER_USER} on ${MASTER_HOSTNAMES[0]}"
$SSH_CMD_FIRST_MASTER "mkdir -p \$HOME/.kube"
$SSH_CMD_FIRST_MASTER "sudo cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config"
$SSH_CMD_FIRST_MASTER "sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config"

# Get the join commands
print_color "blue" "Retrieving join commands from the first master..."
MASTER_JOIN_CMD=$($SSH_CMD_FIRST_MASTER "kubeadm token create --print-join-command")
WORKER_JOIN_CMD=$($SSH_CMD_FIRST_MASTER "kubeadm token create --print-join-command") # A separate token for workers is good practice

# --- Join Additional Master Nodes ---
if [ "$MASTER_COUNT" -gt 1 ]; then
    print_color "blue" "\n--- Joining Additional Master Nodes to the Cluster ---"
    for (( i=1; i<MASTER_COUNT; i++ )); do
        IP=${MASTER_IPS[$i]}
        USER=${MASTER_ADMIN_USERS[$i]}
        KEY=${MASTER_SSH_KEYS[$i]}
        HOSTNAME=${MASTER_HOSTNAMES[$i]}
        print_color "green" "Joining Master Node: ${HOSTNAME} (${IP})"
        SSH_CMD=$(get_ssh_cmd "$USER" "$IP" "$KEY")
        $SSH_CMD "sudo ${MASTER_JOIN_CMD} --control-plane"
    done
fi

# --- Provision and Join Worker Nodes ---
print_color "blue" "\n--- Provisioning and Joining Worker Nodes ---"
for (( i=0; i<WORKER_COUNT; i++ )); do
    IP=${WORKER_IPS[$i]}
    USER=${WORKER_ADMIN_USERS[$i]}
    KEY=${WORKER_SSH_KEYS[$i]}
    HOSTNAME=${WORKER_HOSTNAMES[$i]}

    print_color "green" "Provisioning Worker Node: ${HOSTNAME} (${IP})"
    SSH_CMD=$(get_ssh_cmd "$USER" "$IP" "$KEY")
    SCP_CMD=$(get_scp_cmd "$USER" "$IP" "$KEY")

    # Set hostname
    $SSH_CMD "sudo hostnamectl set-hostname ${HOSTNAME}"

    # Copy and execute setup script
    $SCP_CMD /tmp/k8s_node_setup.sh ${USER}@${IP}:/tmp/k8s_node_setup.sh
    $SSH_CMD "chmod +x /tmp/k8s_node_setup.sh && /tmp/k8s_node_setup.sh"

    print_color "green" "Joining Worker Node: ${HOSTNAME} (${IP})"
    $SSH_CMD "sudo ${WORKER_JOIN_CMD}"
done


# --- Final Steps ---
print_color "blue" "\n--- Applying CNI (Calico) ---"
# Note: You can replace this with Flannel or another CNI if you prefer.
$SSH_CMD_FIRST_MASTER "kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml"


# --- Cleanup ---
rm /tmp/k8s_node_setup.sh

print_color "green" "\n🎉 Kubernetes cluster '${CLUSTER_NAME}' has been created successfully! 🎉"
print_color "green" "You can now access your cluster by SSHing into the first master node:"
print_color "green" "  ${SSH_CMD_FIRST_MASTER}"
print_color "green" "Once logged in, you can run 'kubectl get nodes' to see the status of your cluster."
