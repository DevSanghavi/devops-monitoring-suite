# Alarm Response Guide

## Alarm Overview

| Alarm | Metric | Triggers when | Meaning |
|---|---|---|---|
| devops-monitoring-cpu-high-70 | AWS/EC2 CPUUtilization | Average above 70 percent for 2 periods | Sustained high CPU |
| devops-monitoring-memory-high-80 | DevOpsMonitoring mem_used_percent | Average above 80 percent for 2 periods | Sustained high memory use |
| devops-monitoring-disk-high-85 | DevOpsMonitoring disk_used_percent | Average above 85 percent for 2 periods | Root disk is filling up |

Each period is five minutes. Missing data is treated as not breaching. The disk alarm uses the full agent dimensions: InstanceId, path, device, and fstype.

Run the commands in this guide from the project folder after loading the local environment file with source .env.

## CPU Alarm

1. Check that production and staging health still pass.
2. Look at CPU for the last hour.
3. Find the busy container.
4. Check for a recent deployment or unusual traffic.
5. Read the application logs in CloudWatch Logs.
6. Do not restart or recreate the EC2 as a first response.

CPU history:

~~~bash
aws cloudwatch get-metric-statistics --profile "$PROFILE" --region "$REGION" --namespace AWS/EC2 --metric-name CPUUtilization --dimensions Name=InstanceId,Value="$EC2_INSTANCE_ID" --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)" --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" --period 300 --statistics Average --query 'sort_by(Datapoints,&Timestamp)[].Average' --output text
~~~

Per-container CPU and memory:

~~~bash
ssmrun 'docker stats --no-stream --format "{{.Name}} {{.CPUPerc}} {{.MemUsage}}"'
~~~

## Memory Alarm

1. Confirm health on ports 80 and 8080.
2. Check memory and the busiest processes.
3. Look for a leak, too many containers, or unexpected load.
4. If availability is at risk, escalate before acting.
5. Do not remove containers or touch the Nginx container without approval.

Memory and top processes:

~~~bash
ssmrun 'free -h; ps aux --sort=-%mem | head -n 6'
~~~

## Disk Alarm

1. Confirm usage on the root disk.
2. Check Docker log sizes and the backup log.
3. Confirm logrotate is active and has run.
4. Confirm recent backups exist in S3.
5. If logs are the cause, verify the logrotate policies.
6. Do not delete S3 objects or containers to free space.

Usage and largest log files:

~~~bash
ssmrun 'df -h /; du -sh /var/lib/docker/containers/*/*-json.log /home/ubuntu/devops-monitoring/backup.log* 2>/dev/null'
~~~

Logrotate status:

~~~bash
ssmrun 'systemctl is-active logrotate.timer; ls -lh /home/ubuntu/devops-monitoring/backup.log*'
~~~

## Test the Notification Path

Force the CPU alarm into the ALARM state, confirm the email arrives, then reset it:

~~~bash
aws cloudwatch set-alarm-state --profile "$PROFILE" --region "$REGION" --alarm-name "$CPU_ALARM_NAME" --state-value ALARM --state-reason "Notification test"
~~~

~~~bash
aws cloudwatch set-alarm-state --profile "$PROFILE" --region "$REGION" --alarm-name "$CPU_ALARM_NAME" --state-value OK --state-reason "Notification test completed"
~~~

## Deployment Failure

1. Open the failed GitHub Actions run.
2. Find which step failed: checkout, AWS authentication, the SSM command, or the remote Nginx test.
3. Read the SSM output and error text.
4. Confirm the EC2 is running and registered with SSM.
5. Confirm the deploy user still has its SSM permissions.
6. Re-run the workflow only after fixing the cause.

Show the failed log lines:

~~~bash
gh run view --repo DevSanghavi/devops-monitoring-suite --log-failed | tail -n 25
~~~
