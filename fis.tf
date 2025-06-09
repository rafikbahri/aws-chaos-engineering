resource "aws_iam_role" "fis_role" {
  name = "${var.project_name}-fis-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "fis.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-fis-role"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "fis_policy" {
  name = "${var.project_name}-fis-policy"
  role = aws_iam_role.fis_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:StopInstances",
          "ec2:StartInstances",
          "ec2:RebootInstances",
          "ec2:TerminateInstances",
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "ecs:DescribeClusters",
          "ecs:ListContainerInstances",
          "ecs:DescribeContainerInstances",
          "ecs:StopTask",
          "logs:CreateLogDelivery",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups",
          "ssm:SendCommand",
          "ssm:ListCommands",
          "ssm:ListCommandInvocations",
          "ssm:DescribeInstanceInformation",
          "ssm:GetCommandInvocation",
          "ssm:DescribeInstanceAssociationsStatus",
          "ssm:DescribeEffectiveInstanceAssociations"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_fis_experiment_template" "stop_instances" {
  description = "Stop random EC2 instances to test resilience"
  role_arn    = aws_iam_role.fis_role.arn

  stop_condition {
    source = "aws:cloudwatch:alarm"
    value  = aws_cloudwatch_metric_alarm.high_cpu.arn
  }

  action {
    name      = "StopInstances"
    action_id = "aws:ec2:stop-instances"

    target {
      key   = "Instances"
      value = "chaos-instances"
    }
  }

  target {
    name           = "chaos-instances"
    resource_type  = "aws:ec2:instance"
    selection_mode = "PERCENT(50)" # Affect 50% of instances

    resource_tag {
      key   = "ChaosReady"
      value = "true"
    }

    filter {
      path   = "State.Name"
      values = ["running"]
    }
  }

  tags = {
    Name        = "${var.project_name}-stop-instances"
    Environment = var.environment
  }
}

resource "aws_fis_experiment_template" "cpu_stress" {
  description = "Apply CPU stress to test performance under load"
  role_arn    = aws_iam_role.fis_role.arn

  stop_condition {
    source = "aws:cloudwatch:alarm"
    value  = aws_cloudwatch_metric_alarm.high_cpu.arn
  }

  action {
    name      = "CPUStress"
    action_id = "aws:ssm:send-command"

    parameter {
      key   = "documentArn"
      value = "arn:aws:ssm:${var.aws_region}::document/AWSFIS-Run-CPU-Stress"
    }

    parameter {
      key = "documentParameters"
      value = jsonencode({
        DurationSeconds = "600"
        CPU             = "80"
      })
    }

    parameter {
      key   = "duration"
      value = "PT10M"
    }

    target {
      key   = "Instances"
      value = "stress-instances"
    }
  }

  target {
    name           = "stress-instances"
    resource_type  = "aws:ec2:instance"
    selection_mode = "COUNT(1)" # Affect 1 instance

    resource_tag {
      key   = "ChaosReady"
      value = "true"
    }

    filter {
      path   = "State.Name"
      values = ["running"]
    }
  }

  tags = {
    Name        = "${var.project_name}-cpu-stress"
    Environment = var.environment
  }
}
