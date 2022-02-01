# AIR Lab build instructions

1. Create a custom topology from `netris-ai.dot` and `netris-ai.svg` files.

2. SSH into `oob-mgmt-server` and create a 6to4 NAT process to connect port 8080 on the `oob-mgmt-server` to a socket on `netq-ts`:

```
sudo -i
apt install socat -y

SRC=8080
DST=192.168.200.250:32178

cat << EOF > /etc/systemd/system/socat.service
[Unit]
Description=6to4 NAT
After=network.target ssh.service
[Service]
Type=simple
ExecStart=/usr/bin/socat TCP6-LISTEN:$SRC,fork TCP4:$DST
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start socat
systemctl enable socat
```

Run the ztp.yaml playbook and copy `./hosts` to `~/.ssh/config`

```
cd ./ztp
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory.ini ztp.yaml
```

3. Connect to netq-ts and install netris controller and operator

Install `arkade` Kubernetes marketplace:

```
curl -sLS https://get.arkade.dev | sudo sh
echo "export PATH=$PATH:$HOME/.arkade/bin/" >> ~/.bashrc
echo "alias k=kubectl" >> ~/.bashrc
source ~/.bashrc
```

Install `helm` and add the required repositories:

```
arkade get kubens
arkade get helm 
helm repo add netrisai https://netrisai.github.io/charts
helm repo add kube-vip https://kube-vip.io/helm-charts
helm repo update
```

Install `kube-vip` to deal with local net-ts LB needs:

```
kubens kube-system
kubectl create configmap kubevip --from-literal range-global=192.168.200.128-192.168.200.150
helm install lb-ctrl kube-vip/kube-vip-cloud-provider
helm install --set env.vip_interface=eth0 vip kube-vip/kube-vip
```

Create a new `netris` namespace:
```
kubectl create ns netris 
kubens netris
```

Configure persistent volumes for stateful applications:

```
cat << EOF | kubectl apply -f -
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: local-storage
  annotations:
    "storageclass.kubernetes.io/is-default-class": "true"
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
EOF


mkdir -p /root/0
mkdir -p /root/1
mkdir -p /root/2
mkdir -p /root/3

for path in 0 1 2 3; do
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-pv-$path
spec:
  capacity:
    storage: 11Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /root/$path
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - netq-ts
EOF
done

```

Install netris controller and expose it as a nodePort service:

```
helm install netris-controller netrisai/netris-controller --namespace netris --set app.ingress.enabled=false --version ^1.0.5 

cat << EOF | kubectl apply -f - 
apiVersion: v1
kind: Service
metadata:
  name: netris-nodeport
spec:
  ports:
  - port: 80
    protocol: TCP
    nodePort: 32178
    targetPort: 80
  selector:
    app.kubernetes.io/instance: netris-controller-app
    app.kubernetes.io/name: netris-controller
  type: NodePort
EOF
```

Install netris operator

```
kubectl -n netris create secret generic netris-creds \
  --from-literal=host="http://netris-controller-app" \
  --from-literal=login="netris" --from-literal=password="newNet0ps" 

helm install netris-operator netrisai/netris-operator \
--namespace netris --version ^0.5.0
```

Check the values of EXTERNAL-IP assigned to netris controller, it will be used for agents to join:

```
root@netq-ts:~# kubectl get svc netris-controller-haproxy
NAME                        TYPE           CLUSTER-IP       EXTERNAL-IP       PORT(S)
        AGE
netris-controller-haproxy   LoadBalancer   10.108.186.157   192.168.200.148   50051:32305/TCP,3033:32314/TCP,3034:31263/TCP,2003:32721/TCP   23s
```


4. Netris bootstrapping

In AIR create another service for port 8080 of oob-mgmt-server. This will get proxied to the netris UI.

Connect to netris UI at `worker06.air.nvidia.com:25345` as netris/newNet0ps. From the UI create two IP allocations and subnets:

 * `192.168.200.0/24` for for `management` purpose
 * `192.0.2.0/24` for `loopback` purpose
 * `198.51.100.0/25` for `nat` purpose
 * `198.51.100.128/25` for `load-balancer` purpose

For every lab device create a device in the inventory with a unique management and Loopback IPs.


Alternative solution is to install [Terraform](https://releases.hashicorp.com/terraform/0.13.7/terraform_0.13.7_linux_amd64.zip)
and netris TF plugin https://github.com/netrisai/terraform-provider-netris

Clone the TF plugin repo and run

```
make OS_ARCH=linux_amd64 install
```

Then, from the `air/bootstrap` directory run:

```
cd ./bootstrap
terraform init
NETRIS_ADDRESS=http://worker10.air.nvidia.com:27520 terraform apply
```


4. Netris agent installation (repeat on each Cumulus devices)



Override a few files for netris installer to work properly:

```
echo "192.168.200.148 worker10.air.nvidia.com" >> /etc/hosts
```

Run the `Install agent` command from the UI (example for leaf0):

```
curl -fksSL https://get.netris.ai | sh -s -- --lo 192.0.2.4 --controller worker01.air.nvidia.com --hostname leaf0 --auth vx9x6gx6t4iwe7v4v25b1b1kge45rsdcfeya67gqdnxzzqgztlmwkw50rgt2s3dn
```

Update the systemd Exec string to run the agent in the `mgmt` vrf:
```
sed -i 's/\/opt\/netris\/bin\/telescope/\/sbin\/ip vrf exec mgmt \/opt\/netris\/bin\/telescope/' /etc/systemd/system/netris-sw.service
```

Make sure timesyncd runs from mgmt vrf and does not have a dependency cycle:

```

systemctl disable ntp

echo systemd-timesyncd >> /etc/vrf/systemd.conf

systemctl disable systemd-timesyncd
systemctl daemon-reload
systemctl enable systemd-timesyncd@mgmt.service

sed -i '/Before=/d' /lib/systemd/system/systemd-timesyncd.service
sed -i '/After=/d' /lib/systemd/system/systemd-timesyncd.service
systemctl daemon-reload


curl -sLO https://github.com/mikefarah/yq/releases/download/v4.17.2/yq_linux_amd64

chmod +x yq_linux_amd64

./yq_linux_amd64 e -i '.services[7].bthreshold = 1' -P -ojson /opt/netris/etc/sys_service_cumulus.conf

rm ./yq_linux_amd64

```

Mask the `collect_vlan_stats` error

```
sed -i 's/\/bin\/sh/\/bin\/true/' /opt/netris/etc/plugins.conf.cumulus
systemctl restart netris-sw.service
```

Restart the switch to take effect:

```
history -c
reboot
```


4. Netris agent installation (border devices)

Little fix for netris installer:

```
echo "192.168.200.148 worker10.air.nvidia.com" >> /etc/hosts
```

Copy the `Install agent` command from the UI (example for border1):

```
curl -fsSL https://get.netris.ai | sh -s -- --lo 192.0.2.14 --controller worker01.air.nvidia.com --hostname border1 --auth vx9x6gx6t4iwe7v4v25b1b1kge45rsdcfeya67gqdnxzzqgztlmwkw50rgt2s3dn --node-prio 2
```

Restart the server:

```
sed -i 's/#NTP=/NTP=ntp.ubuntu.com/' /etc/systemd/timesyncd.conf
history -c
reboot
```

5. Building the EVPN fabric

(This is already built if you ran terraform)

From the `Topology` screen create link following the physical topology.


![](https://gitlab.com/nvidia-networking/systems-engineering/poc-support/netris-on-air/-/raw/main/air/netris-fabric.png)



6. Configure Internet Node

```
curl -s https://deb.frrouting.org/frr/keys.asc | sudo apt-key add -
FRRVER="frr-stable"
echo deb https://deb.frrouting.org/frr $(lsb_release -s -c) $FRRVER | sudo tee -a /etc/apt/sources.list.d/frr.list
sudo apt update && sudo apt install frr frr-pythontools

sed -i 's/bgpd=no/bgpd=yes/' /etc/frr/daemons

cat << EOF > /etc/frr/frr.conf
frr version 8.1
frr defaults traditional
hostname Internet
log syslog informational
no ip forwarding
no ipv6 forwarding
service integrated-vtysh-config
!
interface lo
 ip address 1.1.1.1/32
 ip address 8.8.8.8/32
exit
!
router bgp 64512
 neighbor 100.64.0.2 remote-as 65000
 neighbor 100.64.0.6 remote-as 65000
 !
 address-family ipv4 unicast
  redistribute connected
  neighbor 100.64.0.2 default-originate
  neighbor 100.64.0.2 route-map RMAP-IN in
  neighbor 100.64.0.2 route-map RMAP-OUT out
  neighbor 100.64.0.6 default-originate
  neighbor 100.64.0.6 route-map RMAP-IN in
  neighbor 100.64.0.6 route-map RMAP-OUT out
 exit-address-family
exit
!
ip prefix-list INTERNET seq 5 permit 1.1.1.1/32
ip prefix-list INTERNET seq 10 permit 8.8.8.8/32
ip prefix-list NETRIS-PUBLIC seq 5 permit 198.51.100.0/24 le 32
!
route-map RMAP-OUT permit 10
 match ip address prefix-list INTERNET
exit
!
route-map RMAP-IN permit 10
 match ip address prefix-list NETRIS-PUBLIC
exit
!
EOF

systemctl enable frr
systemctl restart frr
```

Configure interface ips
```
cat << EOF > /etc/netplan/eths.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eth1:
      addresses: [100.64.0.1/30]
    eth2:
      addresses: [100.64.0.5/30]
      
EOF

netplan apply
```

Enable ifconfig service:

```
sudo -i
wget https://github.com/missdeer/ifconfig/releases/download/1.0/ifconfig-linux-amd64.tar.gz
tar zxvf ifconfig-linux-amd64.tar.gz

cat << EOF > /etc/systemd/system/ifconfig.service
[Unit]
Description=ifconfig
After=network.target
[Service]
Type=simple
WorkingDirectory=/root
ExecStart=/root/ifconfig
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start ifconfig
systemctl enable ifconfig
```

7. Server/Host configuration

Apply the following changing the IP/gateway according to

* host-A 10.0.1.11/24 via 10.0.1.1
* host-B 10.0.2.11/24 via 10.0.2.1
* host-C 10.0.1.22/24 via 10.0.1.1
* host-D 10.0.2.22/24 via 10.0.2.1

```
cat << EOF > /etc/netplan/eths.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eth1: {}
    eth2: {}
  bonds:
    bond0:
      dhcp4: no
      interfaces:
        - eth1
        - eth2
      parameters: 
        mode: active-backup
      addresses: [10.0.2.22/24]
      routes: 
        - to: 0.0.0.0/0
          via: 10.0.2.1
EOF

netplan apply
history -c
```



8. Create E-BGP peerings with Internet


For each connection to the internet create the following E-BGP object:

| Name | Router | Port | Neighbor AS | Local IP | Remote IP |
| --- | --- | --- | --- | --- | --- |
| Internet-1 | border0 | swp2 | 64512 | 100.64.0.2 | 100.64.0.1 | 
| Internet-2 | border1 | swp2 | 64512 | 100.64.0.6 | 100.64.0.5 | 

This could be automatically done with Terraform:

```
cd ./bgp
terraform init
NETRIS_ADDRESS=http://worker10.air.nvidia.com:27520 terraform apply
```



9. Expire the password on oob-mgmt-server

```
passwd --expire ubuntu
```

10. Clone the Sim

Shut off the current sim and paste this in your browser replacing  with the current sim ID

https://air.nvidia.com/api/v1/simulation/autoprovision/?simulation_id=<id>


---

Unused


Add netris repos and install the agent:
```
wget -qO - http://repo.netris.ai/repo/public.key | sudo apt-key add - 

echo "deb http://repo.netris.ai/repo/ jessie main" | sudo tee /etc/apt/sources.list.d/netris.list 

apt update 

DEBIAN_FRONTEND=noninteractive sudo apt -o Dpkg::Options::="--force-confnew" install netris-sw=3.0.3.006 -y 

```

Connect and authenticate with the controller:
```
/opt/netris/bin/netris-setup \
--auth ZWUwMWU2MTA0M2JkMGUzNzRlNTgwNGFi \
--controller 192.168.200.134 \
--lo 192.0.2.2 \
--host
```

```bash
cat << EOF > patch.patch
--- original.sh 2022-01-24 14:29:07.396000000 +0000
+++ test.sh     2022-01-24 14:54:18.349000000 +0000
@@ -455,11 +455,29 @@
     exit 0
 fi

+VX=$(cat <<-END
+
+############################################################################
+#                                                                          #
+# Welcome to NVIDIA Air!                                                   #
+#                                                                          #
+# Please login with the following default credentials:                     #
+#                                                                          #
+# Username: cumulus                                                        #
+# Password: CumulusLinux!                                                  #
+#                                                                          #
+# Note: You will be asked to set a new password after your first login     #
+#                                                                          #
+############################################################################
+END
+)
+
 DIST=""
 case $(cat /etc/issue) in
     "Ubuntu 18.04"*) DIST="ubuntu-18-04";;
     "Debian GNU/Linux 8"*) DIST="debian-8";;
     "Debian GNU/Linux 10"*) DIST="debian-10";;
+    $VX*) DIST="debian-8";;
     *)
         print_unsupported_platform
         exit 1
EOF
```

```bash
curl -fksSL https://get.netris.ai --output install.sh
patch install.sh < patch.patch
chmod +x install.sh
./install.sh --lo 192.0.2.4 --controller 192.168.200.144 --hostname leaf0 --auth oi6nf2iua28zvswdyctxdu639lt5ny1xcgj3u53x72vekecrfmittxweg08g5kzz
reboot
```


SG master/slave is only used for SNAT, can be checked with 


```
cat /run/keepalived.state

```


Reset PBR:

```
ip route del 169.254.254.2 dev eth1.4094 table 100
ip route del default via 169.254.254.254 table 100
ip route add 169.254.254.2 dev eth1.4094 table 100
ip route add default via 169.254.254.254 table 100
```

