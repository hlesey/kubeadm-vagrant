#!/usr/bin/env bash
# Setup and bootstrap k8s control-plane 

source /src/scripts/vars.txt

# init the control plane components
kubeadm init --apiserver-advertise-address=$CONTROL_PLANE_IP --pod-network-cidr=10.244.0.0/16 > /src/output/.kubeadmin_init

# tba with kubeadm configfile:
# cat "/src/manifests/kubeadm/cluster.yaml" | sed -e "s'{{CONTROL_PLANE_IP}}'${CONTROL_PLANE_IP}'g"  | kubeadm init --config -

export KUBECONFIG=/etc/kubernetes/admin.conf

# deploy overlay network
if [[ "$NETWORK_PLUGIN" == "cilium" ]]; then
    source /src/scripts/cilium.sh
else
    kubectl apply -f /src/manifests/network/${NETWORK_PLUGIN}
fi

# workaround for 140615704306112:error:2406F079:random number generator:RAND_load_file:Cannot open file:../crypto/rand/randfile.c:88:Filename=/root/.rnd
touch /root/.rnd && chmod 600 /root/.rnd
touch /home/vagrant/.rnd && chmod 600 /home/vagrant/.rnd && chown vagrant:vagrant /home/vagrant/.rnd

# deploy dashboard
source /src/scripts/dashboard.sh

# deploy ingress controller
kubectl apply -f  /src/manifests/ingress/${INGRESS_CONTROLLER}

# deploy metrics-server
kubectl apply -f /src/manifests/metrics-server/

# scale coredns to 1 replica
kubectl -n kube-system scale deployment coredns --replicas=1

# get admin token
kubectl describe secret $(kubectl get secrets | grep cluster | cut -d ' ' -f1) | grep token:  | tr -s ' ' | cut -d ' ' -f2 > /src/output/cluster-admin-token
cp /etc/kubernetes/admin.conf /src/output/kubeconfig.yaml

# configure vagrant and root user with kubeconfig
echo "export KUBECONFIG=/src/output/kubeconfig.yaml"  >> /root/.bashrc
echo "export KUBECONFIG=/src/output/kubeconfig.yaml"  >> /home/vagrant/.bashrc

# Enabling shell autocompletion -> FIXME: add them in the image template
echo "source <(kubectl completion bash)" >> /root/.bashrc
echo ". /usr/share/bash-completion/bash_completion" >> /root/.bashrc
echo  "alias kns='kubectl config set-context \$(kubectl config current-context) --namespace'" >>  /root/.bashrc

# copy root user bash config to vagrant user
cat /root/.bashrc >> /home/vagrant/.bashrc

# finish
ln -s /src/output/cluster-admin-token /root/cluster-admin-token
echo "-------------------------------------------------------------"
echo "Use this token to login to the kubernetes dashboard:"
cat /root/cluster-admin-token
echo "Enjoy."