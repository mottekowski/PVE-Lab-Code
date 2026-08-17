resource "azurerm_public_ip" "nat" {
  count = var.nat_public_ip_enabled ? 1 : 0

  name                = "pip-nat-snb-pve"
  resource_group_name = data.azurerm_resource_group.lab.name
  location            = data.azurerm_resource_group.lab.location

  allocation_method       = "Static"
  sku                     = "Standard"
  sku_tier                = "Regional"
  ip_version              = "IPv4"
  idle_timeout_in_minutes = 4
  ddos_protection_mode    = "VirtualNetworkInherited"

  tags = {
    Customer = "SNB"
    Owner    = "Christoph Zink"
  }
}

resource "azurerm_nat_gateway" "lab" {
  count = var.nat_resources_enabled ? 1 : 0

  name                = "nat-snb-pve"
  resource_group_name = data.azurerm_resource_group.lab.name
  location            = data.azurerm_resource_group.lab.location

  sku_name                = "Standard"
  idle_timeout_in_minutes = 4

  tags = {
    Customer = "SNB"
    Owner    = "Christoph Zink"
  }
}

resource "azurerm_nat_gateway_public_ip_association" "lab" {
  count = var.nat_public_ip_enabled && var.nat_resources_enabled && var.nat_associations_enabled ? 1 : 0

  nat_gateway_id       = azurerm_nat_gateway.lab[0].id
  public_ip_address_id = azurerm_public_ip.nat[0].id
}

resource "azurerm_subnet_nat_gateway_association" "pve_lab" {
  count = var.nat_resources_enabled && var.nat_associations_enabled ? 1 : 0

  subnet_id      = data.azurerm_subnet.pve_lab.id
  nat_gateway_id = azurerm_nat_gateway.lab[0].id
}
