# LabAFX

Scripts to use Trident with the AFX Lab on Demand

Lab to reserve: https://labondemand.netapp.com/lab/gsafx. 

Once in the lab, you can connect with a terminal to one of the rhel nodes.  

As 'git' is not present, you first need to install it before cloning the repo and launching the setup.  
Copy and paste the following lines:  
```bash
dnf install -y git
git clone https://github.com/YvosOnTheHub/LabAFX.git
cd LabAFX
./setup.sh
```

This script will perform the following tasks:  
- Install KinD (Kubernetes in Docker). 
- Install Helm and Kubectl
- Create a KinD cluster
- Install a snapshot controller
- Install and configure Trident 25.10
- Create a storage class and a volume snapshot class

You will also find in this folder:  
- _busybox.yaml_: creates a Busybox pod with a NFS PVC
- *busybox_pvc_snapshot.yaml*: creates a CSI Snapshot of the PVC
