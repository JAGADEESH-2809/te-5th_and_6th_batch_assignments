#!/bin/bash

yum update -y
# Update all installed packages to their latest available versions.
# The -y option automatically answers "yes" to all prompts.

yum install -y httpd
# Install the Apache HTTP Server (httpd) package.
# The -y option automatically confirms the installation.

systemctl enable --now httpd
# Enable the Apache service to start automatically at system boot.
# The --now option also starts the service immediately without requiring a reboot.


# Create an HTML file named index.html in the Apache web server's default document root.
# The content between <<EOF and EOF is written directly into the file.

cat <<EOF > /var/www/html/index.html
<!DOCTYPE html>
<html>
<head>
    <title>Terraform Project</title>
    <style>
        body {
            text-align: center;
            font-family: Arial, sans-serif;
            margin-top: 100px;
        }
    </style>
</head>
<body>
    <h1>Hello welcome to Saranya web server</h1>
    <h2>Terraform Project1 </h2>
    <p>2-TIER WEB APPLICATION INFRASTRUCTURE HOSTED ON AWS EC2</p>
    <p>Thank you for visiting!</p>
</body>
</html>
EOF