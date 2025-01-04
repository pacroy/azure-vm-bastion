terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.14.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.3"
    }
  }
  required_version = "~> 1.3"
}

provider "azurerm" {
  resource_provider_registrations = "none"
  features {}
}

provider "random" {}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type    = string
  default = ""
}

variable "suffix" {
  type = string
}

variable "bastion" {
  type    = bool
  default = true
}

module "naming" {
  source  = "Azure/naming/azurerm"
  version = "~> 0.4.2"
  suffix  = [var.suffix]
}

data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

data "azurerm_client_config" "main" {
}

resource "random_integer" "byte_2" {
  min = 0
  max = 255
}

resource "random_password" "password" {
  length  = 24
  special = true
}

locals {
  vnet_cidr = "10.${random_integer.byte_2.result}.0.0/16"
  location  = coalesce(var.location, data.azurerm_resource_group.main.location)
}

resource "azurerm_virtual_network" "main" {
  address_space       = [local.vnet_cidr]
  location            = local.location
  name                = module.naming.virtual_network.name
  resource_group_name = data.azurerm_resource_group.main.name

  subnet {
    address_prefix = cidrsubnet(local.vnet_cidr, 8, 1)
    name           = "AzureBastionSubnet"
    security_group = azurerm_network_security_group.bastion.id
  }

  subnet {
    address_prefix = cidrsubnet(local.vnet_cidr, 8, 0)
    name           = "default"
    security_group = azurerm_network_security_group.default.id
  }

}

resource "azurerm_network_security_group" "bastion" {
  location            = local.location
  name                = "${module.naming.network_security_group.name}-bastion"
  resource_group_name = data.azurerm_resource_group.main.name

  security_rule {
    access                     = "Allow"
    destination_address_prefix = "VirtualNetwork"
    destination_port_ranges    = ["22", "3389"]
    direction                  = "Outbound"
    name                       = "AllowSshRdpOutbound"
    priority                   = 100
    protocol                   = "*"
    source_address_prefix      = "*"
    source_port_range          = "*"
  }

  security_rule {
    access                     = "Allow"
    destination_address_prefix = "*"
    destination_port_range     = "443"
    direction                  = "Inbound"
    name                       = "AllowHTTPSInbound"
    priority                   = 100
    protocol                   = "Tcp"
    source_address_prefix      = "Internet"
    source_port_range          = "*"
  }

  security_rule {
    access                     = "Allow"
    destination_address_prefix = "*"
    destination_port_range     = "443"
    direction                  = "Inbound"
    name                       = "AllowGatewayManagerInbound"
    priority                   = 110
    protocol                   = "Tcp"
    source_address_prefix      = "GatewayManager"
    source_port_range          = "*"
  }

  security_rule {
    access                     = "Allow"
    destination_address_prefix = "AzureCloud"
    destination_port_range     = "443"
    direction                  = "Outbound"
    name                       = "AllowAzureCloudOutbound"
    priority                   = 110
    protocol                   = "Tcp"
    source_address_prefix      = "*"
    source_port_range          = "*"
  }

}

resource "azurerm_network_security_group" "default" {
  location            = local.location
  name                = "${module.naming.network_security_group.name}-default"
  resource_group_name = data.azurerm_resource_group.main.name
}

resource "azurerm_network_interface" "main" {
  enable_accelerated_networking = true

  ip_configuration {
    name                          = "ipconfig1"
    primary                       = true
    private_ip_address_allocation = "Dynamic"
    private_ip_address_version    = "IPv4"
    subnet_id                     = "${azurerm_virtual_network.main.id}/subnets/default"
  }

  location            = local.location
  name                = module.naming.network_interface.name
  resource_group_name = data.azurerm_resource_group.main.name
}

resource "azurerm_public_ip" "main" {
  allocation_method       = "Static"
  idle_timeout_in_minutes = 4
  ip_version              = "IPv4"
  location                = local.location
  name                    = module.naming.public_ip.name
  resource_group_name     = data.azurerm_resource_group.main.name
  sku                     = "Standard"
  sku_tier                = "Regional"
}

resource "azurerm_windows_virtual_machine" "main" {
  admin_password             = random_password.password.result
  admin_username             = "sysadmin"
  allow_extension_operations = true
  computer_name              = module.naming.windows_virtual_machine.name
  enable_automatic_updates   = true
  extensions_time_budget     = "PT1H30M"
  license_type               = "Windows_Client"
  location                   = local.location
  max_bid_price              = -1
  name                       = module.naming.windows_virtual_machine.name
  network_interface_ids      = [azurerm_network_interface.main.id]
  encryption_at_host_enabled = true

  os_disk {
    caching              = "ReadWrite"
    disk_size_gb         = 127
    name                 = "${module.naming.windows_virtual_machine.name}_osdisk"
    storage_account_type = "Premium_LRS"
  }

  patch_mode          = "AutomaticByOS"
  priority            = "Regular"
  provision_vm_agent  = true
  resource_group_name = data.azurerm_resource_group.main.name
  size                = "Standard_D4s_v3"

  source_image_reference {
    offer     = "windows-11"
    publisher = "microsoftwindowsdesktop"
    sku       = "win11-22h2-pro"
    version   = "latest"
  }

}

resource "azurerm_dev_test_global_vm_shutdown_schedule" "main" {
  virtual_machine_id = azurerm_windows_virtual_machine.main.id
  location           = local.location
  enabled            = true

  daily_recurrence_time = "0000"
  timezone              = "UTC"

  notification_settings {
    enabled = false
  }
}

resource "azurerm_bastion_host" "main" {
  count               = (var.bastion) ? 1 : 0
  name                = module.naming.bastion_host.name
  location            = local.location
  resource_group_name = data.azurerm_resource_group.main.name

  ip_configuration {
    name                 = "configuration"
    subnet_id            = "${azurerm_virtual_network.main.id}/subnets/AzureBastionSubnet"
    public_ip_address_id = azurerm_public_ip.main.id
  }
}

output "azurerm_client_id" {
  value = data.azurerm_client_config.main.client_id
}

output "azurerm_tenant_id" {
  value = data.azurerm_client_config.main.tenant_id
}

output "azurerm_subscription_id" {
  value = data.azurerm_client_config.main.subscription_id
}

output "resource_group_name" {
  value = var.resource_group_name
}

output "location" {
  value = var.location
}

output "suffix" {
  value = var.suffix
}

output "bastion" {
  value = var.bastion
}

output "vnet_cidr" {
  value = local.vnet_cidr
}

output "virtual_network" {
  value = azurerm_virtual_network.main
}

output "virtual_network_name" {
  value = azurerm_virtual_network.main.name
}

output "nsg_bastion" {
  value = azurerm_network_security_group.bastion
}

output "nsg_default" {
  value = azurerm_network_security_group.default
}

output "network_interface" {
  value = azurerm_network_interface.main
}

output "public_ip" {
  value = azurerm_public_ip.main
}

output "public_ip_name" {
  value = azurerm_public_ip.main.name
}

output "windows_virtual_machine" {
  value     = azurerm_windows_virtual_machine.main
  sensitive = true
}

output "windows_virtual_machine_name" {
  value = azurerm_windows_virtual_machine.main.name
}

output "windows_virtual_machine_admin_username" {
  value = azurerm_windows_virtual_machine.main.admin_username
}

output "windows_virtual_machine_admin_password" {
  value     = azurerm_windows_virtual_machine.main.admin_password
  sensitive = true
}

output "vm_shutdown_schedule" {
  value = azurerm_dev_test_global_vm_shutdown_schedule.main
}

output "bastion_host" {
  value = azurerm_bastion_host.main
}

output "azurerm_bastion_host_name" {
  value = module.naming.bastion_host.name
}
