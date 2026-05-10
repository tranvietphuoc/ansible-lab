# Ansible Lab Guide — Deploy với Teleport

## Điều kiện tiên quyết

Lab đã chạy và Ansible ping thành công:

```bash
ansible all -m ping
# node-01 | SUCCESS => {"ping": "pong"}
# node-02 | SUCCESS => {"ping": "pong"}
```

Nếu chưa được, xem README.md để setup Teleport trước.

---

## Phase 1: Nginx Web Server

### Mục tiêu học
- Playbook cơ bản (tasks, become, hosts)
- Module: apt, template, service, file, debug
- Handler (restart service khi config thay đổi)
- Variable và Jinja2 template

### Chạy playbook

```bash
cd /home/teleport/ansible

# Bước 1: Setup hệ thống (cài packages, timezone)
ansible-playbook playbooks/01-system-setup.yaml
```

**Output mong đợi:**
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
# Bước 2: Deploy nginx
ansible-playbook playbooks/02-deploy-nginx.yaml
```

**Output mong đợi:**
```
TASK [Verify nginx is responding] *****************
ok: [node-01]
ok: [node-02]

TASK [Show result] ********************************
ok: [node-01] => {"msg": "Nginx running on node-01:80 (HTTP 200)"}
ok: [node-02] => {"msg": "Nginx running on node-02:80 (HTTP 200)"}
```

### Kiểm tra kết quả

```bash
# Từ trong container teleport-master
curl http://node-01
curl http://node-02

# Hoặc dùng tsh ssh
tsh ssh root@node-01 curl -s localhost
```

Mỗi node sẽ hiện trang web khác nhau (hostname, IP khác nhau) vì được render từ Jinja2 template.

### Cấu trúc role nginx

```
roles/nginx/
  ├── defaults/main.yaml      # Biến mặc định (có override trong group_vars)
  ├── handlers/main.yaml      # Reload/restart nginx khi config thay đổi
  ├── tasks/main.yaml         # Cài nginx, deploy config + index.html
  └── templates/
      ├── nginx.conf.j2       # Config template (dùng biến nginx_port)
      └── index.html.j2       # Trang web template (dùng biến inventory_hostname)
```

### Thử thay đổi variable

Sửa `group_vars/webservers.yaml`:

```yaml
nginx_port: 8080    # Đổi port
site_title: "My Lab"
```

Chạy lại:

```bash
ansible-playbook playbooks/02-deploy-nginx.yaml
```

Nginx sẽ reload (handler được trigger) và lắng nghe port 8080.

---

## Phase 2: Monitoring (Prometheus + Node Exporter)

### Mục tiêu học
- Multi-play playbook (nhiều plays trong 1 file)
- Role structure đầy đủ (tasks, handlers, defaults, templates)
- Module mới: get_url, unarchive, user, systemd
- group_vars cho nhóm host khác nhau
- delegate_to, when, register

### Chạy playbook

```bash
ansible-playbook playbooks/03-deploy-monitoring.yaml
```

**Output mong đợi:**
```
PLAY [Deploy Node Exporter] ***********************
TASK [Download node_exporter] *********************
changed: [node-01]
changed: [node-02]

PLAY [Deploy Prometheus] **************************
TASK [Verify prometheus is running] ***************
ok: [teleport-master]
```

### Kiểm tra kết quả

```bash
# Node exporter trên node-01
curl http://node-01:9100/metrics | head -5

# Prometheus trên master
curl http://teleport-master:9090/-/healthy
```

### Nội dung chính của playbook

Playbook `03-deploy-monitoring.yaml` có 3 plays:
1. **Install curl** — chạy trên tất cả hosts
2. **Deploy node-exporter** — chỉ chạy trên group `webservers`
3. **Deploy prometheus** — chỉ chạy trên group `monitoring` (teleport-master)

### Thử restart lại service

```bash
# Dùng ansible để restart node-exporter trên tất cả nodes
ansible webservers -m systemd -a "name=node-exporter state=restarted" --become
```

---

## Phase 3: Full Stack (Webapp + Reverse Proxy)

### Mục tiêu học
- Multi-role trong 1 playbook (webapp → nginx)
- pre_tasks / post_tasks
- block / rescue (error handling)
- Reverse proxy config

### Chạy playbook

```bash
ansible-playbook playbooks/04-deploy-fullstack.yaml
```

**Output mong đợi:**
```
TASK [Health check - nginx proxy] *****************
ok: [node-01]
ok: [node-02]

TASK [Show results] *******************************
ok: [node-01] => {"msg": "node-01 - App: 200, Proxy: 200"}
ok: [node-02] => {"msg": "node-02 - App: 200, Proxy: 200"}
```

### Kiểm tra kết quả

```bash
# API trả về JSON
curl http://node-01
# {"app":"Teleport Lab App","host":"node-01","visitors":0,...}

# Ghi nhận visitor
curl -X POST http://node-01/visit
# {"status":"recorded","total_visitors":1}

# Xem lại trạng thái
curl http://node-01
# "visitors": 1
```

### Health check

```bash
ansible-playbook playbooks/05-health-check.yaml
```

**Output mong đợi:**
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

## Các lệnh Ansible hữu ích

### Thao tác nhanh (không cần playbook)

```bash
# Ping tất cả
ansible all -m ping

# Ping chỉ webservers
ansible webservers -m ping

# Chạy 1 lệnh trên tất cả nodes
ansible webservers -m shell -a "uptime"

# Xem facts (thông tin hệ thống)
ansible webservers -m setup

# Cài 1 package nhanh
ansible webservers -m apt -a "name=htop state=present" --become

# Restart 1 service
ansible webservers -m systemd -a "name=nginx state=restarted" --become

# Copy 1 file lên node
ansible webservers -m copy -a "src=/tmp/test.txt dest=/tmp/test.txt"
```

### Kiểm tra playbook trước khi chạy

```bash
# Kiểm tra cú pháp
ansible-playbook playbooks/02-deploy-nginx.yaml --syntax-check

# Dry run (không thay đổi gì)
ansible-playbook playbooks/02-deploy-nginx.yaml --check

# Chỉ chạy trên 1 node
ansible-playbook playbooks/02-deploy-nginx.yaml --limit node-01

# Verbose output
ansible-playbook playbooks/02-deploy-nginx.yaml -v
```

---

## Tổng hợp quy trình deploy

```
Bước 1: ansible-playbook 01-system-setup.yaml
  |     Cài packages cơ bản, đặt timezone
  v
Bước 2: ansible-playbook 02-deploy-nginx.yaml
  |     Deploy Nginx + static site
  |     Kết quả: http://node-01, http://node-02
  v
Bước 3: ansible-playbook 03-deploy-monitoring.yaml
  |     Deploy node-exporter + prometheus
  |     Kết quả: http://teleport-master:9090
  v
Bước 4: ansible-playbook 04-deploy-fullstack.yaml
  |     Deploy Flask app + nginx reverse proxy
  |     Kết quả: API JSON tại http://node-01
  v
Bước 5: ansible-playbook 05-health-check.yaml
        Báo cáo trạng thái tất cả services
```

---

## Teleport + Ansible kết hợp

### Kiểm tra SSH qua Teleport

```bash
# Xem nodes
tsh ls

# SSH vào node để kiểm tra thủ công
tsh ssh root@node-01

# Truyền file từ local lên node
echo "test" > /tmp/test.txt
tsh scp /tmp/test.txt root@node-01:/tmp/

# Xem audit log của các SSH session
tsh recordings ls
```

### WebUI

Mở `https://localhost:3080`:
- **Nodes**: xem danh sách nodes và trạng thái
- **Sessions**: xem SSH sessions (live và recorded)
- **Audit**: xem log tất cả thao tác
- **Access**: quản lý user và role
