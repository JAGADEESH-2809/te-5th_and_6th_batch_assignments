#!/bin/bash

# Update packages
yum update -y

# Install Apache Web Server
yum install -y httpd

# Start Apache Service
systemctl start httpd

# Enable Apache at boot
systemctl enable httpd

# Create Web Page
cat <<EOF > /var/www/html/index.html
<!DOCTYPE html>
<html>
<head>
    <title>Terraform Project 2</title>
</head>
<body>
    <h1>Terraform Project 2</h1>
    <h2>Multi-Environment Infrastructure</h2>
    <p>Apache Web Server is Running Successfully.</p>
    <p>Created by Jagadeesh</p>
</body>
</html>
EOF