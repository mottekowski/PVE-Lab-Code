resource "azurerm_public_ip" "bastion" {
  count = var.bastion_enabled ? 1 : 0

  name                = "pip-bas-snb-pve"
  resource_group_name = data.azurerm_resource_group.lab.name
  location            = data.azurerm_resource_group.lab.location

  allocation_method       = "Static"
  sku                     = "Standard"
  sku_tier                = "Regional"
  ip_version              = "IPv4"
  idle_timeout_in_minutes = 4
  ddos_protection_mode    = "VirtualNetworkInherited"
}

resource "azurerm_bastion_host" "lab" {
  count = var.bastion_enabled ? 1 : 0

  name                = "vnet_snb_pve_bastion"
  resource_group_name = data.azurerm_resource_group.lab.name
  location            = data.azurerm_resource_group.lab.location

  sku                    = "Standard"
  scale_units            = 2
  copy_paste_enabled     = true
  file_copy_enabled      = false
  ip_connect_enabled     = false
  kerberos_enabled       = false
  shareable_link_enabled = false
  tunneling_enabled      = true

  ip_configuration {
    name                 = "IpConf"
    subnet_id            = data.azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }

  tags = {
    Customer = "SNB"
    Owner    = "Christoph Zink"
  }
}

