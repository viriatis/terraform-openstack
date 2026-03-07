# OpenStack Networking — Complete Guide

Understanding OpenStack networking through real-world parallels with AWS, Azure, GCP, and your home network.

---

## The Problem Networking Solves

You have VMs that need two things simultaneously:
- Talk to each other **privately and securely**
- Some of them need to **reach the internet** or be reached from it

You can't give every VM a public IP — you'd run out of IPs, it's a massive security risk, and it's expensive. The solution is the same everywhere — OpenStack, AWS, your home router — **private networks with a controlled boundary to the outside world**.

---

## The Mental Model

```
Internet
    │
    │  (public IP)
┌───▼────────────────┐
│       Router       │  ← the boundary, does NAT
│  (external gateway)│
└───────────┬────────┘
            │
    ┌───────▼────────┐
    │  Private Net   │  ← your internal world
    │  10.0.0.0/24   │
    └──┬──────────┬──┘
       │          │
    ┌──▼──┐    ┌──▼──┐
    │ VM1 │    │ VM2 │  ← private IPs, can go out via NAT
    └─────┘    └─────┘
```

This is the same diagram whether you're drawing OpenStack, AWS VPC, Azure VNet, or your home network.

---

## The Layers — Every Cloud Uses These

### 1. External Network

The "internet side". Represents the upstream connection — your ISP, your datacenter uplink, the actual internet.

**You don't own this.** The admin/provider owns and creates it. Your VMs never connect directly to it.

| Platform | Equivalent |
|---|---|
| OpenStack | `external network` (admin-created) |
| AWS | The internet itself |
| Azure | The internet itself |
| GCP | The internet itself |
| Home | Your ISP connection (WAN port) |

```bash
# OpenStack — admin creates the external network once
openstack network create --external --provider-network-type flat \
  --provider-physical-network physnet1 external-net

openstack subnet create --network external-net \
  --subnet-range 203.0.113.0/24 \
  --no-dhcp external-subnet
```

---

### 2. Router

The critical boundary between your private network and the external world. It does two jobs:

**NAT (Network Address Translation)** — when your VM (10.0.0.5) wants to reach the internet, the router replaces the source IP with its own public IP. The response comes back to the router, which forwards it to the VM. The internet never sees your private IP.

**Gateway** — it's the door. Without a router connected to the external network, your VMs are completely isolated — they can talk to each other but can't go anywhere.

| Platform | Equivalent |
|---|---|
| OpenStack | `openstack_networking_router_v2` |
| AWS | Internet Gateway + Route Table |
| Azure | Virtual Network Gateway / Route Table |
| GCP | Cloud Router |
| Home | Your Livebox / Freebox / router |

```hcl
# Terraform — OpenStack
resource "openstack_networking_router_v2" "main" {
  name                = "main-router"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.external.id
  # ↑ this is what connects the router to the internet side
}
```

```hcl
# Terraform — AWS equivalent
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}
```

**Key insight:** AWS splits the router concept into two resources (IGW + Route Table). OpenStack merges them into one Router object. Same function, different API.

---

### 3. Private Network

Your internal network where VMs live. VMs here have private IPs and can't be reached directly from the internet — they're isolated by default.

VMs on the same private network can talk to each other freely without going through the router.

| Platform | Equivalent |
|---|---|
| OpenStack | `openstack_networking_network_v2` |
| AWS | VPC (Virtual Private Cloud) |
| Azure | VNet (Virtual Network) |
| GCP | VPC Network |
| Home | Your LAN (192.168.1.0/24) |

```hcl
# Terraform — OpenStack
resource "openstack_networking_network_v2" "private" {
  name           = "private-net"
  admin_state_up = true
}
```

```hcl
# Terraform — AWS equivalent
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}
```

---

### 4. Subnet

A slice of your network with a specific IP range (CIDR). VMs are attached to subnets, not directly to networks. The subnet defines the IP pool, the gateway IP, and DHCP settings.

You can have multiple subnets inside one network — useful for segmenting workloads (app tier, db tier, etc.).

| Platform | Equivalent |
|---|---|
| OpenStack | `openstack_networking_subnet_v2` |
| AWS | Subnet (literally the same name) |
| Azure | Subnet (literally the same name) |
| GCP | Subnetwork |
| Home | Your single LAN subnet |

```hcl
# Terraform — OpenStack
resource "openstack_networking_subnet_v2" "private" {
  name       = "private-subnet"
  network_id = openstack_networking_network_v2.private.id
  cidr       = "10.0.1.0/24"
  ip_version = 4
  dns_nameservers = ["8.8.8.8", "8.8.4.4"]
}
```

```hcl
# Terraform — AWS equivalent
resource "aws_subnet" "private" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
}
```

**AWS has public vs private subnets** — a subnet is "public" if it has a route to an IGW, "private" if it doesn't. OpenStack achieves the same through whether the router interface is attached or not.

---

### 5. Router Interface

The connection point between the router and your private subnet. Without this, your private network exists but is completely cut off — VMs can't reach the router, so they can't reach the internet.

Think of it as **plugging a cable from your router into your LAN switch**.

| Platform | Equivalent |
|---|---|
| OpenStack | `openstack_networking_router_interface_v2` |
| AWS | Subnet route table association + routes |
| Azure | Subnet association to route table |
| GCP | Implicit (subnets auto-attached to router in same region) |
| Home | The LAN port on your router |

```hcl
# Terraform — OpenStack
resource "openstack_networking_router_interface_v2" "private" {
  router_id = openstack_networking_router_v2.main.id
  subnet_id = openstack_networking_subnet_v2.private.id
}
```

```hcl
# Terraform — AWS equivalent
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.main.id
}
```

---

### 6. Floating IP

A public IP that you can attach and detach from VMs on demand. The router maps this public IP to the VM's private IP — when traffic arrives at the floating IP, the router forwards it to the correct VM.

Without a floating IP, your VM can initiate connections outbound (NAT), but **nobody can initiate a connection inbound to your VM**.

| Platform | Equivalent |
|---|---|
| OpenStack | Floating IP |
| AWS | Elastic IP (EIP) |
| Azure | Public IP Address |
| GCP | External IP (static) |
| Home | Port forwarding rule on your router |

```hcl
# Terraform — OpenStack
resource "openstack_networking_floatingip_v2" "vm1" {
  pool = "external-net"  # must be the external network
}

resource "openstack_compute_floatingip_associate_v2" "vm1" {
  floating_ip = openstack_networking_floatingip_v2.vm1.address
  instance_id = openstack_compute_instance_v2.vm1.id
}
```

```hcl
# Terraform — AWS equivalent
resource "aws_eip" "vm1" {
  domain = "vpc"
}

resource "aws_eip_association" "vm1" {
  instance_id   = aws_instance.vm1.id
  allocation_id = aws_eip.vm1.id
}
```

**Important:** Floating IPs cost money in real clouds even when not attached to anything. Same concept applies — allocate only what you need.

---

### 7. Security Group

A stateful firewall applied at the VM level (not the network level). Controls what traffic can enter and leave each VM independently.

**Stateful** means if you allow outbound traffic on port 80, the return traffic is automatically allowed — you don't need an explicit inbound rule for the response.

By default in OpenStack (like AWS): **all inbound is denied, all outbound is allowed**.

| Platform | Equivalent |
|---|---|
| OpenStack | Security Group |
| AWS | Security Group (literally the same name) |
| Azure | Network Security Group (NSG) |
| GCP | Firewall Rules |
| Home | Your router's firewall |

```hcl
# Terraform — OpenStack
resource "openstack_networking_secgroup_v2" "app" {
  name        = "app-sg"
  description = "Security group for app VMs"
}

resource "openstack_networking_secgroup_rule_v2" "ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "10.0.0.0/8"  # only from internal
  security_group_id = openstack_networking_secgroup_v2.app.id
}

resource "openstack_networking_secgroup_rule_v2" "http" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.app.id
}
```

```hcl
# Terraform — AWS equivalent
resource "aws_security_group" "app" {
  name   = "app-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

---

## Full Picture — Everything Connected

```
                        Internet
                            │
                    ┌───────▼────────┐
                    │  External Net  │  (admin-managed)
                    │ 203.0.113.0/24 │
                    └───────┬────────┘
                            │ external gateway
                    ┌───────▼────────┐
                    │     Router     │  ← NAT happens here
                    │                │  ← Floating IPs resolve here
                    └───────┬────────┘
                            │ router interface
                    ┌───────▼────────┐
                    │  Private Net   │
                    │  10.0.1.0/24   │
                    └──┬──────────┬──┘
                       │          │
              ┌────────▼──┐  ┌────▼──────┐
              │    VM1    │  │    VM2    │
              │ 10.0.1.10 │  │ 10.0.1.11 │
              │ [+FIP]    │  │ (private) │
              └───────────┘  └───────────┘
              203.0.113.50 ↗
              (Floating IP)
```

VM1 is reachable from internet via Floating IP. VM2 is internal only but can initiate outbound connections via NAT.

---

## Complete Terraform Example

```hcl
# Provider
provider "openstack" {
  user_name   = "admin"
  tenant_name = "admin"
  password    = var.os_password
  auth_url    = "http://<microstack-ip>:5000/v3"
  region      = "microstack"
}

# Data source — get the external network
data "openstack_networking_network_v2" "external" {
  name     = "external-net"
  external = true
}

# Private network
resource "openstack_networking_network_v2" "private" {
  name           = "private-net"
  admin_state_up = true
}

# Subnet
resource "openstack_networking_subnet_v2" "private" {
  name            = "private-subnet"
  network_id      = openstack_networking_network_v2.private.id
  cidr            = "10.0.1.0/24"
  ip_version      = 4
  dns_nameservers = ["8.8.8.8"]
}

# Router
resource "openstack_networking_router_v2" "main" {
  name                = "main-router"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.external.id
}

# Connect router to subnet
resource "openstack_networking_router_interface_v2" "private" {
  router_id = openstack_networking_router_v2.main.id
  subnet_id = openstack_networking_subnet_v2.private.id
}

# Security group
resource "openstack_networking_secgroup_v2" "app" {
  name = "app-sg"
}

resource "openstack_networking_secgroup_rule_v2" "ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.app.id
}

# VM
resource "openstack_compute_instance_v2" "app" {
  name            = "app-vm"
  image_name      = "cirros"
  flavor_name     = "m1.tiny"
  security_groups = [openstack_networking_secgroup_v2.app.name]

  network {
    uuid = openstack_networking_network_v2.private.id
  }

  depends_on = [openstack_networking_router_interface_v2.private]
}

# Floating IP
resource "openstack_networking_floatingip_v2" "app" {
  pool = data.openstack_networking_network_v2.external.name
}

resource "openstack_compute_floatingip_associate_v2" "app" {
  floating_ip = openstack_networking_floatingip_v2.app.address
  instance_id = openstack_compute_instance_v2.app.id
}
```

---

## Concept Mapping — Full Cheat Sheet

| OpenStack | AWS | Azure | GCP | Purpose |
|---|---|---|---|---|
| External Network | Internet + IGW | Internet | Internet | Upstream connection |
| Router | Internet Gateway + Route Table | Virtual Network Gateway | Cloud Router | NAT + routing boundary |
| Network | VPC | VNet | VPC Network | Private isolated network |
| Subnet | Subnet | Subnet | Subnetwork | IP range slice |
| Router Interface | Route Table Association | Subnet → Route Table | Implicit | Connect subnet to router |
| Floating IP | Elastic IP | Public IP Address | Static External IP | Inbound public access |
| Security Group | Security Group | NSG | Firewall Rule | VM-level firewall |
| Project/Tenant | Account + VPC | Subscription + VNet | Project | Isolation boundary |

---

## Key Principles (Same Everywhere)

**Private by default** — VMs are born isolated. You explicitly open access.

**NAT for outbound** — VMs go out via the router using NAT. The internet sees the router's IP, not the VM's.

**Floating IP / EIP for inbound** — if something needs to be reached from outside, it needs a public IP explicitly assigned.

**Security Groups are additive** — you add allow rules. There is no "deny" rule — if there's no allow, it's denied.

**Subnets don't route between each other automatically** — you need router interfaces or peering.

---

## Kubernetes on OpenStack — Load Balancing

When you run one or more Kubernetes clusters on top of OpenStack VMs, you need to expose services outside the cluster. This is where the `LoadBalancer` service type comes in — and this is where OpenStack and bare-metal k8s diverge.

### The problem

In AWS/GCP/Azure, when you create a Kubernetes `Service` of type `LoadBalancer`, the cloud controller manager automatically provisions an ELB/ALB/NLB for you. The cloud owns that integration.

On bare-metal or OpenStack-hosted k8s, **there is no cloud controller by default** — `LoadBalancer` services stay in `<Pending>` forever because nothing is watching to fulfill them.

You have two paths:

---

### Path 1 — MetalLB (bare-metal / kubeadm clusters)

What you already use at Desigual. MetalLB runs inside the k8s cluster and watches for `LoadBalancer` services. When one is created, it assigns an IP from a pool you define and announces it via ARP (L2 mode) or BGP (L3 mode).

```
K8s Service (LoadBalancer)
        │
        ▼
    MetalLB
        │ assigns IP from pool
        ▼
   192.168.1.200  ← announced via ARP/BGP to your network
```

**L2 mode** — MetalLB responds to ARP requests for the IP. Simple, no BGP router needed. One node owns the IP at a time (failover via gratuitous ARP).

**BGP mode** — MetalLB peers with your network router and announces routes. True load balancing across nodes. Needs a BGP-capable router.

```yaml
# MetalLB IPAddressPool
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: lab-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.1.200-192.168.1.250

---
# L2 Advertisement
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: lab-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - lab-pool
```

---

### Path 2 — Octavia (OpenStack native)

**Octavia is the OpenStack Load Balancer service** — the direct equivalent of AWS ELB. When you install the OpenStack Cloud Controller Manager (OCCM) in your k8s cluster, it integrates with Octavia automatically. Creating a `LoadBalancer` service triggers Octavia to provision a real load balancer in OpenStack.

```
K8s Service (LoadBalancer)
        │
        ▼
OpenStack Cloud Controller Manager (OCCM)
        │ calls OpenStack API
        ▼
    Octavia LB
        │ gets a Floating IP
        ▼
   203.0.113.50  ← real public IP from OpenStack external net
```

Octavia creates an **Amphora** — a VM running HAProxy — that does the actual load balancing. It's fully managed by OpenStack.

```hcl
# Terraform — Octavia Load Balancer
resource "openstack_lb_loadbalancer_v2" "k8s_lb" {
  name          = "k8s-ingress-lb"
  vip_subnet_id = openstack_networking_subnet_v2.private.id
}

resource "openstack_lb_listener_v2" "http" {
  name            = "http-listener"
  protocol        = "HTTP"
  protocol_port   = 80
  loadbalancer_id = openstack_lb_loadbalancer_v2.k8s_lb.id
}

resource "openstack_lb_pool_v2" "k8s_nodes" {
  name        = "k8s-nodes"
  protocol    = "HTTP"
  lb_method   = "ROUND_ROBIN"
  listener_id = openstack_lb_listener_v2.http.id
}

resource "openstack_lb_member_v2" "node1" {
  pool_id       = openstack_lb_pool_v2.k8s_nodes.id
  address       = "10.0.1.10"   # k8s node IP
  protocol_port = 30080          # NodePort
  subnet_id     = openstack_networking_subnet_v2.private.id
}

# Attach a Floating IP to the LB VIP
resource "openstack_networking_floatingip_v2" "lb" {
  pool = "external-net"
}

resource "openstack_networking_floatingip_associate_v2" "lb" {
  floating_ip = openstack_networking_floatingip_v2.lb.address
  port_id     = openstack_lb_loadbalancer_v2.k8s_lb.vip_port_id
}
```

---

### MetalLB vs Octavia — When to use what

| | MetalLB | Octavia |
|---|---|---|
| Where it runs | Inside k8s | Outside k8s (OpenStack service) |
| Requires OpenStack | No | Yes |
| Cloud controller needed | No | Yes (OCCM) |
| IP source | Pool you define | OpenStack external net |
| HA | L2: single node failover / BGP: true HA | Built-in (active-standby Amphora) |
| Best for | Bare-metal, kubeadm, no cloud | k8s on OpenStack VMs |
| AWS equivalent | No equivalent (cloud handles it) | ELB / ALB / NLB |

**Rule of thumb:**
- k8s on **bare-metal or kubeadm** (like at Desigual) → **MetalLB**
- k8s on **OpenStack VMs** (Magnum or manual) → **Octavia + OCCM**
- k8s on **AWS/GCP/Azure** → cloud controller handles it automatically, nothing to install

---

### Multiple Clusters on OpenStack

If you run multiple k8s clusters on OpenStack (common in multi-tenant setups), each cluster can have its own Octavia load balancers. OpenStack Magnum is the managed k8s service that automates this — think of it as OpenStack's equivalent of EKS/GKE/AKS.

```
OpenStack Project A          OpenStack Project B
┌─────────────────┐          ┌─────────────────┐
│  k8s cluster 1  │          │  k8s cluster 2  │
│  + Octavia LB   │          │  + Octavia LB   │
│  + Floating IP  │          │  + Floating IP  │
└─────────────────┘          └─────────────────┘
         │                            │
         └──────────┬─────────────────┘
                    │
             OpenStack Neutron
             (shared network infra)
```

Each cluster is isolated at the OpenStack project level — separate networks, separate LBs, separate security groups. Same isolation model as separate VPCs in AWS.

---

### Cloud Mapping — Load Balancers

| OpenStack | AWS | Azure | GCP | Purpose |
|---|---|---|---|---|
| Octavia | ELB / ALB / NLB | Azure Load Balancer | Cloud Load Balancing | Managed LB service |
| MetalLB (L2) | — | — | — | Bare-metal LB (ARP) |
| MetalLB (BGP) | — | — | — | Bare-metal LB (BGP) |
| Magnum | EKS | AKS | GKE | Managed k8s service |
| OCCM | AWS Cloud Controller | Azure CCM | GCP CCM | k8s ↔ cloud integration |

---

## References

- [OpenStack Neutron docs](https://docs.openstack.org/neutron/latest/)
- [Terraform OpenStack networking provider](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_router_v2)
- [AWS VPC concepts](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html)
- [MicroStack](https://microstack.run)
- [OpenStack Octavia docs](https://docs.openstack.org/octavia/latest/)
- [MetalLB docs](https://metallb.universe.tf)
- [OpenStack Cloud Controller Manager](https://github.com/kubernetes/cloud-provider-openstack)
- [OpenStack Magnum docs](https://docs.openstack.org/magnum/latest/)
