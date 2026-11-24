# DevOps Capstone: File Transfer Client

This is the client side of the capstone project. It runs in a Docker container, connects to the server container, receives a file, saves it to the `/clientdata` directory and checks that the file was not changed in transit by comparing SHA-256 checksums.

The client has a web interface built with Streamlit, available at `http://localhost:8501`.

## Features

- Connects to the server over TCP (`server:5000` by default)
- Receives the file together with a JSON header holding the file name, size and checksum
- Saves each received file to `/clientdata` with a timestamp, so earlier files are kept
- Calculates the SHA-256 checksum of the received file and compares it with the server's checksum
- Lists every file stored in the `clientvol` volume

## Project Structure

```
devops-capstone-client/
├── app.py               # Client application (Python + Streamlit)
├── Dockerfile           # Builds the client image
├── docker-compose.yml   # Defines and runs the client container
├── requirements.txt     # Python dependencies
├── images/              # Screenshots
└── README.md
```

## Dockerfile

The image is based on the official `python:3.12-slim` image. It installs the dependencies, copies in the application and declares `/clientdata` as a volume.

```dockerfile
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# Volume mount point
RUN mkdir -p /clientdata
VOLUME ["/clientdata"]

# Streamlit default port
EXPOSE 8501

CMD ["streamlit", "run", "app.py", "--server.port=8501", "--server.address=0.0.0.0", "--browser.gatherUsageStats=false"]
```

## Docker Compose

The Compose file builds the client, mounts the named volume `clientvol` at `/clientdata` and connects the container to the shared `filenet` network so it can reach the server.

```yaml
services:
  client:
    build: .
    container_name: client
    ports:
      - "8501:8501"
    environment:
      - SERVER_HOST=${SERVER_HOST:-server}
      - SERVER_PORT=${SERVER_PORT:-5000}
    volumes:
      - clientvol:/clientdata
    networks:
      - filenet
    restart: unless-stopped

volumes:
  clientvol:
    name: clientvol

networks:
  filenet:
    external: true
```

## Requirements

```
streamlit==1.39.0
```

## How the Transfer Works

1. The client opens a TCP connection to the server.
2. The server sends one line of JSON followed by the file bytes:
   ```json
   {"filename": "file.txt", "size": 1024, "checksum": "<sha256-hex>"}
   ```
3. The client reads bytes until it has received `size` bytes.
4. The file is saved to `/clientdata/<name>_<timestamp><ext>`.
5. The client calculates the SHA-256 of the received bytes and compares it with `checksum`. It shows a success message if they match and an error if they do not.

## How to Run

### 1. Create the shared network (only if it does not exist yet)

```bash
docker network create filenet
```

### 2. Start the server container

Start the server project first, so that a container named `server` is listening on port 5000 on the `filenet` network.

### 3. Build and start the client

```bash
docker compose up -d --build
```

### 4. Open the client

Go to `http://localhost:8501` and click **Fetch file from server**.

### 5. Check the volume

```bash
docker exec client ls -l /clientdata
docker volume inspect clientvol
```

### 6. Stop the client

```bash
docker compose down
```

## Environment Variables

| Variable      | Default  | Description                  |
|---------------|----------|------------------------------|
| `SERVER_HOST` | `server` | Host name of the server      |
| `SERVER_PORT` | `5000`   | Port the server listens on   |

## Screenshots

### 1. Building and starting the client

Running `docker compose up -d --build` builds the image from `python:3.12-slim`, installs the dependencies, creates the `clientvol` volume and starts the `client` container.

![Building and starting the client](images/01.png)

### 2. Client web interface

The Streamlit interface at `localhost:8501`. The sidebar sets the server host (`server`) and port (`5000`). The table lists the files already saved in `/clientdata`.

![Client web interface](images/02.png)

### 3. File received and checksum verified

After you click **Fetch file from server**, the client receives a 1024-byte file and saves it to `/clientdata`. The expected and actual SHA-256 checksums match, which confirms the file is intact.

![File received and checksum verified](images/03.png)

### 4. Docker volumes

`docker volume ls` shows the `clientvol` volume used by the client, alongside the server's `servervol` volume.

![Docker volumes](images/04.png)

## Part 2: Creating VMs, Infra as a Code (IaC)

This part has 3 sub parts:

- **2a.** Create two AWS EC2 instances (VMs), one for hosting the server container and another for hosting the client container.
- **2b.** Configure the VPC and subnets appropriately to allow communication between the two EC2 instances. Use the t2.micro instance type, which is covered in the AWS free tier.
- **2c.** Use Terraform for infrastructure automation. Place your Terraform scripts in the "terraform" directory of your client and server GitHub repositories.

### 2a. Create Two EC2 Instances

Two EC2 instances are created in the `ap-southeast-2` (Sydney) region:

| Name         | Purpose                         | AMI                 | Instance type |
|--------------|---------------------------------|---------------------|---------------|
| `saa-server` | Hosts the server container      | Ubuntu 22.04 (x86)  | `t2.micro`    |
| `saa-client` | Hosts the client container      | Ubuntu 22.04 (x86)  | `t2.micro`    |

The server instance is created by the Terraform scripts in the server repository, and the client instance by the Terraform scripts in this repository (see 2c). The screenshots below show the same setup done manually in the AWS console.

#### Step 1: Name the instance and choose the AMI

In **EC2 > Instances > Launch an instance**, the instance is named `saa-client` and the **Ubuntu** AMI is selected from Quick Start.

![Name the instance and choose the AMI](AWS_qwen_image/client_01.jpg)

#### Step 2: Choose the instance type and key pair

The free tier eligible `t3.micro` instance type is selected (2 vCPU, 1 GiB memory), and the `saa-key` key pair is used for SSH access.

![Choose the instance type and key pair](AWS_qwen_image/client_02.jpg)

### 2b. Configure the VPC and Subnets

Both instances are placed in the same VPC and subnet, so they can reach each other over private IP addresses.

| Setting          | Value                                                        |
|------------------|--------------------------------------------------------------|
| VPC              | `saa-vpc` (`10.0.0.0/16`)                                    |
| Subnet           | `saa-public-subnet` (`10.0.1.0/24`) in `ap-southeast-2a`     |
| Internet access  | `saa-igw` internet gateway and `saa-public-rt` route table   |
| Auto-assign IP   | Enabled (public IP for SSH and the web interface)            |
| Security group   | `saa-sg`, shared by both instances: SSH, server port, and all traffic inside the VPC |
| Client SG        | `saa-client-sg`: port `8501` for the client web interface    |

The VPC, subnet, internet gateway and `saa-sg` are created by the server repository. Because `saa-sg` allows all traffic from `10.0.0.0/16`, the client reaches the server on its private IP.

#### Step 3: Select the VPC, subnet and security group

The instance is launched into `saa-vpc` and the public subnet in `ap-southeast-2a`, with auto-assign public IP enabled and the existing `saa-sg` security group attached.

![Select the VPC, subnet and security group](AWS_qwen_image/client_03.jpg)

#### Step 4: Launch the instance

After clicking **Launch instance**, AWS confirms that the client instance launched successfully.

![Instance launched successfully](AWS_qwen_image/client_04.jpg)

#### Step 5: Verify both instances are running

The Instances page shows `saa-server` and `saa-client` both in the **Running** state in the same availability zone (`ap-southeast-2a`).

![Both instances running](AWS_qwen_image/client_05.jpg)

### 2c. Terraform for Infrastructure Automation

The Terraform scripts are in the [terraform](terraform/) directory of this repository. The client scripts reuse the network created by the server repository, look up the server instance, and create the client EC2 instance.

```
terraform/
├── providers.tf          # Terraform settings and AWS provider
├── variables.tf          # Input variables
├── terraform.tfvars      # Values for the variables
├── main.tf               # Looks up the shared network and server, creates the client EC2
├── outputs.tf            # Client IPs, server private IP and client URL
└── user_data.sh.tftpl    # Startup script that installs Docker and runs the client
```

#### providers.tf

```hcl
terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}
```

#### variables.tf

```hcl
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
  default     = "t2.micro"
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

variable "repo_url" {
  description = "Client GitHub repository"
  type        = string
  default     = "https://github.com/Amin-0513/devops-capstone-client.git"
}
```

#### terraform.tfvars

```hcl
region        = "ap-southeast-2"
key_name      = "saa-key"
instance_type = "t2.micro"
server_port   = 5000
```

#### main.tf

```hcl
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

data "aws_vpc" "saa_vpc" {
  tags = { Name = "saa-vpc" }
}

data "aws_subnet" "saa_public_subnet" {
  vpc_id = data.aws_vpc.saa_vpc.id
  tags   = { Name = "saa-public-subnet" }
}

data "aws_security_group" "saa_sg" {
  vpc_id = data.aws_vpc.saa_vpc.id
  name   = "saa-sg"
}

data "aws_instance" "server" {
  filter {
    name   = "tag:Name"
    values = ["saa-server"]
  }
  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

resource "aws_security_group" "saa_client_sg" {
  name        = "saa-client-sg"
  description = "Client web interface"
  vpc_id      = data.aws_vpc.saa_vpc.id

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
```

#### outputs.tf

```hcl
output "client_public_ip" {
  value = aws_instance.client.public_ip
}

output "client_private_ip" {
  value = aws_instance.client.private_ip
}

output "server_private_ip" {
  description = "Server IP the client container connects to"
  value       = data.aws_instance.server.private_ip
}

output "client_url" {
  value = "http://${aws_instance.client.public_ip}:8501"
}
```

#### user_data.sh.tftpl

```bash
#!/bin/bash
apt-get update -y
apt-get install -y docker.io docker-compose-v2 git
systemctl enable --now docker
usermod -aG docker ubuntu

echo "SERVER_HOST=${server_ip}" >> /etc/environment
echo "SERVER_PORT=${server_port}" >> /etc/environment

git clone ${repo_url} /opt/client
cd /opt/client
docker network create filenet || true
SERVER_HOST=${server_ip} SERVER_PORT=${server_port} docker compose up -d --build
```

#### Step 6: Apply the server Terraform first

The client depends on the VPC, subnet, security group and server instance, so run `terraform apply` in the server repository's `terraform` directory first.

#### Step 7: Apply the client Terraform

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

When it finishes, Terraform prints `client_url`. Open it in a browser to use the client.

#### Step 8: Destroy the resources when finished

Destroy the client first, then the server, because the server owns the shared network.

```bash
terraform destroy
```

### Verification

The EC2 Instances page shows both VMs, `saa-server` and `saa-client`, in the **Running** state in the same availability zone (`ap-southeast-2a`). Each instance has its own public IPv4 DNS name, the server has passed all 3 status checks, and the EC2 service status is **Operating normally**.

![Verification of both EC2 instances](AWS_qwen_image/image.png)
