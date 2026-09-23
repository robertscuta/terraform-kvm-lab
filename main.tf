# Provider block
terraform {
  required_providers {
    libvirt = {
        source = "dmacvicar/libvirt"
        version = "~> 0.8.0"
    }
  }
}

provider "libvirt" {
    uri = "qemu+ssh://USER@KVM_HOST/system" # Append "?keyfile=...&sshauth=privkey" to override ssh-agent.
}

# Storage pool
resource "libvirt_pool" "homelab" {   # You can choose a different name from "homelab", adjust further references.
    name = "homelab"
    type = "dir"
    target { path = "/path/to/your/pool" }

 lifecycle {
    prevent_destroy = false     # Chose if "terraform destroy" operation can remove the KVM pool.
  }
}

# Base volume
resource "libvirt_volume" "ubuntu_base" {
    name = "ubuntu-24.04-base.qcow2"
    pool = libvirt_pool.homelab.name
    source = "https://cloud-images.ubuntu.com/noble/20260826/noble-server-cloudimg-amd64.img" # Pinned date on img for reproducibility, can use "latest".
    format = "qcow2"  
}

# Per-VM disk volumes
resource "libvirt_volume" "vm_disk" {
    for_each        = var.nodes
    name            = "${each.key}.qcow2"
    pool            = libvirt_pool.homelab.name
    base_volume_id  = libvirt_volume.ubuntu_base.id
    size            = each.value.disk_size
}

# Define the IP addresses of the VMs according to your DHCP range and the VCPUs for each.
variable "nodes" {
    type = map(object({
        vcpu      = number
        memory    = number   # MiB
        disk_size = number   # bytes
        ip        = string
        cores     = number
        threads   = number
    }))
    default = {
    network-node = { vcpu = 2, memory = 4096, disk_size = 21474836480, ip = "192.168.XX.XX", cores = 2, threads = 1 }
    controller   = { vcpu = 4, memory = 8192, disk_size = 32212254720, ip = "192.168.XX.XX", cores = 2, threads = 2 }
    compute1     = { vcpu = 4, memory = 8192, disk_size = 32212254720, ip = "192.168.XX.XX", cores = 2, threads = 2 }
    compute2     = { vcpu = 4, memory = 8192, disk_size = 32212254720, ip = "192.168.XX.XX", cores = 2, threads = 2 }
  }
}

# Cloud-init
resource "libvirt_cloudinit_disk" "init" {
  for_each  = var.nodes
  name      = "${each.key}-init.iso"
  pool      = libvirt_pool.homelab.name
  user_data = file("${path.module}/cloud-init/${each.key}.yaml")
  network_config = templatefile("${path.module}/cloud-init/network-config.yaml.tpl",{
    ip = each.value.ip
  })
}

# Sets driver.Type = "qcow2" for plain qcow2 files, CPU topology.
locals {
  force_qcow2_and_topology_xslt = {
    for k, v in var.nodes : k => <<-EOT
      <?xml version="1.0"?>
      <xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
        <xsl:template match="@*|node()">
          <xsl:copy>
            <xsl:apply-templates select="@*|node()"/>
          </xsl:copy>
        </xsl:template>
        <xsl:template match="disk[@device='disk']/driver/@type">
          <xsl:attribute name="type">qcow2</xsl:attribute>
        </xsl:template>
        <xsl:template match="cpu">
          <xsl:copy>
            <xsl:apply-templates select="@*|node()"/>
            <topology sockets="1" cores="${v.cores}" threads="${v.threads}"/>
          </xsl:copy>
        </xsl:template>
      </xsl:stylesheet>
    EOT
  }
}

# The domain - VM
resource "libvirt_domain" "vm" {
  for_each   = var.nodes
  depends_on = [libvirt_volume.vm_disk]
  name       = each.key
  vcpu       = each.value.vcpu
  memory     = each.value.memory
  autostart  = true
  cpu { mode = "host-passthrough" }

  disk {
    file = "/path/to/your/pool/${each.key}.qcow2"
  }

  network_interface {
    bridge = "br0"
  }

  cloudinit = libvirt_cloudinit_disk.init[each.key].id

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  xml {
    xslt = local.force_qcow2_and_topology_xslt[each.key]
  }
}

# Info output
output "vm_ips" {
  value = { for k, v in var.nodes : k => v.ip }
}
