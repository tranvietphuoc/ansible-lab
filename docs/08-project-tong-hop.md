# Project Tổng hợp & Production

> **Tuần 4 — Ngày 15 đến 20**
> Mục tiêu: Áp dụng tất cả kiến thức để tạo 1 hệ thống hoàn chỉnh, hiểu các thực hành tốt cho Production.

---

## Phần 1: Project cuối khoá (Ngày 15-17)

### Đề bài

Xây dựng hệ thống với các yêu cầu:

1. **2 web servers** (node-01, node-02) chạy Flask app + Nginx reverse proxy
2. **1 monitoring server** (teleport-master) chạy Prometheus
3. **3 Teleport users** với quyền khác nhau
4. **Ansible playbooks** deploy tất cả từ đầu

### Bước 1: Reset lab

```bash
# Trên host (máy tính cá nhân)
docker compose down
sudo rm -rf data/
docker compose build
docker compose up -d
```

### Bước 2: Setup Teleport

```bash
docker exec -it teleport-master bash

# Tạo user + role
tctl --auth-server=localhost:3025 users add admin --roles=editor,access

# Tạo role node-access (như README hướng dẫn)
cat <<'EOF' | tctl --auth-server=localhost:3025 create -f
kind: role
version: v5
metadata:
  name: node-access
spec:
  allow:
    logins: [root, admin]
    node_labels:
      "*": "*"
  options:
    max_session_ttl: 30h0m0s
EOF

# Gán role
tctl --auth-server=localhost:3025 users update admin --set-roles=editor,access,node-access

# Login
tsh login --proxy=localhost:3080 --user=admin

# Tạo SSH config
mkdir -p ~/.ssh && cat > ~/.ssh/config <<'EOF'
Host node-01 node-02 teleport-master
    UserKnownHostsFile /root/.tsh/known_hosts
    IdentityFile /root/.tsh/keys/localhost/admin
    CertificateFile /root/.tsh/keys/localhost/admin-ssh/teleport-master-cert.pub
    Port 3022
    StrictHostKeyChecking no
    ProxyCommand /usr/local/bin/tsh proxy ssh --cluster=teleport-master --proxy=localhost:3080 %r@%h:%p
EOF
chmod 600 ~/.ssh/config
```

### Bước 3: Deploy tất cả

```bash
cd /home/teleport/ansible

ansible all -m ping                                    # Xác nhận kết nối
ansible-playbook playbooks/01-system-setup.yaml        # Setup hệ thống
ansible-playbook playbooks/02-deploy-nginx.yaml        # Deploy web
ansible-playbook playbooks/03-deploy-monitoring.yaml   # Deploy monitoring
ansible-playbook playbooks/04-deploy-fullstack.yaml    # Deploy app
ansible-playbook playbooks/05-health-check.yaml        # Kiểm tra
```

### Bước 4: Xác nhận toàn bộ

```bash
# Web
curl http://node-01
curl http://node-02

# Monitoring
curl http://node-01:9100/metrics | head -3
curl http://teleport-master:9090/-/healthy

# Teleport audit
tsh recordings ls
```

### Bước 5: Tạo môi trường multi-user

Tạo 3 users (như hướng dẫn ở phần Tích hợp), test với từng user.

---

## Phần 2: So sánh Lab vs Production (Ngày 18-19)

### Bảng so sánh chi tiết

| Yếu tố | Docker Lab | Production |
|---------|-----------|------------|
| **Hệ điều hành** | Container (Debian) | VM/Physical server |
| **TLS/SSL** | Self-signed | Let's Encrypt hoặc CA riêng |
| **Domain** | localhost | ssh.congty.com |
| **Token join** | Static (trong teleport.yaml) | Ephemeral (`tctl nodes add --ttl=30m`) |
| **Xác thực user** | Password đơn giản | SSO/OIDC/SAML hoặc MFA |
| **SSH config** | Tạo thủ công | `tsh config` tự động |
| **Inventory** | node-01, node-02 | node-01.ssh.congty.com |
| **Dữ liệu** | Docker volume | /var/lib/teleport (backup định kỳ) |
| **Mạng** | Docker bridge | Firewall, VPN, security group |
| **Systemd** | docker-systemctl-replacement | Systemd thật |
| **Ansible control** | Trên container master | Trên laptop cá nhân hoặc CI/CD |
| **Backup** | Không có | Backup định kỳ auth data |

### Workflow Production thực tế

```
┌─────────────────────────────────────────────────────┐
│                   PRODUCTION WORKFLOW                │
│                                                     │
│  1. Mua VPS mới ─┬─ Cloud-init script tự động:     │
│                   │  • Cài Teleport Agent            │
│                   │  • Điền file /etc/teleport.yaml  │
│                   │  • systemctl start teleport      │
│                   └─ VPS tự join Teleport cluster    │
│                                                     │
│  2. Trên Laptop ──┬─ tsh login                      │
│                   │  tsh config > ~/.ssh/config      │
│                   └─ ansible-playbook deploy.yaml    │
│                                                     │
│  3. CI/CD ────────── Git push → Pipeline trigger    │
│                      → tbot lấy certificate          │
│                      → ansible-playbook deploy.yaml  │
│                      → Certificate tự huỷ sau 10p    │
└─────────────────────────────────────────────────────┘
```

---

## Phần 3: Production Best Practices

### 3.1 Token quản lý

```bash
# KHÔNG dùng static token trong production
tokens:
  - "node:my-secret-token"

# Dùng token tạm thời (tự hết hạn)
tctl nodes add --ttl=30m
# Output: token ngẫu nhiên, sống 30 phút
```

### 3.2 Backup Auth Server

```bash
# Backup cấu hình và keys
sudo tar czf teleport-backup-$(date +%Y%m%d).tar.gz /var/lib/teleport/

# Lưu trữ an toàn (mã hoá, offsite)
```

### 3.3 TLS / Certificate

- Dùng Let's Encrypt cho domain công khai (cấu hình `acme` trong proxy_service)
- Hoặc dùng certificate từ CA riêng
- **Không bao giờ** dùng `insecure: true` trong production

### 3.4 Firewall

```bash
# Chỉ mở các port cần thiết
sudo ufw allow 443/tcp     # WebUI + API
sudo ufw allow 3023/tcp    # SSH proxy

# KHÔNG mở port 3025 (Auth) ra internet!
# Port 3025 chỉ dành cho nội bộ
```

### 3.5 Audit Logging

```bash
# Danh sách session
tsh recordings ls

# Replay session
tsh play <session-id>

# Tìm kiếm trong audit log
tctl audit query --query "event = session.start"
```

---

## Phần 4: Tổng hợp (Ngày 20)

### Chủ đề ôn tập

**1. SSH Fundamentals**
- [ ] Giải thích SSH handshake
- [ ] Phân biệt password vs key vs certificate authentication
- [ ] Giải thích tại sao Teleport dùng certificate

**2. Teleport**
- [ ] Vẽ kiến trúc: Auth, Proxy, Node
- [ ] Giải thích: User → Role → Login → Node
- [ ] Hiểu: static token vs ephemeral token
- [ ] Cách tạo SSH config cho Ansible

**3. Ansible**
- [ ] Phân biệt: ad-hoc vs playbook vs role
- [ ] Hiểu: inventory, group_vars, facts
- [ ] Hiểu: module, handler, template, variable
- [ ] Debug: -v, --check, --limit, --step
- [ ] Sử dụng các module nâng cao (Docker, lineinfile, uri, cron...)

**4. Tích hợp**
- [ ] Hiểu cách Ansible kết nối qua Teleport
- [ ] Deploy ứng dụng qua Teleport SSH proxy
- [ ] Quản lý truy cập với RBAC

---

## Checklist tổng kết khoá học

Sau khi hoàn thành 20 ngày:

### SSH
- [ ] Hiểu SSH handshake và 3 cách xác thực
- [ ] Biết đọc và viết SSH config

### Teleport
- [ ] Cài đặt và cấu hình Teleport (Auth + Proxy + Node)
- [ ] Quản lý User và Role (RBAC)
- [ ] Sử dụng `tsh ssh`, `tsh scp`, `tsh recordings`
- [ ] Cấu hình SSH cho Ansible integration
- [ ] Hiểu audit logging

### Ansible
- [ ] Sử dụng ad-hoc commands
- [ ] Viết playbooks với tasks, variables, handlers
- [ ] Tạo và sử dụng roles
- [ ] Sử dụng Jinja2 templates
- [ ] Debug và troubleshoot
- [ ] Deploy multi-tier application
- [ ] Sử dụng module nâng cao (Docker, cron, lineinfile, uri...)

### Tích hợp
- [ ] Hiểu cách Ansible kết nối qua Teleport
- [ ] Deploy ứng dụng qua Teleport SSH proxy
- [ ] Quản lý truy cập với RBAC

---

## Tài liệu tham khảo

| Tài liệu | Đường dẫn |
|----------|----------|
| Hướng dẫn thực hành nhanh | [ANSIBLE_LAB_GUIDE.md](../ANSIBLE_LAB_GUIDE.md) |
| Hướng dẫn Production | [TELEPORT_ANSIBLE_GUIDE.md](../TELEPORT_ANSIBLE_GUIDE.md) |
| Ansible Documentation | https://docs.ansible.com/ |
| Teleport Documentation | https://goteleport.com/docs/ |
| Ansible Galaxy (community roles) | https://galaxy.ansible.com/ |

**Trước đó:** [← Tích hợp Teleport + Ansible](07-teleport-ansible-tich-hop.md)
**Quay lại:** [Giới thiệu khoá học](00-gioi-thieu.md)
