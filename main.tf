terraform {
  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "3.0.2-rc07"
    }
  }
}

provider "proxmox" {
  pm_api_url      = "https://10.20.10.11:8006/api2/json"
  pm_user         = "root@pam"
  pm_password     = "Merc1234!"
  pm_tls_insecure = true
}

# Path to your template in Proxmox storage
variable "template_vm" {
  default = "Ubuntu-Cloudinit"  # replace with your template name
}

locals {
  vms = {
    zabbix = {
      name    = "Zabbix"
      node    = "proxmox-node1"
      cores   = 2
      sockets = 1
      memory  = 2048
      disk    = 20
      ip      = "10.20.10.101"
    }

    CA-Server = {
      name    = "CA-Server"
      node    = "proxmox-node2"
      cores   = 2
      sockets = 1
      memory  = 1024
      disk    = 20
      ip      = "10.20.10.102"
    }
    
    Passbolt = {
      name    = "Passbolt"
      node    = "proxmox-node2"
      cores   = 2
      sockets = 1
      memory  = 4096
      disk    = 20
      ip      = "10.20.10.116"
    }

    PXE = {
      name    = "PXE"
      node    = "proxmox-node3"
      cores   = 2
      sockets = 1
      memory  = 2048
      disk    = 20
      ip      = "10.20.10.117"
    }

    ipam = {
      name    = "IPAM"
      node    = "proxmox-node3"
      cores   = 2
      sockets = 1
      memory  = 2048
      disk    = 20
      ip      = "10.20.10.103"
    }
    
    ntp = {
      name    = "NTP"
      node    = "proxmox-node2"
      cores   = 1
      sockets = 1
      memory  = 512
      disk    = 20
      ip      = "10.20.10.108"
    }

    
    graylog = {
      name    = "Graylog"
      node    = "proxmox-node3"
      cores   = 4
      sockets = 1
      memory  = 8192
      disk    = 30
      ip      = "10.20.10.109"
    }
    
    nginx = {
      name    = "Nginx"
      node    = "proxmox-node1"
      cores   = 1
      sockets = 1
      memory  = 1024
      disk    = 20
      ip      = "10.20.10.110"
    }

    bind9 = {
      name    = "Bind9"
      node    = "proxmox-node2"
      cores   = 1
      sockets = 1
      memory  = 2048
      disk    = 20
      ip      = "10.20.10.111"
    }

    bind9-slave = {
      name    = "Bind9-slave"
      node    = "proxmox-node3"
      cores   = 1
      sockets = 1
      memory  = 2048
      disk    = 20
      ip      = "10.20.10.112"
    }

    Webmin-ReverseProxy = {
      name    = "Webmin-ReverseProxy"
      node    = "proxmox-node1"
      cores   = 1
      sockets = 1
      memory  = 2048
      disk    = 20
      ip      = "10.20.10.115"
    }
  }
}


# Create one VM per cluster node
resource "proxmox_vm_qemu" "cluster_vm" {
  for_each    = local.vms

  name        = each.value.name
  target_node = each.value.node
  clone       = var.template_vm
  os_type     = "cloud-init"
  memory      = each.value.memory
  agent       = 1  # QEMU Guest Agent enabled
  bios        = "ovmf"
  scsihw      = "virtio-scsi-single"
  
  serial {
    id    = 0
    type  = "socket"
}

  cpu {
  cores   = each.value.cores
  sockets = each.value.sockets
}
  ciuser      = "user"
  cipassword  = "Merc1234!"
  sshkeys = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMlvvKOomyk2/3p5F1a6awr7iaRNxgMDkk89bRHY65xJ bhh@BHHMOBIL\nssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMVbWqrmcCOKr8e8u8woUQHnR1x6OU3XA3VVN8JR/AA5 klar@LAPTOP-84VRJEAS\nssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIONl6CkVTNAV6HHunlM1YEoGmApkK/NAPj9Sax+uOP3i gustav.dam@baettr.com\nssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAU9IPgbDuopi804RdSSZq4OfW7Xkfz/h9Gh5g7Iav9/ user@Automation01"
  
  provisioner "remote-exec" {
    inline = [
      # 1. Set the OS timezone to Copenhagen (fixes the UTC issue)
      "sudo timedatectl set-timezone Europe/Copenhagen",

      # 2. Check if the service exists and update the NTP server IP
      "if systemctl list-unit-files | grep -q systemd-timesyncd.service; then sudo sed -i 's/#NTP=/NTP=10.20.10.108 /' /etc/systemd/timesyncd.conf; fi",

      # 3. RESTART the service to force synchronization (fixes 'System clock synchronized: no')
      "if systemctl list-unit-files | grep -q systemd-timesyncd.service; then sudo systemctl restart systemd-timesyncd; else echo 'Skipping restart - service not found'; fi",

      # 4. Optional: Provide a quick status in the Terraform log
      "timedatectl status | grep 'synchronized' || true"
    ]

    connection {
      type     = "ssh"
      user     = "user" # Skift til din template bruger
      private_key = file("/home/user/.ssh/id_ed25519")
      host     = each.value.ip
    }
  }

  ipconfig0 = "ip=${each.value.ip}/24,gw=10.20.10.1"
  
  # Conditional DNS for Bind9 servers only
  nameserver  = each.key == "bind9" || each.key == "bind9-slave" ? "8.8.8.8 8.8.4.4" : "10.20.10.111 10.20.10.112"
  searchdomain = "dk-prod.lan"

  disk {
    slot    = "ide2"
    type    = "cloudinit"
    storage = "nvme"
}
  
  disk {
    slot    = "scsi0"
    size    = "${each.value.disk}G"
    type    = "disk"
    storage = "nvme"
    format  = "raw"
  }

  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
  }

  lifecycle {
  ignore_changes = [
    startup_shutdown,
    disk[0].format,
    disk[1].format,
    qemu_os
    ]
  }
}

# Outputs for Ansible / Semaphore
output "vm_names" {
  value = [for vm in proxmox_vm_qemu.cluster_vm : vm.name]
}

output "vm_nodes" {
  value = [for vm in proxmox_vm_qemu.cluster_vm : vm.target_node]
}
