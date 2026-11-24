variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-2"
}

variable "key_name" {
  description = "Existing EC2 key pair name"
  type        = string
  default     = "saa-key"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "ui_cidr" {
  description = "Who may open the client web interface"
  type        = string
  default     = "0.0.0.0/0"
}

variable "server_port" {
  description = "Port the server container listens on"
  type        = number
  default     = 5000
}

variable "vpc_id" {
  description = "VPC ID to use when more than one saa-vpc exists"
  type        = string
  default     = ""
}

variable "server_instance_id" {
  description = "Server instance ID to use when more than one saa-server exists"
  type        = string
  default     = ""
}

variable "repo_url" {
  description = "Client GitHub repository"
  type        = string
  default     = "https://github.com/Amin-0513/devops-capstone-client.git"
}
