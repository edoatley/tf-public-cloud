# Virtual Machines

- [Virtual Machines](#virtual-machines)
  - [Introduction](#introduction)
    - [What each example provisions](#what-each-example-provisions)
  - [Concepts and terminology](#concepts-and-terminology)
    - [Networking](#networking)
    - [Public IP addresses](#public-ip-addresses)
    - [Firewall / security rules](#firewall--security-rules)
    - [SSH key injection](#ssh-key-injection)
    - [Machine images](#machine-images)
  - [AWS - EC2 Instance](#aws---ec2-instance)
  - [GCP - Compute Engine Instance](#gcp---compute-engine-instance)
  - [Azure - Linux Virtual Machine](#azure---linux-virtual-machine)
  - [SSH key setup](#ssh-key-setup)
  - [Deploying](#deploying)
    - [Via GitHub Actions (recommended)](#via-github-actions-recommended)
    - [Locally](#locally)
      - [AWS](#aws)
      - [GCP](#gcp)
      - [Azure](#azure)
  - [Connecting to a VM](#connecting-to-a-vm)
    - [AWS (SSH)](#aws-ssh)
    - [GCP (SSH)](#gcp-ssh)
    - [Azure (SSH)](#azure-ssh)
    - [Summary of differences](#summary-of-differences)

## Introduction

Comparison of the virtual-machine example across all three clouds. Each module provisions the smallest, cheapest instance available on that cloud, along with the networking and security infrastructure required to reach it over SSH.

### What each example provisions

|                         | AWS                           | GCP                              | Azure                          |
| ----------------------- | ----------------------------- | -------------------------------- | ------------------------------ |
| **Module path**         | `aws/virtual-machine`         | `gcp/virtual-machine`            | `azure/virtual-machine`        |
| **Instance type**       | `t3.micro` (1 vCPU, 1 GB)     | `e2-micro` (1 vCPU shared, 1 GB) | `Standard_D2s_v3` (2 vCPU, 8 GB) |
| **Operating system**    | Amazon Linux 2023             | Debian 12                        | Ubuntu 22.04 LTS (gen2)        |
| **Network**             | VPC + public subnet           | Custom VPC + subnetwork          | VNet + subnet                  |
| **Firewall**            | Security Group (TCP 22)       | Firewall rule + network tag      | NSG inline rule (TCP 22)       |
| **Public IP**           | Auto-assigned via subnet flag | Reserved static regional address | Static Standard SKU public IP  |
| **SSH key attachment**  | `aws_key_pair` resource       | Instance metadata `ssh-keys`     | `admin_ssh_key` block on VM    |
| **Default SSH user**    | `ec2-user`                    | `debian`                         | `azureuser`                    |
| **Root disk**           | 8 GB gp3                      | 10 GB pd-standard                | Standard_LRS (OS disk default) |
| **Tagging / labelling** | `default_tags` on provider    | `labels` on resources            | `tags` on all resources        |

## Concepts and terminology

Virtual machines require more supporting infrastructure than object storage. Each cloud uses different names and models for the same underlying concepts. This section explains them side by side.

### Networking

All three modules create an isolated private network so the VM is not placed into a shared default network.

**AWS** uses a **VPC** (Virtual Private Cloud). A VPC is a logically isolated network. Within it you create **subnets** — slices of the VPC's address space bound to an availability zone. Traffic can only leave the subnet and reach the internet if the subnet has a **route table** pointing to an **Internet Gateway** (IGW). The IGW is a managed gateway attached to the VPC; without it, instances have no internet path regardless of whether they have a public IP.

**GCP** uses a **VPC network** that is global — a single VPC spans all regions. Within it you create **subnetworks** (subnets), which are regional. This module creates a custom-mode VPC (`auto_create_subnetworks = false`) so that subnets are only created where you explicitly define them, rather than GCP creating one in every region automatically. GCP VPC networks have internet access by default via Google's routing fabric; no separate internet gateway resource exists.

**Azure** uses a **Virtual Network (VNet)**, which is regional. Within it you create **subnets**. Unlike AWS, there is no separate internet gateway resource — outbound internet access is provided automatically for any VM that has a public IP attached to its network interface.

### Public IP addresses

**AWS** does not require a separate IP resource for the simplest case. Setting `map_public_ip_on_launch = true` on the subnet causes any instance launched there to automatically receive an ephemeral public IP. This is sufficient for a demo module — the IP changes if the instance is stopped and started, but for a minimal example that is acceptable.

**GCP** requires an explicit `google_compute_address` resource to reserve a static regional IP. Instances do not receive a public IP automatically; you must attach one via an `access_config` block in the `network_interface` section of the instance. A static address survives instance restarts and can be released and reused, which is why it is preferred over ephemeral addresses even in a demo.

**Azure** also requires an explicit `azurerm_public_ip` resource. It must be created before the network interface and then referenced in the NIC's `ip_configuration` block. The module uses `allocation_method = "Static"` with `sku = "Standard"` — the Standard SKU is required for availability zone support and is the recommended default for new deployments. The older Basic SKU is being retired.

### Firewall / security rules

Each cloud has a different model for controlling which traffic can reach an instance.

**AWS** uses **Security Groups**, which are stateful virtual firewalls attached to network interfaces (not subnets). Stateful means you only need to allow inbound traffic — the return traffic is automatically permitted. The module defines the security group with inline `ingress` and `egress` blocks. The egress rule allows all outbound traffic, which is the AWS default and necessary for the instance to reach package repositories.

**GCP** uses **Firewall rules** applied at the VPC network level, not per-instance. To target specific instances rather than all VMs in the network, firewall rules use **network tags** — labels applied to instances. The module creates a firewall rule that allows TCP 22 from anywhere, but only to instances tagged `ssh-enabled`. The instance is given that tag, making the rule apply to it while leaving any other instances in the VPC unaffected.

**Azure** uses **Network Security Groups (NSGs)**, which are stateful like AWS security groups. An NSG contains a list of security rules with priorities — lower numbers are evaluated first. The module defines an NSG with a single inbound rule for TCP 22 at priority 1001. The NSG is associated at the NIC level (via `azurerm_network_interface_security_group_association`) rather than the subnet level, which is more granular and appropriate for a single-VM module.

### SSH key injection

All three clouds support SSH key-based authentication, but the mechanism for attaching a public key differs significantly.

**AWS** has a first-class **Key Pair** resource (`aws_key_pair`). You register a public key with AWS once, and it is stored regionally. When launching an instance, you reference the key pair by name. AWS injects the public key into the instance's `~/.ssh/authorized_keys` during first boot via the instance metadata service, handled by the `cloud-init` agent present in all official AMIs.

**GCP** does not have a separate key pair resource. Instead, the public key is passed directly in the instance's **metadata** under the key `ssh-keys`. The format is `username:ssh-rsa AAAA...`, where the username determines which user account the key is added to. GCP's guest agent reads this metadata and updates `authorized_keys` accordingly. This means the key is tied to the instance definition, not a reusable registered resource.

**Azure** attaches the public key via an `admin_ssh_key` block directly on the `azurerm_linux_virtual_machine` resource. You specify the username and public key together. When `disable_password_authentication = true` is set (which is required when using `admin_ssh_key` in provider version 4.x), password login is disabled entirely and SSH key authentication is the only method.

In all three modules the public key material comes from the `ssh_public_key` variable, which is injected at deploy time via `TF_VAR_ssh_public_key`. No key material is generated by Terraform or stored in state.

### Machine images

Each cloud resolves the base operating system image differently.

**AWS** uses **AMIs** (Amazon Machine Images). AMIs are region-specific and identified by an ID that changes with every release. Hardcoding an AMI ID would mean the module becomes stale. Instead, a `data "aws_ami"` source dynamically resolves the latest Amazon Linux 2023 HVM image at plan time, filtering by name pattern (`al2023-ami-*-x86_64`), architecture, and virtualisation type. The `owners = ["amazon"]` guard ensures only AWS-published images are considered.

**GCP** uses **Compute Engine images** grouped into **image families**. A family always points to the latest non-deprecated image in that series. The `data "google_compute_image"` source with `family = "debian-12"` and `project = "debian-cloud"` resolves to the current Debian 12 image at plan time. This is the idiomatic GCP approach — no version pinning is needed because the family pointer is maintained by the OS publisher.

**Azure** references images via a publisher/offer/SKU/version tuple in the `source_image_reference` block. Setting `version = "latest"` tells the Azure platform to resolve the most recent image in that SKU at deployment time. The Ubuntu 22.04 LTS offer from Canonical is `0001-com-ubuntu-server-jammy` (Canonical restructured their Azure publishing in 2022; this is the current offer name). The `22_04-lts-gen2` SKU selects the Generation 2 variant, which supports Secure Boot and modern VM features.

## AWS - EC2 Instance

**Required variables:**

- `ssh_public_key` — OpenSSH public key string (injected via `TF_VAR_ssh_public_key` in CI)

**Optional variables (all have defaults):**

- `region` — defaults to `eu-west-2`
- `instance_type` — defaults to `t3.micro`
- `vpc_cidr` — defaults to `10.0.0.0/16`
- `subnet_cidr` — defaults to `10.0.1.0/24`
- `name_prefix` — defaults to `tf-public-cloud-vm`
- `tags` — passed to the provider `default_tags` block

**Key design decisions:**

- The public subnet has `map_public_ip_on_launch = true`, so no separate Elastic IP resource is needed
- The availability zone is pinned to `{region}a` to avoid introducing a variable; for a demo module a single AZ is sufficient
- The AMI is resolved at plan time via a data source — no hardcoded AMI ID
- The root volume uses `gp3` (the current-generation SSD type) with `delete_on_termination = true` to avoid orphaned EBS volumes after `terraform destroy`
- The security group uses inline `ingress`/`egress` blocks rather than separate `aws_security_group_rule` resources, keeping the module self-contained

## GCP - Compute Engine Instance

**Required variables:**

- `project` — GCP project ID
- `ssh_public_key` — OpenSSH public key string (injected via `TF_VAR_ssh_public_key` in CI)

**Optional variables (all have defaults):**

- `region` — defaults to `europe-west2`
- `zone` — defaults to `europe-west2-a`
- `machine_type` — defaults to `e2-micro`
- `network_cidr` — defaults to `10.0.0.0/16`
- `name_prefix` — defaults to `tf-public-cloud-vm`
- `labels` — applied to the instance

**Key design decisions:**

- The VPC is created in custom mode (`auto_create_subnetworks = false`) to avoid GCP creating subnets in every region automatically
- A reserved `google_compute_address` is used rather than an ephemeral IP, giving a stable address that survives instance restarts
- SSH access is scoped to tagged instances via `target_tags = ["ssh-enabled"]` on the firewall rule, rather than opening SSH to the entire VPC
- The boot disk uses `pd-standard` (magnetic) rather than `pd-ssd` to minimise cost for a demo instance; the image is resolved dynamically via the `debian-12` image family

## Azure - Linux Virtual Machine

**Required variables:**

- `subscription_id` — Azure subscription ID (injected via `TF_VAR_subscription_id` in CI)
- `ssh_public_key` — OpenSSH public key string (injected via `TF_VAR_ssh_public_key` in CI)

**Optional variables (all have defaults):**

- `location` — defaults to `westeurope`
- `vm_size` — defaults to `Standard_D2s_v3`
- `admin_username` — defaults to `azureuser`
- `address_space` — defaults to `10.0.0.0/16`
- `subnet_prefix` — defaults to `10.0.1.0/24`
- `name_prefix` — defaults to `tfpubcloudvm` (kept short due to Azure naming length limits)
- `resource_group_name` — defaults to `rg-tf-public-cloud-vm`
- `tags` — applied to all resources

**Key design decisions:**

- The resource group must exist before any other Azure resource can be created; it is therefore the first resource in `main.tf`
- `resource_provider_registrations = "none"` on the provider avoids requiring subscription-level write access in CI
- The NSG is associated at the NIC level (`azurerm_network_interface_security_group_association`) rather than the subnet level, keeping the security scope to this single VM
- `disable_password_authentication = true` is required by the AzureRM 4.x provider when `admin_ssh_key` is set
- `depends_on = [azurerm_network_interface_security_group_association.this]` on the VM ensures the NSG is fully attached before the instance boots
- The public IP uses `sku = "Standard"` with `allocation_method = "Static"` — Standard SKU is the current recommended default; Basic SKU is being retired

## SSH key setup

The modules do not generate SSH keys. You supply a pre-existing public key, which keeps key material out of Terraform state entirely.

Run the setup script once before deploying:

```sh
bash scripts/generate-ssh-key.sh
```

This generates an RSA 4096-bit key pair at `~/.ssh/vm_deploy_key`, base64-encodes the public key, and stores it as a GitHub Actions variable (`SSH_PUBLIC_KEY`). CI picks it up automatically via the `load-tf-vars` action. For local use, pass the public key directly:

```sh
terraform plan -var="ssh_public_key=$(cat ~/.ssh/vm_deploy_key.pub)"
```

## Deploying

### Via GitHub Actions (recommended)

Use the `Deploy Resource` workflow — no local credentials needed:

```sh
# Plan all clouds
gh workflow run plan-resource.yml \
  --ref virtual-machines \
  --field resource_type=virtual-machine \
  --field cloud=all

# Apply all clouds
gh workflow run apply-resource.yml \
  --ref virtual-machines \
  --field resource_type=virtual-machine \
  --field cloud=all \
  --field action=apply

# Destroy all clouds
gh workflow run apply-resource.yml \
  --ref virtual-machines \
  --field resource_type=virtual-machine \
  --field cloud=all \
  --field action=destroy

# Watch the run
gh run watch
```

You can also target a single cloud by passing `--field cloud=aws` (or `gcp` / `azure`).

### Locally

The `ssh_public_key` variable has no default and must always be supplied. Run from the repo root.

#### AWS

```sh
terraform -chdir=aws/virtual-machine init
terraform -chdir=aws/virtual-machine apply \
  -var="ssh_public_key=$(cat ~/.ssh/vm_deploy_key.pub)"
```

#### GCP

```sh
terraform -chdir=gcp/virtual-machine init
terraform -chdir=gcp/virtual-machine apply \
  -var="project=<your-gcp-project-id>" \
  -var="ssh_public_key=$(cat ~/.ssh/vm_deploy_key.pub)"
```

#### Azure

`subscription_id` must also be supplied:

```sh
export TF_VAR_subscription_id=<your-subscription-id>
export ARM_SUBSCRIPTION_ID=<your-subscription-id>
terraform -chdir=azure/virtual-machine init
terraform -chdir=azure/virtual-machine apply \
  -var="ssh_public_key=$(cat ~/.ssh/vm_deploy_key.pub)"
```

## Connecting to a VM

After a successful apply, use the helper scripts in `scripts/examples/` to connect and verify the VM is healthy. Each script takes the public IP and private key path, then prints the root directory listing, hostname, and OS release before exiting.

### AWS (SSH)

```sh
IP=$(terraform -chdir=aws/virtual-machine output -raw public_ip)
./scripts/examples/virtual-machine-aws.sh "$IP" ~/.ssh/vm_deploy_key
```

<details>
<summary>Example AWS output</summary>

```terminaloutput
==> Connecting to ec2-user@18.132.97.48
==> Root directory listing
Warning: Permanently added '18.132.97.48' (ED25519) to the list of known hosts.
total 32
dr-xr-xr-x.  18 root root   237 Jun 11 01:49 .
dr-xr-xr-x.  18 root root   237 Jun 11 01:49 ..
lrwxrwxrwx.   1 root root     7 Jan 30  2023 bin -> usr/bin
dr-xr-xr-x.   5 root root 16384 Jun 11 01:50 boot
drwxr-xr-x.  14 root root  3100 Jun 14 10:45 dev
drwxr-xr-x.  59 root root 16384 Jun 14 10:45 etc
drwxr-xr-x.   3 root root    22 Jun 14 10:45 home
lrwxrwxrwx.   1 root root     7 Jan 30  2023 lib -> usr/lib
lrwxrwxrwx.   1 root root     9 Jan 30  2023 lib64 -> usr/lib64
drwxr-xr-x.   2 root root     6 Jun 11 01:49 local
drwxr-xr-x.   2 root root     6 Jan 30  2023 media
drwxr-xr-x.   2 root root     6 Jan 30  2023 mnt
drwxr-xr-x.   2 root root     6 Jan 30  2023 opt
dr-xr-xr-x. 154 root root     0 Jun 14 10:45 proc
dr-xr-x---.   3 root root   103 Jun 11 01:50 root
drwxr-xr-x.  25 root root   640 Jun 14 10:46 run
lrwxrwxrwx.   1 root root     8 Jan 30  2023 sbin -> usr/sbin
drwxr-xr-x.   2 root root     6 Jan 30  2023 srv
dr-xr-xr-x.  13 root root     0 Jun 14 10:45 sys
drwxrwxrwt.  11 root root   220 Jun 14 12:37 tmp
drwxr-xr-x.  12 root root   144 Jun 11 01:49 usr
drwxr-xr-x.  18 root root   251 Jun 14 10:45 var
==> Hostname
ip-10-0-1-68.eu-west-2.compute.internal
==> OS release
PRETTY_NAME="Amazon Linux 2023.12.20260611"
==> Done
```

</details>

### GCP (SSH)

```sh
IP=$(terraform -chdir=gcp/virtual-machine output -raw public_ip)
./scripts/examples/virtual-machine-gcp.sh "$IP" ~/.ssh/vm_deploy_key
```

<details>
<summary>Example GCP output</summary>

```terminaloutput
==> Connecting to debian@34.105.247.227
==> Root directory listing
Warning: Permanently added '34.105.247.227' (ED25519) to the list of known hosts.
total 68
drwxr-xr-x  18 root root  4096 Jun 14 11:58 .
drwxr-xr-x  18 root root  4096 Jun 14 11:58 ..
lrwxrwxrwx   1 root root     7 Jun  9 15:05 bin -> usr/bin
drwxr-xr-x   4 root root  4096 Jun  9 15:08 boot
drwxr-xr-x  14 root root  3060 Jun 14 11:58 dev
drwxr-xr-x  76 root root  4096 Jun 14 11:59 etc
drwxr-xr-x   3 root root  4096 Jun 14 11:59 home
lrwxrwxrwx   1 root root     7 Jun  9 15:05 lib -> usr/lib
lrwxrwxrwx   1 root root     9 Jun  9 15:05 lib64 -> usr/lib64
drwx------   2 root root 16384 Jun  9 15:04 lost+found
drwxr-xr-x   2 root root  4096 Jun  9 15:05 media
drwxr-xr-x   2 root root  4096 Jun  9 15:05 mnt
drwxr-xr-x   2 root root  4096 Jun  9 15:05 opt
dr-xr-xr-x 141 root root     0 Jun 14 11:58 proc
drwx------   3 root root  4096 Jun  9 15:07 root
drwxr-xr-x  23 root root   640 Jun 14 12:37 run
lrwxrwxrwx   1 root root     8 Jun  9 15:05 sbin -> usr/sbin
drwxr-xr-x   2 root root  4096 Jun  9 15:05 srv
dr-xr-xr-x  13 root root     0 Jun 14 11:58 sys
drwxrwxrwt  10 root root  4096 Jun 14 11:59 tmp
drwxr-xr-x  12 root root  4096 Jun  9 15:05 usr
drwxr-xr-x  12 root root  4096 Jun  9 15:06 var
==> Hostname
tf-public-cloud-vm-76ac
==> OS release
PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
==> Done
```

</details>

### Azure (SSH)

```sh
IP=$(terraform -chdir=azure/virtual-machine output -raw public_ip)
./scripts/examples/virtual-machine-azure.sh "$IP" ~/.ssh/vm_deploy_key
```

<details>
<summary>Example Azure output</summary>

```terminaloutput
==> Connecting to azureuser@20.224.139.249
==> Root directory listing
Warning: Permanently added '20.224.139.249' (ED25519) to the list of known hosts.
total 72
drwxr-xr-x  19 root root  4096 Jun 14 12:26 .
drwxr-xr-x  19 root root  4096 Jun 14 12:26 ..
lrwxrwxrwx   1 root root     7 Jun 11 07:49 bin -> usr/bin
drwxr-xr-x   4 root root  4096 Jun 11 07:57 boot
drwxr-xr-x  17 root root  4040 Jun 14 12:26 dev
drwxr-xr-x  99 root root  4096 Jun 14 12:26 etc
drwxr-xr-x   3 root root  4096 Jun 14 12:26 home
lrwxrwxrwx   1 root root     7 Jun 11 07:49 lib -> usr/lib
lrwxrwxrwx   1 root root     9 Jun 11 07:49 lib32 -> usr/lib32
lrwxrwxrwx   1 root root     9 Jun 11 07:49 lib64 -> usr/lib64
lrwxrwxrwx   1 root root    10 Jun 11 07:49 libx32 -> usr/libx32
drwx------   2 root root 16384 Jun 11 07:53 lost+found
drwxr-xr-x   2 root root  4096 Jun 11 07:49 media
drwxr-xr-x   3 root root  4096 Jun 14 12:26 mnt
drwxr-xr-x   2 root root  4096 Jun 11 07:49 opt
dr-xr-xr-x 173 root root     0 Jun 14 12:26 proc
drwx------   4 root root  4096 Jun 14 12:26 root
drwxr-xr-x  27 root root   900 Jun 14 12:37 run
lrwxrwxrwx   1 root root     8 Jun 11 07:49 sbin -> usr/sbin
drwxr-xr-x   6 root root  4096 Jun 11 07:57 snap
drwxr-xr-x   2 root root  4096 Jun 11 07:49 srv
dr-xr-xr-x  12 root root     0 Jun 14 12:26 sys
drwxrwxrwt  11 root root  4096 Jun 14 12:32 tmp
drwxr-xr-x  14 root root  4096 Jun 11 07:49 usr
drwxr-xr-x  13 root root  4096 Jun 11 07:51 var
==> Hostname
tfpubcloudvm-8a90
==> OS release
PRETTY_NAME="Ubuntu 22.04.5 LTS"
==> Done
```

</details>

### Summary of differences

| Aspect               | AWS                                    | GCP                             | Azure                                   |
| -------------------- | -------------------------------------- | ------------------------------- | --------------------------------------- |
| **Default SSH user** | `ec2-user`                             | `debian`                        | `azureuser`                             |
| **IP stability**     | Ephemeral (changes on stop/start)      | Static (reserved address)       | Static (Standard SKU)                   |
| **Key registration** | Regional key pair resource             | Instance metadata               | Inline block on VM resource             |
| **Firewall scope**   | Per network interface (security group) | Per network tag (firewall rule) | Per NIC (NSG association)               |
| **Internet gateway** | Explicit IGW + route table required    | Implicit (GCP routing fabric)   | Implicit (auto with public IP)          |
| **Image resolution** | Data source with name filter           | Data source with image family   | `version = "latest"` in image reference |
