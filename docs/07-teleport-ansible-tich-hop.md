# Tích hợp Teleport + Ansible

> **Tuần 3 — Ngày 11 đến 14**
> Mục tiêu: Hiểu cách Ansible kết nối qua Teleport, multi-role playbooks, error handling, debugging, và RBAC nâng cao.

---

## Phần 1: Ansible qua Teleport — Cách hoạt động (Ngày 11)

### Vấn đề

Ansible dùng SSH thường, nhưng nodes chỉ chấp nhận Teleport SSH. Làm sao để kết nối?

### Giải pháp: SSH config làm cầu nối

```
Ansible -> đọc ~/.ssh/config -> thấy ProxyCommand
  -> "tsh proxy ssh" tạo tunnel qua Teleport -> Node
  -> IdentityFile + CertificateFile từ Teleport để xác thực
```

Ansible **hoàn toàn không biết** nó đang đi qua Teleport. Nó cứ tưởng nó đang SSH bình thường nhờ file `~/.ssh/config` đã cấu hình sẵn.

### Thực hành

**Bài 1: Phân tích SSH config**

```bash
cat ~/.ssh/config
```

Giải thích từng dòng:

| Thuộc tính | Ý nghĩa |
|-----------|---------|
| `Host node-01 node-02` | Áp dụng cho hosts nào |
| `IdentityFile` | Private key (từ Teleport) |
| `CertificateFile` | SSH certificate (từ Teleport CA) |
| `Port 3022` | Teleport SSH port (không phải 22) |
| `ProxyCommand` | Tunnel qua Teleport proxy |

**Bài 2: Xác minh từng thành phần**

```bash
# 1. Teleport certificate tồn tại không?
ls -la /root/.tsh/keys/localhost/admin
ls -la /root/.tsh/keys/localhost/admin-ssh/

# 2. Certificate hợp lệ không?
ssh-keygen -L -f /root/.tsh/keys/localhost/admin-ssh/teleport-master-cert.pub

# 3. ProxyCommand hoạt động không?
tsh proxy ssh --cluster=teleport-master --proxy=localhost:3080 root@node-01:3022 < /dev/null
```

**Bài 3: Kiểm tra kết nối**

```bash
# SSH thường (không qua Teleport) — thất bại
ssh -p 22 root@node-01 hostname

# SSH qua config (qua Teleport) — thành công
ssh root@node-01 hostname

# Ansible (dùng SSH config) — thành công
ansible webservers -m ping
```

**Bài 4: Xử lý certificate hết hạn**

```bash
# Xem certificate còn hạn bao lâu
tsh status

# Khi hết hạn — SSH sẽ thất bại
# Fix: login lại
tsh login --proxy=localhost:3080 --user=admin

# Regenerate SSH config (trong production dùng lệnh này)
tsh config > ~/.ssh/config
```

### Bài tập
- [ ] Xoá `~/.ssh/config`, chạy ansible ping. Chuyện gì xảy ra?
- [ ] Tạo lại config, xác minh ansible ping hoạt động
- [ ] Tìm hiểu: trong production, làm sao tự động renew certificate?

---

## Phần 2: Multi-role Playbooks (Ngày 12)

### Deploy monitoring stack

```bash
cat playbooks/03-deploy-monitoring.yaml
```

Phân tích:
- 3 plays trong 1 file (install curl → node-exporter → prometheus)
- `hosts: webservers` vs `hosts: monitoring` — chạy trên group khác nhau
- `post_tasks` — kiểm tra sau khi deploy

```bash
ansible-playbook playbooks/03-deploy-monitoring.yaml
```

### Kiểm tra monitoring

```bash
# Node exporter trên node-01
curl -s http://node-01:9100/metrics | head -5

# Prometheus trên master
curl -s http://teleport-master:9090/-/healthy
```

### Deploy full stack

```bash
cat playbooks/04-deploy-fullstack.yaml
```

Phân tích:
- `pre_tasks` — chạy trước roles
- 2 roles: `webapp` → `nginx`
- `post_tasks` — health check

```bash
ansible-playbook playbooks/04-deploy-fullstack.yaml
```

### Kiểm tra full stack

```bash
# API JSON
curl http://node-01

# Ghi nhận visitor
curl -X POST http://node-01/visit

# Xem lại
curl http://node-01
```

### Health check

```bash
ansible-playbook playbooks/05-health-check.yaml
```

---

## Phần 3: Error Handling & Debugging (Ngày 13)

### `register` và `when`

```yaml
---
- name: "Kiểm tra register và when"
  hosts: webservers
  become: yes
  tasks:
    - name: Kiểm tra nginx có chạy không
      ansible.builtin.shell: "pgrep nginx"
      register: nginx_check
      failed_when: false         # Không đánh lỗi dù lệnh trả về rc != 0
      changed_when: false        # Không đánh dấu changed

    - name: Nginx đang chạy
      ansible.builtin.debug:
        msg: "Nginx PID: {{ nginx_check.stdout }}"
      when: nginx_check.rc == 0

    - name: Nginx không chạy
      ansible.builtin.debug:
        msg: "Nginx không chạy!"
      when: nginx_check.rc != 0
```

### `block / rescue` (try/catch)

```yaml
---
- name: "Kiểm tra block/rescue"
  hosts: webservers
  become: yes
  tasks:
    - name: Thử kiểm tra service
      block:
        - name: Kiểm tra nginx
          ansible.builtin.uri:
            url: "http://localhost:80"
            status_code: 200
          register: check
      rescue:
        - name: Nginx không phản hồi — cần sửa
          ansible.builtin.debug:
            msg: "Nginx thất bại (HTTP {{ check.status | default('N/A') }}) — cần fix"

    - name: Tiếp tục các task khác
      ansible.builtin.debug:
        msg: "Tiếp tục bình thường"
```

### Kỹ thuật Debugging

```bash
# Verbose output
ansible-playbook playbooks/02-deploy-nginx.yaml -v    # level 1
ansible-playbook playbooks/02-deploy-nginx.yaml -vv   # level 2
ansible-playbook playbooks/02-deploy-nginx.yaml -vvv  # level 3 (SSH commands)

# Check mode (dry run)
ansible-playbook playbooks/02-deploy-nginx.yaml --check

# Chỉ chạy trên 1 node
ansible-playbook playbooks/02-deploy-nginx.yaml --limit node-01

# Step mode (dừng giữa các task)
ansible-playbook playbooks/02-deploy-nginx.yaml --step
```

### Bài tập
- [ ] Viết playbook kiểm tra: nginx, node-exporter, webapp trên tất cả nodes
- [ ] Nếu 1 service fail, báo cáo nhưng không dừng playbook
- [ ] Sử dụng `--check` và nhận xét kết quả

---

## Phần 4: Teleport RBAC Nâng cao (Ngày 14)

### Challenge: Tạo môi trường giống production

```bash
# 1. Tạo 3 roles
# Mỗi role có thể lưu thành file riêng và áp dụng bằng: tctl create -f <file>

# Role admin — toàn quyền
cat <<'EOF' | tctl --auth-server=localhost:3025 create -f
kind: role
version: v5
metadata:
  name: lab-admin
spec:
  allow:
    logins: [root]
    node_labels:
      "*": "*"
  options:
    max_session_ttl: 12h0m0s
EOF

# Role developer — chỉ đọc, không sudo
cat <<'EOF' | tctl --auth-server=localhost:3025 create -f
kind: role
version: v5
metadata:
  name: lab-developer
spec:
  allow:
    logins: [viewer]
    node_labels:
      env: lab
  options:
    max_session_ttl: 4h0m0s
    forward_agent: false
EOF

# Role SRE — được SSH nhưng bị hạn chế
cat <<'EOF' | tctl --auth-server=localhost:3025 create -f
kind: role
version: v5
metadata:
  name: lab-sre
spec:
  allow:
    logins: [root]
    node_labels:
      "*": "*"
  options:
    max_session_ttl: 8h0m0s
EOF

# 2. Tạo users
tctl --auth-server=localhost:3025 users add dev1 --set-roles=lab-developer
tctl --auth-server=localhost:3025 users add sre1 --set-roles=lab-sre

# 3. Test với từng user
tsh logout
tsh login --proxy=localhost:3080 --user=dev1
tsh ssh viewer@node-01 hostname    # Được không?

tsh logout
tsh login --proxy=localhost:3080 --user=sre1
tsh ssh root@node-01 hostname      # Được không?

# 4. Quay lại admin
tsh logout
tsh login --proxy=localhost:3080 --user=admin
```

### Bài tập
- [ ] Tạo user chỉ được phép SSH vào node-01, không vào node-02
- [ ] Tạo role không cho phép chạy lệnh `apt` commands
- [ ] Giải thích: tại sao RBAC quan trọng trong production?

---

## Tóm tắt

| Khái niệm | Giải thích ngắn |
|-----------|----------------|
| SSH Config | File cấu hình kết nối — cầu nối giữa Ansible và Teleport |
| ProxyCommand | Lệnh tạo tunnel qua Teleport Proxy |
| Certificate | Chứng chỉ SSH có thời hạn, cần renew khi hết hạn |
| `tsh config` | Lệnh tự động sinh SSH config từ Teleport |
| multi-play | Nhiều plays trong 1 playbook, mỗi play cho 1 nhóm host |
| `block/rescue` | Cơ chế try/catch trong Ansible |
| `register/when` | Lưu kết quả và chạy có điều kiện |
| RBAC | Phân quyền theo vai trò: Role → Login → Node Label |

**Trước đó:** [← Ansible Modules nâng cao](06-ansible-modules-nang-cao.md)
**Tiếp theo:** [Project tổng hợp & Production →](08-project-tong-hop.md)
