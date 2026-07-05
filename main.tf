# main.tf
# Tells Terraform which version to use and which provider plugins to download.

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configures the AWS provider: which region to deploy in, plus a set of tags
# that get attached automatically to every resource we create (handy for
# tracking cost and knowing what Terraform owns).
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "Terraform"
    }
  }
}
