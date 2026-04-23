locals {
  public_tcp_ports = toset([
    "22",    # SSH
    "80",    # HTTP redirect / optional ingress
    "443",   # HTTPS ingress
    "3000",  # local Grafana fallback
    "3001",  # local Actual Vite fallback
    "5000",  # local MLflow fallback
    "5006",  # local Actual sync/server fallback
    "8000",  # MLflow externalIP and SmartCat local fallback
    "8888",  # Jupyter troubleshooting
    "9000",  # MinIO API
    "9001",  # MinIO console
    "9090",  # local Prometheus fallback
    "30080", # legacy Actual NodePort fallback
    "30083", # Actual HTTP NodePort fallback
    "30090", # SmartCat serving NodePort
    "30300", # Grafana NodePort
    "30443", # Actual HTTPS nginx NodePort
    "30901", # optional MinIO console NodePort
    "30909"  # Prometheus NodePort
  ])
}

resource "openstack_networking_secgroup_v2" "proj08_public_services" {
  name        = "proj08-public-services-${var.suffix}"
  description = "Browser and demo ports for proj08 Smart Transaction Categorization"
}

resource "openstack_networking_secgroup_rule_v2" "proj08_public_tcp" {
  for_each          = local.public_tcp_ports
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = tonumber(each.value)
  port_range_max    = tonumber(each.value)
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.proj08_public_services.id
}

resource "openstack_networking_secgroup_rule_v2" "proj08_icmp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.proj08_public_services.id
}

resource "openstack_networking_network_v2" "private_net" {
  name                  = "private-net-mlops-${var.suffix}"
  port_security_enabled = false
}

resource "openstack_networking_subnet_v2" "private_subnet" {
  name       = "private-subnet-mlops-${var.suffix}"
  network_id = openstack_networking_network_v2.private_net.id
  cidr       = "192.168.1.0/24"
  no_gateway = true
}

resource "openstack_networking_port_v2" "private_net_ports" {
  for_each              = var.nodes
  name                  = "port-${each.key}-mlops-${var.suffix}"
  network_id            = openstack_networking_network_v2.private_net.id
  port_security_enabled = false

  fixed_ip {
    subnet_id  = openstack_networking_subnet_v2.private_subnet.id
    ip_address = each.value
  }
}

resource "openstack_networking_port_v2" "sharednet1_ports" {
  for_each           = var.nodes
  name               = "sharednet1-${each.key}-mlops-${var.suffix}"
  network_id         = data.openstack_networking_network_v2.sharednet1.id
  security_group_ids = [openstack_networking_secgroup_v2.proj08_public_services.id]
}

resource "openstack_compute_instance_v2" "nodes" {
  for_each = var.nodes

  name       = "${each.key}-mlops-${var.suffix}"
  image_name = "CC-Ubuntu24.04"
  flavor_id  = var.reservation
  key_pair   = var.key

  network {
    port = openstack_networking_port_v2.sharednet1_ports[each.key].id
  }

  network {
    port = openstack_networking_port_v2.private_net_ports[each.key].id
  }

  user_data = <<-EOF
    #! /bin/bash
    sudo echo "127.0.1.1 ${each.key}-mlops-${var.suffix}" >> /etc/hosts
    su cc -c /usr/local/bin/cc-load-public-keys
  EOF
}

resource "openstack_networking_floatingip_v2" "floating_ip" {
  pool        = "public"
  description = "proj08 Smart Transaction Categorization IP for ${var.suffix}"
  port_id     = openstack_networking_port_v2.sharednet1_ports["node1"].id
}
