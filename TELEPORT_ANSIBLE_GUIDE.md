# Teleport + Ansible: Hướng dẫn cấu hình môi trường thực tế

## Mô tả

Hướng dẫn triển khai Teleport làm SSH proxy cho Ansible trên môi trường thực tế (physical server hoặc VM).

## Kiến trúc

```
                        Internet / VPN
                             |
                    +--------+--------+
                    |  Teleport Proxy  |
                    |  (WebUI + SSH)   |
                    |  domain: ssh.example.com
                    +--------+--------+
                             |
                    +--------+--------+
                    |  Teleport Auth  |
                    |  Server         |
                    +--------+--------+
                             |
              +--------------+--------------+
              |                             |
     +--------+--------+          +--------+--------+
     |    Node-01       |          |    Node-02       |
     |  (Ansible target)|          |  (Ansible target)|
     +------------------+          +------------------+

     +------------------+
     | Ansible Control  |  ---> Teleport proxy ---> Nodes
     | (có tsh + ansible)|
     +------------------+
```

### 3 thành phần chính

| Thành phần | Vai trò | Chạy trên |
|-----------|---------|-----------|
| Teleport Auth Server | Quản lý user, certificate, RBAC | Server riêng hoặc chung Proxy |
| Teleport Proxy | SSH proxy, WebUI, API | Server có public IP/domain |
| Teleport Agent | SSH service trên node | Mỗi target node |

Ansible control node có thể là laptop của bạn hoặc một server riêng.

---

## Phần 1: Cài đặt Teleport Auth + Proxy

### 1.1 Yêu cầu

- 1 server với public IP hoặc domain (ví dụ: `ssh.example.com`)
- OS: Ubuntu 22.04/24.04, Debian 12, RHEL 8/9
- Port mở: 443 (WebUI/API), 3023 (SSH proxy)
- DNS record trỏ domain đến IP server

### 1.2 Cài đặt Teleport

**Ubuntu/Debian:**

```bash
# Thêm repository
curl https://goteleport.com/static/install.sh | bash -s <version>
# Ví dụ:
curl https://goteleport.com/static/install.sh | bash -s v18.7.6

# Hoặc dùng apt
sudo apt-get install teleport
```

**RHEL/CentOS:**

```bash
sudo yum-config-manager --add-repo https://rpm.releases.teleport.dev/teleport.repo
sudo yum install teleport-18.7.6
```

### 1.3 Cấu hình Teleport

Tạo file `/etc/teleport.yaml` trên Auth/Proxy server:

```yaml
version: v3
teleport:
  nodename: teleport-proxy
  data_dir: /var/lib/teleport
  log:
    output: stderr
    severity: INFO

auth_service:
  enabled: "yes"
  listen_addr: 0.0.0.0:3025
  # Token cho node join — ĐỔI thành giá trị ngẫu nhiên
  tokens:
    - "node:changeme-use-a-strong-random-token"
    - "auth:changeme-auth-join-token"
  # Cấu hình TLS — cần certificate cho domain
  cluster_name: ssh.example.com

proxy_service:
  enabled: "yes"
  web_listen_addr: 0.0.0.0:443
  # Dùng Let's Encrypt tự động
  acme:
    enabled: true
    email: admin@example.com
  ssh_public_addr: ssh.example.com:3023
  tunnel_public_addr: ssh.example.com:443

ssh_service:
  enabled: "no"    # Không cần SSH service trên Proxy server
```

### 1.4 Khởi động Teleport

```bash
# Cấu hình systemd
sudo systemctl enable teleport
sudo systemctl start teleport

# Kiểm tra
sudo teleport status
```

### 1.5 Mở firewall

```bash
# UFW (Ubuntu)
sudo ufw allow 443/tcp     # WebUI + API
sudo ufw allow 3023/tcp    # SSH proxy
sudo ufw allow 3025/tcp    # Auth (chỉ mở nội bộ, không mở ra internet)

# Hoặc firewalld (RHEL)
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=3023/tcp
sudo firewall-cmd --reload
```

---

## Phần 2: Cài đặt Teleport Agent trên target nodes

Làm tương tự cho mỗi node cần quản lý.

### 2.1 Cài đặt Teleport

```bash
# Cùng cách cài đặt như trên Auth/Proxy
curl https://goteleport.com/static/install.sh | bash -s v18.7.6
```

### 2.2 Cấu hình Agent

Tạo file `/etc/teleport.yaml` trên mỗi node:

```yaml
version: v3
teleport:
  nodename: node-01          # ĐỔI tên cho mỗi node
  data_dir: /var/lib/teleport
  join_params:
    token_name: changeme-use-a-strong-random-token
    method: token
  proxy_server: ssh.example.com:443

auth_service:
  enabled: "no"

proxy_service:
  enabled: "no"

ssh_service:
  enabled: "yes"
  labels:
    env: production
    role: web
```

### 2.3 Khởi động và kiểm tra

```bash
sudo systemctl enable teleport
sudo systemctl start teleport

# Xem log để kiểm tra join
sudo journalctl -u teleport -f
```

### 2.4 Xác nhận trên Auth server

```bash
# Chạy trên Auth/Proxy server
tctl nodes ls
```

Phải thấy node mới trong danh sách.

---

## Phần 3: Quản lý User và Role

### 3.1 Tạo user

```bash
# Chạy trên Auth server
tctl users add ansible-admin --roles=editor,access
```

Mở link output trên trình duyệt để đặt mật khẩu và MFA.

### 3.2 Tạo role cho phép SSH login

Role mặc định `access` có thể không cho login `root`. Tạo role riêng:

```bash
cat <<'EOF' | tctl create -f
kind: role
version: v5
metadata:
  name: ansible-access
spec:
  allow:
    logins: [root, ansible]
    node_labels:
      "*": "*"
    rules:
      - resources: [session]
        verbs: [read, list]
      - resources: [event]
        verbs: [list, read]
  options:
    max_session_ttl: 30h0m0s
    forward_agent: true
    ssh_file_copy: true
EOF
```

Gán role cho user:

```bash
tctl users update ansible-admin --set-roles=editor,access,ansible-access
```

### 3.3 Tạo role hạn chế (ví dụ: chỉ truy cập node production)

```bash
cat <<'EOF' | tctl create -f
kind: role
version: v5
metadata:
  name: prod-readonly
spec:
  allow:
    logins: [readonly]
    node_labels:
      env: production
    rules:
      - resources: [session, event]
        verbs: [read, list]
  options:
    max_session_ttl: 8h0m0s
    forward_agent: false
EOF
```

---

## Phần 4: Cấu hình Ansible Control Node

Ansible control node có thể là laptop của bạn hoặc một server riêng.

### 4.1 Cài đặt

```bash
# Cài đặt Teleport client
curl https://goteleport.com/static/install.sh | bash -s v18.7.6

# Cài đặt Ansible
pip install ansible
# Hoặc
sudo apt install ansible
```

### 4.2 Đăng nhập vào Teleport

```bash
tsh login --proxy=ssh.example.com --user=ansible-admin
```

Kiểm tra:

```bash
tsh status
# Phải thấy Roles: access, editor, ansible-access
# Phải thấy Logins: root, ansible

tsh ls
# Phải thấy danh sách nodes
```

### 4.3 Tạo SSH config cho Ansible

```bash
mkdir -p ~/.ssh

# Tự động generate từ Teleport
tsh config > ~/.ssh/config
```

Lệnh `tsh config` sẽ generate config dạng:

```
Host *.ssh.example.com ssh.example.com
    UserKnownHostsFile ~/.tsh/known_hosts
    IdentityFile ~/.tsh/keys/ssh.example.com/ansible-admin
    CertificateFile ~/.tsh/keys/ssh.example.com/ansible-admin-ssh/teleport-proxy-cert.pub

Host *.ssh.example.com !ssh.example.com
    Port 3022
    ProxyCommand /usr/local/bin/tsh proxy ssh --cluster=ssh.example.com --proxy=ssh.example.com:443 %r@%h:%p
```

### 4.4 Cấu hình Ansible

**ansible.cfg:**

```ini
[defaults]
inventory = ./inventory.ini
host_key_checking = False
remote_user = root
stdout_callback = default

[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=30m
```

**inventory.ini:**

```ini
[webservers]
node-01.ssh.example.com
node-02.ssh.example.com

[webservers:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_port=3022

[dbservers]
db-01.ssh.example.com

[dbservers:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_port=3022

[all:children]
webservers
dbservers
```

**Lưu ý:** Tên host trong inventory phải có hậu tố `.ssh.example.com` (khớp với SSH config pattern `*.ssh.example.com`).

### 4.5 Kiểm tra

```bash
# Kiểm tra SSH trực tiếp
tsh ssh root@node-01 hostname

# Kiểm tra SSH qua config
ssh root@node-01.ssh.example.com hostname

# Kiểm tra Ansible
ansible all -m ping
```

---

## Phần 5: Tự động hoá với Script

### 5.1 Script khởi tạo Ansible session

Tạo file `/usr/local/bin/ansible-teleport`:

```bash
#!/bin/bash
# Tự động login Teleport và generate SSH config cho Ansible

set -e

PROXY="ssh.example.com"
USER="ansible-admin"

echo "==> Đăng nhập Teleport..."
tsh login --proxy="$PROXY" --user="$USER"

echo "==> Tạo SSH config..."
mkdir -p ~/.ssh
tsh config > ~/.ssh/config
chmod 600 ~/.ssh/config

echo "==> Sẵn sàng! Kiểm tra nodes..."
tsh ls

echo ""
echo "Chạy: ansible all -m ping"
```

```bash
chmod +x /usr/local/bin/ansible-teleport
```

### 5.2 Ansible playbook mẫu

```yaml
---
- name: "Kiểm tra trạng thái hệ thống"
  hosts: all
  become: yes
  tasks:
    - name: Thông tin OS
      ansible.builtin.setup:

    - name: Dung lượng ổ đĩa
      ansible.builtin.command: df -h
      register: disk_info
      changed_when: false

    - name: Hiển thị ổ đĩa
      ansible.builtin.debug:
        msg: "{{ disk_info.stdout_lines }}"

    - name: Thời gian hoạt động
      ansible.builtin.command: uptime
      register: uptime_info
      changed_when: false

    - name: Hiển thị uptime
      ansible.builtin.debug:
        msg: "{{ uptime_info.stdout }}"
```

---

## Phần 6: Security Best Practices

### 6.1 Quản lý Token

- **Không dùng static token trong production** — dùng token tạm thời (`tctl nodes add --ttl=30m`)
- Sau khi node join thành công, certificate được tự động làm mới
- Thu hồi token khi không cần: `tctl tokens rm <token>`

### 6.2 Phân quyền theo Role

```yaml
# Ví dụ: Admin được tất cả, Operator chỉ được deploy, Viewer chỉ đọc
kind: role
version: v5
metadata:
  name: operator
spec:
  allow:
    logins: [deploy]
    node_labels:
      env: production
    rules:
      - resources: [session]
        verbs: [read, list]
  options:
    max_session_ttl: 4h0m0s
```

### 6.3 TLS / Certificate

- Dùng Let's Encrypt cho domain công khai (cấu hình `acme` trong proxy_service)
- Hoặc dùng certificate từ CA riêng
- Không bao giờ dùng `insecure: true` trong production

### 6.4 Backup Auth server

```bash
# Backup cấu hình và keys
sudo tar czf teleport-backup-$(date +%Y%m%d).tar.gz /var/lib/teleport/

# Lưu trữ an toàn (mã hoá, offsite)
```

### 6.5 Audit logging

Teleport tự động log tất cả SSH session. Xem:

```bash
# Danh sách session
tsh recordings ls

# Replay session
tsh play <session-id>

# Tìm kiếm trong audit log
tctl audit query --query "event = session.start"
```

---

## Phần 7: Xử lý sự cố

### Node không join được

```bash
# Trên node, xem log
sudo journalctl -u teleport -f

# Kiểm tra kết nối đến proxy
curl -k https://ssh.example.com:443/webapi/ping

# Kiểm tra token trên auth server
tctl tokens ls
```

### SSH bị từ chối truy cập

```bash
# Kiểm tra user roles
tctl get user/ansible-admin

# Kiểm tra role cho phép logins gì
tctl get role/ansible-access

# Đăng nhập lại sau khi update role
tsh logout
tsh login --proxy=ssh.example.com --user=ansible-admin
```

### Ansible kết nối thất bại

```bash
# Kiểm tra SSH config
cat ~/.ssh/config

# Kiểm tra certificate còn hạn
tsh status

# Tạo lại SSH config
tsh config > ~/.ssh/config

# Kiểm tra SSH trực tiếp
ssh -vvv root@node-01.ssh.example.com hostname
```

### Certificate hết hạn

```bash
# Teleport certificate có TTL (mặc định 12h)
# Đăng nhập lại để làm mới
tsh login --proxy=ssh.example.com --user=ansible-admin

# Tạo lại SSH config
tsh config > ~/.ssh/config
```

---

## So sánh Docker Lab vs Production

| Yếu tố | Docker Lab | Production |
|---------|-----------|------------|
| OS | Container (Debian) | VM/Physical server |
| TLS | Self-signed | Let's Encrypt hoặc CA riêng |
| Domain | localhost | ssh.example.com |
| Token | Static (teleport.yaml) | Tạm thời (`tctl nodes add`) |
| User | admin (password) | SSO/OIDC/SAML hoặc MFA |
| SSH config | Tạo thủ công | `tsh config` tự động |
| Inventory | node-01, node-02 | node-01.ssh.example.com |
| Dữ liệu | Docker volume | /var/lib/teleport (backup định kỳ) |
| Mạng | Docker bridge | Firewall, VPN, security group |
