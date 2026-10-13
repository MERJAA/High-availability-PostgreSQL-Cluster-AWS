terraform {
  backend "s3" {
    bucket       = "patroni-tf-state-my-name-12345" 
    key          = "database/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true   # <--- THE NEW MODERN STANDARD
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_region" "current" {}