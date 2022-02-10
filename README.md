# EVPN Services Orchestration with Netris

This demo combines NVIDIA Cumulus EVPN fabric together with [Netris](https://www.netris.ai/) private cloud orchestration platform. The goal of this demo are summarized below:

* Using a simple GUI, orchestrate EVPN services across Nvidia Cumulus EVPN fabric.
* Demonstrate how EVPN configuration can be managed declaratively.
* Show how Netris can implement common cloud network services, like NAT and L4 load-balancing.

Here's the high-level diagram of what we'll be trying to achieve:

![](https://gitlab.com/nvidia-networking/systems-engineering/poc-support/netris-on-air/-/raw/main/images/netris.png)


In order to simplify this demonstration, some things have already been pre-configured, for example:
* Netris IPAM is pre-populated with subnets.
* All devices are added to the Netris inventory.
* Hosts and Internet devices are fully pre-configured.
* E-BGP peering with the Internet.

All Netris bootstrapping has been performed using Terraform, all configuration files are saved in the [`./air/bootstrap`](https://gitlab.com/nvidia-networking/systems-engineering/poc-support/netris-on-air/-/tree/main/air/bootstrap) directory.

> **NOTE**: For instructions on how to build the demo, install and configure Netris see the [`./air`]((https://gitlab.com/nvidia-networking/systems-engineering/poc-support/netris-on-air/-/tree/main/air)) directory. 


## Lab Details

The following diagram demonstrates the physical network topology, omitting the out-of-band components.

![](https://gitlab.com/nvidia-networking/systems-engineering/poc-support/netris-on-air/-/raw/main/images/netris-topo.png)

Default logins and software versions:

| Device/Application | sw version | username | password | 
| -- | -- | -- | -- | 
| oob-mgmt-server | Ubuntu 18.04 | ubuntu | nvidia | 
| netq-ts | NetQ 4.0.0 | cumulus | cumulus | 
| leaf0X, spine0X | CL 3.7.15 | cumulus | CumulusLinux! | 
| host-X, border0X, Internet | Ubuntu 18.04 | ubuntu | nvidia | 
| Netris Controller | 3.0.3 | netris | newNet0ps | 

To interact with the lab, you can connect to lab devices via SSH and to Netris UI via HTTP. In order to enable remote access go to the "Advanced" view and

* Click "Enable SSH" to expose the `out-of-band` management server to the Internet.
* Click "Add Service" and add a new service of type "Other" to the `oob-mgmt-server:eth0` port `8080`. 

![](https://gitlab.com/nvidia-networking/systems-engineering/poc-support/netris-on-air/-/raw/main/images/netris-services.png)

The web UI is now available at `http://<External Hostname>:<External Port>`, e.g. http://worker01.air.nvidia.com:27828

> You may see some high load alarms once the lab is up, this is due to initial boot process. They should disappear after a few minutes.

## Walkthrough


### 1. EVPN orchestration

In the first part of this demo we will walk you through how to configure virtual networks ([V-Net](https://www.netris.ai/docs/en/stable/vnet.html)) in Netris, that will get automatically translated into an EVPN instances (EVI) and anycast gateway configurations inside the NVIDIA Cumulus network fabric.

### 1.1 Interactive VNET Operations

V-Net is one of the fundamental concepts in Netris data model and represents a single L2 domain. 

Create a new V-NET by going to `Services->V-NET` and adding a new instance with the following details:

| Name | Owner | Sites | IPv4 Gateway | Ports | 
| -----|-------|-------|--------------|-------|
| vnet-one | Admin | Default | 10.0.1.1/24 | swp3@leaf0, swp3@leaf1, swp3@leaf2, swp3@leaf3 |


![](https://gitlab.com/nvidia-networking/systems-engineering/poc-support/netris-on-air/-/raw/main/images/vnet.png)


Once created, connect to `host-a` and verify connectivity within the new V-Net:

```
ubuntu@host-A:~$ ping -c 2 10.0.1.1
PING 10.0.1.1 (10.0.1.1) 56(84) bytes of data.
64 bytes from 10.0.1.1: icmp_seq=1 ttl=64 time=0.341 ms
64 bytes from 10.0.1.1: icmp_seq=2 ttl=64 time=0.356 ms

--- 10.0.1.1 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1031ms
rtt min/avg/max/mdev = 0.341/0.348/0.356/0.020 ms
ubuntu@host-A:~$ ping -c 2 10.0.1.22
PING 10.0.1.22 (10.0.1.22) 56(84) bytes of data.
64 bytes from 10.0.1.22: icmp_seq=1 ttl=64 time=1.38 ms
64 bytes from 10.0.1.22: icmp_seq=2 ttl=64 time=1.43 ms

--- 10.0.1.22 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1001ms
rtt min/avg/max/mdev = 1.381/1.409/1.438/0.047 ms
ubuntu@host-A:~$ ping -c 2 10.0.2.11
PING 10.0.2.11 (10.0.2.11) 56(84) bytes of data.

--- 10.0.2.11 ping statistics ---
2 packets transmitted, 0 received, 100% packet loss, time 1012ms
```

We're still unable to ping `host-b` or `host-d`, this is what we're going to do next.

### 1.2 Declarative VNET Operations

> Declarative APIs describe the desired state of the system instead of a set of imperative steps, relying on the controller to adjust the current state to match the intent.

Netris supports two declarative interfaces. One of them is Terraform via a [custom Netris provider](https://github.com/netrisai/terraform-provider-netris). We won't focus on Terraform here, however you can see example playbooks in it's [github repository](https://github.com/netrisai/terraform-provider-netris/tree/main/examples) or see Terraform files that were used to build this demo in the [`./air/bootstrap`](https://gitlab.com/nvidia-networking/systems-engineering/poc-support/netris-on-air/-/tree/main/air/bootstrap) directory.



Instead we will demonstrate how to use Kubernetes custom resources to create a second V-Net and establish reachability between all 4 hosts. 

Connect to `netq-ts` and create a new Kubernetes manifest:

```
cumulus@netq-ts:~$ sudo -i
root@netq-ts:~# cat << EOF > vnet.yaml
apiVersion: k8s.netris.ai/v1alpha1
kind: VNet
metadata:
 name: vnet-two
spec:
 ownerTenant: Admin
 guestTenants: []
 sites:
   - name: Default
     gateways:
       - 10.0.2.1/24
     switchPorts:
       - name: swp4@leaf0
       - name: swp4@leaf1
       - name: swp4@leaf2
       - name: swp4@leaf3
EOF
```

This YAML file describes the desired state of a V-Net in a text format, which makes it easy to store in git and apply automatically using GitOps frameworks ([see this](https://gitlab.com/nvidia-networking/systems-engineering/poc-support/kubernetes-on-baremetal-network) for an example of using Flux).

The new V-Net can now be created with a single command:

```
root@netq-ts:~# kubectl apply -f vnet.yaml
vnet.k8s.netris.ai/vnet-two created
```

Behind the scenes, Netris creates another EVPN instance (EVI) and configures anycast gateway on all participating switches. 

Both declarative (TF and K8S) and imperative (REST and web UI) interfaces all manage the same state inside the Netris Controller and EVPN fabric, so the new V-Net is now also visible in the web UI:

![](https://gitlab.com/nvidia-networking/systems-engineering/poc-support/netris-on-air/-/raw/main/images/vnet-all.png)

Reconnect to `host-a` and verify that both `host-b` and `host-d` are now reachable.
```
ubuntu@host-A:~$ ping -c 2 10.0.2.11
PING 10.0.2.11 (10.0.2.11) 56(84) bytes of data.
64 bytes from 10.0.2.11: icmp_seq=1 ttl=63 time=0.445 ms
64 bytes from 10.0.2.11: icmp_seq=2 ttl=63 time=0.544 ms

--- 10.0.2.11 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1012ms
rtt min/avg/max/mdev = 0.445/0.494/0.544/0.054 ms
ubuntu@host-A:~$ ping -c 2 10.0.2.22
PING 10.0.2.22 (10.0.2.22) 56(84) bytes of data.
64 bytes from 10.0.2.22: icmp_seq=1 ttl=62 time=1.39 ms
64 bytes from 10.0.2.22: icmp_seq=2 ttl=62 time=1.32 ms

--- 10.0.2.22 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1001ms
rtt min/avg/max/mdev = 1.320/1.358/1.397/0.053 ms
```

### 2. SoftGate Services

In the second part of this demo we demonstrate some of the capabilities of Netris Softgate, a software routing stack capable of high-speed NAT and L4 load-balancing. In our lab, it's running inside a KVM virtual machine, so you won't see high performance numbers, however, in production it runs on a general purpose x86 server with SmartNIC, such as Nvidia Mellanox Connect-X 5 or 6 series card ([see this](https://www.netris.ai/docs/en/stable/softgate-performance.html) for SoftGate performance numbers).

### 2.2 NAT operations

Our EVPN fabric is connected to the `Internet` node which has two public IPs configured on its loopback interface. Before we do anything, none of the hosts are able to reach them:

```
ubuntu@host-A:~$ ping 8.8.8.8 -c 2
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.

--- 8.8.8.8 ping statistics ---
2 packets transmitted, 0 received, 100% packet loss, time 1012ms
```

In Netris web UI, create two NAT instances by going to `Net -> Nat` and using the following details:

| Name | Site | Action | Source | Destination | SNAT to IP | IP | 
| -----|-------|-------|--------------|-------|-----------| ---- |
| nat-1 | Default | SNAT | 10.0.0.0/8 | 1.1.1.1/32 | Yes | 198.51.100.1 |
| nat-2 | Default | SNAT | 10.0.0.0/8 | 8.8.8.8/32 | Yes | 198.51.100.2 |

To validate that NAT now works as expected connect to the [ifconfig.me](https://ifconfig.me/) service running on the Internet router and confirm that the source IP gets changed according our configuration:

```
ubuntu@host-A:~$ curl http://8.8.8.8:8080/ip
198.51.100.2
ubuntu@host-A:~$ curl http://1.1.1.1:8080/ip
198.51.100.1
```

### 2.2 L4 load-balancer operations

Create a new load-balancer in `Services -> L4 Load Balancer`. This would be a simple round-robin load-balancer exposing SSH ports `host-a` and `host-b` to the `Internet` router on port `2222`.

![](https://gitlab.com/nvidia-networking/systems-engineering/poc-support/netris-on-air/-/raw/main/images/l4-lb.png)

Now from the `Internet` router you can verify that sessions are being load-balanced to different backend hosts.

```
root@Internet:~# ssh -b 1.1.1.1 -p 2222 ubuntu@198.51.100.129
ubuntu@198.51.100.129's password:

ubuntu@host-B:~$ logout
Connection to 198.51.100.129 closed.
root@Internet:~# ssh -b 8.8.8.8 -p 2222 ubuntu@198.51.100.129
ubuntu@198.51.100.129's password:

ubuntu@host-A:~$ logout
Connection to 198.51.100.129 closed.
```
