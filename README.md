# Ansible Lab voi Teleport

Lab moi truong thuc hanh Ansible thong qua Teleport SSH proxy. Gom 1 Teleport master (chay Ansible) va 2 node dich.

## Kien truc

```
+---------------------------------------------------+
|  Docker Network: lab_net                           |
|                                                    |
|  +-------------------+     +-------------------+  |
|  | teleport-master   |     |     node-01        |  |
|  | - Auth Server     |---->| SSH target (3022)  |  |
|  | - Proxy (WebUI)   |     +-------------------+  |
|  | - Ansible + tsh   |     +-------------------+  |
|  |                   |---->|     node-02        |  |
|  +-------------------+     | SSH target (3022)  |  |
|         |                  +-------------------+  |
|   Ports: 3080, 3023, 3025                         |
+---------------------------------------------------+
```

## Cau truc thu muc

```
ansible_lab/
  ├── Dockerfile              # Image teleport-master (Teleport + Ansible + tsh + tctl)
  ├── Dockerfile.node         # Image node (Debian + Teleport + Python3 + Nginx + Flask)
  ├── docker-compose.yml
  ├── teleport-config/
  │   └── teleport.yaml       # Cau hinh Teleport master
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
  └── data/                   # Du lieu Teleport (tu tao)
```

## Cac file cau hinh

### 1. teleport.yaml (Master config)

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

### 2. Dockerfile (Master image)

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

# Install docker-systemctl-replacement to mock systemd for Ansible
RUN curl -kL https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/master/files/docker/systemctl3.py -o /usr/bin/systemctl && \
    chmod +x /usr/bin/systemctl
```

### 3. Dockerfile.node (Node image)

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

# Install docker-systemctl-replacement to mock systemd for Ansible
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

## Quy trinh khoi chay

### Buoc 1: Build va khoi dong

```bash
docker compose build
docker compose up -d
```

Doi master khoi dong xong (~15s):

```bash
docker logs -f teleport-master
# Doi thay: "Auth Server started"
```

### Buoc 2: Kiem tra node da join

```bash
docker exec -it teleport-master tctl --auth-server=localhost:3025 nodes ls
```

Phai thay `node-01`, `node-02`, va `teleport-master`.

### Buoc 3: Tao user admin

```bash
docker exec -it teleport-master tctl --auth-server=localhost:3025 users add admin --roles=editor,access
```

Mo WebUI tai `https://localhost:3080`, dung link output de set password.

### Buoc 4: Tao role cho phep SSH login root

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

Gan role cho user:

```bash
docker exec -it teleport-master tctl --auth-server=localhost:3025 users update admin --set-roles=editor,access,node-access
```

### Buoc 5: Login Teleport

```bash
docker exec -it teleport-master tsh login --proxy=localhost:3080 --user=admin
```

Kiem tra: phai thay `Roles: access, editor, node-access` va `Logins: root`.

### Buoc 6: Tao SSH config cho Ansible

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

### Buoc 7: Test SSH va Ansible

```bash
docker exec -it teleport-master bash

# Test SSH
tsh ssh root@node-01 hostname

# Test Ansible
cd /home/teleport/ansible
ansible all -m ping
```

## Deploy voi Ansible

Xem chi tiet tai [ANSIBLE_LAB_GUIDE.md](ANSIBLE_LAB_GUIDE.md)

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

## Cac loi thuong gap

| Loi | Nguyen nhan | Fix |
|-----|-------------|-----|
| token expired or not found | Token join het han | `auth_service.tokens` trong teleport.yaml phai match `--token` trong docker-compose |
| access denied to root | User khong co role cho phep login root | Tao role `node-access` voi `logins: [root]` |
| fork/exec /sbin/nologin | Node image distroless khong co shell | Dung `Dockerfile.node` (Debian base) |
| Permission denied (publickey) | SSH config thieu IdentityFile/CertificateFile | Tao `~/.ssh/config` dung format |
| role 'nginx' not found | `roles_path` khong dung | Them `roles_path = ./roles` trong ansible.cfg |
| duplicate nodes | Restart node ma khong xoa data cu | `docker compose down` roi `rm -rf data/` truoc khi start lai |

## Reset toan bo lab

```bash
docker compose down
sudo rm -rf data/
docker compose build
docker compose up -d
```

Sau do lap lai tu Buoc 3.

## Ports

| Port | Dich vu |
|------|---------|
| 3080 | Teleport WebUI |
| 3023 | Teleport SSH Proxy |
| 3025 | Teleport Auth Server |
| 3022 | Teleport SSH tren node (dung cho Ansible) |
| 80 | Nginx tren node (sau khi deploy) |
| 9100 | Node Exporter tren node (sau khi deploy) |
| 9090 | Prometheus tren master (sau khi deploy) |
| 5000 | Flask webapp tren node (sau khi deploy) |
