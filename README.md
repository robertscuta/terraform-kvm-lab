# terraform-kvm-lab

Terraform config to provision a 4-node Ubuntu 24.04 lab (network node, controller, 2x
compute) on a remote KVM host via the [`dmacvicar/libvirt`](https://registry.terraform.io/providers/dmacvicar/libvirt/latest)
provider — meant as a base for a Kolla-Ansible OpenStack install (not included here).

## Architecture

```
Terraform → libvirt provider (dmacvicar/libvirt v0.8.x) → libvirtd → QEMU/KVM
```

- Remote KVM host reached over SSH (`qemu+ssh://`), not local.
- VMs are bridged onto the host's real LAN (`br0`), not libvirt's default NAT network.
- Adopts an existing storage pool rather than creating one.

## Prerequisites

1. Passwordless SSH to the KVM host (key-based auth, host key already trusted).
2. Your user in the `libvirt` group (or root) on the KVM host.
3. `xsltproc` installed on the machine running `terraform`. The `dmacvicar/libvirt`
   provider (v0.8.x) has two gaps this config works around with an `xml { xslt = ... }`
   post-processing step in `main.tf`, applied locally to the domain XML before it's sent
   to libvirtd:
   - the `disk { file = ... }` form never sets `driver type="qcow2"` for a plain qcow2
     path, leaving it at the default `raw` — which makes the guest unbootable;
   - there's no `sockets`/`cores`/`threads` topology field on the `cpu` block.

   Check with `xsltproc --version`; install with `apt install xsltproc` on
   Ubuntu/Debian or `brew install libxslt` on macOS if missing.
4. An ISO-building tool installed on the machine running `terraform` — needed by
   `libvirt_cloudinit_disk` to build the cloud-init ISO locally before it's uploaded to
   the pool:
   - macOS: `brew install cdrtools` (provides `mkisofs`)
   - Ubuntu/Debian: `apt install genisoimage xorriso`
5. Nested virtualization enabled on the KVM host if you plan to run nova-compute inside
   the compute-node VMs later.
6. An existing libvirt storage pool on the host — get its UUID with
   `virsh pool-uuid <pool-name>` on the host.
7. An SSH keypair to inject into the VMs via cloud-init.

## Setup

1. Edit `main.tf`:
   - `provider "libvirt" { uri = ... }` — set your SSH user and KVM host.
   - `libvirt_pool.homelab` — set `target.path` to your pool's real path.
   - `libvirt_domain.vm` → `disk.file` — same path, must match the pool path above.
   - `var.nodes` — set real IPs for your LAN/DHCP range and adjust vcpu/memory/disk as
     needed.
2. Edit `cloud-init/*.yaml` — replace `YOUR_PUB_SSH_HERE` with your real public SSH key
   in all four files. Uncomment/set a `password:` only if you want console-login access
   (not recommended as-is — plaintext).
3. Edit `cloud-init/network-config.yaml.tpl` — set your real gateway IP.
4. Import the existing pool once:
   ```
   terraform import libvirt_pool.homelab <pool-uuid>
   ```

## Running it

```
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply "tfplan"
```

## Verifying

```
virsh -c qemu:///system list --all      # all 4 should show "running"
ssh openstack@<controller-ip>            # via the injected SSH key
```

## Notes

- `xslt` in the domain resource is `ForceNew` — changing it recreates all 4 domains.
- Cloud-init only applies on a VM's first boot. To force a re-apply after editing
  `cloud-init/*`, use `terraform apply -replace=...` per domain.
- No `terraform.tfvars`/`variables.tf` split — intentional, single-file POC for 4 nodes.
