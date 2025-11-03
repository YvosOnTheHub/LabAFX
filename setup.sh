echo "###################################################################################"
echo "# Setting up LabNetApp AFX Lab Environment"
echo 
echo "# AFX Requirements:"
echo "# Make sure you have gone though the lab guide setup (chapter 2.1.1 - Steps 1 to 20)"
echo
echo "# This script must be run as root user on the host rhel1 (or rhel2-3-4)"
echo "####################################################################################"

read -rsp $'Press any key to proceed with the setup\n' -n1 key

echo
echo "#######################################################################################"
echo "# Install KinD - Kubernetes in Docker"
echo "#######################################################################################"
[ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.29.0/kind-linux-amd64
chmod +x ./kind
mv ./kind /usr/local/bin/kind

echo
echo "#######################################################################################"
echo "# Install Helm"
echo "#######################################################################################"
wget https://get.helm.sh/helm-v3.15.3-linux-amd64.tar.gz
tar -xvf helm-v3.15.3-linux-amd64.tar.gz
cp -f linux-amd64/helm /usr/local/bin/

echo
echo "#######################################################################################"
echo "# Deal with SELINUX and FIREWALL"
echo "#######################################################################################"
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
systemctl stop firewalld && sudo systemctl disable firewalld

echo
echo "#######################################################################################"
echo "# Install Kubectl"
echo "#######################################################################################"

cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.34/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.34/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

dnf install -y kubectl --disableexcludes=kubernetes

echo
echo "#######################################################################################"
echo "# Adding shortcuts to bash"
echo "#######################################################################################"
cat <<EOT >> ~/.bashrc
alias kc='kubectl create'
alias kg='kubectl get'
alias kdel='kubectl delete'
alias kx='kubectl exec -it'
alias kdesc='kubectl describe'
alias kedit='kubectl edit'
alias trident='tridentctl -n trident'
EOT
source ~/.bashrc

echo
echo "#######################################################################################"
echo "# Create a KinD cluster"
echo "#######################################################################################"
kind create cluster --name afx-k8s

echo "###"
echo "### Check"
echo "###"
kubectl get nodes
sleep 1

echo
echo "#######################################################################################"
echo "# Install Trident"
echo "#######################################################################################"
cd
mkdir -p trident && cd trident

cat <<EOT >> trident_values.yaml
operatorImage: quay.io/yvosonthehub/netapp/trident-operator:25.10.0
tridentImage: quay.io/yvosonthehub/netapp/trident:25.10.0
tridentAutosupportImage: quay.io/yvosonthehub/netapp/trident-autosupport:25.10.0
EOT

helm repo add netapp-trident https://netapp.github.io/trident-helm-chart
helm install trident netapp-trident/trident-operator --version 100.2510.0 -n trident --create-namespace -f trident_values.yaml

sleep 5
frames="/ | \\ -"
while [ $(kubectl get tver -A | grep trident | awk '{print $3}') != '25.10.0' ];do
    for frame in $frames; do
        sleep 0.5; printf "\rWaiting for Trident to be ready $frame" 
    done
done
echo
while [ $(kubectl get -n trident pod | grep Running | grep -e '1/1' -e '2/2' -e '6/6' | wc -l) -ne 3 ]; do
    for frame in $frames; do
        sleep 0.5; printf "\rWaiting for Trident to be ready $frame" 
    done
done

echo "###"
echo "### Check"
echo "###"
kubectl get -n trident po
kubectl get tver -A
sleep 1

echo
echo "#######################################################################################"
echo "# Install Tridentctl"
echo "#######################################################################################"
wget https://github.com/NetApp/trident/releases/download/v25.10.0/trident-installer-25.10.0.tar.gz
tar -xf trident-installer-25.10.0.tar.gz
mv trident-installer/tridentctl /usr/local/bin/

echo
echo "#######################################################################################"
echo "# Install Snapshot Controller"
echo "#######################################################################################"
kubectl kustomize https://github.com/kubernetes-csi/external-snapshotter/client/config/crd?ref=v8.2.0 | kubectl apply -f -
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/release-8.2/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/release-8.2/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml

cat << EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: csi-snap-class
  annotations:
    snapshot.storage.kubernetes.io/is-default-class: "true"
driver: csi.trident.netapp.io
deletionPolicy: Delete
EOF

echo
echo "#######################################################################################"
echo "# Configure Trident backend and storage class"
echo "#######################################################################################"
cat << EOF > trident_backend.yaml
apiVersion: v1
kind: Secret
metadata:
  name: cluster-credentials
  namespace: trident
type: Opaque
stringData:
  username: admin
  password: Netapp1!
---
apiVersion: trident.netapp.io/v1
kind: TridentBackendConfig
metadata:
  name: backend-nfs
  namespace: trident
spec:
  version: 1
  backendName: nfs
  storageDriverName: ontap-nas
  managementLIF: 192.168.0.101
  dataLIF: 192.168.0.131
  svm: svm1
  exportPolicy: default
  credentials:
    name: cluster-credentials
EOF
kubectl create -f trident_backend.yaml

cat << EOF > storageclass.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: sc-nfs
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: csi.trident.netapp.io
parameters:
  backendType: "ontap-nas"
allowVolumeExpansion: true
EOF

kubectl create -f storageclass.yaml
kubectl delete sc standard

echo
echo "###"
echo "### Check"
echo "###"
kubectl get tbc -n trident
kubectl get sc

echo
echo
echo "#######################################################################################"
echo "# SETUP COMPLETED!"
echo "#######################################################################################"
