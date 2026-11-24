data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

data "aws_subnet" "saa_public_subnet" {
  vpc_id = var.vpc_id != "" ? var.vpc_id : null
  tags   = { Name = "saa-public-subnet" }
}

locals {
  vpc_id = data.aws_subnet.saa_public_subnet.vpc_id
}

data "aws_security_group" "saa_sg" {
  vpc_id = local.vpc_id
  name   = "saa-sg"
}

data "aws_instance" "server" {
  instance_id = var.server_instance_id != "" ? var.server_instance_id : null

  dynamic "filter" {
    for_each = var.server_instance_id == "" ? [1] : []
    content {
      name   = "tag:Name"
      values = ["saa-server"]
    }
  }

  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }

  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

resource "aws_security_group" "saa_client_sg" {
  name        = "saa-client-sg"
  description = "Client web interface"
  vpc_id      = local.vpc_id

  ingress {
    description = "Streamlit"
    from_port   = 8501
    to_port     = 8501
    protocol    = "tcp"
    cidr_blocks = [var.ui_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "saa-client-sg" }
}

resource "aws_instance" "client" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id     = data.aws_subnet.saa_public_subnet.id
  key_name      = var.key_name

  vpc_security_group_ids = [
    data.aws_security_group.saa_sg.id,
    aws_security_group.saa_client_sg.id,
  ]

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    server_ip   = data.aws_instance.server.private_ip
    server_port = var.server_port
    repo_url    = var.repo_url
  })

  tags = { Name = "saa-client" }
}
