variable "env" {
  description = "Environment name (dev, test, prod). Used in resource names."
  type        = string
}

variable "tags" {
  description = "Common tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}
