# Playbooks, Variables & Templates

> **Tuần 2 — Ngày 08 đến 09**
> Mục tiêu: Hiểu playbook là gì, viết playbook đầu tiên, sử dụng variables và Jinja2 templates.

---

## Phần 1: Playbooks (Ngày 08)

### Playbook là gì?

**Playbook** = tập hợp các tasks được viết theo thứ tự trong file YAML. Nếu ad-hoc command là "gõ 1 lệnh đơn", thì playbook là "viết kịch bản hoàn chỉnh".

```
Playbook
  └── Play (hosts: webservers)
        ├── Task 1: Update apt
        ├── Task 2: Install nginx
        ├── Task 3: Copy config
        ├── Task 4: Start nginx
        └── Task 5: Verify
```

### So sánh ad-hoc vs playbook

```bash
# Ad-hoc: 1 lệnh duy nhất
ansible webservers -m apt -a "name=nginx state=present"

# Playbook: nhiều tasks liên tục, có thể lặp lại
ansible-playbook playbooks/02-deploy-nginx.yaml
```

### Cấu trúc cơ bản của Playbook

```yaml
---                              # Bắt đầu file YAML
- name: "Tên play"               # Mô tả play này làm gì
  hosts: webservers               # Chạy trên nhóm server nào
  become: yes                     # Dùng sudo
  tasks:                          # Danh sách các việc cần làm
    - name: Mô tả task            # Mô tả task
      ansible.builtin.apt:        # Module sử dụng
        name: nginx               # Tham số của module
        state: present

    - name: Task tiếp theo
      ansible.builtin.service:
        name: nginx
        state: started
```

### Thực hành

**Bài 1: Đọc và hiểu playbook**

```bash
cat playbooks/01-system-setup.yaml
```

Phân tích từng phần:
- `hosts: webservers` — chạy trên máy nào?
- `become: yes` — dùng sudo
- `name: ...` — mô tả task
- `ansible.builtin.apt` — module nào
- `register` — lưu kết quả vào biến
- `debug` — in kết quả ra màn hình

**Bài 2: Chạy playbook**

```bash
ansible-playbook playbooks/01-system-setup.yaml
```

Quan sát output:
- `ok` = task thành công, không thay đổi
- `changed` = task thành công, có thay đổi
- `failed` = task thất bại
- `skipped` = task bị bỏ qua (do điều kiện `when`)

**Bài 3: Chạy lại playbook — Hiểu Idempotent**

```bash
ansible-playbook playbooks/01-system-setup.yaml
```

Câu hỏi: Tại sao lần 2 ít task `changed` hơn? → Đó chính là **Idempotency** — Ansible kiểm tra trạng thái trước, nếu đúng rồi thì không làm gì.

**Bài 4: Viết playbook của mình**

Tạo file `playbooks/my-first-playbook.yaml`:

```yaml
---
- name: "Bài tập playbook đầu tiên"
  hosts: webservers
  become: yes
  tasks:
    - name: Tạo directory
      ansible.builtin.file:
        path: /tmp/my-lab
        state: directory

    - name: Tạo file với nội dung
      ansible.builtin.copy:
        dest: /tmp/my-lab/info.txt
        content: |
          Hostname: {{ inventory_hostname }}
          Date: {{ ansible_date_time.date }}

    - name: Đọc file vừa tạo
      ansible.builtin.shell: cat /tmp/my-lab/info.txt
      register: file_content

    - name: In nội dung
      ansible.builtin.debug:
        msg: "{{ file_content.stdout_lines }}"

    - name: Dọn dẹp
      ansible.builtin.file:
        path: /tmp/my-lab
        state: absent
```

Chạy:

```bash
ansible-playbook playbooks/my-first-playbook.yaml
```

### Các lệnh hữu ích khi chạy Playbook

```bash
# Kiểm tra cú pháp (không chạy thật)
ansible-playbook playbooks/02-deploy-nginx.yaml --syntax-check

# Dry run (mô phỏng, không thay đổi gì)
ansible-playbook playbooks/02-deploy-nginx.yaml --check

# Chỉ chạy trên 1 node
ansible-playbook playbooks/02-deploy-nginx.yaml --limit node-01

# Verbose output (thêm -v, -vv, -vvv cho chi tiết hơn)
ansible-playbook playbooks/02-deploy-nginx.yaml -v

# Chạy từng bước (dừng giữa các task để xác nhận)
ansible-playbook playbooks/02-deploy-nginx.yaml --step
```

---

## Phần 2: Variables (Ngày 09)

### Variables trong Ansible

Ansible có nhiều cấp độ biến, từ cao đến thấp ưu tiên:

```
┌─────────────────────────────────────┐
│ Thứ tự ưu tiên (cao -> thấp):      │
│                                     │
│ 1. CLI: --extra-vars                │  ← Ghi đè tất cả
│ 2. Playbook vars:                   │
│ 3. host_vars/<hostname>.yaml        │  ← Riêng cho 1 host
│ 4. group_vars/webservers.yaml       │  ← Chung cho group
│ 5. group_vars/all.yaml              │  ← Chung tất cả
│ 6. roles/.../defaults/main.yaml     │  ← Mặc định của role
└─────────────────────────────────────┘
```

### Thực hành

**Bài 1: Khám phá biến**

```bash
# Biến chung cho tất cả
cat group_vars/all.yaml

# Biến cho webservers
cat group_vars/webservers.yaml

# Xem tất cả facts (biến từ hệ thống)
ansible node-01 -m setup | grep -A2 "ansible_distribution"
```

**Bài 2: Sử dụng biến trong ad-hoc**

```bash
# In ra giá trị của biến
ansible webservers -m debug -a "msg='Timezone: {{ timezone }}'"
ansible webservers -m debug -a "msg='Site: {{ site_title }}'"
```

**Bài 3: Override biến từ CLI**

```bash
# Chạy với biến override
ansible-playbook playbooks/02-deploy-nginx.yaml \
  --extra-vars "site_title='Trang web do tôi đặt tên'"
```

---

## Phần 3: Jinja2 Templates

### Template là gì?

**Jinja2 Template** = file mẫu có thể chèn biến vào. Khi deploy, Ansible thay `{{ biến }}` bằng giá trị thực tế.

```html
<!-- Template (roles/nginx/templates/index.html.j2) -->
<title>{{ site_title }} - {{ inventory_hostname }}</title>

<!-- Kết quả trên node-01 -->
<title>Ansible Lab - node-01</title>

<!-- Kết quả trên node-02 -->
<title>Ansible Lab - node-02</title>
```

### Cú pháp Jinja2

| Cú pháp | Ý nghĩa | Ví dụ |
|---------|---------|-------|
| `{{ biến }}` | In giá trị biến | `{{ site_title }}` |
| `{% if %}` | Điều kiện | `{% if env == 'prod' %}...{% endif %}` |
| `{% for %}` | Vòng lặp | `{% for item in list %}...{% endfor %}` |
| `{# comment #}` | Ghi chú (không xuất ra) | `{# Đây là comment #}` |
| `{{ biến \| filter }}` | Áp dụng bộ lọc | `{{ name \| upper }}` |

### Các filter phổ biến

| Filter | Chức năng | Ví dụ |
|--------|-----------|-------|
| `upper` | Viết hoa | `{{ name \| upper }}` → `HELLO` |
| `lower` | Viết thường | `{{ name \| lower }}` → `hello` |
| `default` | Giá trị mặc định | `{{ port \| default(80) }}` |
| `join` | Nối danh sách | `{{ list \| join(', ') }}` |
| `length` | Đếm số phần tử | `{{ list \| length }}` |
| `replace` | Thay thế chuỗi | `{{ text \| replace('a', 'b') }}` |

### Thực hành

**Bài 4: Hiểu template**

```bash
# Xem template nginx
cat roles/nginx/templates/index.html.j2
```

Tìm các biến `{{ ... }}` trong template:
- `{{ site_title }}` → từ `group_vars/webservers.yaml`
- `{{ inventory_hostname }}` → từ Ansible facts
- `{{ ansible_hostname }}` → từ Ansible facts
- `{{ ansible_distribution }}` → từ Ansible facts

**Bài 5: Deploy và kiểm tra**

```bash
ansible-playbook playbooks/02-deploy-nginx.yaml

# Kiểm tra — mỗi node sẽ có nội dung khác nhau
curl http://node-01
curl http://node-02
```

**Bài 6: Viết template của mình**

Tạo file `roles/nginx/templates/custom-page.html.j2`:

```html
<!DOCTYPE html>
<html>
<head><title>{{ site_title }}</title></head>
<body>
  <h1>Chào mừng đến {{ inventory_hostname }}</h1>
  <p>Hệ điều hành: {{ ansible_distribution }} {{ ansible_distribution_version }}</p>
  <p>Địa chỉ IP: {{ ansible_default_ipv4.address }}</p>
  <p>RAM: {{ ansible_memtotal_mb }} MB</p>

  {% if ansible_processor_vcpus > 2 %}
  <p>Server này có nhiều CPU!</p>
  {% else %}
  <p>Server cơ bản</p>
  {% endif %}

  <h2>Danh sách dịch vụ</h2>
  <ul>
  {% for svc in services | default(['nginx']) %}
    <li>{{ svc }}</li>
  {% endfor %}
  </ul>
</body>
</html>
```

---

## Bài tập

- [ ] Sửa `site_title` trong `group_vars/webservers.yaml` và deploy lại
- [ ] Tạo biến mới `site_color` và dùng nó trong template
- [ ] Giải thích tại sao 2 nodes có nội dung khác nhau dù cùng 1 template
- [ ] Sửa playbook để tạo user `labuser` và directory `/home/labuser`
- [ ] Thêm task kiểm tra user đã tồn tại chưa
- [ ] Chạy với `--check` (dry run) và nhận xét

---

## Tóm tắt

| Khái niệm | Giải thích ngắn |
|-----------|----------------|
| Playbook | File YAML chứa danh sách tasks chạy tuần tự |
| Play | Một đơn vị trong playbook, gắn với 1 nhóm hosts |
| Task | Một bước cụ thể sử dụng 1 module |
| Variables | Giá trị có thể thay đổi, có thứ tự ưu tiên rõ ràng |
| group_vars | Biến chung cho một nhóm server |
| Facts | Biến hệ thống tự động thu thập (IP, OS, RAM...) |
| Template (Jinja2) | File mẫu có chèn biến, điều kiện, vòng lặp |
| `register` | Lưu kết quả task vào biến để dùng ở task sau |
| `--check` | Chạy thử (dry run) không thay đổi gì thật |
| `--extra-vars` | Ghi đè biến từ dòng lệnh |

**Trước đó:** [← Ansible căn bản](03-ansible-co-ban.md)
**Tiếp theo:** [Roles & Handlers →](05-ansible-roles.md)
