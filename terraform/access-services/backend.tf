terraform {
  backend "azurerm" {
    use_azuread_auth = true
    use_cli          = true

    subscription_id      = "57bc067e-192d-4109-93f9-993336ef639f"
    tenant_id            = "cdd918c4-c82a-45c9-87dd-395f50e7a680"
    resource_group_name  = "rg_snb_pve"
    storage_account_name = "stsnbpvetfstate"
    container_name       = "tfstate"
    key                  = "access-services.tfstate"
  }
}
