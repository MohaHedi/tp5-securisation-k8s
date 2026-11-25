# TP 2 - Infrastructure as Code & élasticité (version corrigée après le scan Checkov du TP 5)
#
#   Internet ──► Load Balancer :80 ──► groupe élastique de VM (VMSS + autoscale)
#   Admin (IP autorisée) ──SSH──► VM d'administration

resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.prefixe}-tp2"
  location = var.region
}

# ---------- Réseau ----------
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${var.prefixe}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.20.0.0/16"]
}

resource "azurerm_subnet" "web" {
  name                 = "snet-web"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.20.1.0/24"]
}

resource "azurerm_network_security_group" "web" {
  name                = "nsg-web"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  # CORRECTION Checkov CKV_AZURE_10 : SSH limité à l'IP de l'administrateur (et plus "*")
  security_rule {
    name                       = "ssh-admin"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.ip_admin_autorisee
    destination_address_prefix = "*"
  }

  #checkov:skip=CKV_AZURE_160:Site web public : le port 80 doit être joignable depuis Internet via le load balancer.
  security_rule {
    name                       = "http-public"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "web" {
  subnet_id                 = azurerm_subnet.web.id
  network_security_group_id = azurerm_network_security_group.web.id
}

# ---------- VM d'administration ----------
resource "azurerm_public_ip" "admin" {
  name                = "pip-admin"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "admin" {
  #checkov:skip=CKV_AZURE_119:VM d'administration joignable en SSH, filtrée par le NSG sur l'IP de l'admin.
  name                = "nic-admin"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "interne"
    subnet_id                     = azurerm_subnet.web.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.admin.id
  }
}

resource "azurerm_linux_virtual_machine" "admin" {
  name                  = "vm-${var.prefixe}-admin"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  size                  = var.taille_vm
  admin_username        = var.admin_utilisateur
  network_interface_ids = [azurerm_network_interface.admin.id]

  # CORRECTION Checkov CKV_AZURE_149 / CKV_AZURE_178 : clé SSH uniquement, plus de mot de passe
  disable_password_authentication = true
  admin_ssh_key {
    username   = var.admin_utilisateur
    public_key = var.cle_ssh_publique
  }

  # CORRECTION Checkov CKV_AZURE_151 : disques chiffrés directement sur l'hôte
  encryption_at_host_enabled = true

  # CORRECTION Checkov CKV_AZURE_50 : aucune extension installée automatiquement
  allow_extension_operations = false

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}

# ---------- Élasticité : groupe de VM identiques derrière un load balancer ----------
resource "azurerm_public_ip" "lb" {
  name                = "pip-lb"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_lb" "web" {
  name                = "lb-web"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "public"
    public_ip_address_id = azurerm_public_ip.lb.id
  }
}

resource "azurerm_lb_backend_address_pool" "web" {
  name            = "pool-web"
  loadbalancer_id = azurerm_lb.web.id
}

resource "azurerm_lb_probe" "http" {
  name            = "sonde-http"
  loadbalancer_id = azurerm_lb.web.id
  protocol        = "Http"
  port            = 80
  request_path    = "/"
}

resource "azurerm_lb_rule" "http" {
  name                           = "regle-http"
  loadbalancer_id                = azurerm_lb.web.id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "public"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.web.id]
  probe_id                       = azurerm_lb_probe.http.id
  disable_outbound_snat          = true
}

resource "azurerm_linux_virtual_machine_scale_set" "web" {
  name                = "vmss-${var.prefixe}-web"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = var.taille_vm
  instances           = var.instances_min
  admin_username      = var.admin_utilisateur
  upgrade_mode        = "Automatic"
  custom_data         = base64encode(file("${path.module}/cloud-init.yaml"))

  # CORRECTION Checkov CKV_AZURE_49 : clé SSH uniquement
  disable_password_authentication = true
  admin_ssh_key {
    username   = var.admin_utilisateur
    public_key = var.cle_ssh_publique
  }

  # CORRECTION Checkov CKV_AZURE_97 : chiffrement sur l'hôte
  encryption_at_host_enabled = true

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  network_interface {
    name    = "nic-web"
    primary = true

    ip_configuration {
      name                                   = "interne"
      primary                                = true
      subnet_id                              = azurerm_subnet.web.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.web.id]
    }
  }

  depends_on = [azurerm_lb_rule.http]
}

# Règles d'élasticité : + 1 VM si CPU > 70 % pendant 5 min, - 1 VM si CPU < 25 % pendant 10 min
resource "azurerm_monitor_autoscale_setting" "web" {
  name                = "autoscale-web"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.web.id

  profile {
    name = "par-defaut"

    capacity {
      default = var.instances_min
      minimum = var.instances_min
      maximum = var.instances_max
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.web.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 70
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.web.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 25
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }
}
