# AWS DevOps Agent × 5G Core — Cross-Layer Investigation Demo

A hands-on workshop that demonstrates [AWS DevOps Agent](https://docs.aws.amazon.com/devops-agent/) investigating cross-layer incidents on Amazon EKS. Using a simulated 5G Core network as the application layer, four pre-built failure scenarios show the agent tracing from Kubernetes pod failures through AWS infrastructure changes to CloudTrail audit logs — identifying who broke what, when, and from where — in under 3 minutes per scenario.

## The Problem: Incidents Don't Respect Team Boundaries

Modern cloud-native applications — especially telco workloads running on Kubernetes — fail in ways that span multiple operational layers. A single Security Group change can cascade from AWS networking → ElastiCache connectivity → Kubernetes pod health → application-level service discovery → subscriber-facing outage. Traditional monitoring tools show you **what** broke. Figuring out **why** it broke and **who** caused it requires an engineer to manually correlate pod events, application logs, CloudWatch metrics, VPC configuration, and CloudTrail audit trails — often across different consoles, different teams, and different areas of expertise.

For telco networks, this problem is amplified. The blast radius of infrastructure changes isn't measured in failed HTTP requests — it's measured in **subscribers losing service**. A Network Repository Function (NRF) losing its Redis backend means every Network Function in the 5G Core loses service discovery simultaneously. Millions of subscribers can't register, handover between cells, or establish data sessions — and the NOC team is hunting through logs trying to figure out which layer broke first.

## The Solution: AWS DevOps Agent

[AWS DevOps Agent](https://docs.aws.amazon.com/devops-agent/) is an AI-powered operations assistant that investigates incidents across your entire AWS environment. You describe a symptom in plain language — *"The catalog service is returning errors"* or *"AMF pods are stuck in Pending"* — and it autonomously traces the full causal chain from application to infrastructure to human action.

**What it connects to:**

- **Kubernetes API** — pod status, deployment state, events (OOMKill, FailedScheduling, ImagePullBackOff), HPA configuration, node conditions
- **CloudWatch Logs** — application logs, EKS control plane audit logs (who ran what kubectl commands)
- **CloudWatch Metrics** — Container Insights (CPU, memory, network per pod/node), custom metrics, ALB metrics
- **CloudTrail** — every AWS API call with principal, IP address, timestamp, and request parameters
- **Topology discovery** — resource relationships (pod → node → ASG → EC2 instance → Security Group → ElastiCache)

**How it investigates:**

The agent reasons through the problem dynamically: checks pod status, reads logs for error patterns, follows dependency chains, inspects infrastructure configuration, and correlates with CloudTrail to identify the specific human action that caused the incident. It can also leverage saved skills and runbooks for domain-specific investigation patterns. It reports back with a complete timeline, root cause, and evidence.

## What This Demo Does

This repository provides a lightweight set of 5G Core stub services on Amazon EKS — not a real 5G core, but Python microservices that speak correct 3GPP vocabulary and use real AWS dependencies (ElastiCache Redis, SQS). It includes four pre-built failure scenarios that showcase DevOps Agent's cross-layer investigation capabilities. Each scenario:

1. **Injects** a real infrastructure problem (one shell command)
2. **Triggers** a CloudWatch alarm (NOC-style alerting)
3. **Prompts** the DevOps Agent to investigate (paste a sentence)
4. **Demonstrates** the agent tracing from symptom to root cause across layers
5. **Restores** to healthy state (one shell command)

The goal is to prove that DevOps Agent can identify root causes that would normally require coordination across platform, networking, and application teams — in minutes instead of hours.

### Architecture

A 5G Core is the brain of a mobile network, built as cloud-native microservices. Each service is a **Network Function (NF)**:

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         5G Core (demo-5g namespace)                       │
│                                                                          │
│                              ┌─────────┐                                 │
│                  ┌───────────│   NRF   │───────────┐                     │
│                  │           │ Registry│           │                     │
│                  │           └────┬────┘           │                     │
│                  │ Nnrf      Nnrf │          Nnrf  │                     │
│                  │                │                │                     │
│      ┌───────────▼──┐        ┌───▼────┐      ┌───▼────┐    ┌────────┐  │
│      │     AMF      │──N11──▶│  SMF   │      │  PCF   │    │   UE   │  │
│      │ Registration │        │Session │      │ Policy │    │Simulator│  │
│      │ & Mobility   │        │ Mgmt   │      └────────┘    │ (load) │  │
│      └──────────────┘        └───┬────┘                    └───┬────┘  │
│                                   │ N4                     N1/N2│       │
│                               ┌───▼────┐                       │       │
│                               │  UPF   │◀──────────────────────┘       │
│                               │  Data  │                               │
│                               │ Plane  │                               │
│                               └────────┘                               │
└──────────────────────────────────────────────────────────────────────────┘
                    │
                    ▼
          ElastiCache Redis (NRF backend — service registry state)
```

| NF | Role | What breaks when it's down |
|----|------|---------------------------|
| **NRF** | Service registry (backed by Redis) | All NFs lose service discovery → total core outage |
| **AMF** | Subscriber registration & mobility | Devices can't attach to network or handover between cells |
| **SMF** | Data session management | No new internet/data connections |
| **UPF** | User data plane (packet forwarding) | Active sessions lose connectivity |
| **PCF** | Policy & QoS decisions | No quality-of-service enforcement |

The NFs are Python stubs that speak correct 3GPP vocabulary and use real AWS dependencies (ElastiCache Redis, SQS). They are not a production 5G core — but the infrastructure, failure modes, cascading dependencies, logs, metrics, and CloudTrail events are all real.

## Demo Scenarios

Each scenario demonstrates a different cross-layer correlation — the agent starts at the symptom and works backward to the root cause:

| # | Scenario | Symptom Layer | Root Cause Layer | What the Agent Finds | Time |
|---|----------|--------------|-----------------|---------------------|------|
| 1 | **Security Group Change** | Application (NRF connection errors) | AWS Networking (VPC Security Group) | Traces NRF→Redis connectivity loss through SG rule removal to the specific CloudTrail event — identifies who removed the rule, when, and from what IP | ~2 min |
| 2 | **ASG Capacity Ceiling** | Kubernetes (pods stuck Pending) | AWS Compute (Auto Scaling Group max) | Correlates FailedScheduling events with node CPU saturation and ASG at max capacity — explains why Cluster Autoscaler can't provision new nodes | ~4 min |
| 3 | **Bad Deployment** | Kubernetes (ImagePullBackOff) | CI/CD (kubectl set image) | Traces pod failures to a non-existent image tag, finds the exact `kubectl set image` command in EKS audit logs — identifies the user, kubectl version, and source IP | ~3 min |
| 4 | **HPA Scaling Storm** | Application (intermittent failures) | Configuration (HPA parameters) | Explains the feedback loop: HPA target too low + no stabilization window → rapid scale up/down → NRF connection pool churn → intermittent 5G registration failures | ~8 min |

### Example: Scenario 1 Investigation

You inject the failure:
```bash
./scripts-5g/scenario-1-sg-change.sh inject
```

You give the agent a symptom (not a hint):
> *"The NRF service is returning errors. Investigate."*

The agent autonomously:
1. Checks NRF pod status → Running (not crashed)
2. Reads NRF logs → `ConnectionRefusedError` to Redis endpoint
3. Verifies Redis is healthy → ElastiCache node is up
4. Inspects Security Group → port 6379 inbound rule is **missing**
5. Queries CloudTrail → finds `RevokeSecurityGroupIngress` API call
6. Reports: *"User X removed the inbound rule allowing port 6379 from the pod CIDR at timestamp Y from IP Z"*

![Scenario 1 — Agent identifies the CloudTrail event](docs/images/scenario-1-investigation_root-cause.png)

## Infrastructure Deployed

Everything is managed by Terraform and deployed via a single `deploy.sh` script:

- **VPC** — 3 AZs, public/private subnets, single NAT gateway
- **EKS Cluster** (v1.30) — system node group (2× t3.medium, tainted) + app node group (2× t3.medium, max 3)
- **ElastiCache Redis** — NRF service registry backend
- **SQS Queue** — async message processing
- **Container Insights** (enhanced observability) — pod/node/cluster metrics
- **CloudWatch Alarms** — one per scenario + baseline alarms (NOC-style alerting)
- **ALB Ingress Controller** — internet-facing load balancer
- **Cluster Autoscaler** with IRSA — responds to pod scheduling pressure
- **EKS Control Plane Logging** — API, audit, authenticator, controller manager, scheduler

**Cost:** ~$5/hour while running. The EKS control plane + Redis cost ~$0.12/hour even with nodes at zero. Destroy with `terraform destroy` when done.

## Prerequisites

| Tool | Purpose |
|------|---------|
| AWS CLI v2 | Infrastructure provisioning, scenario scripts |
| Terraform ≥ 1.5 | Infrastructure as code |
| kubectl | Kubernetes deployment and verification |
| Helm 3 | Container Insights + ALB controller |
| jq | JSON parsing in scripts |
| AWS Account | With admin access (EKS, ElastiCache, VPC, IAM) |

Run the automated check:
```bash
./prerequisites.sh
```

## Quick Start

```bash
# Clone
git clone https://github.com/modaoud/aws-devops-agent-5g-core-workshop.git
cd aws-devops-agent-5g-core-workshop

# 1. Deploy infrastructure (~10 min)
cd terraform/
cp terraform.tfvars.example terraform.tfvars   # edit region if needed
terraform init && terraform apply
cd ..

# 2. Deploy 5G Core application (~2 min)
./deploy.sh

# 3. Verify everything is healthy
./verify.sh

# 4. Create DevOps Agent Space (AWS Console — see docs/workshop-guide.md)
#    - Create space, assign IAM role
#    - Add EKS access entry with AmazonAIOpsAssistantPolicy
#    - Verify agent can list pods

# 5. Run a scenario
./scripts-5g/scenario-1-sg-change.sh inject     # break something
# → Open DevOps Agent → paste the prompt from docs/scenario-1.md
# → Watch the investigation
./scripts-5g/scenario-1-sg-change.sh restore    # fix it
```

![verify.sh output — all green](docs/images/verify-output.png)

## Repository Structure

```
├── terraform/              Infrastructure (VPC, EKS, Redis, SQS, IAM, Alarms)
│   ├── main.tf            Provider + VPC
│   ├── eks.tf             Cluster, node groups, addons, IRSA
│   ├── elasticache.tf     Redis cluster
│   ├── alarms.tf          CloudWatch alarms (per-scenario + baseline)
│   └── outputs.tf         Cluster name, Redis endpoint, SQS URL
├── k8s-5g/                 5G Core Kubernetes manifests
│   ├── namespace.yaml
│   ├── nrf.yaml           Network Repository Function (+ Redis connection)
│   ├── amf.yaml           Access & Mobility Management (+ HPA)
│   ├── smf.yaml           Session Management Function
│   ├── upf.yaml           User Plane Function
│   ├── pcf.yaml           Policy Control Function
│   └── ue-simulator.yaml  Load generator (simulates subscriber traffic)
├── scripts-5g/             Scenario inject/restore scripts
│   ├── scenario-1-sg-change.sh
│   ├── scenario-2-asg-ceiling.sh
│   ├── scenario-3-bad-deploy.sh
│   └── scenario-4-scaling-storm.sh
├── docs/                   Full workshop documentation
│   ├── introduction.md    5G primer, DevOps Agent overview, telco value prop
│   ├── workshop-guide.md  Step-by-step setup instructions
│   ├── scenario-1.md      SG change walkthrough
│   ├── scenario-2.md      ASG ceiling walkthrough
│   ├── scenario-3.md      Bad deployment walkthrough
│   ├── scenario-4.md      Scaling storm walkthrough
│   └── images/            Screenshots of agent investigations
├── deploy.sh               Post-Terraform K8s deployment (Helm + manifests)
├── verify.sh               Health check (pods, connectivity, agent access)
├── prerequisites.sh        Tool + credential checker
└── README.md               This file
```

## Documentation

| Document | What's inside |
|----------|---------------|
| [Introduction](docs/introduction.md) | 5G Core concepts, DevOps Agent capabilities, telco value proposition |
| [Workshop Guide](docs/workshop-guide.md) | Full setup walkthrough with screenshots (Terraform → EKS → Agent Space) |
| [Scenario 1 — SG Change](docs/scenario-1.md) | Security Group investigation: inject, prompt, expected path, restore |
| [Scenario 2 — ASG Ceiling](docs/scenario-2.md) | Compute capacity investigation |
| [Scenario 3 — Bad Deploy](docs/scenario-3.md) | CI/CD audit trail investigation |
| [Scenario 4 — Scaling Storm](docs/scenario-4.md) | HPA feedback loop investigation |

## Why 5G?

The 5G Network Functions use proper 3GPP vocabulary (SUPI, PDU sessions, S-NSSAI, DNN, 5QI, Nnrf reference points) so the demo resonates with telco engineers and NOC teams. But the underlying failure modes are **universal EKS patterns** — Security Group misconfigurations, ASG scaling limits, bad deployments, and HPA tuning issues happen in every Kubernetes environment. The same scenarios apply to any microservices architecture running on EKS.

The telco framing amplifies the business impact narrative: "pod restart" becomes "2 million subscribers can't register," which makes the value of fast root-cause identification viscerally clear.

## Cleanup

```bash
# Remove application
kubectl delete namespace demo-5g

# Destroy infrastructure
cd terraform/
terraform destroy
```

## Contributing

This is a demo/workshop repository. If you're adapting it for a different vertical (e-commerce, fintech, gaming), the pattern is:

1. Replace `k8s-5g/` manifests with your domain's microservices
2. Keep the same Terraform infrastructure (it's generic EKS + Redis)
3. Rewrite scenario scripts to target your app's failure points
4. Update docs with your domain's vocabulary and impact language
