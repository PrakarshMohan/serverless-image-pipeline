# variables.tf
# Input values you can change without editing the rest of the code.

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1" # Mumbai — closest region to you in India
}

variable "project_name" {
  description = "Prefix used to name all resources in this project"
  type        = string
  default     = "img-pipeline"
}
