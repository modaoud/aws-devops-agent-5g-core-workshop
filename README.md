# AWS DevOps Agent × 5G Core — Cross-Layer Investigation Demo

Demonstrate [AWS DevOps Agent](https://docs.aws.amazon.com/devops-agent/) investigating cross-layer incidents on EKS — from Kubernetes pod failures to AWS infrastructure changes to CloudTrail audit logs — in under 3 minutes per scenario.

## What's Inside

A simulated 5G Core network (AMF, SMF, UPF, NRF, PCF) running on EKS with ElastiCache Redis as the service registry backend. Four pre-built failure scenarios inject real infrastructure problems that the DevOps Agent investigates end-to-end.

| Scenario | Telco Impact | Root Cause | Agent Finds | Time |
|----------|-------------|------------|-------------|------|
| 1. SG Change | NRF registry offline → all NF discovery fails → total 5G core outage | Security Group blocks Redis port 6379 | Traces NRF→Redis connectivity loss to specific SG change via CloudTrail — identifies who, when, and from where | ~2 min |
| 2. ASG Ceiling | AMF can't scale during busy hour → UE registration timeouts | ASG max capped at current node count | Correlates AMF FailedScheduling with ASG capacity limit — explains why Cluster Autoscaler can't provision nodes for 5G UE registration busy hour demand | ~4 min |
| 3. Bad Deploy | AMF fleet down → no subscriber registrations or handovers | Non-existent image tag pushed via kubectl | Traces AMF pod failures to a bad image tag pushed during an AMF upgrade — identifies the exact command and user via EKS audit logs | ~3 min |
| 4. Scaling Storm | Intermittent PDU session failures during busy hour (oscillating) | HPA target 15% + 0s stabilization window | Explains AMF HPA feedback loop causing Nnrf discovery disruptions — identifies NRF connection pool churn during scaling oscillation | ~8 min |

## Prerequisites

You need an AWS account with admin access and a few CLI tools on your laptop. Not sure if you have everything? Run the check:

```bash
git clone https://github.com/modaoud/aws-devops-agent-5g-core-workshop.git
cd aws-devops-agent-5g-core-workshop
chmod +x prerequisites.sh deploy.sh verify.sh scripts-5g/*.sh
./prerequisites.sh
```

It checks for: AWS CLI, Terraform, kubectl, Helm, jq, and valid AWS credentials. If anything is missing, it shows the install command for your OS (macOS or Linux).

**Cost:** ~$5/hour while the cluster is running. Destroy when done.

## Quick Start

![verify.sh output](docs/images/verify-output.png)

```bash
# 1. Infrastructure (~10 min)
cd terraform/
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply

# 2. Application (~2 min)
cd ..
./deploy.sh

# 3. Verify
./verify.sh

# 4. Create DevOps Agent Space (console — see docs/)

# 5. Run scenarios
./scripts-5g/scenario-1-sg-change.sh inject
# → paste agent prompt → watch investigation → restore
./scripts-5g/scenario-1-sg-change.sh restore
```

## Repository Structure

```
├── terraform/              Infrastructure (VPC, EKS, Redis, SQS, Alarms)
├── k8s-5g/                 5G Core manifests (NRF, AMF, SMF, UPF, PCF)
├── scripts-5g/             Scenario inject/restore scripts
├── docs/                   Workshop guide + per-scenario walkthroughs
├── deploy.sh               Post-Terraform K8s deployment
└── verify.sh               Health check
```

## Documentation

- **[Introduction](docs/introduction.md)** — 5G Core primer, DevOps Agent overview, telco value proposition
- **[Workshop Guide](docs/workshop-guide.md)** — Full setup instructions
- **[Scenario 1](docs/scenario-1.md)** — Security Group change
- **[Scenario 2](docs/scenario-2.md)** — ASG capacity ceiling
- **[Scenario 3](docs/scenario-3.md)** — Bad deployment
- **[Scenario 4](docs/scenario-4.md)** — HPA scaling storm

## Why 5G?

The 5G network functions use proper 3GPP vocabulary (SUPI, PDU sessions, S-NSSAI, DNN, 5QI) so the demo resonates with telco engineers. The underlying failure modes are universal EKS patterns — the same scenarios apply to any microservices architecture.

## Cleanup

```bash
kubectl delete namespace demo-5g
cd terraform/ && terraform destroy
```
