#!/bin/bash

resource_url=http://172.16.0.6:81/k8s/


ssh_key(){
	yum install -y epel-release sshpass
	ssh-keygen -f ~/.ssh/id_rsa -P '' -q
	sshpass -ptansi201407@ ssh-copy-id -f -i ~/.ssh/id_rsa.pub "-o StrictHostKeyChecking=no" 172.16.1.21
	sshpass -ptansi201407@ ssh-copy-id -f -i ~/.ssh/id_rsa.pub "-o StrictHostKeyChecking=no" 172.16.1.22
}

update_kernel(){
rpm -qa | grep nfs-utils &> /dev/null && echo -e "\033[32;32m 已完成依赖环境安装，退出依赖环境安装步骤 \033[0m \n" && return
yum install -y nfs-utils curl yum-utils device-mapper-persistent-data lvm2 net-tools conntrack-tools wget vim  ntpdate libseccomp libtool-ltdl telnet
echo -e "\033[32;32m 升级Centos7系统内核到5版本，解决Docker-ce版本兼容问题\033[0m \n"
rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org && \
rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm && \
yum --disablerepo=\* --enablerepo=elrepo-kernel repolist && \
yum --disablerepo=\* --enablerepo=elrepo-kernel install -y kernel-ml.x86_64 && \
yum remove -y kernel-tools-libs.x86_64 kernel-tools.x86_64 && \
yum --disablerepo=\* --enablerepo=elrepo-kernel install -y kernel-ml-tools.x86_64 && \
grub2-set-default 0
modprobe br_netfilter
}

init(){
mkdir -p /opt/tools
mkdir /opt/etcd/
systemctl stop firewalld
systemctl disable firewalld

# 关闭selinux
sed -i 's/enforcing/disabled/' /etc/selinux/config  # 永久
setenforce 0  # 临时

# 关闭swap
swapoff -a  # 临时
sed -ri 's/.*swap.*/#&/' /etc/fstab    # 永久



# 将桥接的IPv4流量传递到iptables的链
cat <<-EOF >> /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
net.ipv4.tcp_tw_recycle=0
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.forwarding = 1
net.ipv6.conf.all.forwarding = 1
vm.swappiness=0
vm.overcommit_memory=1
vm.panic_on_oom=0
fs.inotify.max_user_watches=89100
fs.file-max=52706963
fs.nr_open=52706963
EOF

sysctl --system  # 生效


# 在master添加hosts
cat >> /etc/hosts << EOF
172.16.1.20 k8s-master
172.16.1.21 k8s-node1
172.16.1.22 k8s-node1
EOF


sed -i '/#UseDNS*/aUseDNS no' /etc/ssh/sshd_config
systemctl restart sshd.service


yum install ntpdate -y
ntpdate time.windows.com
timedatectl set-timezone Asia/Shanghai



#ssh_key
}


cert(){
	mkdir /opt/tools 
	cd /opt/tools
	wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
	wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
	wget https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64

	chmod +x cfssl_linux-amd64 cfssljson_linux-amd64 cfssl-certinfo_linux-amd64
	mv cfssl_linux-amd64 /usr/local/bin/cfssl
	mv cfssljson_linux-amd64 /usr/local/bin/cfssljson
	mv cfssl-certinfo_linux-amd64 /usr/bin/cfssl-certinfo

	mkdir -p ~/TLS/{etcd,k8s}

	cd ~/TLS/etcd

	# 自签CA
cat > ca-config.json << EOF
{
  "signing": {
	"default": {
	  "expiry": "87600h"
	},
	"profiles": {
	  "www": {
		 "expiry": "87600h",
		 "usages": [
			"signing",
			"key encipherment",
			"server auth",
			"client auth"
		]
	  }
	}
  }
}
EOF

cat > ca-csr.json << EOF
{
    "CN": "etcd CA",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "Beijing",
            "ST": "Beijing"
        }
    ]
}
EOF


	# 生成证书
	cfssl gencert -initca ca-csr.json | cfssljson -bare ca -

	# 创建证书请求文件
cat > server-csr.json << EOF
{
    "CN": "etcd",
    "hosts": [
    "172.16.1.20",
    "172.16.1.21",
    "172.16.1.22"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "BeiJing",
            "ST": "BeiJing"
        }
    ]
}
EOF


# 生成证书
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=www server-csr.json | cfssljson -bare server

}


etcd(){
cd /opt/tools/
wget ${resource_url}etcd-v3.4.9-linux-amd64.tar.gz

# 创建工作目录并解压二进制包
mkdir /opt/etcd/{bin,cfg,ssl} -p
tar zxvf etcd-v3.4.9-linux-amd64.tar.gz
mv etcd-v3.4.9-linux-amd64/{etcd,etcdctl} /opt/etcd/bin/

# 创建etcd配置文件
cat > /opt/etcd/cfg/etcd.conf << EOF
#[Member]
ETCD_NAME="etcd-1"
ETCD_DATA_DIR="/var/lib/etcd/default.etcd"
ETCD_LISTEN_PEER_URLS="https://172.16.1.20:2380"
ETCD_LISTEN_CLIENT_URLS="https://172.16.1.20:2379"
#[Clustering]
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://172.16.1.20:2380"
ETCD_ADVERTISE_CLIENT_URLS="https://172.16.1.20:2379"
ETCD_INITIAL_CLUSTER="etcd-1=https://172.16.1.20:2380,etcd-2=https://172.16.1.21:2380,etcd-3=https://172.16.1.22:2380"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster"
ETCD_INITIAL_CLUSTER_STATE="new"


#[Security]
ETCD_CERT_FILE="/opt/etcd/ssl/server.pem"
ETCD_KEY_FILE="/opt/etcd/ssl/server-key.pem"
ETCD_TRUSTED_CA_FILE="/opt/etcd/ssl/ca.pem"
ETCD_CLIENT_CERT_AUTH="true"
ETCD_PEER_CERT_FILE="/opt/etcd/ssl/server.pem"
ETCD_PEER_KEY_FILE="/opt/etcd/ssl/server-key.pem"
ETCD_PEER_TRUSTED_CA_FILE="/opt/etcd/ssl/ca.pem"
ETCD_PEER_CLIENT_CERT_AUTH="true"
EOF

# systemd管理etcd
cat > /usr/lib/systemd/system/etcd.service << EOF
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target
[Service]
Type=notify
EnvironmentFile=/opt/etcd/cfg/etcd.conf
ExecStart=/opt/etcd/bin/etcd \
--cert-file=/opt/etcd/ssl/server.pem \
--key-file=/opt/etcd/ssl/server-key.pem \
--peer-cert-file=/opt/etcd/ssl/server.pem \
--peer-key-file=/opt/etcd/ssl/server-key.pem \
--trusted-ca-file=/opt/etcd/ssl/ca.pem \
--peer-trusted-ca-file=/opt/etcd/ssl/ca.pem \
--logger=zap
Restart=on-failure
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOF

# 拷贝刚才生成的证书
cp ~/TLS/etcd/ca*pem ~/TLS/etcd/server*pem /opt/etcd/ssl/

# 启动并设置开机启动
scp -r /opt/etcd/ root@172.16.1.21:/opt/
scp /usr/lib/systemd/system/etcd.service root@172.16.1.21:/usr/lib/systemd/system/
scp -r /opt/etcd/ root@172.16.1.22:/opt/
scp /usr/lib/systemd/system/etcd.service root@172.16.1.22:/usr/lib/systemd/system/


systemctl daemon-reload
systemctl start etcd
systemctl enable etcd


ETCDCTL_API=3 /opt/etcd/bin/etcdctl --cacert=/opt/etcd/ssl/ca.pem --cert=/opt/etcd/ssl/server.pem --key=/opt/etcd/ssl/server-key.pem --endpoints="https://172.16.1.20:2379,https://172.16.1.21:2379,https://172.16.1.22:2379" endpoint health

}


main(){
	init
	cert
	etcd
}