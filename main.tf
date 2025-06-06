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

  user_data = base64encode(<<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              
              # Create a simple web page
              cat > /var/www/html/index.html << 'HTML'
              <!DOCTYPE html>
              <html>
              <head>
                  <title>Chaos Engineering Demo</title>
                  <style>
                      body { font-family: Arial, sans-serif; margin: 40px; }
                      .container { max-width: 800px; margin: 0 auto; }
                      .status { padding: 20px; border-radius: 5px; margin: 20px 0; }
                      .healthy { background-color: #d4edda; color: #155724; }
                  </style>
              </head>
              <body>
                  <div class="container">
                      <h1>🚀 Chaos Engineering Demo</h1>
                      <div class="status healthy">
                          <h2>✅ Service Status: Healthy</h2>
                          <p>Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>
                          <p>Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)</p>
                          <p>Timestamp: $(date)</p>
                      </div>
                      <h3>Ready for Chaos Experiments!</h3>
                      <p>This instance is ready to participate in AWS FIS experiments.</p>
                  </div>
              </body>
              </html>
              HTML
              
              # Update index.html with actual metadata
              INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
              AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
              TIMESTAMP=$(date)
              
              # Create web page for Paris region
              cat > /var/www/html/index.html << 'HTML'
              <!DOCTYPE html>
              <html lang="en">
              <head>
                  <title>Chaos Engineering Demo - Paris Region</title>
                  <meta charset="UTF-8">
                  <style>
                      body { font-family: Arial, sans-serif; margin: 40px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; }
                      .container { max-width: 800px; margin: 0 auto; background: rgba(255,255,255,0.1); padding: 30px; border-radius: 15px; backdrop-filter: blur(10px); }
                      .status { padding: 20px; border-radius: 10px; margin: 20px 0; background: rgba(255,255,255,0.2); }
                      .healthy { border-left: 5px solid #28a745; }
                      .region-info { background: rgba(0,123,255,0.2); padding: 15px; border-radius: 8px; margin: 15px 0; }
                      .emoji { font-size: 1.2em; }
                  </style>
              </head>
              <body>
                  <div class="container">
                      <h1><span class="emoji">🚀</span> Chaos Engineering Demo - Paris Region <span class="emoji">🗼</span></h1>
                      <div class="region-info">
                          <h3><span class="emoji">🌍</span> AWS Region: Europe (Paris) - eu-west-3</h3>
                          <p>Server deployed in AWS Paris region</p>
                      </div>
                      <div class="status healthy">
                          <h2><span class="emoji">✅</span> Service Status: Healthy</h2>
                          <p><strong>Instance ID:</strong> INSTANCE_ID_PLACEHOLDER</p>
                          <p><strong>Availability Zone:</strong> AZ_PLACEHOLDER</p>
                          <p><strong>Timestamp:</strong> TIMESTAMP_PLACEHOLDER</p>
                          <p><strong>Timezone:</strong> Europe/Paris (CET/CEST)</p>
                      </div>
                      <h3><span class="emoji">🧪</span> Ready for Chaos Experiments!</h3>
                      <p>This instance is ready to participate in AWS FIS experiments in the Paris region.</p>
                      <div style="background: rgba(255,255,255,0.1); padding: 15px; border-radius: 8px; margin-top: 20px;">
                          <h4><span class="emoji">🔬</span> Available experiment types:</h4>
                          <ul>
                              <li>Random instance termination</li>
                              <li>CPU stress testing</li>
                              <li>Load balancer resilience testing</li>
                          </ul>
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

resource "aws_key_pair" "main" {
  key_name   = "${var.project_name}-key"
  public_key = file("~/.ssh/id_rsa.pub")
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