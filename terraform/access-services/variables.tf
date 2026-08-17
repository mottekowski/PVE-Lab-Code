variable "nat_public_ip_enabled" {
  description = "Controls whether the NAT Gateway Public IP is deployed. Keep true for both ON and COLD states."
  type        = bool
  default     = true
}

variable "nat_resources_enabled" {
  description = "Controls whether the NAT Gateway is deployed."
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
  default     = false
}
