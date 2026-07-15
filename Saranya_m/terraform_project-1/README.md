# Project 1 - 2 Tier Web Application on AWS using Terraform

## Infrastructure

- VPC
- Public Subnet
- Private Subnet
- Internet Gateway
- Route Table
- Web Security Group
- Database Security Group
- EC2 Web Server
- EC2 Database Server
- Elastic IP
- Remote Backend (S3)

## Prerequisites

- Terraform
- AWS CLI
- AWS Account

## Configure AWS

```bash
aws configure
```

## Initialize

```bash
terraform init
```

## Validate

```bash
terraform validate
```

## Format

```bash
terraform fmt
```

## Plan

```bash
terraform plan
```

## Deploy

```bash
terraform apply
```

## Outputs

- VPC ID
- Web Public IP
- Web URL
- Database Private IP

## Destroy

```bash
terraform destroy
```