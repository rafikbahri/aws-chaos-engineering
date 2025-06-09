#!/bin/bash

set -e

# Configuration
PROJECT_NAME="chaos-engineering-demo"
AWS_REGION="eu-west-3"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

check_requirements() {
    print_header "Checking Requirements"
    
    command -v aws >/dev/null 2>&1 || { print_error "AWS CLI is required but not installed. Aborting."; exit 1; }
    command -v terraform >/dev/null 2>&1 || { print_error "Terraform is required but not installed. Aborting."; exit 1; }
    command -v jq >/dev/null 2>&1 || { print_error "jq is required but not installed. Aborting."; exit 1; }
    
    local configured_region=$(aws configure get region)
    if [ "$configured_region" != "$AWS_REGION" ]; then
        print_warning "AWS region configured: $configured_region, required region: $AWS_REGION"
        print_status "Configuring AWS region..."
        aws configure set region $AWS_REGION
    fi
    
    print_status "All required tools are installed"
    print_status "AWS region configured: $(aws configure get region)"
}

deploy_infrastructure() {
    print_header "Deploying Infrastructure"
    
    # Check if SSH key exists
    if [ ! -f ~/.ssh/id_rsa.pub ]; then
        print_warning "SSH public key not found at ~/.ssh/id_rsa.pub"
        print_status "Generating SSH key pair..."
        ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ""
    fi
    
    terraform init
    terraform plan -var="aws_region=$AWS_REGION" -out=tfplan
    terraform apply tfplan
    
    print_status "Infrastructure deployed successfully in region $AWS_REGION"
    
    # Wait for load balancer to be ready
    print_status "Waiting for load balancer to be ready..."
    local lb_url=$(terraform output -raw load_balancer_url)
    local ready=false
    local attempts=0
    
    while [ $ready = false ] && [ $attempts -lt 30 ]; do
        if curl -s -o /dev/null -w "%{http_code}" "$lb_url" | grep -q "200"; then
            ready=true
            print_status "Application accessible at: $lb_url"
        else
            print_status "Attempt $((attempts + 1))/30 - Waiting..."
            sleep 30
            attempts=$((attempts + 1))
        fi
    done
    
    if [ $ready = false ]; then
        print_warning "Application is not yet accessible. Please check manually."
    fi
}

get_experiment_ids() {
    STOP_INSTANCES_ID=$(terraform output -raw fis_experiment_stop_instances_id)
    CPU_STRESS_ID=$(terraform output -raw fis_experiment_cpu_stress_id)
    LB_URL=$(terraform output -raw load_balancer_url)
    
    print_status "Stop Instances Experiment ID: $STOP_INSTANCES_ID"
    print_status "CPU Stress Experiment ID: $CPU_STRESS_ID"
    print_status "Load Balancer URL: $LB_URL"
    print_status "Region: $AWS_REGION"
}

run_experiment() {
    local experiment_id=$1
    local experiment_name=$2
    
    print_header "Running Experiment: $experiment_name"
    
    # Start the experiment
    local execution_id=$(aws fis start-experiment \
        --experiment-template-id "$experiment_id" \
        --region "$AWS_REGION" \
        --query 'experiment.id' \
        --output text)
    
    print_status "Experiment started with ID: $execution_id"
    print_status "Region: $AWS_REGION"
    
    # Monitor experiment status
    while true; do
        local status=$(aws fis get-experiment \
            --id "$execution_id" \
            --region "$AWS_REGION" \
            --query 'experiment.state.status' \
            --output text)
        
        print_status "Experiment status: $status"
        
        case $status in
            "completed")
                print_status "Experiment completed successfully"
                break
                ;;
            "stopped")
                print_warning "Experiment stopped (stop condition triggered)"
                break
                ;;
            "failed")
                print_error "Experiment failed"
                break
                ;;
            *)
                sleep 30
                ;;
        esac
    done
    
    experiment_output_file="experiment_${execution_id}_results.json"
    aws fis get-experiment \
        --id "$execution_id" \
        --region "$AWS_REGION" \
        --output json > "$experiment_output_file"
    
    print_status "Experiment completed. Results saved to $experiment_output_file"
}

monitor_health() {
    print_header "Monitoring Application Health"
    
    local lb_url=$(terraform output -raw load_balancer_url)
    local check_count=0
    local success_count=0
    local failure_count=0
    
    print_status "Monitoring $lb_url for 5 minutes..."
    print_status "Region: $AWS_REGION"
    
    while [ $check_count -lt 60 ]; do
        if curl -s -o /dev/null -w "%{http_code}" "$lb_url" | grep -q "200"; then
            success_count=$((success_count + 1))
        else
            failure_count=$((failure_count + 1))
        fi
        
        # Show progress every 30 seconds
        if [ $((check_count % 6)) -eq 5 ]; then
            local timestamp=$(date '+%H:%M:%S')
            local current_rate=$(echo "scale=1; $success_count * 100 / ($check_count + 1)" | bc -l)
            print_status "[$timestamp] Health checks: ${success_count}/$((check_count + 1)) successful (${current_rate}%)"
        fi
        
        check_count=$((check_count + 1))
        sleep 5
    done
    
    print_status "Health check completed:"
    print_status "  Successful checks: $success_count/60"
    print_status "  Failed checks: $failure_count/60"
    print_status "  Success rate: $(echo "scale=2; $success_count * 100 / 60" | bc -l)%"
    print_status "  Region: $AWS_REGION"
}

check_metrics() {
    print_header "Checking CloudWatch Metrics"
    
    local end_time=$(date -u +%Y-%m-%dT%H:%M:%S)
    local start_time=$(date -u -v-1H +%Y-%m-%dT%H:%M:%S)
    
    # Get CPU utilization metrics
    aws cloudwatch get-metric-statistics \
        --namespace AWS/EC2 \
        --metric-name CPUUtilization \
        --dimensions Name=AutoScalingGroupName,Value="${PROJECT_NAME}-asg" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --period 300 \
        --statistics Average \
        --region "$AWS_REGION" \
        --output table    
}

cleanup() {
    print_header "Cleaning Up Resources"
    
    print_warning "This will destroy all resources created by Terraform"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        terraform destroy
        print_status "Resources cleaned up successfully"
    else
        print_status "Cleanup cancelled"
    fi
}

run_complete_experiment() {
    print_header "Running Complete Chaos Engineering Experiment"
    
    get_experiment_ids
    
    print_status "Starting background health monitoring..."
    (
        while true; do
            monitor_health
            sleep 60
        done
    ) &
    local monitor_pid=$!
    
    print_status "Waiting for application to be ready..."
    sleep 60
    run_experiment "$STOP_INSTANCES_ID" "Stop Instances"
    
    sleep 120
    run_experiment "$CPU_STRESS_ID" "CPU Stress"
    
    kill $monitor_pid 2>/dev/null || true
    
    check_metrics
    print_status "Complete chaos engineering experiment finished"
}

case "${1:-help}" in
    "deploy")
        check_requirements
        deploy_infrastructure
        ;;
    "run-stop-instances")
        get_experiment_ids
        run_experiment "$STOP_INSTANCES_ID" "Stop Instances"
        ;;
    "run-cpu-stress")
        get_experiment_ids
        run_experiment "$CPU_STRESS_ID" "CPU Stress"
        ;;
    "run-complete")
        run_complete_experiment
        ;;
    "monitor")
        monitor_health
        ;;
    "metrics")
        check_metrics
        ;;
    "cleanup")
        cleanup
        ;;
    "help"|*)
        echo "Chaos Engineering Experiment Runner"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  deploy              Deploy infrastructure using Terraform"
        echo "  run-stop-instances  Run the stop instances experiment"
        echo "  run-cpu-stress      Run the CPU stress experiment"
        echo "  run-complete        Run complete chaos engineering experiment"
        echo "  monitor             Monitor application health"
        echo "  metrics             Check CloudWatch metrics"
        echo "  cleanup             Destroy all resources"
        echo "  help                Show this help message"
        echo ""
        echo "Example workflow:"
        echo "  1. $0 deploy"
        echo "  2. $0 run-complete"
        echo "  3. $0 cleanup"
        echo ""
        echo "AWS Region: $AWS_REGION"
        ;;
esac