data "azurerm_resource_group" "lab" {
  name = "rg_snb_pve"
}

data "azurerm_virtual_network" "lab" {
  name                = "vnet_snb_pve"
  resource_group_name = data.azurerm_resource_group.lab.name
}

data "azurerm_subnet" "pve_lab" {
  name                 = "snet-pve-lab"
  virtual_network_name = data.azurerm_virtual_network.lab.name
  resource_group_name  = data.azurerm_resource_group.lab.name
}

data "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  virtual_network_name = data.azurerm_virtual_network.lab.name
  resource_group_name  = data.azurerm_resource_group.lab.name
}
