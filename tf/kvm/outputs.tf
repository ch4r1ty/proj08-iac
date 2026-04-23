output "floating_ip_out" {
  description = "Floating IP assigned to node1"
  value       = openstack_networking_floatingip_v2.floating_ip.address
}

output "node1_sharednet_port_id" {
  description = "Neutron port id for node1 public/shared network interface"
  value       = openstack_networking_port_v2.sharednet1_ports["node1"].id
}

output "public_service_ports" {
  description = "TCP ports opened by the proj08 public services security group"
  value       = sort(tolist(local.public_tcp_ports))
}
