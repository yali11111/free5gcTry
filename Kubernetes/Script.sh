#!/bin/bash
set -e

# -----------------------------
# 1️⃣ Install containerd and configure registry
# -----------------------------
echo "Installing containerd and configuring registry..."
apt-get update
apt-get install -y containerd libseccomp2 apt-transport-https curl

mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

cat << EOF >> /etc/containerd/config.toml
[plugins."io.containerd.grpc.v1.cri".registry.mirrors."oss.registry"]
  endpoint = ["http://oss:2345"]
[plugins."io.containerd.grpc.v1.cri".registry.configs."oss.registry".tls]
  insecure_skip_verify = true
EOF

systemctl restart containerd

# -----------------------------
# 2️⃣ Install Kubernetes
# -----------------------------
echo "Installing Kubernetes components..."
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
bash -c 'echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list'
apt-get update
apt-get install -y kubelet=1.22.2-00 kubeadm=1.22.2-00 kubectl=1.22.2-00
apt-mark hold kubelet kubeadm kubectl

# -----------------------------
# 3️⃣ Configure kubelet for containerd
# -----------------------------
mkdir -p /etc/systemd/system/kubelet.service.d
cat << EOF > /etc/systemd/system/kubelet.service.d/0-containerd.conf
[Service]
Environment="KUBELET_EXTRA_ARGS=--container-runtime=remote --runtime-request-timeout=15m --container-runtime-endpoint=unix:///run/containerd/containerd.sock"
EOF
systemctl daemon-reload
systemctl restart kubelet

# -----------------------------
# 4️⃣ Enable kernel modules and networking
# -----------------------------
echo "Configuring kernel modules and network..."
modprobe br_netfilter
echo 'br_netfilter' > /etc/modules-load.d/br_netfilter.conf
echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/10-ip-forwarding.conf
sysctl -p /etc/sysctl.d/10-ip-forwarding.conf

# -----------------------------
# 5️⃣ Initialize Kubernetes master
# -----------------------------
echo "Initializing Kubernetes master..."
kubeadm init --pod-network-cidr=192.168.0.0/16 --cri-socket unix:///run/containerd/containerd.sock

# -----------------------------
# 6️⃣ Configure kubectl
# -----------------------------
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# -----------------------------
# 7️⃣ Install Calico CNI
# -----------------------------
echo "Installing Calico networking..."
kubectl apply -f https://docs.projectcalico.org/v3.20/manifests/calico.yaml
echo "Waiting 20s for networking..."
sleep 20
kubectl get pods -n kube-system

# -----------------------------
# 8️⃣ Remove master taint for single-node scheduling
# -----------------------------
kubectl taint node $(hostname) node-role.kubernetes.io/master:NoSchedule- || true

# -----------------------------
# 9️⃣ Tag & push free5GC images to private registry
# -----------------------------
echo "Tagging and pushing free5GC images to oss.registry..."
IMAGES=(
  webui n3iwf udr udm smf pcf nssf ausf amf nrf upf-1 upf-2 upf-b
)

for img in "${IMAGES[@]}"; do
  echo "Processing $img..."
  docker tag free5gc-compose-k8s_free5gc-$img oss.registry/free5gc/$img:latest
  docker push oss.registry/free5gc/$img:latest
done

# Base images
docker tag free5gc/base oss.registry/free5gc:base
docker push oss.registry/free5gc:base

docker tag mongo oss.registry/mongo:latest
docker push oss.registry/mongo:latest

echo "--- Registry catalog ---"
curl oss.registry/v2/_catalog

# -----------------------------
# 10️⃣ Deploy free5GC Kubernetes YAML manifests
# -----------------------------
echo "Creating free5GC namespace..."
kubectl create namespace free5gc || true

echo "Applying free5GC NFs..."
NF_YAMLS=(
  mongodb amf smf upf udm udr nrf pcf nssf ausf webui n3iwf
)

for nf in "${NF_YAMLS[@]}"; do
  kubectl apply -f "https://raw.githubusercontent.com/your-repo/free5gc-k8s/main/$nf.yaml" -n free5gc
done

echo "Waiting 30s for NFs to start..."
sleep 30
kubectl get pods -n free5gc

echo "✅ free5GC Kubernetes deployment completed!"
