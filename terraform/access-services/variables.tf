variable "nat_resources_enabled" {
  description = "Controls whether the NAT Gateway and its Public IP are deployed."
  type        = bool
  default     = false
}

variable "nat_associations_enabled" {
  description = "Controls whether the NAT Gateway is associated with its Public IP and the PVE lab subnet."
  type        = bool
  default     = false
}

variable "bastion_public_ip_enabled" {
  description = "Controls whether the Azure Bastion Public IP is deployed."
  type        = bool
  default     = true
}

variable "bastion_host_enabled" {
  description = "Controls whether the Azure Bastion Host is deployed."
  type        = bool
  default     = true
}
