variable "nat_resources_enabled" {
  description = "Controls whether the NAT Gateway and its Public IP are deployed."
  type        = bool
  default     = true
}

variable "nat_associations_enabled" {
  description = "Controls whether the NAT Gateway is associated with its Public IP and the PVE lab subnet."
  type        = bool
  default     = false
}

variable "bastion_enabled" {
  description = "Controls whether Azure Bastion and its Public IP are deployed."
  type        = bool
  default     = true
}
