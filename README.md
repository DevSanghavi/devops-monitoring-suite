# DevOps Monitoring Suite

A monitoring and operations suite for the existing Project 1 EC2 instance. It adds CloudWatch Agent metrics, alarms, SNS notifications, automated S3 log backups, systemd scheduling, log rotation, and a simple health dashboard without recreating or disrupting the existing Project 1 or Project 2 stacks.

## Architecture

```text
GitHub Actions
      |
      v
Existing Project 1 EC2 (monitoring target)
      |
      +-- CloudWatch Agent --> CloudWatch custom RAM/disk metrics
      +-- CloudWatch Alarms --> SNS topic --> confirmed email
      +-- Backup script --> compressed date-stamped logs --> S3 backup bucket
      +-- systemd timer --> daily backup schedule
      +-- logrotate --> Nginx and application log rotation
      +-- Nginx container --> simple HTML health dashboard
```

The monitoring target is the existing Project 1 EC2 instance. Its instance ID, public IP, and security group ID are discovered by AWS CLI and stored as non-secret GitHub variables. Project 2 production remains on port 80 and staging remains on port 8080.

## Build Map

| Day | Project Day | Work |
|---|---:|---|
| 136 | 1 | Project planning, repository setup, EC2 discovery, blueprint, GitHub variables, baseline health checks |
| 137 | 2 | Install and configure CloudWatch Agent for RAM and disk metrics |
| 138 | 3 | Create CPU, memory, and disk CloudWatch alarms |
| 139 | 4 | Configure SNS email notifications for alarm state changes |
| 140 | 5 | Create a Bash backup script that compresses logs and uploads date-stamped archives to S3 |
| 141 | 6 | Schedule the backup script with a systemd service and timer |
| 142 | 7 | Configure logrotate for Nginx and application logs |
| 143 | 8 | Create a simple HTML health dashboard served by the existing Nginx container |
| 144 | 9 | Add GitHub Actions deployment for monitoring scripts and dashboard |
| 145 | 10 | Write on-call runbook, alarm response steps, and architecture documentation |

## Final File Tree

```text
devops-monitoring-suite/
├── .env (local only, ignored)
├── .env.example
├── .gitignore
├── README.md
├── config/
│   ├── cloudwatch-agent-config.json
│   ├── logrotate-app.conf
│   └── logrotate-nginx.conf
├── scripts/
│   ├── backup-logs.sh
│   └── deploy-monitoring.sh
├── systemd/
│   ├── devops-monitoring-backup.service
│   └── devops-monitoring-backup.timer
├── dashboard/
│   └── index.html
├── docs/
│   ├── architecture.md
│   ├── on-call-runbook.md
│   └── alarm-response.md
└── .github/workflows/
    └── deploy-monitoring.yml
```

## Safety Rules

- Never terminate, recreate, or destroy the existing Project 1 EC2, RDS, VPC, or Project 2 resources.
- Never stop or restart the existing `terraform-aws-infra-nginx` container.
- Change Nginx configuration only by writing the host bind-mount source file with `sudo tee`, validating with `nginx -t`, and reloading with `nginx -s reload`.
- Discover all EC2 values with AWS CLI; never hardcode them.
- Create new Project 3 resources with the `devops-monitoring-` prefix and least-privilege permissions.
- Keep backups in S3; never delete backup objects.

## Documentation

- docs/architecture.md: components, monitoring flow, deployment flow, and boundaries.
- docs/on-call-runbook.md: first response, quick checks, backups, redeploy, and Nginx restore.
- docs/alarm-response.md: step-by-step response for CPU, memory, disk, notifications, and deployment failures.

## Status

Project 3 is complete (Days 136-145). Metrics, alarms, email alerts, daily S3 log backups, systemd scheduling, log rotation, the Nginx dashboard, and GitHub Actions deployment all run against the existing Project 1 EC2. Cleanup is documentation only; nothing is ever destroyed.
