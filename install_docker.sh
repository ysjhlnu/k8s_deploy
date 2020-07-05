#!/bin/bash


cd /opt

if [ ! -f "docker-19.03.9.tgz"  ];then
	wget https://download.docker.com/linux/static/stable/x86_64/docker-19.03.9.tgz
fi

tar zxvf docker-19.03.9.tgz
mv docker/* /usr/bin


cat > /usr/lib/systemd/system/docker.service << EOF
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service
Wants=network-online.target
[Service]
Type=notify
ExecStart=/usr/bin/dockerd
ExecReload=/bin/kill -s HUP \$MAINPID
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TimeoutStartSec=0
Delegate=yes
KillMode=process
Restart=on-failure
StartLimitBurst=3
StartLimitInterval=60s
[Install]
WantedBy=multi-user.target
EOF

# 创建配置文件
mkdir /etc/docker
cat > /etc/docker/daemon.json << EOF
{
  "registry-mirrors": ["https://b9pmyelo.mirror.aliyuncs.com"]
}
EOF


systemctl daemon-reload
systemctl start docker
systemctl enable docker
