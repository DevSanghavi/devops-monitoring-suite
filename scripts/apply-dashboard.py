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
