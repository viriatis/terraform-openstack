# ============================================================
# Outputs
# ============================================================

output "nginx_floating_ip" {
  description = "Public floating IP of the nginx instance"
  value       = openstack_networking_floatingip_v2.nginx_fip.address
}

output "nginx_private_ip" {
  description = "Private IP of the nginx instance"
  value       = openstack_compute_instance_v2.nginx.access_ip_v4
}

output "nginx_url" {
  description = "URL to access nginx"
  value       = "http://${openstack_networking_floatingip_v2.nginx_fip.address}"
}

output "ssh_command" {
  description = "SSH command to connect to the nginx instance"
  value       = "ssh -i ${trimsuffix(var.public_key_path, ".pub")} ubuntu@${openstack_networking_floatingip_v2.nginx_fip.address}"
}

output "network_info" {
  description = "Network details"
  value = {
    network = openstack_networking_network_v2.nginx_net.name
    subnet  = openstack_networking_subnet_v2.nginx_subnet.cidr
    router  = openstack_networking_router_v2.nginx_router.name
  }
}
