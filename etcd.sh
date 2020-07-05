#!/bin/bash

ETCD_NAME=${1:-"etcd01"}
ETCD_IP=${2:-"127.0.0.1"}
ETCD_CLUSTER=${3:-"etcd01=https://127.0.0.1:2379"}

cat >/opt/etcd/cfg/etcd.yml<<EOF
name: ${ETCD_NAME}
data-dir: /var/lib/etcd/default.etcd
listen-peer-urls: https://${ETCD_IP}:2380
listen-client-urls: https://${ETCD_IP}:2379,https://127.0.0.1:2379

advertise-client-urls: https://${ETCD_IP}:2379
initial-advertise-peer-urls: https://${ETCD_IP}:2380
initial-cluster: ${ETCD_CLUSTER}
initial-cluster-token: etcd-cluster
initial-cluster-state: new

client-transport-security:
  cert-file: /opt/etcd/ssl/server.pem
  key-file: /opt/etcd/ssl/server-key.pem
  client-cert-auth: false
  trusted-ca-file: /opt/etcd/ssl/ca.pem
  auto-tls: false

peer-transport-security:
  cert-file: /opt/etcd/ssl/server.pem
  key-file: /opt/etcd/ssl/server-key.pem
  client-cert-auth: false
  trusted-ca-file: /opt/etcd/ssl/ca.pem
  auto-tls: false

debug: false
logger: zap
log-outputs: [stderr]
EOF

cat >/usr/lib/systemd/system/etcd.service<<EOF
[Unit]
Description=Etcd Server
Documentation=https://github.com/etcd-io/etcd
Conflicts=etcd.service
After=network.target
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
LimitNOFILE=65536
Restart=on-failure
RestartSec=5s
TimeoutStartSec=0
ExecStart=/opt/etcd/bin/etcd --config-file=/opt/etcd/cfg/etcd.yml

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable etcd
systemctl restart etcd

#./etcd.sh etcd-1 172.16.1.20 etcd-1=https://172.16.1.20:2380,etcd-2=https://172.16.1.21:2380,etcd-3=https://172.16.1.22:2380