# Ansible Lab Guide - Deploy voi Teleport

## Dieu kien tien quyet

Lab da chay va Ansible ping thanh cong:

```bash
ansible all -m ping
# node-01 | SUCCESS => {"ping": "pong"}
# node-02 | SUCCESS => {"ping": "pong"}
```

Neu chua duoc, xem README.md de setup Teleport truoc.

---

## Phase 1: Nginx Web Server

### Muc tieu hoc
- Playbook co ban (tasks, become, hosts)
- Module: apt, template, service, file, debug
- Handler (restart service khi config thay doi)
- Variable va Jinja2 template

### Chay playbook

```bash
cd /home/teleport/ansible

# Buoc 1: Setup he thong (cai packages, timezone)
ansible-playbook playbooks/01-system-setup.yaml
```

**Output mong doi:**
```
TASK [Show system info] ***************************
ok: [node-01] => {
    "msg": "node-01 ready (Debian 12)"
}
ok: [node-02] => {
    "msg": "node-02 ready (Debian 12)"
}
```

```bash
# Buoc 2: Deploy nginx
ansible-playbook playbooks/02-deploy-nginx.yaml
```

**Output mong doi:**
```
TASK [Verify nginx is responding] *****************
ok: [node-01]
ok: [node-02]

TASK [Show result] ********************************
ok: [node-01] => {"msg": "Nginx running on node-01:80 (HTTP 200)"}
ok: [node-02] => {"msg": "Nginx running on node-02:80 (HTTP 200)"}
```

### Kiem tra ket qua

```bash
# Tu trong container teleport-master
curl http://node-01
curl http://node-02

# Hoac dung tsh ssh
tsh ssh root@node-01 curl -s localhost
```

Moi node se hien trang web khac nhau (hostname, IP khac nhau) vi duoc render tu Jinja2 template.

### Cau truc role nginx

```
roles/nginx/
  ├── defaults/main.yaml      # Bien mac dinh (co override trong group_vars)
  ├── handlers/main.yaml      # Reload/restart nginx khi config thay doi
  ├── tasks/main.yaml         # Cai nginx, deploy config + index.html
  └── templates/
      ├── nginx.conf.j2       # Config template (dung bien nginx_port)
      └── index.html.j2       # Trang web template (dung bien inventory_hostname)
```

### Thu thay doi variable

Sua `group_vars/webservers.yaml`:

```yaml
nginx_port: 8080    # Doi port
site_title: "My Lab"
```

Chay lai:

```bash
ansible-playbook playbooks/02-deploy-nginx.yaml
```

Nginx se reload (handler duoc trigger) va lang nghe port 8080.

---

## Phase 2: Monitoring (Prometheus + Node Exporter)

### Muc tieu hoc
- Multi-play playbook (nhieu plays trong 1 file)
- Role structure day du (tasks, handlers, defaults, templates)
- Module moi: get_url, unarchive, user, systemd
- group_vars cho nhom host khac nhau
- delegate_to, when, register

### Chay playbook

```bash
ansible-playbook playbooks/03-deploy-monitoring.yaml
```

**Output mong doi:**
```
PLAY [Deploy Node Exporter] ***********************
TASK [Download node_exporter] *********************
changed: [node-01]
changed: [node-02]

PLAY [Deploy Prometheus] **************************
TASK [Verify prometheus is running] ***************
ok: [teleport-master]
```

### Kiem tra ket qua

```bash
# Node exporter tren node-01
curl http://node-01:9100/metrics | head -5

# Prometheus tren master
curl http://teleport-master:9090/-/healthy
```

### Noi dung chinh cua playbook

Playbook `03-deploy-monitoring.yaml` co 3 plays:
1. **Install curl** - chay tren tat ca hosts
2. **Deploy node-exporter** - chi chay tren group `webservers`
3. **Deploy prometheus** - chi chay tren group `monitoring` (teleport-master)

### Thu restart lai service

```bash
# Dung ansible de restart node-exporter tren tat ca nodes
ansible webservers -m systemd -a "name=node-exporter state=restarted" --become
```

---

## Phase 3: Full Stack (Webapp + Reverse Proxy)

### Muc tieu hoc
- Multi-role trong 1 playbook (webapp -> nginx)
- pre_tasks / post_tasks
- block / rescue (error handling)
- Reverse proxy config

### Chay playbook

```bash
ansible-playbook playbooks/04-deploy-fullstack.yaml
```

**Output mong doi:**
```
TASK [Health check - nginx proxy] *****************
ok: [node-01]
ok: [node-02]

TASK [Show results] *******************************
ok: [node-01] => {"msg": "node-01 - App: 200, Proxy: 200"}
ok: [node-02] => {"msg": "node-02 - App: 200, Proxy: 200"}
```

### Kiem tra ket qua

```bash
# API tra ve JSON
curl http://node-01
# {"app":"Teleport Lab App","host":"node-01","visitors":0,...}

# Ghi nhan visitor
curl -X POST http://node-01/visit
# {"status":"recorded","total_visitors":1}

# Xem lai trang thai
curl http://node-01
# "visitors": 1
```

### Health check

```bash
ansible-playbook playbooks/05-health-check.yaml
```

**Output mong doi:**
```
=== node-01 ===
Nginx:    200
Webapp:   200
Exporter: OK

=== node-02 ===
Nginx:    200
Webapp:   200
Exporter: OK
```

---

## Cac lenh Ansible huu ich

### Thao tac nhanh (khong can playbook)

```bash
# Ping tat ca
ansible all -m ping

# Ping chi webservers
ansible webservers -m ping

# Chay 1 lenh tren tat ca nodes
ansible webservers -m shell -a "uptime"

# Xem facts (thong tin he thong)
ansible webservers -m setup

# Install 1 package nhanh
ansible webservers -m apt -a "name=htop state=present" --become

# Restart 1 service
ansible webservers -m systemd -a "name=nginx state=restarted" --become

# Copy 1 file len node
ansible webservers -m copy -a "src=/tmp/test.txt dest=/tmp/test.txt"
```

### Check playbook truoc khi chay

```bash
# Syntax check
ansible-playbook playbooks/02-deploy-nginx.yaml --syntax-check

# Dry run (khong thay doi gi)
ansible-playbook playbooks/02-deploy-nginx.yaml --check

# Chi chay tren 1 node
ansible-playbook playbooks/02-deploy-nginx.yaml --limit node-01

# Verbose output
ansible-playbook playbooks/02-deploy-nginx.yaml -v
```

---

## Tong hop quy trinh deploy

```
Buoc 1: ansible-playbook 01-system-setup.yaml
  |     Cai packages co ban, set timezone
  v
Buoc 2: ansible-playbook 02-deploy-nginx.yaml
  |     Deploy Nginx + static site
  |     Ket qua: http://node-01, http://node-02
  v
Buoc 3: ansible-playbook 03-deploy-monitoring.yaml
  |     Deploy node-exporter + prometheus
  |     Ket qua: http://teleport-master:9090
  v
Buoc 4: ansible-playbook 04-deploy-fullstack.yaml
  |     Deploy Flask app + nginx reverse proxy
  |     Ket qua: API JSON tai http://node-01
  v
Buoc 5: ansible-playbook 05-health-check.yaml
        Bao cao trang thai tat ca services
```

---

## Teleport + Ansible ket hop

### Kiem tra SSH qua Teleport

```bash
# Xem nodes
tsh ls

# SSH vao node de kiem tra thu cong
tsh ssh root@node-01

# Truyen file tu local len node
echo "test" > /tmp/test.txt
tsh scp /tmp/test.txt root@node-01:/tmp/

# Xem audit log cua cac SSH session
tsh recordings ls
```

### WebUI

Mo `https://localhost:3080`:
- **Nodes**: xem danh sach nodes va trang thai
- **Sessions**: xem SSH sessions (live va recorded)
- **Audit**: xem log tat ca thao tac
- **Access**: quan ly user va role
