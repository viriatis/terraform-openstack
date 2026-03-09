# ============================================================
# OpenStack - Nginx Instance with Security Configuration
# ============================================================

terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.4.0"
    }
  }

  backend "s3" {
    bucket = "terraform-state"
    key    = "nginx/terraform.tfstate"
    region = "RegionOne"

    endpoints = {
      s3 = "http://192.168.200.102:3000"
    }

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    use_path_style              = true
    use_lockfile                = true
  }
}

provider "openstack" {
  endpoint_overrides = {
    identity     = "http://192.168.200.102/openstack-keystone/v3/"
    compute      = "http://192.168.200.102/openstack-nova/v2.1/"
    network      = "http://192.168.200.102/openstack-neutron/v2.0/"
    image        = "http://192.168.200.102/openstack-glance/v2/"
    placement    = "http://192.168.200.102/openstack-placement/"
    volume       = "http://192.168.200.102/openstack-cinder/v3/"
    blockstorage = "http://192.168.200.102/openstack-cinder/v3/"
  }
  user_name           = var.os_username
  tenant_name         = var.os_project
  password            = var.os_password
  auth_url            = var.os_auth_url
  region              = var.os_region
  user_domain_name    = var.os_user_domain_name
  project_domain_name = var.os_project_domain_name
}

# ============================================================
# NETWORKING
# ============================================================

# Private network for nginx
resource "openstack_networking_network_v2" "nginx_net" {
  name           = "nginx-network"
  admin_state_up = true
}

# Subnet — isolated from default network
resource "openstack_networking_subnet_v2" "nginx_subnet" {
  name            = "nginx-subnet"
  network_id      = openstack_networking_network_v2.nginx_net.id
  cidr            = var.nginx_subnet_cidr
  ip_version      = 4
  dns_nameservers = ["8.8.8.8", "8.8.4.4"]
}

# Router to allow outbound internet (package installs)
resource "openstack_networking_router_v2" "nginx_router" {
  name                = "nginx-router"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.external.id
}

# Connect router to nginx subnet
resource "openstack_networking_router_interface_v2" "nginx_router_iface" {
  router_id = openstack_networking_router_v2.nginx_router.id
  subnet_id = openstack_networking_subnet_v2.nginx_subnet.id
}

# ============================================================
# SECURITY GROUPS
# ============================================================

# Security group for nginx
resource "openstack_networking_secgroup_v2" "nginx_sg" {
  name                 = "nginx-sg"
  description          = "Security group for nginx server - HTTP/HTTPS only"
  delete_default_rules = true
}

# Allow ICMP from anywhere
resource "openstack_networking_secgroup_rule_v2" "icmp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.nginx_sg.id
  description       = "Allow ICMP ping"
}

# Allow HTTP from anywhere
resource "openstack_networking_secgroup_rule_v2" "http" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.nginx_sg.id
  description       = "Allow HTTP"
}

# Allow HTTPS from anywhere
resource "openstack_networking_secgroup_rule_v2" "https" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.nginx_sg.id
  description       = "Allow HTTPS"
}

# Allow SSH only from management network (NOT from 0.0.0.0/0)
resource "openstack_networking_secgroup_rule_v2" "ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.management_cidr
  security_group_id = openstack_networking_secgroup_v2.nginx_sg.id
  description       = "Allow SSH from management network only"
}

resource "openstack_networking_secgroup_rule_v2" "egress_all" {
  direction         = "egress"
  ethertype         = "IPv4"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.nginx_sg.id
  description       = "Allow all outbound"
}

# ============================================================
# SSH KEYPAIR
# ============================================================

resource "openstack_compute_keypair_v2" "nginx_key" {
  name       = "nginx-keypair"
  public_key = file(pathexpand(var.public_key_path))
}

# ============================================================
# FLOATING IP
# ============================================================

resource "openstack_networking_floatingip_v2" "nginx_fip" {
  pool = data.openstack_networking_network_v2.external.name
}

# ============================================================
# FLAVOR
# ============================================================

resource "openstack_compute_flavor_v2" "small" {
  name      = var.flavor_name
  ram       = 2048
  vcpus     = 1
  disk      = 20
  is_public = true
}

# ============================================================
# IMAGE
# ============================================================

resource "openstack_images_image_v2" "ubuntu" {
  name             = var.image_name
  image_source_url = "https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img"
  container_format = "bare"
  disk_format      = "qcow2"
  web_download     = true
}

# ============================================================
# INSTANCE
# ============================================================

resource "openstack_compute_instance_v2" "nginx" {
  name            = "nginx-server"
  image_id        = openstack_images_image_v2.ubuntu.id
  flavor_id       = openstack_compute_flavor_v2.small.id
  key_pair        = openstack_compute_keypair_v2.nginx_key.name
  security_groups = [openstack_networking_secgroup_v2.nginx_sg.name]

  # Place instance in nginx subnet
  network {
    uuid = openstack_networking_network_v2.nginx_net.id
  }

  # Cloud-init to install and configure nginx on boot
  user_data = <<-EOF
    #cloud-config
    package_update: true
    package_upgrade: false
    packages:
      - nginx

    write_files:
      - path: /var/www/html/index.html
        content: |
          <!DOCTYPE html>
          <html>
            <head><title>Nginx on OpenStack</title></head>
            <body>
              <h1>Nginx running on OpenStack Sunbeam</h1>
              <p>Deployed with Terraform</p>
            </body>
          </html>

    runcmd:
      - sed -i 's/# server_tokens off;/server_tokens off;/' /etc/nginx/nginx.conf
      - systemctl enable nginx
      - systemctl start nginx
  EOF

  # Wait for network to be ready before marking instance as done
  depends_on = [openstack_networking_router_interface_v2.nginx_router_iface]
}

# Get the port of the nginx instance
data "openstack_networking_port_v2" "nginx_port" {
  device_id  = openstack_compute_instance_v2.nginx.id
  network_id = openstack_networking_network_v2.nginx_net.id
}

# Attach floating IP to nginx instance port
resource "openstack_networking_floatingip_associate_v2" "nginx_fip" {
  floating_ip = openstack_networking_floatingip_v2.nginx_fip.address
  port_id     = data.openstack_networking_port_v2.nginx_port.id
}

# ============================================================
# DATA SOURCES
# ============================================================

data "openstack_networking_network_v2" "external" {
  name     = var.external_network_name
  external = true
}
