
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "0a800b44-8d19-4b08-ac0f-5d9c5ce2dcad"
}

variable "location" {
  description = "Azure region for LearningSteps resources"
  type        = string
  default     = "westeurope"
}

variable "resource_group_name" {
  description = "Resource group for LearningSteps"
  type        = string
  default     = "rg-learningsteps-dev"
}

resource "azurerm_resource_group" "learningsteps" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_virtual_network" "learningsteps" {
  name                = "vnet-learningsteps-dev"
  location            = azurerm_resource_group.learningsteps.location
  resource_group_name = azurerm_resource_group.learningsteps.name
  address_space       = ["10.20.0.0/16"]
}

resource "azurerm_subnet" "aks" {
  name                 = "snet-aks"
  resource_group_name  = azurerm_resource_group.learningsteps.name
  virtual_network_name = azurerm_virtual_network.learningsteps.name
  address_prefixes     = ["10.20.1.0/24"]
}

resource "azurerm_private_dns_zone" "postgres" {
  name                = "pg-learningsteps-dev.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.learningsteps.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "link-learningsteps-postgres"
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  resource_group_name   = azurerm_resource_group.learningsteps.name
  virtual_network_id    = azurerm_virtual_network.learningsteps.id
}

resource "azurerm_subnet" "database" {
  name                 = "snet-database"
  resource_group_name  = azurerm_resource_group.learningsteps.name
  virtual_network_name = azurerm_virtual_network.learningsteps.name
  address_prefixes     = ["10.20.2.0/24"]

  delegation {
    name = "postgresql-delegation"

    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"

      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}


resource "azurerm_kubernetes_cluster" "learningsteps" {
  name                = "aks-learningsteps-dev"
  location            = azurerm_resource_group.learningsteps.location
  resource_group_name = azurerm_resource_group.learningsteps.name
  dns_prefix          = "learningsteps-dev"

  default_node_pool {
    name           = "system"
    node_count     = 1
    vm_size        = "Standard_D2s_v6"
    vnet_subnet_id = azurerm_subnet.aks.id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    load_balancer_sku   = "standard"
  }

  role_based_access_control_enabled = true
}

variable "postgres_admin_password" {
  description = "Administrator password for PostgreSQL"
  type        = string
  sensitive   = true
}


resource "azurerm_postgresql_flexible_server" "learningsteps" {
  name                = "pg-learningsteps-dev-flxpostgresql"
  resource_group_name = azurerm_resource_group.learningsteps.name
  location            = azurerm_resource_group.learningsteps.location
  private_dns_zone_id = azurerm_private_dns_zone.postgres.id

  version    = "16"
  sku_name   = "B_Standard_B1ms"
  storage_mb = 32768

  delegated_subnet_id = azurerm_subnet.database.id

  public_network_access_enabled = false

  administrator_login    = "learningadmin"
  administrator_password = var.postgres_admin_password

  backup_retention_days = 7
}
