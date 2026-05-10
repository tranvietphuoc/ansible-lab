# Roles & Handlers

> **Tuần 2 — Ngày 10**
> Mục tiêu: Hiểu role structure và handler (restart khi config thay đổi).

---

## Roles là gì?

**Role** là cách tổ chức code Ansible thành đơn vị tái sử dụng. Thay vì viết tất cả vào 1 file playbook dài ngoằng, bạn tách thành các "vai trò" riêng biệt.

### Tại sao cần Roles?

```
❌ Không dùng role:
playbooks/deploy-everything.yaml  (500 dòng, khó đọc, khó sửa)

✅ Dùng role:
roles/nginx/       → Cài đặt và cấu hình Nginx
roles/webapp/      → Deploy Flask app
roles/prometheus/  → Cài đặt Prometheus
```

### Cấu trúc thư mục của 1 Role

```
roles/nginx/
  ├── defaults/main.yaml    # Biến mặc định (có thể ghi đè từ group_vars)
  ├── handlers/main.yaml    # Hành động khi có thay đổi (ví dụ: reload nginx)
  ├── tasks/main.yaml       # Danh sách tasks chính
  └── templates/
      ├── nginx.conf.j2     # Template cấu hình
      └── index.html.j2     # Template trang web
```

| Thư mục | Vai trò | Bắt buộc? |
|---------|---------|-----------|
| `tasks/` | Chứa danh sách các tasks chính | ✅ Có |
| `handlers/` | Chứa các handler (chạy khi được notify) | Không |
| `templates/` | Chứa file Jinja2 template | Không |
| `defaults/` | Biến mặc định của role (ưu tiên thấp nhất) | Không |
| `vars/` | Biến cố định của role (ưu tiên cao) | Không |
| `files/` | File tĩnh (copy nguyên xi, không xử lý template) | Không |
| `meta/` | Metadata: phụ thuộc role khác | Không |

---

## Handlers là gì?

**Handler** = task đặc biệt, chỉ chạy khi được "gọi" (`notify`). Dùng để thực hiện hành động phụ thuộc vào kết quả của task trước đó.

### Ví dụ thực tế

```yaml
# tasks/main.yaml
- name: Deploy cấu hình nginx
  ansible.builtin.template:
    src: nginx.conf.j2
    dest: /etc/nginx/sites-available/default
  notify: Reload nginx              # ← Gọi handler

# handlers/main.yaml
- name: Reload nginx                # ← Chỉ chạy khi được notify
  ansible.builtin.service:
    name: nginx
    state: reloaded
```

### Cách handler hoạt động

```
Lần 1 (deploy mới):
  Task "Deploy config" → config thay đổi → changed → NOTIFY handler
  Handler "Reload nginx" → CHẠY (reload nginx)

Lần 2 (chạy lại, không đổi gì):
  Task "Deploy config" → config giống cũ → ok → KHÔNG notify
  Handler "Reload nginx" → KHÔNG CHẠY
```

**Điểm quan trọng:**
- Handler chỉ chạy 1 lần duy nhất, dù bị notify nhiều lần
- Handler chạy ở **cuối play**, không phải ngay sau task notify
- Nếu playbook bị lỗi giữa chừng, handler có thể không chạy

---

## Thực hành

### Bài 1: Phân tích role nginx

```bash
# Tasks — thứ tự chạy
cat roles/nginx/tasks/main.yaml

# Defaults — biến mặc định
cat roles/nginx/defaults/main.yaml

# Handlers — khi nào chạy?
cat roles/nginx/handlers/main.yaml
```

Câu hỏi:
- Task nào gọi `notify`?
- Handler tên gì? Nó làm gì?
- Biến mặc định có những gì?

### Bài 2: Thử handler — Lần chạy đầu tiên

```bash
# Lần 1 — mọi thứ changed
ansible-playbook playbooks/02-deploy-nginx.yaml
```

Quan sát: handler `Reload nginx` có chạy không?

```bash
# Lần 2 — mọi thứ ok (không thay đổi)
ansible-playbook playbooks/02-deploy-nginx.yaml
```

Quan sát: handler có chạy lần 2 không? (Không, vì không có gì thay đổi)

### Bài 3: Kích hoạt handler bằng thay đổi

Sửa `roles/nginx/defaults/main.yaml` — đổi port:

```yaml
nginx_port: 8080
```

```bash
ansible-playbook playbooks/02-deploy-nginx.yaml
```

Quan sát: handler `Reload nginx` chạy vì config thay đổi!

### Bài 4: Khôi phục

```yaml
nginx_port: 80
```

```bash
ansible-playbook playbooks/02-deploy-nginx.yaml
```

### Bài 5: Cách gọi role trong playbook

Xem file `playbooks/04-deploy-fullstack.yaml`:

```yaml
---
- name: "Deploy Full Stack"
  hosts: webservers
  become: yes
  pre_tasks:                           # ← Chạy TRƯỚC roles
    - name: Cài Flask
      ansible.builtin.apt:
        name: python3-flask
        state: present

  roles:                               # ← Gọi roles theo thứ tự
    - webapp                           # Role 1
    - role: nginx                      # Role 2, có thể truyền biến
      vars:
        nginx_config_template: "nginx-reverse-proxy.conf.j2"

  post_tasks:                          # ← Chạy SAU roles
    - name: Health check
      ansible.builtin.uri:
        url: "http://localhost:80"
        status_code: 200
```

Thứ tự chạy: `pre_tasks` → `roles` → `post_tasks`

---

## Tạo Role mới

### Cách tạo role bằng tay

```bash
# Tạo cấu trúc thư mục
mkdir -p roles/my-role/{tasks,handlers,templates,defaults}

# Tạo file tasks chính
cat > roles/my-role/tasks/main.yaml << 'EOF'
---
- name: In thông báo
  ansible.builtin.debug:
    msg: "Role my-role đang chạy trên {{ inventory_hostname }}"

- name: Tạo file marker
  ansible.builtin.copy:
    content: "Deployed by Ansible at {{ ansible_date_time.iso8601 }}\n"
    dest: /tmp/my-role-marker.txt
  notify: Thông báo hoàn thành
EOF

# Tạo handler
cat > roles/my-role/handlers/main.yaml << 'EOF'
---
- name: Thông báo hoàn thành
  ansible.builtin.debug:
    msg: "Role my-role đã deploy thành công!"
EOF

# Tạo defaults
cat > roles/my-role/defaults/main.yaml << 'EOF'
---
my_role_message: "Hello from my-role"
EOF
```

### Gọi role trong playbook

```yaml
---
- name: "Test my-role"
  hosts: webservers
  become: yes
  roles:
    - my-role
```

---

## Bài tập

- [ ] Thêm 1 handler mới: khi `index.html` thay đổi, restart nginx (thay vì reload)
- [ ] Tìm hiểu sự khác biệt giữa `reloaded` và `restarted`:
  - `reloaded`: Đọc lại config mà không tắt service (không mất kết nối)
  - `restarted`: Tắt rồi bật lại service (mất kết nối tạm thời)
- [ ] Tạo 1 role mới tên `motd` (Message of the Day) — thay đổi nội dung file `/etc/motd` trên tất cả nodes
- [ ] Phân tích role `node-exporter`: nó có những file gì, tasks nào?

---

## Tóm tắt

| Khái niệm | Giải thích ngắn |
|-----------|----------------|
| Role | Đơn vị tổ chức code Ansible, tái sử dụng được |
| Handler | Task đặc biệt, chỉ chạy khi có thay đổi (notify) |
| `notify` | Gọi handler khi task có trạng thái `changed` |
| `defaults/` | Biến mặc định của role, ưu tiên thấp nhất |
| `pre_tasks` | Chạy trước roles |
| `post_tasks` | Chạy sau roles |
| `reloaded` | Đọc lại config, không ngắt dịch vụ |
| `restarted` | Tắt và bật lại dịch vụ |

**Trước đó:** [← Playbooks, Variables & Templates](04-ansible-playbook.md)
**Tiếp theo:** [Ansible Modules nâng cao →](06-ansible-modules-nang-cao.md)
