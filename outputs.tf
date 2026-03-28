# outputs - printed in terminal after terraform successfully deploys infrastructure

# bastion host public IP - what you'll use to SSH into the bastion
output "bastion_public_ip" {
  description = "Public IP address of the bastion host"
  value       = aws_instance.bastion.public_ip  # grabs public IP from bastion EC2 resource
}

# private EC2 private IP - what you'll use to SSH from bastion to private EC2
output "private_ec2_private_ip" {
  description = "Private IP address of the private EC2"
  value       = aws_instance.private.private_ip  # grabs private IP from private EC2 resource
}

/*
  output blocks - tell Terraform what information to print after a successful deploy
  value - references a resource attribute, same dot notation we used throughout main.tf
  public_ip - the internet facing IP of the bastion, this is what you'll SSH into
  private_ip - the internal VPC IP of the private EC2, only reachable from inside the VPC

  after terraform apply runs successfully you'll see something like:
  bastion_public_ip = "54.123.45.67"
  private_ec2_private_ip = "10.0.2.45"
*/