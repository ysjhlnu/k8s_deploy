#!/bin/bash


mkdir -p /opt/cni/bin

cd /opt
if [ ! -f "cni-plugins-linux-amd64-v0.8.6.tgz" ];then
	wget http://172.16.0.6:81/k8s/cni-plugins-linux-amd64-v0.8.6.tgz
fi

if [ ! -f "kube-flannel.yml" ];then
	wget http://172.16.0.6:81/k8s/kube-flannel.yml
fi

sed -i -r "s#quay.io/coreos/flannel:.*-amd64#lizhenliang/flannel:v0.12.0-amd64#g" kube-flannel.yml

tar zxvf cni-plugins-linux-amd64-v0.8.6.tgz -C /opt/cni/bin


kubectl apply -f kube-flannel.yml

kubectl get pods -n kube-system


kubectl get node


cat > apiserver-to-kubelet-rbac.yaml << EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups:
      - ""
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
      - pods/log
    verbs:
      - "*"
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
  namespace: ""
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: kubernetes
EOF

kubectl apply -f apiserver-to-kubelet-rbac.yaml


scp -r /opt/kubernetes root@172.16.1.21:/opt/

scp -r /usr/lib/systemd/system/{kubelet,kube-proxy}.service root@172.16.1.21:/usr/lib/systemd/system

scp -r /opt/cni/ root@172.16.1.21:/opt/

scp /opt/kubernetes/ssl/ca.pem root@172.16.1.21:/opt/kubernetes/ssl


scp -r /opt/kubernetes root@172.16.1.22:/opt/

scp -r /usr/lib/systemd/system/{kubelet,kube-proxy}.service root@172.16.1.22:/usr/lib/systemd/system

scp -r /opt/cni/ root@172.16.1.22:/opt/

scp /opt/kubernetes/ssl/ca.pem root@172.16.1.22:/opt/kubernetes/ssl

ssh root@172.16.1.21 "rm /opt/kubernetes/cfg/kubelet.kubeconfig" 
ssh root@172.16.1.21 "rm -f /opt/kubernetes/ssl/kubelet*"

ssh root@172.16.1.22 "rm /opt/kubernetes/cfg/kubelet.kubeconfig" 
ssh root@172.16.1.22 "rm -f /opt/kubernetes/ssl/kubelet*"


#vi /opt/kubernetes/cfg/kubelet.conf
#--hostname-override=k8s-node1

ssh root@172.16.1.21 "sed -i 's#hostnameOverride: k8s-master#hostnameOverride: k8s-node1#' /opt/kubernetes/cfg/kube-proxy-config.yml"
ssh root@172.16.1.22 "sed -i 's#hostnameOverride: k8s-master#hostnameOverride: k8s-node2#' /opt/kubernetes/cfg/kube-proxy-config.yml"


systemctl daemon-reload
systemctl start kubelet
systemctl enable kubelet
systemctl start kube-proxy
systemctl enable kube-proxy
