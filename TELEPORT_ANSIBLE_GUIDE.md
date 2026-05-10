# Teleport + Ansible: Huong dan cau hinh moi truong thuc te

## Mo ta

Huong dan trien khai Teleport lam SSH proxy cho Ansible tren moi truong thuc te (physical server hoac VM).

## Kien truc

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
     | (co tsh + ansible)|
     +------------------+
```

### 3 thanh phan chinh

| Thanh phan | Vai tro | Di chay tren |
|------------|---------|--------------|
| Teleport Auth Server | Quan ly user, certificate, RBAC | Server rieng hoac cung Proxy |
| Teleport Proxy | SSH proxy, WebUI, API | Server co public IP/domain |
| Teleport Agent | SSH service tren node | Moi target node |

Ansible control node co the la mot server rieng hoac chay chung voi Auth/Proxy.

---

## Phan 1: Cai dat Teleport Auth + Proxy

### 1.1 Yeu cau

- 1 server voi public IP hoac domain (vd: `ssh.example.com`)
- OS: Ubuntu 22.04/24.04, Debian 12, RHEL 8/9
- Port mo: 443 (WebUI/API), 3023 (SSH proxy)
- DNS record tro domain den IP server

### 1.2 Cai dat Teleport

**Ubuntu/Debian:**

```bash
# Them repository
curl https://goteleport.com/static/install.sh | bash -s <version>
# Vi du:
curl https://goteleport.com/static/install.sh | bash -s v18.7.6

# Hoac dung apt
sudo apt-get install teleport
```

**RHEL/CentOS:**

```bash
sudo yum-config-manager --add-repo https://rpm.releases.teleport.dev/teleport.repo
sudo yum install teleport-18.7.6
```

### 1.3 Cau hinh Teleport

Tao file `/etc/teleport.yaml` tren Auth/Proxy server:

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
  # Token cho node join - DOI thanh gia tri ngau nhien
  tokens:
    - "node:changeme-use-a-strong-random-token"
    - "auth:changeme-auth-join-token"
  # Cau hinh TLS - can certificate cho domain
  cluster_name: ssh.example.com

proxy_service:
  enabled: "yes"
  web_listen_addr: 0.0.0.0:443
  # Dung Let's Encrypt tu dong
  acme:
    enabled: true
    email: admin@example.com
  ssh_public_addr: ssh.example.com:3023
  tunnel_public_addr: ssh.example.com:443

ssh_service:
  enabled: "no"    # Khong can SSH service tren Proxy server
```

### 1.4 Khoi dong Teleport

```bash
# Cau hinh systemd
sudo systemctl enable teleport
sudo systemctl start teleport

# Kiem tra
sudo teleport status
```

### 1.5 Mo firewall

```bash
# UFW (Ubuntu)
sudo ufw allow 443/tcp     # WebUI + API
sudo ufw allow 3023/tcp    # SSH proxy
sudo ufw allow 3025/tcp    # Auth (chi mo noi bo, khong mo ra internet)

# Hoac firewalld (RHEL)
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=3023/tcp
sudo firewall-cmd --reload
```

---

## Phan 2: Cai dat Teleport Agent tren target nodes

Lam tuong tu cho moi node can quan ly.

### 2.1 Cai dat Teleport

```bash
# Cung cach cai dat nhu tren Auth/Proxy
curl https://goteleport.com/static/install.sh | bash -s v18.7.6
```

### 2.2 Cau hinh Agent

Tao file `/etc/teleport.yaml` tren moi node:

```yaml
version: v3
teleport:
  nodename: node-01          # DOI ten cho moi node
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

### 2.3 Khoi dong va kiem tra

```bash
sudo systemctl enable teleport
sudo systemctl start teleport

# Xem log de kiem tra join
sudo journalctl -u teleport -f
```

### 2.4 Xac nhan tren Auth server

```bash
# Chay tren Auth/Proxy server
tctl nodes ls
```

Phai thay node moi trong danh sach.

---

## Phan 3: Quan ly User va Role

### 3.1 Tao user

```bash
# Chay tren Auth server
tctl users add ansible-admin --roles=editor,access
```

Mo link output tren trinh duyet de set password va MFA.

### 3.2 Tao role cho phep SSH login

Role mac dinh `access` co the khong cho login `root`. Tao role rieng:

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

Gan role cho user:

```bash
tctl users update ansible-admin --set-roles=editor,access,ansible-access
```

### 3.3 Tao role han che (vi du: chi truy cap node production)

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

## Phan 4: Cau hinh Ansible Control Node

Ansible control node co the la laptop cua ban hoac mot server rieng.

### 4.1 Cai dat

```bash
# Cai dat Teleport client
curl https://goteleport.com/static/install.sh | bash -s v18.7.6

# Cai dat Ansible
pip install ansible
# Hoac
sudo apt install ansible
```

### 4.2 Login vao Teleport

```bash
tsh login --proxy=ssh.example.com --user=ansible-admin
```

Kiem tra:

```bash
tsh status
# Phai thay Roles: access, editor, ansible-access
# Phai thay Logins: root, ansible

tsh ls
# Phai thay danh sach nodes
```

### 4.3 Tao SSH config cho Ansible

```bash
mkdir -p ~/.ssh

# Tu dong generate tu Teleport
tsh config > ~/.ssh/config
```

Lenh `tsh config` se generate config dang:

```
Host *.ssh.example.com ssh.example.com
    UserKnownHostsFile ~/.tsh/known_hosts
    IdentityFile ~/.tsh/keys/ssh.example.com/ansible-admin
    CertificateFile ~/.tsh/keys/ssh.example.com/ansible-admin-ssh/teleport-proxy-cert.pub

Host *.ssh.example.com !ssh.example.com
    Port 3022
    ProxyCommand /usr/local/bin/tsh proxy ssh --cluster=ssh.example.com --proxy=ssh.example.com:443 %r@%h:%p
```

### 4.4 Cau hinh Ansible

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

**Luu y:** Ten host trong inventory phai co hau to `.ssh.example.com` (match voi SSH config pattern `*.ssh.example.com`).

### 4.5 Test

```bash
# Test SSH truc tiep
tsh ssh root@node-01 hostname

# Test SSH qua config
ssh root@node-01.ssh.example.com hostname

# Test Ansible
ansible all -m ping
```

---

## Phan 5: Tu dong hoa voi Script

### 5.1 Script khoi tao Ansible session

Tao file `/usr/local/bin/ansible-teleport`:

```bash
#!/bin/bash
# Tu dong login Teleport va generate SSH config cho Ansible

set -e

PROXY="ssh.example.com"
USER="ansible-admin"

echo "==> Login Teleport..."
tsh login --proxy="$PROXY" --user="$USER"

echo "==> Generate SSH config..."
mkdir -p ~/.ssh
tsh config > ~/.ssh/config
chmod 600 ~/.ssh/config

echo "==> Ready! Checking nodes..."
tsh ls

echo ""
echo "Run: ansible all -m ping"
```

```bash
chmod +x /usr/local/bin/ansible-teleport
```

### 5.2 Ansible playbook mau

```yaml
---
- name: "Kiem tra trang thai he thong"
  hosts: all
  become: yes
  tasks:
    - name: Thong tin OS
      ansible.builtin.setup:

    - name: Disk usage
      ansible.builtin.command: df -h
      register: disk_info
      changed_when: false

    - name: Hien thi disk
      ansible.builtin.debug:
        msg: "{{ disk_info.stdout_lines }}"

    - name: Uptime
      ansible.builtin.command: uptime
      register: uptime_info
      changed_when: false

    - name: Hien thi uptime
      ansible.builtin.debug:
        msg: "{{ uptime_info.stdout }}"
```

---

## Phan 6: Security Best Practices

### 6.1 Token quan ly

- **Khong dung static token trong production** - dung token tam thoi (`tctl nodes add --ttl=30m`)
- Sau khi node join thanh cong, certificate duoc tu dong lam moi
- Thu hoi token khi khong can: `tctl tokens rm <token>`

### 6.2 Role-based access

```yaml
# Vi du: Admin duoc tat ca, Operator chi duoc deploy, Viewer chi doc
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

- Dung Let's Encrypt cho domain cong khai (cau hinh `acme` trong proxy_service)
- Hoac dung certificate tu CA rieng
- Khong bao gio dung `insecure: true` trong production

### 6.4 Backup Auth server

```bash
# Backup cau hinh va keys
sudo tar czf teleport-backup-$(date +%Y%m%d).tar.gz /var/lib/teleport/

# Luu tru an toan (encrypted, offsite)
```

### 6.5 Audit logging

Teleport tu dong log tat ca SSH session. Xem:

```bash
# Danh sach session
tsh recordings ls

# Replay session
tsh play <session-id>

# Tim kiem trong audit log
tctl audit query --query "event = session.start"
```

---

## Phan 7: Troubleshooting

### Node khong join duoc

```bash
# Tren node, xem log
sudo journalctl -u teleport -f

# Kiem tra ket noi den proxy
curl -k https://ssh.example.com:443/webapi/ping

# Kiem tra token tren auth server
tctl tokens ls
```

### SSH access denied

```bash
# Kiem tra user roles
tctl get user/ansible-admin

# Kiem tra role cho phep logins gi
tctl get role/ansible-access

# Login lai sau khi update role
tsh logout
tsh login --proxy=ssh.example.com --user=ansible-admin
```

### Ansible connection failed

```bash
# Kiem tra SSH config
cat ~/.ssh/config

# Kiem tra certificate con han
tsh status

# Regenerate SSH config
tsh config > ~/.ssh/config

# Test SSH truc tiep
ssh -vvv root@node-01.ssh.example.com hostname
```

### Certificate het han

```bash
# Teleport certificate co TTL (mac dinh 12h)
# Login lai de lam moi
tsh login --proxy=ssh.example.com --user=ansible-admin

# Regenerate SSH config
tsh config > ~/.ssh/config
```

---

## So sanh Docker Lab vs Production

| Yeu to | Docker Lab | Production |
|--------|-----------|------------|
| OS | Container (Debian) | VM/Physical server |
| TLS | Self-signed | Let's Encrypt hoac CA rieng |
| Domain | localhost | ssh.example.com |
| Token | Static (teleport.yaml) | Ephemeral (`tctl nodes add`) |
| User | admin (password) | SSO/OIDC/SAML hoac MFA |
| SSH config | Tao thu cong | `tsh config` tu dong |
| Inventory | node-01, node-02 | node-01.ssh.example.com |
| Data | Docker volume | /var/lib/teleport (backup dinh ky) |
| Networking | Docker bridge | Firewall, VPN, security group |
