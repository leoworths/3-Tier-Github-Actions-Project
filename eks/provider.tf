provider "aws" {
  region = local.region

}
data "aws_availability_zones" "available" {}


locals {
  region          = "us-east-1"
  name            = "devops-cluster"
  azs             = data.aws_availability_zones.available.names
  vpc_cidr        = "10.1.0.0/16"
  private_subnets = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
  public_subnets  = ["10.1.4.0/24", "10.1.5.0/24", "10.1.6.0/24"]
  intra_subnets   = ["10.1.7.0/24", "10.1.8.0/24", "10.1.9.0/24"]

  tags = {
    Name = local.name
  }
}
