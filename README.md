# AWS DevOps Agent × 5G Core — Cross-Layer Investigation Demo

Demonstrate [AWS DevOps Agent](https://docs.aws.amazon.com/devops-agent/) investigating cross-layer incidents on EKS — from Kubernetes pod failures to AWS infrastructure changes to CloudTrail audit logs — in under 3 minutes per scenario.

## What's Inside

A simulated 5G Core network (AMF, SMF, UPF, NRF, PCF) running on EKS with ElastiCache Redis as the service registry backend. Four pre-built failure scenarios inject real infrastructure problems that the DevOps Agent investigates end-to-end.

| Scenario | Telco Impact | Root Cause | Agent Finds | Time |
|----------|-------------|------------|-------------|------|
| 1. SG Change | NRF registry offline → all NF discovery fails → total 5G core outage | Security Group blocks Redis port 6379 | CloudTrail: who revoked the rule, when, from which IP | ~2 min |
| 2. ASG Ceiling | AMF can't scale during busy hour → UE registration timeouts | ASG max capped at current node count | ASG maxSize limit, node saturation at 17/17 pods, Cluster Autoscaler blocked | ~4 min |
| 3. Bad Deploy | AMF fleet down → no subscriber registrations or handovers | Non-existent image tag pushed via kubectl | EKS audit log: exact `kubectl set image` command, user, IP, kubectl version | ~3 min |
| 4. Scaling Storm | Intermittent PDU session failures during busy hour (oscillating) | HPA target 15% + 0s stabilization window | Feedback loop mechanism, NRF connection pooling bug (450× Redis connection spike) | ~8 min |

## Quick Start

![verify.sh output](docs/images/verify-output.png)

```bash
# 0. Clone
git clone https://github.com/modaoud/devops-agent-eks-demo.git
cd devops-agent-eks-demo
chmod +x deploy.sh verify.sh scripts-5g/*.sh

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

## Prerequisites

- AWS account (Isengard or standard — admin access needed)
- Terraform ≥ 1.5, AWS CLI v2, kubectl, helm, jq
- ~$5/hour while running

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
