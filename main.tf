provider "vsphere" {
  user           = var.vsphere_user
  password       = var.vsphere_password
  vsphere_server = var.vsphere_server

  # If you have a self-signed cert
  allow_unverified_ssl = true
}

data "vsphere_datacenter" "dc" {
  name = "Labo"
}

data "vsphere_datastore" "datastore" {
  name          = "FreeNAS-FS"
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_resource_pool" "pool" {
  name          = "DRS-Cluster/Resources"
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network" {
  name          = "VM Network"
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_virtual_machine" "template" {
  name = "ubuntu-1804-tpl"
  datacenter_id = data.vsphere_datacenter.dc.id
}

resource "vsphere_folder" "folder" {
  path = "stijn-pieters"
  type = "vm"
  datacenter_id = data.vsphere_datacenter.dc.id
}

resource "vsphere_virtual_machine" "web" {
  name = "${var.hostname}-${count.index+1}"
  resource_pool_id = data.vsphere_resource_pool.pool.id
  datastore_id = data.vsphere_datastore.datastore.id
  guest_id = "ubuntu64Guest"
  folder = vsphere_folder.folder.path
  network_interface {
    network_id = data.vsphere_network.network.id
  }
  num_cpus = 1
  memory = 1024
  count = var.webserver_amount
  disk {
    label = "disk0"
    size = data.vsphere_virtual_machine.template.disks.0.size
    eagerly_scrub = data.vsphere_virtual_machine.template.disks.0.eagerly_scrub
    thin_provisioned = data.vsphere_virtual_machine.template.disks.0.thin_provisioned
  }
  clone {
    template_uuid = data.vsphere_virtual_machine.template.id

    customize {
      linux_options {
        host_name = "${var.hostname}-${count.index+1}"
        domain = "howest.local"
      }
      network_interface {}
    }
  }
  provisioner "remote-exec" {
    connection {
      type = "ssh"
      user = "student"
      password = "${var.vm_pass}"
      host = "vcenter.cloud2.local"
      port = lookup(var.internal_ips, self.default_ip_address)
    }
    inline = [
      "echo ${var.vm_pass} | sudo -S apt install && sudo apt upgrade -y",
      "sudo apt install nginx -y",
      "sudo sed -i 's/nginx/webstijn${count.index+0}/' /var/www/html/index.nginx-debian.html"
    ]
  }
}
resource "vsphere_virtual_machine" "lb" {
  name = "stijnpieters-loadbalancer"
  resource_pool_id = data.vsphere_resource_pool.pool.id
  datastore_id = data.vsphere_datastore.datastore.id
  guest_id = "ubuntu64Guest"
  folder = vsphere_folder.folder.path
  network_interface {
    network_id = data.vsphere_network.network.id
  }
  disk {
    label            = "disk0"
    size             = data.vsphere_virtual_machine.template.disks.0.size
    eagerly_scrub    = data.vsphere_virtual_machine.template.disks.0.eagerly_scrub
    thin_provisioned = data.vsphere_virtual_machine.template.disks.0.thin_provisioned
  }
  clone {
    template_uuid = data.vsphere_virtual_machine.template.id

    customize {
      linux_options {
        host_name = "stijnpieters-loadbalancer"
        domain = "howest.local"
      }
      network_interface {}
    }
  }
  provisioner "file" {
    connection {
      type     = "ssh"
      user     = "student"
      password = "${var.vm_pass}"
      host     = "vcenter.cloud2.local"
      port = lookup(var.internal_ips, self.default_ip_address)
    }
    content = templatefile("${path.cwd}/nginx_ldb.tmpl" , {ip_addrs=vsphere_virtual_machine.web[*].default_ip_address})
    destination = "/home/student/load-balancer.conf"
  }
  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      user     = "student"
      password = "${var.vm_pass}"
      host     = "vcenter.cloud2.local"
      port = lookup(var.internal_ips, self.default_ip_address)
    }
    inline = [
      "echo ${var.vm_pass} | sudo -S apt update && sudo apt upgrade -y",
      "sudo apt install nginx -y",
      "echo ${var.vm_pass} | sudo -S cp /home/student/load-balancer.conf /etc/nginx/conf.d/load-balancer.conf",
      "echo ${var.vm_pass} | sudo -S rm /etc/nginx/sites-enabled/default",
      "sudo systemctl restart nginx"
    ]
  }
}




#resource "<PROVIDER>_<TYPE>" "<NAME>" {
# [CONFIG …]
#}
