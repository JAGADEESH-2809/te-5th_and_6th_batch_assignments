# Terraform Project 2 - Multi Environment Infrastructure Using Modules

## About This Project

In this project, I created a reusable AWS infrastructure using Terraform modules.

Instead of writing the same Terraform code multiple times, I created reusable modules for VPC, EC2 and S3. Then I used those modules to deploy separate Development and Production environments.

I also configured a remote backend using Amazon S3 and DynamoDB to store and lock the Terraform state file.

---

## Technologies Used

- Terraform
- AWS EC2
- AWS VPC
- Amazon S3
- Amazon DynamoDB
- Git & GitHub

---

## Project Structure

```
project-2/
│
├── modules/
│   ├── ec2/
│   ├── s3/
│   └── vpc/
│
├── environments/
│   ├── dev/
│   └── prod/
│
└── README.md
```

---

## Infrastructure Created

### VPC

- Custom VPC
- Public Subnet
- Private Subnet
- Internet Gateway
- Route Table

### Development Environment

- 1 EC2 Web Server
- Instance Type: t3.micro

### Production Environment

- 1 EC2 Web Server
- Instance Type: t3.small

### Security Group

- SSH (22) allowed only from my IP
- HTTP (80) allowed from anywhere

---

## Modules

### VPC Module

This module creates:

- VPC
- Public Subnet
- Private Subnet
- Internet Gateway
- Route Table

### EC2 Module

This module creates:

- Security Group
- EC2 Instance
- Apache Web Server using User Data

### S3 Module

This module creates:

- S3 Bucket
- DynamoDB Table

---

## Remote Backend

Terraform state files are stored in Amazon S3.

```
dev/terraform.tfstate

prod/terraform.tfstate
```

DynamoDB is used for state locking to prevent multiple users from updating the same state file at the same time.

---

## Variables Used

I used variables to avoid hardcoding values like:

- AWS Region
- Project Name
- Environment Name
- VPC CIDR
- Instance Type
- Key Pair
- Allowed SSH IP

I also added input validation for the instance type.

---

## Commands

### Initialize

```bash
terraform init
```

### Validate

```bash
terraform validate
```

### Plan

Development

```bash
terraform plan -var-file="dev.tfvars"
```

Production

```bash
terraform plan -var-file="prod.tfvars"
```

### Apply

Development

```bash
terraform apply -var-file="dev.tfvars"
```

Production

```bash
terraform apply -var-file="prod.tfvars"
```

### Destroy

Development

```bash
terraform destroy -var-file="dev.tfvars"
```

Production

```bash
terraform destroy -var-file="prod.tfvars"
```

---

## What I Learned

From this project, I learned:

- Terraform Modules
- Multi-Environment Infrastructure
- Remote Backend
- State Locking using DynamoDB
- Terraform Variables
- Input Validation
- Reusable Infrastructure
- AWS Networking

---

## Future Improvements

- Publish Terraform modules to GitHub and use Git source.
- Use Terraform Workspaces instead of separate folders.
- Add Auto Scaling Group and Load Balancer.

---

## Author

**Jagadeesh Surineni**

DevOps & Cloud Eng