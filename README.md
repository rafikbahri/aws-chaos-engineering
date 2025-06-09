# AWS Chaos Engineering Project

This project provides a Terraform solution to deploy a resilient web application and run AWS Fault Injection Simulator (FIS) experiments against it. The infrastructure includes an Application Load Balancer (ALB) with an Auto Scaling Group (ASG) to demonstrate resilience during controlled failures.

## Architecture

The infrastructure consists of:

- VPC with 2 public subnets across different Availability Zones
- Application Load Balancer with HTTP listener
- Auto Scaling Group with 2-4 EC2 instances (t3.micro)
- CloudWatch alarms and metrics for monitoring
- AWS Fault Injection Simulator (FIS) experiments
- SNS Topic for alerts
- CloudWatch Logs for experiment logs

The EC2 instances run Amazon Linux 2 with a simple web server displaying instance metadata and availability zone information.
See the detailed Architecture diagram in [docs/archi.md](docs/archi.md).

## Chaos Experiments

The project includes two predefined AWS FIS experiments:

1. **Stop Instances Experiment**: Randomly stops 50% of the running instances tagged with `ChaosReady=true`.
2. **CPU Stress Experiment**: Applies CPU stress (80% utilization) to one instance for 10 minutes.

Both experiments have safety mechanisms using CloudWatch alarms as stop conditions.

## Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform v0.14+ installed
- SSH key pair (default: `~/.ssh/id_rsa.pub`)
- jq command-line tool

## Deployment

To deploy the infrastructure:

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

## Running Experiments

The project includes a comprehensive bash script (`chaos-experiment.sh`) to facilitate running the chaos experiments:

```bash
# Deploy the infrastructure
./chaos-experiment.sh deploy

# Run the stop instances experiment
./chaos-experiment.sh run-stop-instances

# Run the CPU stress experiment
./chaos-experiment.sh run-cpu-stress

# Run a complete chaos engineering experiment
./chaos-experiment.sh run-complete

# Monitor application health
./chaos-experiment.sh monitor

# Check CloudWatch metrics
./chaos-experiment.sh metrics

# Destroy all resources
./chaos-experiment.sh cleanup
```

## Monitoring

The infrastructure includes CloudWatch alarms configured to notify when CPU utilization exceeds 80%. During experiments, you can monitor application health using the provided script or through the AWS Management Console.

## Security

The infrastructure implements basic security controls:

- Security group restricting access to ports 80 (HTTP) and 22 (SSH)
- IAM roles with least privilege permissions
- EC2 instances with SSM agent for management without requiring SSH access

## Cleanup

To avoid ongoing charges, destroy the resources when done:

```bash
./chaos-experiment.sh cleanup
```

## Customization

Adjust the following variables in `variables.tf` to customize the deployment:

- `aws_region`: The AWS region for deployment (default: `eu-west-3`)
- `project_name`: Project name for resource naming (default: `chaos-engineering-demo`)
- `environment`: Environment name (default: `dev`)

Please refer to the [Terraform documentation](./docs/tf-config.md) for more details about the complete configuration 

## License

GNU AFFERO GENERAL PUBLIC LICENSE.
