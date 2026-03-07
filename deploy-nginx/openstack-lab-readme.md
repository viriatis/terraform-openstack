# OpenStack Lab — MicroStack + Terraform

Local OpenStack lab using MicroStack on a Multipass VM, with Terraform for infrastructure provisioning.

---

## What is MicroStack?

OpenStack is not a single installable thing — it's a collection of 30+ services (Nova, Neutron, Glance, Cinder, Keystone, Horizon...) that in production are deployed with tools like Kolla-Ansible across multiple machines.

**MicroStack is OpenStack**, pre-packaged as a snap by Canonical into a single-node installation. Under the hood you still get all the core services:

| Service | Purpose |
|---|---|
| Keystone | Identity & authentication |
| Nova | Compute (VMs) |
| Neutron | Networking |
| Glance | Image management |
| Cinder | Block storage |
| Horizon | Web dashboard |

Think of it like the difference between building Kubernetes with `kubeadm` vs using `kind` for a local lab — same technology, different packaging for different purposes.

---

## Prerequisites

### Windows
Multipass on Windows uses **Hyper-V** as the backend, which supports nested virtualization — meaning VMs inside OpenStack actually work.

Enable Hyper-V if not already active:
```powershell
# Run as Administrator
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
```

Install Multipass from [multipass.run](https://multipass.run).

### Recommended host specs
| RAM | Result |
|---|---|
| 16GB | Workable — 8GB to the VM |
| 32GB | Comfortable — 12-16GB to the VM |

---

## Setup

### 1. Create the Multipass VM

```powershell
# Windows PowerShell
multipass launch --name openstack-lab `
  --cpus 4 `
  --memory 8G `
  --disk 50G `
  22.04
```

```bash
# macOS / Linux
multipass launch --name openstack-lab \
  --cpus 4 \
  --memory 8G \
  --disk 50G \
  22.04
```

### 2. Enter the VM

```bash
multipass shell openstack-lab
```

### 3. Install MicroStack

```bash
sudo snap install microstack --beta
sudo microstack init --auto --control
```

### 4. Get the admin password

```bash
sudo snap get microstack config.credentials.keystone-password
```

### 5. Access the Horizon dashboard

Get the VM IP:
```bash
multipass info openstack-lab
```

Open `http://<vm-ip>` in your browser. Login with user `admin` and the password from step 4.

---

## Terraform — OpenStack Provider

MicroStack exposes standard OpenStack APIs, so the Terraform OpenStack provider works against it exactly like a real production OpenStack.

### Provider configuration

```hcl
terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.53"
    }
  }
}

provider "openstack" {
  user_name   = "admin"
  tenant_name = "admin"
  password    = "<your-microstack-password>"
  auth_url    = "http://<vm-ip>:5000/v3"
  region      = "microstack"
}
```

### Create a compute instance

```hcl
resource "openstack_compute_instance_v2" "test" {
  name        = "test-vm"
  image_name  = "cirros"   # MicroStack ships with cirros by default
  flavor_name = "m1.tiny"

  network {
    name = "test"
  }
}
```

```bash
terraform init
terraform plan
terraform apply
```

### Create a network and router

```hcl
resource "openstack_networking_network_v2" "lab_net" {
  name           = "lab-network"
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "lab_subnet" {
  name       = "lab-subnet"
  network_id = openstack_networking_network_v2.lab_net.id
  cidr       = "192.168.100.0/24"
  ip_version = 4
}

resource "openstack_networking_router_v2" "lab_router" {
  name                = "lab-router"
  admin_state_up      = true
  external_network_id = "<external-network-id>"
}

resource "openstack_networking_router_interface_v2" "lab_router_interface" {
  router_id = openstack_networking_router_v2.lab_router.id
  subnet_id = openstack_networking_subnet_v2.lab_subnet.id
}
```

### Security group

```hcl
resource "openstack_networking_secgroup_v2" "lab_sg" {
  name        = "lab-sg"
  description = "Lab security group"
}

resource "openstack_networking_secgroup_rule_v2" "ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  security_group_id = openstack_networking_secgroup_v2.lab_sg.id
}
```

---

## What you can practice

- Creating instances, networks, routers, security groups via Terraform
- Managing tenants/projects (equivalent to namespaces in Kubernetes)
- Uploading images to Glance
- Managing floating IPs
- OpenStack RBAC — projects, roles, users (very different from k8s RBAC, interesting to compare)
- Full IaC workflow against a real OpenStack API

---

## OpenStack vs Kubernetes RBAC — quick comparison

| | OpenStack | Kubernetes |
|---|---|---|
| Identity unit | Project/Tenant | Namespace |
| User management | Built-in (Keystone) | External (certs, OIDC) |
| Permission binding | Role assignment per project | RoleBinding / ClusterRoleBinding |
| Service identity | Application Credentials | ServiceAccount |
| Admin scope | Cloud-wide vs project | Cluster vs namespace |

---

## Useful commands

```bash
# Check MicroStack status
sudo microstack.openstack service list

# List available images
sudo microstack.openstack image list

# List flavors
sudo microstack.openstack flavor list

# List running instances
sudo microstack.openstack server list

# Get Keystone endpoint
sudo microstack.openstack endpoint list
```

---

## References

- [MicroStack docs](https://microstack.run)
- [Terraform OpenStack provider](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs)
- [OpenStack docs](https://docs.openstack.org)
- [Multipass](https://multipass.run)
