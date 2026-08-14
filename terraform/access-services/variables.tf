variable "nat_gateway_enabled" {
  description = "Controls whether the NAT Gateway and its Public IP and associations are deployed."
  type        = bool
  default     = true
}

variable "bastion_enabled" {
  description = "Controls whether Azure Bastion and its Public IP are deployed."
  type        = bool
  default     = true
}
