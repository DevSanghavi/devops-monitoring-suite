# On-Call Runbook

## Purpose

First actions to take when the DevOps Monitoring Suite reports an alarm or a service looks unhealthy.

## Setup

Run all commands from the project folder after loading the local environment file.

~~~bash
cd ~/cloud-practice/devops-monitoring-suite && source .env
~~~

The local .env file is git-ignored. It holds PROFILE, REGION, the EC2 values, the alarm names, the SNS topic, the backup bucket, the dashboard URL, and the ssmrun helper, which runs one shell command on the EC2 through SSM and prints the result. If the file is missing, .env.example lists every variable name and contains the ssmrun helper. The EC2 values are also stored as GitHub variables and can be read with gh variable list.

## First Response Steps

1. Open the dashboard and check whether the production API shows HEALTHY.
2. Check the production and staging health endpoints.
3. Identify which alarm fired: CPU, memory, or disk.
4. Inspect the instance with SSM.
5. Follow the matching section in docs/alarm-response.md.
6. Never terminate, recreate, or destroy the EC2, RDS, VPC, or the Project 2 containers.
7. Record the cause, the action taken, and any follow-up.

## Quick Checks

Production health through Nginx:

~~~bash
curl -fsS "http://$EC2_PUBLIC_IP/health"
~~~

Staging health:

~~~bash
curl -fsS "http://$EC2_PUBLIC_IP:8080/health"
~~~

Alarm states:

~~~bash
aws cloudwatch describe-alarms --profile "$PROFILE" --region "$REGION" --alarm-names "$CPU_ALARM_NAME" "$MEMORY_ALARM_NAME" "$DISK_ALARM_NAME" --query 'MetricAlarms[].[AlarmName,StateValue]' --output text
~~~

CPU, memory, and root disk on the server:

~~~bash
ssmrun 'uptime; free -h; df -h /'
~~~

Running containers:

~~~bash
ssmrun 'docker ps --format "{{.Names}} {{.Status}}"'
~~~

## Backups

Check the backup timer and the next run:

~~~bash
ssmrun 'systemctl list-timers devops-monitoring-backup.timer --no-pager'
~~~

Run a backup now and check the result:

~~~bash
ssmrun 'systemctl start devops-monitoring-backup.service; systemctl show devops-monitoring-backup.service --property=Result --no-pager'
~~~

Show the newest backup folders:

~~~bash
aws s3 ls "s3://$BACKUP_BUCKET/" --profile "$PROFILE" --region "$REGION" | tail -n 5
~~~

## Redeploy the Monitoring Files

~~~bash
gh workflow run deploy-monitoring.yml --repo DevSanghavi/devops-monitoring-suite --ref main
~~~

## Restore the Nginx Configuration

Every dashboard deployment saves a backup of the Nginx configuration first. Restore the newest backup, test it, and reload:

~~~bash
ssmrun 'cat "$(ls -1t /home/ubuntu/devops-monitoring/nginx-default.conf.backup-* | head -n 1)" > /home/ubuntu/app/nginx/default.conf && docker exec terraform-aws-infra-nginx nginx -t && docker exec terraform-aws-infra-nginx nginx -s reload && echo RESTORED'
~~~

## Escalation

Escalate if any of these is true:

- Production or staging stays unhealthy after the first checks.
- Disk usage keeps rising after log rotation.
- Memory stays above 80 percent for more than 15 minutes.
- The backup service fails repeatedly or no new backup appears for more than 24 hours.
- The Nginx container is unhealthy or unavailable.

## Safety Rules

- Never run terraform destroy.
- Never run EC2 termination or resource deletion commands.
- Never stop or restart the existing Nginx container; only reload it.
- Never delete S3 backup objects.
- Make only narrow, reversible changes to the existing EC2.
