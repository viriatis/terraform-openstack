# ============================================================
# Variables
# ============================================================

# OpenStack Auth
variable "os_auth_url" {
  description = "OpenStack Keystone auth URL"
  type        = string
}

variable "os_username" {
  description = "OpenStack username"
  type        = string
}

variable "os_password" {
  description = "OpenStack password"
  type        = string
  sensitive   = true
}

variable "os_project" {
  description = "OpenStack project/tenant name"
  type        = string
}

variable "os_region" {
  description = "OpenStack region"
  type        = string
}

variable "os_project_domain_name" {
  description = "OpenStack project domain name"
  type        = string
}
variable "os_user_domain_name" {
  description = "OpenStack user domain name"
  type        = string
}

# Networking
variable "external_network_name" {
  description = "Name of the external network for floating IPs"
  type        = string
  default     = "external-network"
}

variable "nginx_subnet_cidr" {
  description = "CIDR for nginx private subnet"
  type        = string
}

variable "management_cidr" {
  description = "CIDR allowed to SSH into the nginx instance. Restrict this to your IP."
  type        = string
}

# Instance
variable "image_name" {
  description = "OS image to use for the instance"
  type        = string
}

variable "flavor_name" {
  description = "Instance flavor/size"
  type        = string
}

variable "public_key_path" {
  description = "Path to your SSH public key"
  type        = string
}
