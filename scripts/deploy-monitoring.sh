#!/usr/bin/env bash
set -euo pipefail
: "${EC2_INSTANCE_ID:?EC2_INSTANCE_ID is required}"
: "${AWS_REGION:?AWS_REGION is required}"
export AWS_PAGER=""
command -v aws >/dev/null || { echo "FAIL: AWS CLI not found"; exit 1; }
[[ -f dashboard/index.html ]] || { echo "FAIL: dashboard/index.html not found"; exit 1; }
[[ -f scripts/backup-logs.sh ]] || { echo "FAIL: scripts/backup-logs.sh not found"; exit 1; }
cat > /tmp/apply_dashboard.py << 'PY'
import re, subprocess, sys, time
CONF = "/home/ubuntu/app/nginx/default.conf"
HTML = "/tmp/dashboard.html"
NGINX = "terraform-aws-infra-nginx"
BACKUP = "/home/ubuntu/devops-monitoring/nginx-default.conf.backup-" + time.strftime("%Y%m%d%H%M%S")
html = re.sub(r"\s+", " ", open(HTML).read()).strip()
if not html.isascii() or any(c in html for c in ["'", "$", "\\"]):
    print("FAIL: dashboard HTML must be ASCII with no single quote, dollar sign, or backslash")
    sys.exit(1)
orig = open(CONF).read()
open(BACKUP, "w").write(orig)
s = re.sub(r"[ \t]*# BEGIN devops-monitoring-dashboard.*?# END devops-monitoring-dashboard\n?", "", orig, flags=re.S)
if "location = /dashboard" in s:
    print("FAIL: /dashboard already defined outside the managed block")
    sys.exit(1)
chunks = [html[i:i + 3000] for i in range(0, len(html), 3000)]
lines = ["    # BEGIN devops-monitoring-dashboard", "    location = /dashboard {", "        default_type text/html;", "        charset utf-8;"]
for n, c in enumerate(chunks):
    lines.append("        set $dash%d '%s';" % (n, c))
lines.append('        return 200 "' + "".join("${dash%d}" % n for n in range(len(chunks))) + '";')
lines += ["    }", "    # END devops-monitoring-dashboard", ""]
block = "\n".join(lines)
i = s.rstrip().rfind("}")
if i < 0:
    print("FAIL: no closing brace in Nginx config")
    sys.exit(1)
open(CONF, "w").write(s[:i] + block + s[i:])
t = subprocess.run(["docker", "exec", NGINX, "nginx", "-t"], capture_output=True, text=True)
print(t.stderr.strip())
if t.returncode != 0:
    open(CONF, "w").write(orig)
    print("FAIL: nginx -t failed, original config restored")
    sys.exit(1)
r = subprocess.run(["docker", "exec", NGINX, "nginx", "-s", "reload"], capture_output=True, text=True)
print(r.stderr.strip())
print("DASHBOARD_APPLIED" if r.returncode == 0 else "FAIL: reload failed")
sys.exit(r.returncode)
PY
HTML_B64=$(base64 -w0 dashboard/index.html)
BACKUP_B64=$(base64 -w0 scripts/backup-logs.sh)
PY_B64=$(base64 -w0 /tmp/apply_dashboard.py)
COMMAND=$(printf 'mkdir -p /home/ubuntu/devops-monitoring && echo %s | base64 -d > /tmp/dashboard.html && echo %s | base64 -d > /home/ubuntu/devops-monitoring/backup-logs.sh && chmod +x /home/ubuntu/devops-monitoring/backup-logs.sh && echo %s | base64 -d > /tmp/apply_dashboard.py && python3 /tmp/apply_dashboard.py && curl -fsS http://localhost/dashboard >/dev/null && curl -fsS http://localhost/health >/dev/null && echo DEPLOY_OK' "$HTML_B64" "$BACKUP_B64" "$PY_B64")
PARAMS=$(python3 -c 'import json,sys;print(json.dumps({"commands":[sys.argv[1]]}))' "$COMMAND")
COMMAND_ID=$(aws ssm send-command --region "$AWS_REGION" --instance-ids "$EC2_INSTANCE_ID" --document-name AWS-RunShellScript --parameters "$PARAMS" --query Command.CommandId --output text)
sleep 3
aws ssm wait command-executed --region "$AWS_REGION" --command-id "$COMMAND_ID" --instance-id "$EC2_INSTANCE_ID" || true
STATUS=$(aws ssm get-command-invocation --region "$AWS_REGION" --command-id "$COMMAND_ID" --instance-id "$EC2_INSTANCE_ID" --query Status --output text)
aws ssm get-command-invocation --region "$AWS_REGION" --command-id "$COMMAND_ID" --instance-id "$EC2_INSTANCE_ID" --query StandardOutputContent --output text
aws ssm get-command-invocation --region "$AWS_REGION" --command-id "$COMMAND_ID" --instance-id "$EC2_INSTANCE_ID" --query StandardErrorContent --output text >&2
echo "SSM_STATUS=$STATUS"
[[ "$STATUS" == "Success" ]] || { echo "FAIL: deployment command did not succeed"; exit 1; }
