variable "env" {
  description = "Environment name."
  type        = string
}

variable "tags" {
  description = "Tags to apply to the table."
  type        = map(string)
  default     = {}
}
