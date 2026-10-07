# PRD: Agentic Coding Platform (C++ / Python)

Course context: DA2 CAD, cloud-native AWS design. Internal assignment project.

## 1. Overview
A browser-based IDE where an AI agent solves LeetCode-style problems in C++ or Python. The agent writes a solution, runs it in a sandbox against test cases, reads failures, and fixes the code. The model is self-hosted on the owner's EC2 GPU instance.

## 2. Goals and non-goals
**Goals**
- Working, deployed demo of the full agent loop (write, run, observe, fix).
- IDE-like experience in the browser: editor, file list, run, output.
- Safe execution of untrusted code (sandboxed C++ and Python only).
- Total cost fits well inside the $100 AWS student credits.
- A documented production-scale AWS architecture covering deployment, database, storage, networking, security, scalability, monitoring, backup and DR.

**Non-goals**
- Multi-user accounts, billing, or public availability.
- Languages beyond C++ and Python.
- Fetching problems from LeetCode (the user pastes the statement).
- Hard-problem accuracy guarantees from a small model.

## 3. User and scenarios
One user (the owner), about 10 sessions.
1. Start the instance, open the IDE through an SSH tunnel.
2. Paste a problem and sample tests, press Solve, watch attempts and results.
3. Edit the generated code manually, run it with custom input, save the file.
4. Stop the instance (manual or automatic after idle).

## 4. Functional requirements
| ID | Requirement |
|---|---|
| FR1 | Monaco editor with C++ and Python modes, file list, create/open/save in a workspace folder |
| FR2 | Run button executes the editor code with optional stdin and shows stdout, stderr, exit status, timeout |
| FR3 | Sandbox: no network, 256 MB memory, 1 CPU, 64 processes, read-only filesystem, 5 s run limit |
| FR4 | Solve action takes problem text, language, and JSON tests, then streams progress |
| FR5 | Agent loop: up to 5 attempts; each failure (wrong output, error, timeout) is fed back to the model |
| FR6 | Model gateway uses an OpenAI-compatible API, configurable by env (vLLM now, fallback provider later) |
| FR7 | HTTP basic auth on every route |
| FR8 | Instance auto-stops after 30 minutes without requests |

## 5. Non-functional requirements
- **Cost:** under about $20 for the evaluation period; a budget alert is set.
- **Security:** server reachable only via SSH tunnel; sandbox flags are never relaxed; file names validated.
- **Performance:** first token within a few seconds once the model is loaded; cold start after instance stop is several minutes.
- **Reproducibility:** setup is scripted (`README.md`); the infrastructure can be rebuilt from the repo plus the model download.

## 6. Architecture
**Prototype (deployed)**
```
Browser --SSH tunnel--> EC2 g4dn.xlarge
                          FastAPI (auth, files, run, agent SSE) + static IDE
                          Docker sandbox (g++ / python3)
                          vLLM (quantized 7B coder model)
                        EBS volume: model weights + workspace
```

**Production target (documented in the report)**
| Topic | Target design |
|---|---|
| Deployment | ECS Fargate services, ECR, CodePipeline blue/green, IaC with Terraform/CDK |
| Execution | Separate worker fleet with per-job containers or Firecracker microVMs, fed by SQS |
| Model | GPU Auto Scaling Group behind an internal NLB, scaling on queue depth, Bedrock fallback |
| Database | Aurora PostgreSQL (users, projects, usage), DynamoDB (run history), ElastiCache (rate limits) |
| Storage | S3 versioned project files with lifecycle rules; EBS for model hosts; CloudFront for the frontend |
| Networking | Multi-AZ VPC with public, private-app, and isolated-data subnets; ALB, NAT, VPC endpoints, Route 53 |
| Security | Cognito, least-privilege IAM, KMS, Secrets Manager, WAF, GuardDuty, CloudTrail |
| Monitoring | CloudWatch metrics and alarms, X-Ray, GPU metrics, token and cost dashboards |
| Backup and DR | Aurora PITR plus cross-region replica, S3 cross-region replication, AMI copies, pilot-light second region |

## 7. Cost and guardrails
- g4dn.xlarge is billed only while running; a stopped instance costs only EBS (a few dollars a month).
- AWS Budgets alerts at $10 and $20; idle shutdown script; terminate everything after evaluation.
- GPU quota ("Running On-Demand G and VT instances") must be requested before first launch.

## 8. Milestones
1. AWS account, budget alert, GPU quota request.
2. Sandbox runner working locally; editor and Run button.
3. vLLM serving the model; agent loop connected.
4. Deploy on EC2, idle shutdown, SSH tunnel access.
5. Report: production architecture, prototype screenshots, cost summary.

## 9. Acceptance criteria
- Run executes C++ and Python and reports compile errors, runtime errors, and timeouts correctly.
- Network access from user code fails inside the sandbox.
- Agent solves a typical Easy problem end to end and retries after a deliberately failing test.
- Instance stops itself after the idle limit.
- Total spend stays under $20.

## 10. Risks
| Risk | Mitigation |
|---|---|
| Small model fails on Medium/Hard problems | Write-run-fix loop; stronger model on a g5 instance or a hosted fallback via the gateway |
| GPU quota is 0 on a new account | Request the increase first; CPU-only small-model fallback |
| Malicious or runaway code | Sandbox limits, no network, timeouts, localhost-only server |
| Forgotten running instance | Idle shutdown cron, budget alerts |
