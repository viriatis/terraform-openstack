# Terraform — OpenStack Nginx Instance

Deploys an nginx instance on a dedicated private subnet in OpenStack (Sunbeam). SSH is locked to a management CIDR, HTTP/HTTPS open to the world.

## Architecture

```
External Network (floating IP pool)
        │
        │ Floating IP (public access)
        ▼
    nginx-router
        │
        │ router interface
        ▼
    nginx-subnet (10.10.10.0/24)   ← isolated subnet
        │
        ▼
    nginx-server
    ├── Security Group: nginx-sg
    │   ├── TCP 80  (HTTP)   → 0.0.0.0/0
    │   ├── TCP 443 (HTTPS)  → 0.0.0.0/0
    │   └── TCP 22  (SSH)    → management CIDR only
    └── Nginx installed via cloud-init
```

## What gets created

- Private network + subnet (`10.10.10.0/24`) — isolated from default network
- Router connected to external network (for floating IP + outbound NAT)
- Security group with HTTP/HTTPS open, SSH restricted to management CIDR
- SSH keypair from your public key
- Ubuntu instance with nginx installed via cloud-init
- Floating IP attached to the instance

## Prerequisites

```bash
# Install Terraform
brew install terraform  # macOS
# or
snap install terraform --classic  # Ubuntu

# Source your OpenStack credentials
source ~/operator-openrc

# Get S3 credentials for operator user
openstack ec2 credentials create

# Verify OpenStack connectivity
openstack image list
openstack flavor list
openstack network list --external
```

You also need a running S3-compatible backend for remote state (see [Remote State](#remote-state) below). This project uses [Garage](https://garagehq.deuxfleurs.fr/) but any S3-compatible service works (MinIO, AWS S3, etc.).

## Usage
Use Makefile instead

```bash
# 1. Clone and enter the project
cd deploy-nginx

# 2. Configure your variables
# Edit terraform.tfvars with your values (OS credentials, key path, CIDRs)
vim terraform.tfvars

# 3. Initialize Terraform
terraform init -backend-config=backend.hcl

# 4. Preview what will be created
terraform plan -out=tfplan

## CICD Pipelines
terraform plan -out=${GIT_COMMIT}.tfplan

# 5. Deploy
terraform apply tfplan && rm tfplan

## CICD Pipelines
terraform apply ${GIT_COMMIT}.tfplan && rm tfplan


# 6. Get outputs
terraform output
```

## Outputs

After apply you'll get:

```
nginx_floating_ip = "203.0.113.50"
nginx_private_ip  = "10.10.10.5"
nginx_url         = "http://203.0.113.50"
ssh_command       = "ssh -i ~/.ssh/ubuntu-server ubuntu@203.0.113.50"
network_info = {
  network = "nginx-network"
  subnet  = "10.10.10.0/24"
  router  = "nginx-router"
}
```

## Verify nginx is running

```bash
# HTTP check
curl http://<floating-ip>

# SSH in
ssh -i ~/.ssh/id_rsa ubuntu@<floating-ip>

# Check nginx inside the VM
sudo systemctl status nginx
```

## Find your OpenStack values

```bash
# Source credentials first
source operator-openrc

# Find external network name
openstack network list --external

# Find available images
openstack image list

# Find available flavors
openstack flavor list
```

## Security notes

- SSH is restricted to `management_cidr` — set this to your IP, not `0.0.0.0/0`
- `server_tokens off` hides nginx version from HTTP headers
- Instance lives on a dedicated subnet, isolated from other workloads
- Floating IP is the only public entry point
- All other inbound traffic is denied by default (OpenStack security group behavior)

## Remote State

State is stored remotely in an S3-compatible bucket. The backend config is in `main.tf`:

```hcl
backend "s3" {
  bucket   = "terraform-state"
  key      = "nginx/terraform.tfstate"
  region   = "RegionOne"
  endpoints = { s3 = "http://<your-openstack-s3-bucket>:3000" }
  ...
}
```

Create a backend.hcl and add it to .gitignore:
```hcl
access_key = "xxxx"
secret_key = "xxxx"
```

Update the `endpoints.s3` URL and credentials to match your setup before running `terraform init -backend-config=backend.hcl`.

### Starting fresh (no existing state)

Just run `terraform init` normally — it will create the state file in the bucket on first apply.

### Migrating from local state

If you already ran `terraform apply` with a local `terraform.tfstate`, migrate it to the remote backend:

```bash
# Make sure the S3 backend is configured in main.tf first
terraform init -migrate-state -backend-config=backend.hcl
```

Terraform will detect the local state and ask if you want to copy it to the remote backend. Say yes. After that you can delete the local `terraform.tfstate`.

> If you want to go back to local state temporarily (e.g. the backend is down), comment out the `backend "s3"` block and run `terraform init -migrate-state` again to pull state back locally.

## Cleanup

```bash
terraform destroy
```

This removes everything — instance, floating IP, network, router, security group, keypair.
