# Giới thiệu Khoá học: Teleport + Ansible Lab

## Tổng quan

- **Thời lượng**: 4 tuần (20 ngày)
- **Yêu cầu**: Docker và Docker Compose đã được cài đặt trên máy
- **Mục tiêu**: Từ mới bắt đầu → thông thạo Teleport và Ansible, hiểu SSH fundamentals

```
Tuần 1: SSH + Teleport cơ bản
Tuần 2: Ansible cơ bản
Tuần 3: Ansible trung cấp + Kết hợp Teleport
Tuần 4: Project tổng hợp + Production practices
```

---

## Kiến trúc Lab

Lab sử dụng Docker để mô phỏng một môi trường nhiều máy chủ:

```
+---------------------------------------------------+
|  Docker Network: lab_net                           |
|                                                    |
|  +-------------------+     +-------------------+  |
|  | teleport-master   |     |     node-01       |  |
|  | - Auth Server     |---->| SSH target (3022) |  |
|  | - Proxy (WebUI)   |     +-------------------+  |
|  | - Ansible + tsh   |     +-------------------+  |
|  |                   |---->|     node-02       |  |
|  +-------------------+     | SSH target (3022) |  |
|         |                  +-------------------+  |
|   Ports: 3080, 3023, 3025                         |
+---------------------------------------------------+
```

### Các thành phần

| Thành phần | Vai trò | Image |
|-----------|---------|-------|
| `teleport-master` | Auth Server + Proxy + Ansible control node | Debian + Teleport + Ansible |
| `node-01` | SSH target (web server) | Debian + Teleport Agent |
| `node-02` | SSH target (web server) | Debian + Teleport Agent |

### Trong Lab vs Thực tế

| Yếu tố | Trong Lab | Thực tế (Production) |
|---------|-----------|---------------------|
| Ansible chạy ở đâu? | Container `teleport-master` | Laptop cá nhân hoặc CI/CD |
| Teleport Master | Container Docker | VPS trên Cloud |
| Target nodes | Container Docker | VPS/VM/Physical server |
| Kết nối mạng | Docker bridge network | Internet/VPN |
| Xác thực | Password đơn giản | SSO/OIDC/MFA |

---

## Cấu trúc thư mục

```
ansible_lab/
  ├── Dockerfile              # Image teleport-master (Teleport + Ansible + tsh + tctl)
  ├── Dockerfile.node         # Image node (Debian + Teleport + Python3 + Nginx + Flask)
  ├── docker-compose.yml
  ├── teleport-config/
  │   └── teleport.yaml       # Cấu hình Teleport master
  ├── ansible/
  │   ├── ansible.cfg
  │   ├── inventory.ini
  │   ├── group_vars/
  │   │   ├── all.yaml
  │   │   └── webservers.yaml
  │   ├── playbooks/
  │   │   ├── 01-system-setup.yaml
  │   │   ├── 02-deploy-nginx.yaml
  │   │   ├── 03-deploy-monitoring.yaml
  │   │   ├── 04-deploy-fullstack.yaml
  │   │   └── 05-health-check.yaml
  │   └── roles/
  │       ├── nginx/
  │       ├── node-exporter/
  │       ├── prometheus/
  │       ├── webapp/
  │       └── common/
  ├── docs/                   # Tài liệu khoá học (bạn đang đọc)
  └── data/                   # Dữ liệu Teleport (tự tạo khi chạy)
```

---

## Cài đặt và khởi động Lab

### Bước 1: Build và khởi động

```bash
docker compose build
docker compose up -d
```

Đợi master khởi động xong (~15s):

```bash
docker logs -f teleport-master
# Đợi thấy: "Auth Server started"
```

### Bước 2: Kiểm tra node đã join

```bash
docker exec -it teleport-master tctl --auth-server=localhost:3025 nodes ls
```

Phải thấy `node-01`, `node-02`, và `teleport-master`.

### Bước 3: Tạo user admin

```bash
docker exec -it teleport-master tctl --auth-server=localhost:3025 users add admin --roles=editor,access
```

Mở WebUI tại `https://localhost:3080`, dùng link output để đặt mật khẩu.

### Bước 4: Tạo role cho phép SSH login root

```bash
docker exec -it teleport-master bash -c 'cat <<EOF | tctl --auth-server=localhost:3025 create -f
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
EOF'
```

Gán role cho user:

```bash
docker exec -it teleport-master tctl --auth-server=localhost:3025 users update admin --set-roles=editor,access,node-access
```

### Bước 5: Đăng nhập Teleport

```bash
docker exec -it teleport-master tsh login --proxy=localhost:3080 --user=admin
```

Kiểm tra: phải thấy `Roles: access, editor, node-access` và `Logins: root`.

### Bước 6: Tạo SSH config cho Ansible

```bash
docker exec -it teleport-master bash -c 'mkdir -p ~/.ssh && cat > ~/.ssh/config <<EOF
Host node-01 node-02 teleport-master
    UserKnownHostsFile /root/.tsh/known_hosts
    IdentityFile /root/.tsh/keys/localhost/admin
    CertificateFile /root/.tsh/keys/localhost/admin-ssh/teleport-master-cert.pub
    Port 3022
    StrictHostKeyChecking no
    ProxyCommand /usr/local/bin/tsh proxy ssh --cluster=teleport-master --proxy=localhost:3080 %r@%h:%p
EOF
chmod 600 ~/.ssh/config'
```

### Bước 7: Kiểm tra kết nối

```bash
docker exec -it teleport-master bash

# Kiểm tra SSH
tsh ssh root@node-01 hostname

# Kiểm tra Ansible
cd /home/teleport/ansible
ansible all -m ping
```

---

## Reset toàn bộ Lab

```bash
docker compose down
sudo rm -rf data/
docker compose build
docker compose up -d
```

Sau đó lặp lại từ Bước 3.

---

## Mục lục khoá học

| Tuần | Chủ đề | File |
|------|--------|------|
| 1 | SSH căn bản | [01-ssh-co-ban.md](01-ssh-co-ban.md) |
| 1 | Teleport căn bản | [02-teleport-co-ban.md](02-teleport-co-ban.md) |
| 2 | Ansible căn bản | [03-ansible-co-ban.md](03-ansible-co-ban.md) |
| 2 | Playbooks, Variables & Templates | [04-ansible-playbook.md](04-ansible-playbook.md) |
| 2 | Roles & Handlers | [05-ansible-roles.md](05-ansible-roles.md) |
| 2-3 | Ansible Modules nâng cao | [06-ansible-modules-nang-cao.md](06-ansible-modules-nang-cao.md) |
| 3 | Tích hợp Teleport + Ansible | [07-teleport-ansible-tich-hop.md](07-teleport-ansible-tich-hop.md) |
| 4 | Project tổng hợp & Production | [08-project-tong-hop.md](08-project-tong-hop.md) |

**Hướng dẫn thực hành nhanh:** [ANSIBLE_LAB_GUIDE.md](../ANSIBLE_LAB_GUIDE.md)
**Hướng dẫn triển khai Production:** [TELEPORT_ANSIBLE_GUIDE.md](../TELEPORT_ANSIBLE_GUIDE.md)
