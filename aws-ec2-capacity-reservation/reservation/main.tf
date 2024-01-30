terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}


variable "access-key-id" {
  sensitive   = true
  default = ""
}

variable "secret-access-key" {
  sensitive   = true
  default = ""
}

variable "instance-type" {
  default = ""
}
resource "aws_ec2_capacity_reservation" "default" {
  instance_type     = "g4dn.xlarge"
  instance_platform = "Linux/UNIX"
  availability_zone = "eu-central-1a"
  instance_count    = 1
}

output "reservation_id" {
  value = aws_ec2_capacity_reservation.default.id 
}
