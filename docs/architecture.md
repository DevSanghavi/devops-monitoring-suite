# DevOps Monitoring Suite Architecture

## Overview

The DevOps Monitoring Suite monitors the existing Project 1 EC2 instance without recreating or disrupting the Project 1 or Project 2 stacks. It collects host-level memory and disk metrics, evaluates CPU, memory, and disk alarms, sends alarm notifications by email, backs up container logs to S3, rotates local logs, serves a simple health dashboard through the existing Nginx container, and deploys its own scripts through GitHub Actions.

## Architecture Diagram

~~~text
GitHub Actions (deploy-monitoring.yml)
                  |
                  | AWS SSM Run Command (no SSH)
                  v
+---------------------------------------------------+
| Existing Project 1 EC2 (monitoring target)        |
|                                                   |
|  CloudWatch Agent                                 |
|    - publishes mem_used_percent                   |
|    - publishes disk_used_percent                  |
|    v                                              |
|  CloudWatch Metrics (DevOpsMonitoring)            |
|                                                   |
|  CloudWatch Alarms                                |
|    - CPU above 70 percent (AWS/EC2)              |
|    - Memory above 80 percent                      |
|    - Disk above 85 percent                        |
|    v                                              |
|  SNS Topic: devops-monitoring-alarms              |
|    v                                              |
|  Confirmed email subscriber                       |
|                                                   |
|  systemd timer (daily 23:45 UTC)                  |
|    - runs backup-logs.sh                          |
|    - compresses the last 24 hours of Docker logs  |
|    - uploads date-stamped archives to S3          |
|                                                   |
|  logrotate (runs after midnight UTC)              |
|    - rotates Docker JSON logs                     |
|    - rotates the backup operations log            |
|                                                   |
|  Nginx container                                  |
|    - serves /dashboard                            |
|    - proxies / and /health to the production API  |
+---------------------------------------------------+
                  |
                  v
   S3 backup bucket (devops-monitoring-logs-*)
   private, versioned, encrypted, upload-only
~~~

## Monitoring Flow

1. The CloudWatch Agent collects memory and root-disk usage every 60 seconds.
2. CloudWatch evaluates the CPU, memory, and disk alarms over two five-minute periods.
3. When an alarm enters the ALARM state, it publishes to the SNS topic.
4. SNS emails the confirmed subscriber.
5. The systemd timer runs the backup script daily at 23:45 UTC, before logrotate runs after midnight.
6. The script compresses the last 24 hours of logs from each application container and uploads them to S3 under a UTC time-stamped prefix.
7. logrotate keeps seven rotated copies and bounds local log growth.
8. Nginx serves the dashboard at /dashboard and keeps proxying production traffic.

## Deployment Flow

~~~text
Push to main
     |
     v
GitHub Actions workflow
     |
     v
IAM user devops-monitoring-deploy (SSM SendCommand on this EC2 only)
     |
     v
AWS SSM Run Command
     |
     v
Existing EC2
     +-- Deploy backup-logs.sh
     +-- Deploy dashboard HTML
     +-- Update the managed Nginx dashboard block (backup first)
     +-- Validate with nginx -t (restore on failure)
     +-- Reload Nginx without restart
     +-- Verify /dashboard and /health
~~~

## Resource Boundaries

- The existing Project 1 VPC, EC2, RDS, and S3 state bucket remain running.
- The existing Project 2 staging and production containers remain running.
- The existing Nginx container is never stopped or restarted.
- Nginx changes are made only through its host bind-mount configuration file.
- New Project 3 resources use the devops-monitoring- prefix.
- S3 backup objects are never deleted by Project 3 automation.
