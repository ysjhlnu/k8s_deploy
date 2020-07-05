#!/bin/bash

cd /opt/tools
if [ ! -f "kube-flannel.yml" ];then
	wget http://172.16.0.6:81/k8s/recommended.yml
fi

sed -i 's/k8s.gcr.io/registry.cn-hangzhou.aliyuncs.com\/google_containers/g' recommended.yml 

kubectl apply -f recommended.yml

kubectl get pods,svc -n kubernetes-dashboard

kubectl create serviceaccount dashboard-admin -n kube-system
kubectl create clusterrolebinding dashboard-admin --clusterrole=cluster-admin --serviceaccount=kube-system:dashboard-admin
kubectl describe secrets -n kube-system $(kubectl -n kube-system get secret | awk '/dashboard-admin/{print $1}')


# 部署CoreDNS
yum install -y git
mkdir /opt/coredns && cd /opt/coredns
git clone https://github.com/coredns/deployment.git
cd deployment/kubernetes


# 默认情况下 CLUSTER_DNS_IP 是自动获取kube-dns的集群ip的，但是由于没有部署kube-dns所以只能手动指定一个集群ip。

 sed -i 's/^CLUSTER_DNS_IP=.*/CLUSTER_DNS_IP=10.0.0.2/' deploy.sh
 

 # 查看执行效果，并未开始部署
./deploy.sh

# 执行部署
./deploy.sh | kubectl apply -f -

# 查看 Coredns
kubectl get svc,pods -n kube-system| grep coredns

# 测试
kubectl run -it --rm dns-test --image=busybox:1.28.4 sh