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

## Phần 3: Tags — Chạy một phần Playbook

### Tags là gì?

**Tags** cho phép bạn gắn nhãn các tasks, rồi chỉ chạy những tasks có nhãn cụ thể. Rất hữu ích khi playbook dài nhưng bạn chỉ muốn chạy 1 phần.

```yaml
---
- name: "Deploy ứng dụng"
  hosts: webservers
  become: yes
  tasks:
    - name: Cài packages
      ansible.builtin.apt:
        name: nginx
        state: present
      tags: [install, nginx]         # ← Gắn tag

    - name: Deploy config
      ansible.builtin.template:
        src: nginx.conf.j2
        dest: /etc/nginx/nginx.conf
      tags: [config, nginx]          # ← Gắn tag

    - name: Khởi động nginx
      ansible.builtin.service:
        name: nginx
        state: started
      tags: [service, nginx]
```

### Sử dụng Tags

```bash
# Chỉ chạy tasks có tag "config"
ansible-playbook deploy.yaml --tags config

# Chạy nhiều tags
ansible-playbook deploy.yaml --tags "install,config"

# Bỏ qua tasks có tag "install"
ansible-playbook deploy.yaml --skip-tags install

# Liệt kê tất cả tags trong playbook
ansible-playbook deploy.yaml --list-tags

# Liệt kê tasks sẽ chạy
ansible-playbook deploy.yaml --list-tasks
```

### Tags đặc biệt

| Tag | Ý nghĩa |
|-----|---------|
| `always` | Luôn chạy, dù bạn chọn tag nào |
| `never` | Không bao giờ chạy trừ khi chỉ định rõ |

```yaml
- name: Reset database (nguy hiểm!)
  ansible.builtin.shell: "drop_all_tables.sh"
  tags: [never, reset]  # Chỉ chạy khi: --tags reset
```

---

## Phần 4: Conditionals — Điều kiện `when`

### Cú pháp `when`

```yaml
tasks:
  # Chỉ chạy trên Debian
  - name: Cài nginx (Debian only)
    ansible.builtin.apt:
      name: nginx
    when: ansible_distribution == "Debian"

  # Chỉ chạy khi biến tồn tại
  - name: Deploy config nếu có
    ansible.builtin.template:
      src: app.conf.j2
      dest: /etc/app.conf
    when: app_config is defined

  # Nhiều điều kiện (AND)
  - name: Chỉ deploy production trên Debian 12
    ansible.builtin.debug:
      msg: "Deploying..."
    when:
      - ansible_distribution == "Debian"
      - ansible_distribution_version == "12"
      - env == "production"

  # Điều kiện OR
  - name: Cài package trên Debian hoặc Ubuntu
    ansible.builtin.apt:
      name: curl
    when: ansible_distribution == "Debian" or ansible_distribution == "Ubuntu"
```

### Tests phổ biến (kiểm tra trạng thái)

| Test | Ý nghĩa | Ví dụ |
|------|---------|-------|
| `is defined` | Biến có tồn tại | `when: my_var is defined` |
| `is not defined` | Biến không tồn tại | `when: my_var is not defined` |
| `is none` | Biến rỗng | `when: my_var is none` |
| `== true` | Giá trị đúng | `when: enable_ssl == true` |
| `in` | Nằm trong danh sách | `when: env in ['staging', 'prod']` |
| `is succeeded` | Task trước thành công | `when: result is succeeded` |
| `is failed` | Task trước thất bại | `when: result is failed` |
| `is changed` | Task trước có thay đổi | `when: result is changed` |
| `is skipped` | Task trước bị bỏ qua | `when: result is skipped` |

### Ví dụ thực tế: Kiểm tra trước khi cài

```yaml
- name: Kiểm tra nginx đã cài chưa
  ansible.builtin.stat:
    path: /usr/sbin/nginx
  register: nginx_binary

- name: Cài nginx nếu chưa có
  ansible.builtin.apt:
    name: nginx
    state: present
  when: not nginx_binary.stat.exists

- name: Thông báo nếu đã cài rồi
  ansible.builtin.debug:
    msg: "Nginx đã tồn tại, bỏ qua cài đặt"
  when: nginx_binary.stat.exists
```

### `ignore_errors`, `failed_when`, `changed_when`

```yaml
# Tiếp tục dù task thất bại
- name: Kiểm tra port 80
  ansible.builtin.shell: "curl -s http://localhost:80"
  ignore_errors: yes         # ← Không dừng playbook nếu lỗi
  register: health

# Tuỳ chỉnh khi nào coi là "lỗi"
- name: Kiểm tra disk space
  ansible.builtin.shell: "df -h / | awk 'NR==2 {print $5}' | tr -d '%'"
  register: disk_usage
  failed_when: disk_usage.stdout | int > 90   # ← Lỗi nếu disk > 90%
  changed_when: false                          # ← Không đánh dấu "changed"
```

---

## Phần 5: Ansible Vault — Mã hoá Secrets

### Tại sao cần Vault?

Bạn cần lưu mật khẩu, API key, SSH key trong playbooks? **Không bao giờ lưu dạng plain text!** Ansible Vault mã hoá chúng.

### Các lệnh cơ bản

```bash
# Mã hoá 1 file
ansible-vault encrypt group_vars/secrets.yaml
# → Nhập mật khẩu vault → File được mã hoá

# Xem file đã mã hoá (không giải mã ra đĩa)
ansible-vault view group_vars/secrets.yaml

# Sửa file đã mã hoá (mở editor, lưu rồi tự mã hoá lại)
ansible-vault edit group_vars/secrets.yaml

# Giải mã file
ansible-vault decrypt group_vars/secrets.yaml

# Đổi mật khẩu vault
ansible-vault rekey group_vars/secrets.yaml
```

### Mã hoá 1 biến (không phải toàn bộ file)

```bash
# Mã hoá 1 chuỗi
ansible-vault encrypt_string 'SuperSecretPassword123' --name 'db_password'

# Output (copy vào group_vars):
# db_password: !vault |
#   $ANSIBLE_VAULT;1.1;AES256
#   62313365396662343061...
```

### Sử dụng Vault trong Playbook

```bash
# Chạy playbook với file đã mã hoá
ansible-playbook deploy.yaml --ask-vault-pass

# Hoặc dùng file chứa mật khẩu (cho CI/CD)
ansible-playbook deploy.yaml --vault-password-file vault_pass.txt

# Hoặc đặt biến môi trường
export ANSIBLE_VAULT_PASSWORD_FILE=vault_pass.txt
ansible-playbook deploy.yaml
```

### Ví dụ thực tế

```yaml
# group_vars/all.yaml (mã hoá bằng ansible-vault encrypt)
---
db_host: 192.168.1.10
db_user: app
db_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  62313365396662343061393464336163383764...
api_key: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  3539616561656233646137...
```

```yaml
# playbook sử dụng biến mã hoá — không khác gì biến thường
- name: Deploy config
  ansible.builtin.template:
    src: db.conf.j2
    dest: /etc/app/db.conf
  # Template bên trong dùng: {{ db_password }}
```

---

## Phần 6: Ansible Galaxy & Collections

### Galaxy là gì?

**Ansible Galaxy** = kho chứa roles và collections do cộng đồng viết sẵn. Thay vì tự viết mọi thứ từ đầu, bạn có thể cài role có sẵn.

### Collections vs Roles

| | Role | Collection |
|---|------|-----------|
| Chứa gì? | Tasks, handlers, templates | Roles + Modules + Plugins |
| Cài bằng | `ansible-galaxy role install` | `ansible-galaxy collection install` |
| Ví dụ | `geerlingguy.nginx` | `community.docker` |

### Cài đặt

```bash
# Cài 1 role
ansible-galaxy role install geerlingguy.nginx

# Cài 1 collection
ansible-galaxy collection install community.docker
ansible-galaxy collection install community.general

# Cài từ file requirements (cho team/CI)
ansible-galaxy install -r requirements.yaml
```

### File `requirements.yaml`

```yaml
---
roles:
  - name: geerlingguy.nginx
    version: "3.2.0"
  - name: geerlingguy.docker

collections:
  - name: community.docker
    version: ">=3.0.0"
  - name: community.general
  - name: ansible.posix
```

### Sử dụng role từ Galaxy

```yaml
---
- name: "Deploy Nginx (dùng role cộng đồng)"
  hosts: webservers
  become: yes
  roles:
    - role: geerlingguy.nginx
      vars:
        nginx_vhosts:
          - listen: "80"
            server_name: "mysite.com"
            root: "/var/www/html"
```

### Liệt kê roles/collections đã cài

```bash
ansible-galaxy role list
ansible-galaxy collection list
```

---

## Phần 7: Check Mode & Diff Mode

### Check Mode (--check) — Dry Run

Chạy playbook mà **không thay đổi gì** trên server. Ansible mô phỏng kết quả.

```bash
ansible-playbook deploy.yaml --check
```

### Diff Mode (--diff) — Xem thay đổi

Hiển thị **chi tiết sự khác biệt** trước/sau khi thay đổi file.

```bash
# Kết hợp check + diff = xem thay đổi mà không áp dụng
ansible-playbook deploy.yaml --check --diff

# Diff khi chạy thật
ansible-playbook deploy.yaml --diff
```

Output dạng:
```diff
--- before: /etc/nginx/nginx.conf
+++ after: /etc/nginx/nginx.conf
@@ -1,3 +1,3 @@
-server_name localhost;
+server_name mysite.com;
```

### Kiểm soát Check Mode từng task

```yaml
tasks:
  # Task này LUÔN chạy dù ở check mode
  - name: Kiểm tra version
    ansible.builtin.command: nginx -v
    check_mode: false     # ← Luôn chạy

  # Task này KHÔNG BAO GIỜ chạy thật (chỉ báo cáo)
  - name: Kiểm tra config syntax
    ansible.builtin.lineinfile:
      line: "important_setting = true"
      dest: /etc/app.conf
    check_mode: true      # ← Chỉ kiểm tra, không sửa
    register: config_check
```

---

## Phần 8: Delegation & Run Once

### `delegate_to` — Chạy task trên máy khác

```yaml
- name: "Deploy ứng dụng"
  hosts: webservers
  tasks:
    - name: Gỡ node khỏi load balancer trước khi deploy
      ansible.builtin.uri:
        url: "http://loadbalancer/api/remove/{{ inventory_hostname }}"
        method: POST
      delegate_to: localhost     # ← Chạy trên máy control, không trên target

    - name: Deploy code
      ansible.builtin.copy:
        src: app.tar.gz
        dest: /opt/app/

    - name: Thêm node trở lại load balancer
      ansible.builtin.uri:
        url: "http://loadbalancer/api/add/{{ inventory_hostname }}"
        method: POST
      delegate_to: localhost
```

### `run_once` — Chỉ chạy 1 lần dù có nhiều hosts

```yaml
- name: "Migrate database (chỉ cần chạy 1 lần)"
  hosts: webservers
  tasks:
    - name: Chạy migration
      ansible.builtin.shell: "python manage.py migrate"
      args:
        chdir: /opt/app
      run_once: true    # ← Chỉ chạy trên host đầu tiên
```

---

## Phần 9: Privilege Escalation (Nâng quyền)

### `become` chi tiết

```yaml
- name: "Quản lý quyền"
  hosts: webservers
  tasks:
    # Chạy với quyền root (mặc định)
    - name: Cài package
      ansible.builtin.apt:
        name: nginx
      become: yes                    # ← sudo

    # Chạy với user cụ thể
    - name: Deploy code với user deploy
      ansible.builtin.copy:
        src: app.py
        dest: /opt/app/
      become: yes
      become_user: deploy            # ← Chạy với user deploy

    # Chạy với method cụ thể
    - name: Chạy lệnh với su
      ansible.builtin.command: "systemctl restart app"
      become: yes
      become_method: su              # ← Dùng su thay vì sudo
```

### Biến `environment` — Đặt biến môi trường

```yaml
- name: Deploy Python app
  ansible.builtin.shell: "python app.py"
  environment:
    DATABASE_URL: "postgresql://user:pass@db:5432/mydb"
    SECRET_KEY: "{{ vault_secret_key }}"
    FLASK_ENV: "production"
  args:
    chdir: /opt/app
```

---

## Phần 10: Jinja2 Templates

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
| `int` | Chuyển sang số nguyên | `{{ '80' \| int }}` |
| `bool` | Chuyển sang boolean | `{{ 'yes' \| bool }}` |
| `ternary` | If/else inline | `{{ is_prod \| ternary('production', 'dev') }}` |
| `map` | Áp dụng filter cho danh sách | `{{ users \| map(attribute='name') \| list }}` |
| `select` | Lọc danh sách | `{{ ports \| select('gt', 1024) \| list }}` |
| `regex_search` | Tìm theo regex | `{{ text \| regex_search('v([0-9]+)', '\\1') }}` |
| `to_json` | Chuyển sang JSON | `{{ data \| to_json }}` |
| `to_yaml` | Chuyển sang YAML | `{{ data \| to_yaml }}` |
| `password_hash` | Hash mật khẩu | `{{ 'pass' \| password_hash('sha512') }}` |
| `combine` | Gộp 2 dict | `{{ dict1 \| combine(dict2) }}` |
| `unique` | Loại bỏ trùng | `{{ list \| unique }}` |
| `sort` | Sắp xếp | `{{ list \| sort }}` |

### Ví dụ Filters nâng cao

```yaml
tasks:
  # Ternary — if/else ngắn gọn
  - name: Chọn config theo môi trường
    ansible.builtin.debug:
      msg: "Port: {{ (env == 'production') | ternary(443, 8080) }}"

  # Map — trích xuất thuộc tính từ danh sách
  - name: Lấy tên tất cả users
    ansible.builtin.debug:
      msg: "{{ users | map(attribute='name') | join(', ') }}"

  # Combine — gộp 2 dict
  - name: Gộp config
    ansible.builtin.set_fact:
      final_config: "{{ default_config | combine(custom_config) }}"
```

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
