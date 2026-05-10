# Ansible Lab với Teleport

Lab môi trường thực hành Ansible thông qua Teleport SSH proxy. Gồm 1 Teleport master (chạy Ansible) và 2 node đích.

## Kiến trúc

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
  ├── docs/                   # Tài liệu khoá học chi tiết
  └── data/                   # Dữ liệu Teleport (tự tạo)
```

## Tài liệu khoá học

Xem thư mục [docs/](docs/) để học chi tiết từ cơ bản đến nâng cao:

| Chủ đề | File |
|--------|------|
| Giới thiệu & Cài đặt Lab | [docs/00-gioi-thieu.md](docs/00-gioi-thieu.md) |
| SSH căn bản | [docs/01-ssh-co-ban.md](docs/01-ssh-co-ban.md) |
| Teleport căn bản | [docs/02-teleport-co-ban.md](docs/02-teleport-co-ban.md) |
| Ansible căn bản | [docs/03-ansible-co-ban.md](docs/03-ansible-co-ban.md) |
| Playbooks, Variables & Templates | [docs/04-ansible-playbook.md](docs/04-ansible-playbook.md) |
| Roles & Handlers | [docs/05-ansible-roles.md](docs/05-ansible-roles.md) |
| Ansible Modules nâng cao | [docs/06-ansible-modules-nang-cao.md](docs/06-ansible-modules-nang-cao.md) |
| Tích hợp Teleport + Ansible | [docs/07-teleport-ansible-tich-hop.md](docs/07-teleport-ansible-tich-hop.md) |
| Project tổng hợp & Production | [docs/08-project-tong-hop.md](docs/08-project-tong-hop.md) |

## Các file cấu hình

### 1. teleport.yaml (Cấu hình Master)

```yaml
teleport:
  nodename: teleport-master
  data_dir: /var/lib/teleport

auth_service:
  enabled: "yes"
  listen_addr: 0.0.0.0:3025
  proxy_listener_mode: multiplex
  tokens:
    - "node:secret-lab-token"

proxy_service:
  enabled: "yes"
  web_listen_addr: 0.0.0.0:3080
  ssh_public_addr: localhost:3023

ssh_service:
  enabled: "yes"
```

### 2. Dockerfile (Image Master)

```dockerfile
FROM public.ecr.aws/gravitational/teleport-distroless:18.7.6 AS teleport-src

FROM debian:bookworm-slim

COPY --from=teleport-src /usr/local/bin/teleport /usr/local/bin/teleport
COPY --from=teleport-src /usr/local/bin/tctl /usr/local/bin/tctl
COPY --from=teleport-src /usr/local/bin/tsh /usr/local/bin/tsh
COPY --from=teleport-src /etc/teleport /etc/teleport

RUN apt-get update && \
    apt-get install -y --no-install-recommends ansible python3-pip curl openssh-client locales && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen en_US.UTF-8 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Cài docker-systemctl-replacement để giả lập systemd cho Ansible
RUN curl -kL https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/master/files/docker/systemctl3.py -o /usr/bin/systemctl && \
    chmod +x /usr/bin/systemctl
```

### 3. Dockerfile.node (Image Node)

```dockerfile
FROM public.ecr.aws/gravitational/teleport-distroless:18.7.6 AS teleport-src

FROM debian:bookworm-slim

COPY --from=teleport-src /usr/local/bin/teleport /usr/local/bin/teleport

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    python3 \
    python3-apt \
    python3-flask \
    curl \
    wget \
    ca-certificates \
    nginx \
    dumb-init \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Cài docker-systemctl-replacement để giả lập systemd cho Ansible
RUN wget --no-check-certificate https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/master/files/docker/systemctl3.py -O /usr/bin/systemctl && \
    chmod +x /usr/bin/systemctl
```

### 4. docker-compose.yml

```yaml
services:
  teleport-master:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: teleport-master
    ports:
      - "3080:3080"
      - "3023:3023"
      - "3025:3025"
    volumes:
      - ./teleport-config/teleport.yaml:/etc/teleport/teleport.yaml:z
      - ./ansible:/home/teleport/ansible:z
      - ./data/master:/var/lib/teleport:z
      - ./data/tsh:/root/.tsh:z
    networks:
      - lab_net
    command: teleport start --config=/etc/teleport/teleport.yaml

  node-01:
    build:
      context: .
      dockerfile: Dockerfile.node
    container_name: node-01
    hostname: node-01
    entrypoint: ["/usr/bin/dumb-init"]
    volumes:
      - ./data/node01:/var/lib/teleport:z
    networks:
      - lab_net
    command: >
      /usr/local/bin/teleport start
      --roles=node
      --auth-server=teleport-master:3025
      --token=secret-lab-token
      --nodename=node-01
    depends_on:
      - teleport-master

  node-02:
    build:
      context: .
      dockerfile: Dockerfile.node
    container_name: node-02
    hostname: node-02
    entrypoint: ["/usr/bin/dumb-init"]
    volumes:
      - ./data/node02:/var/lib/teleport:z
    networks:
      - lab_net
    command: >
      /usr/local/bin/teleport start
      --roles=node
      --auth-server=teleport-master:3025
      --token=secret-lab-token
      --nodename=node-02
    depends_on:
      - teleport-master

networks:
  lab_net:
    driver: bridge
```

### 5. ansible/ansible.cfg

```ini
[defaults]
inventory = ./inventory.ini
roles_path = ./roles
host_key_checking = False
remote_user = root
stdout_callback = default
module_lang = en_US_UTF-8

[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=30m
```

### 6. ansible/inventory.ini

```ini
[webservers]
node-01
node-02

[monitoring]
teleport-master

[all:children]
webservers
monitoring

[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_port=3022
```

## Quy trình khởi chạy

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

### Bước 7: Kiểm tra SSH và Ansible

```bash
docker exec -it teleport-master bash

# Kiểm tra SSH
tsh ssh root@node-01 hostname

# Kiểm tra Ansible
cd /home/teleport/ansible
ansible all -m ping
```

## Deploy với Ansible

Xem chi tiết tại [ANSIBLE_LAB_GUIDE.md](ANSIBLE_LAB_GUIDE.md)

```bash
cd /home/teleport/ansible

# Phase 1: Nginx
ansible-playbook playbooks/01-system-setup.yaml
ansible-playbook playbooks/02-deploy-nginx.yaml

# Phase 2: Monitoring
ansible-playbook playbooks/03-deploy-monitoring.yaml

# Phase 3: Full Stack
ansible-playbook playbooks/04-deploy-fullstack.yaml

# Health Check
ansible-playbook playbooks/05-health-check.yaml
```

## Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách sửa |
|-----|-------------|----------|
| token expired or not found | Token join hết hạn | `auth_service.tokens` trong teleport.yaml phải khớp `--token` trong docker-compose |
| access denied to root | User không có role cho phép login root | Tạo role `node-access` với `logins: [root]` |
| fork/exec /sbin/nologin | Node image distroless không có shell | Dùng `Dockerfile.node` (Debian base) |
| Permission denied (publickey) | SSH config thiếu IdentityFile/CertificateFile | Tạo `~/.ssh/config` đúng format |
| role 'nginx' not found | `roles_path` không đúng | Thêm `roles_path = ./roles` trong ansible.cfg |
| duplicate nodes | Restart node mà không xoá data cũ | `docker compose down` rồi `rm -rf data/` trước khi start lại |

## Reset toàn bộ lab

```bash
docker compose down
sudo rm -rf data/
docker compose build
docker compose up -d
```

Sau đó lặp lại từ Bước 3.

## Ports

| Port | Dịch vụ |
|------|---------|
| 3080 | Teleport WebUI |
| 3023 | Teleport SSH Proxy |
| 3025 | Teleport Auth Server |
| 3022 | Teleport SSH trên node (dùng cho Ansible) |
| 80 | Nginx trên node (sau khi deploy) |
| 9100 | Node Exporter trên node (sau khi deploy) |
| 9090 | Prometheus trên master (sau khi deploy) |
| 5000 | Flask webapp trên node (sau khi deploy) |
