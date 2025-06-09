resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
  }
}

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-public-subnet-${count.index + 1}"
    Environment = var.environment
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "${var.project_name}-public-rt"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "Security group for web servers"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-web-sg"
    Environment = var.environment
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false

  tags = {
    Name        = "${var.project_name}-alb"
    Environment = var.environment
  }
}

resource "aws_lb_target_group" "web" {
  name     = "${var.project_name}-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "${var.project_name}-web-tg"
    Environment = var.environment
  }
}

resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

resource "aws_launch_template" "web" {
  name_prefix   = "${var.project_name}-web-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  key_name      = aws_key_pair.main.key_name

  vpc_security_group_ids = [aws_security_group.web.id]

  # IAM instance profile for SSM access
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              
              # Install and configure SSM agent
              yum install -y amazon-ssm-agent
              systemctl enable amazon-ssm-agent
              systemctl start amazon-ssm-agent
              
              # Install stress tool for CPU testing
              yum install -y stress
              
              systemctl start httpd
              systemctl enable httpd
              
              # Update index.html with actual metadata
              INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
              AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
              Deployment date=$(date)
              
              # Create web page for Paris region
              cat > /var/www/html/index.html << 'HTML'
              <!DOCTYPE html>
              <html lang="en">
              <head>
                  <title>Chaos Engineering Demo - Paris Region</title>
                  <meta charset="UTF-8">
                  <meta name="viewport" content="width=device-width, initial-scale=1.0">
                  <style>
                      body {
                          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                          line-height: 1.6;
                          margin: 0;
                          padding: 40px;
                          background-color: #f8f9fa;
                          color: #333;
                      }
                      .container {
                          max-width: 800px;
                          margin: 0 auto;
                          background: white;
                          padding: 40px;
                          border-radius: 8px;
                          box-shadow: 0 2px 10px rgba(0,0,0,0.1);
                      }
                      h1 {
                          font-size: 2rem;
                          font-weight: 600;
                          margin: 0 0 30px 0;
                          color: #2c3e50;
                          border-bottom: 2px solid #e9ecef;
                          padding-bottom: 15px;
                      }
                      h2 {
                          font-size: 1.25rem;
                          font-weight: 500;
                          margin: 25px 0 15px 0;
                          color: #495057;
                      }
                      h3 {
                          font-size: 1.1rem;
                          font-weight: 500;
                          margin: 20px 0 10px 0;
                          color: #6c757d;
                      }
                      .info-grid {
                          display: grid;
                          grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
                          gap: 20px;
                          margin: 20px 0;
                      }
                      .info-card {
                          background: #f8f9fa;
                          padding: 20px;
                          border-radius: 6px;
                          border-left: 4px solid #007bff;
                      }
                      .status-healthy {
                          border-left-color: #28a745;
                      }
                      .status-healthy h2 {
                          color: #155724;
                      }
                      .region-info {
                          background: #e3f2fd;
                          border-left-color: #1976d2;
                      }
                      .region-info h2 {
                          color: #0d47a1;
                      }
                      .experiment-info {
                          background: #fff3e0;
                          border-left-color: #f57c00;
                      }
                      .experiment-info h2 {
                          color: #e65100;
                      }
                      .data-row {
                          display: flex;
                          justify-content: space-between;
                          padding: 8px 0;
                          border-bottom: 1px solid #dee2e6;
                      }
                      .data-row:last-child {
                          border-bottom: none;
                      }
                      .data-label {
                          font-weight: 500;
                          color: #6c757d;
                      }
                      .data-value {
                          font-family: 'SFMono-Regular', Consolas, monospace;
                          color: #495057;
                      }
                      ul {
                          margin: 15px 0;
                          padding-left: 20px;
                      }
                      li {
                          margin: 8px 0;
                          color: #495057;
                      }
                      .footer {
                          margin-top: 40px;
                          padding-top: 20px;
                          border-top: 1px solid #dee2e6;
                          font-size: 0.9rem;
                          color: #6c757d;
                          text-align: center;
                      }
                  </style>
              </head>
              <body>
                  <div class="container">
                      <h1>Chaos Engineering Demo - Paris Region</h1>
                      
                      <div class="info-grid">
                          <div class="info-card region-info">
                              <h2>AWS Region Information</h2>
                              <div class="data-row">
                                  <span class="data-label">Region:</span>
                                  <span class="data-value">Europe (Paris) - eu-west-3</span>
                              </div>
                              <div class="data-row">
                                  <span class="data-label">Deployment:</span>
                                  <span class="data-value">AWS Paris Region</span>
                              </div>
                          </div>
                          
                          <div class="info-card status-healthy">
                              <h2>Service Status</h2>
                              <div class="data-row">
                                  <span class="data-label">Status:</span>
                                  <span class="data-value">Operational</span>
                              </div>
                              <div class="data-row">
                                  <span class="data-label">SSM Agent:</span>
                                  <span class="data-value">Ready</span>
                              </div>
                          </div>
                      </div>
                      
                      <div class="info-card">
                          <h2>Instance Details</h2>
                          <div class="data-row">
                              <span class="data-label">Instance ID:</span>
                              <span class="data-value">INSTANCE_ID_PLACEHOLDER</span>
                          </div>
                          <div class="data-row">
                              <span class="data-label">Availability Zone:</span>
                              <span class="data-value">AZ_PLACEHOLDER</span>
                          </div>
                          <div class="data-row">
                              <span class="data-label">Timestamp:</span>
                              <span class="data-value">TIMESTAMP_PLACEHOLDER</span>
                          </div>
                          <div class="data-row">
                              <span class="data-label">Timezone:</span>
                              <span class="data-value">Europe/Paris (CET/CEST)</span>
                          </div>
                      </div>
                  
                      
                      <div class="footer">
                          AWS Chaos Engineering using AWS Fault Injection Simulator
                      </div>
                  </div>
              </body>
              </html>
              HTML
              
              # Replace placeholders with actual values
              sed -i "s/INSTANCE_ID_PLACEHOLDER/$INSTANCE_ID/g" /var/www/html/index.html
              sed -i "s/AZ_PLACEHOLDER/$AZ/g" /var/www/html/index.html
              sed -i "s/TIMESTAMP_PLACEHOLDER/$TIMESTAMP/g" /var/www/html/index.html
              
              # Set Paris timezone
              timedatectl set-timezone Europe/Paris
              EOF
  )


  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-web-instance"
      Environment = var.environment
      ChaosReady  = "true"
    }
  }

  tags = {
    Name        = "${var.project_name}-web-template"
    Environment = var.environment
  }
}

# IAM Role for EC2 instances to use SSM
resource "aws_iam_role" "ec2_ssm_role" {
  name = "${var.project_name}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-ec2-ssm-role"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_policy" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_ssm_role.name

  tags = {
    Name        = "${var.project_name}-ec2-profile"
    Environment = var.environment
  }
}

resource "aws_autoscaling_group" "web" {
  name                      = "${var.project_name}-asg"
  vpc_zone_identifier       = aws_subnet.public[*].id
  target_group_arns         = [aws_lb_target_group.web.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  min_size         = 2
  max_size         = 4
  desired_capacity = 2

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-asg-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  tag {
    key                 = "ChaosReady"
    value               = "true"
    propagate_at_launch = true
  }
}