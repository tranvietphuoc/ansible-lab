# Ansible Modules Nâng cao

> **Nội dung mở rộng**
> Mục tiêu: Nắm vững toàn bộ các module quan trọng của Ansible, từ quản lý file nâng cao đến Docker, mạng, và lập lịch.

---

## Tổng quan phân loại Modules

| Nhóm | Modules chính | Mục đích |
|------|--------------|---------|
| Quản lý gói | `apt`, `yum`, `pip`, `apt_repository` | Cài đặt phần mềm |
| Quản lý file nâng cao | `lineinfile`, `blockinfile`, `fetch`, `unarchive` | Sửa file, tải file |
| Quản lý dịch vụ | `service`, `systemd` | Khởi động/dừng dịch vụ |
| Quản lý người dùng | `user`, `group`, `authorized_key` | Tạo user, phân quyền SSH |
| Lệnh & Script | `command`, `shell`, `raw`, `script` | Chạy lệnh tuỳ ý |
| Mạng & HTTP | `uri`, `get_url`, `wait_for`, `ufw` | Tải file, gọi API, firewall |
| Docker | `docker_container`, `docker_image`, `docker_compose_v2` | Quản lý container |
| Điều kiện & Luồng | `assert`, `fail`, `pause`, `set_fact`, `include_tasks` | Kiểm soát luồng thực thi |
| Thông tin hệ thống | `setup`, `stat`, `find`, `hostname` | Thu thập thông tin |
| Lập lịch | `cron`, `at` | Tạo cron job |

---

## 1. Quản lý gói phần mềm

### Module `apt` — Quản lý gói Debian/Ubuntu

```yaml
# Cài đặt 1 gói
- name: Cài nginx
  ansible.builtin.apt:
    name: nginx
    state: present        # present/absent/latest
    update_cache: yes      # Chạy apt update trước

# Cài nhiều gói cùng lúc
- name: Cài các gói cơ bản
  ansible.builtin.apt:
    name:
      - curl
      - vim
      - htop
      - git
    state: present

# Nâng cấp toàn bộ hệ thống
- name: Nâng cấp tất cả packages
  ansible.builtin.apt:
    upgrade: dist          # dist/yes/safe/full
    update_cache: yes

# Xoá packages không cần thiết
- name: Dọn dẹp
  ansible.builtin.apt:
    autoremove: yes
    autoclean: yes
```

### Module `yum` — Quản lý gói RHEL/CentOS

```yaml
- name: Cài nginx trên CentOS
  ansible.builtin.yum:
    name: nginx
    state: present

- name: Cài từ URL trực tiếp
  ansible.builtin.yum:
    name: https://example.com/package.rpm
    state: present
```

### Module `pip` — Quản lý Python packages

```yaml
# Cài package Python
- name: Cài Flask
  ansible.builtin.pip:
    name: flask
    state: present

# Cài từ requirements.txt
- name: Cài dependencies
  ansible.builtin.pip:
    requirements: /opt/app/requirements.txt

# Cài version cụ thể
- name: Cài Flask 3.0
  ansible.builtin.pip:
    name: flask==3.0.0

# Cài vào virtualenv
- name: Cài vào môi trường ảo
  ansible.builtin.pip:
    name: flask
    virtualenv: /opt/app/venv
    virtualenv_command: python3 -m venv
```

### Module `apt_repository` — Thêm repository

```yaml
# Thêm PPA (Ubuntu)
- name: Thêm Nginx PPA
  ansible.builtin.apt_repository:
    repo: "ppa:nginx/stable"
    state: present

# Thêm repository tuỳ chỉnh
- name: Thêm Docker repo
  ansible.builtin.apt_repository:
    repo: "deb https://download.docker.com/linux/debian bookworm stable"
    state: present
```

### Module `apt_key` — Quản lý GPG keys

```yaml
- name: Thêm Docker GPG key
  ansible.builtin.apt_key:
    url: https://download.docker.com/linux/debian/gpg
    state: present
```

---

## 2. Quản lý file nâng cao

### Module `lineinfile` — Sửa 1 dòng trong file

Rất hữu ích khi bạn chỉ cần thay đổi 1 dòng cấu hình mà không muốn ghi đè toàn bộ file.

```yaml
# Thêm hoặc sửa 1 dòng
- name: Đặt timezone trong cấu hình
  ansible.builtin.lineinfile:
    path: /etc/environment
    regexp: '^TZ='              # Tìm dòng bắt đầu bằng TZ=
    line: 'TZ=Asia/Ho_Chi_Minh' # Thay thế bằng dòng này
    create: yes                  # Tạo file nếu chưa tồn tại

# Xoá 1 dòng
- name: Xoá dòng không cần thiết
  ansible.builtin.lineinfile:
    path: /etc/ssh/sshd_config
    regexp: '^PermitRootLogin'
    state: absent

# Thêm dòng vào cuối file (nếu chưa có)
- name: Thêm DNS server
  ansible.builtin.lineinfile:
    path: /etc/resolv.conf
    line: 'nameserver 8.8.8.8'

# Thêm dòng sau 1 dòng khác
- name: Thêm cấu hình sau [defaults]
  ansible.builtin.lineinfile:
    path: /etc/ansible/ansible.cfg
    insertafter: '^\[defaults\]'
    line: 'timeout = 30'
```

### Module `blockinfile` — Thêm/sửa một khối nhiều dòng

```yaml
# Thêm khối cấu hình vào file
- name: Thêm cấu hình firewall
  ansible.builtin.blockinfile:
    path: /etc/sysctl.conf
    block: |
      # Ansible managed - Network tuning
      net.core.somaxconn = 65535
      net.ipv4.tcp_max_syn_backlog = 65535
      net.ipv4.ip_forward = 1
    marker: "# {mark} ANSIBLE MANAGED BLOCK - network"

# Xoá khối
- name: Xoá khối cấu hình
  ansible.builtin.blockinfile:
    path: /etc/sysctl.conf
    marker: "# {mark} ANSIBLE MANAGED BLOCK - network"
    state: absent
```

### Module `fetch` — Tải file từ server về máy mình

Ngược lại với `copy` (máy mình → server).

```yaml
# Tải file log về
- name: Tải log nginx
  ansible.builtin.fetch:
    src: /var/log/nginx/access.log
    dest: /tmp/logs/           # Lưu tại: /tmp/logs/<hostname>/var/log/nginx/access.log
    flat: no                   # Giữ cấu trúc thư mục

# Tải file đơn (không giữ cấu trúc)
- name: Tải file cấu hình
  ansible.builtin.fetch:
    src: /etc/nginx/nginx.conf
    dest: /tmp/nginx-{{ inventory_hostname }}.conf
    flat: yes
```

### Module `unarchive` — Giải nén file

```yaml
# Giải nén file từ máy control lên server
- name: Upload và giải nén
  ansible.builtin.unarchive:
    src: files/app-v1.0.tar.gz     # File local
    dest: /opt/app/

# Giải nén file đã có trên server
- name: Giải nén file trên server
  ansible.builtin.unarchive:
    src: /tmp/app.tar.gz
    dest: /opt/app/
    remote_src: yes                 # File đã nằm trên server rồi

# Tải từ URL và giải nén trực tiếp
- name: Tải và giải nén Node Exporter
  ansible.builtin.unarchive:
    src: https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
    dest: /opt/
    remote_src: yes
```

### Module `archive` — Nén file

```yaml
- name: Nén thư mục log
  community.general.archive:
    path: /var/log/nginx/
    dest: /tmp/nginx-logs.tar.gz
    format: gz
```

### Module `template` — Render Jinja2 template

```yaml
- name: Deploy cấu hình nginx
  ansible.builtin.template:
    src: nginx.conf.j2           # File template trong roles/<role>/templates/
    dest: /etc/nginx/nginx.conf
    owner: root
    group: root
    mode: '0644'
    validate: '/usr/sbin/nginx -t -c %s'  # Kiểm tra syntax trước khi áp dụng
  notify: Reload nginx
```

---

## 3. Quản lý người dùng nâng cao

### Module `group` — Quản lý nhóm

```yaml
- name: Tạo nhóm deploy
  ansible.builtin.group:
    name: deploy
    gid: 1500
    state: present
```

### Module `user` — Quản lý người dùng (nâng cao)

```yaml
# Tạo user với đầy đủ cấu hình
- name: Tạo user deploy
  ansible.builtin.user:
    name: deploy
    uid: 1500
    group: deploy
    groups: www-data,docker       # Thêm vào các nhóm phụ
    shell: /bin/bash
    home: /home/deploy
    create_home: yes
    password: "{{ 'mypassword' | password_hash('sha512') }}"  # Hash mật khẩu
    state: present

# Tạo user hệ thống (không có shell, không login được)
- name: Tạo user chạy service
  ansible.builtin.user:
    name: node-exporter
    system: yes
    shell: /usr/sbin/nologin
    create_home: no
```

### Module `authorized_key` — Quản lý SSH public keys

```yaml
# Thêm SSH key cho user
- name: Thêm SSH key cho deploy
  ansible.posix.authorized_key:
    user: deploy
    key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... admin@laptop"
    state: present

# Thêm key từ URL (ví dụ Github)
- name: Thêm SSH key từ Github
  ansible.posix.authorized_key:
    user: deploy
    key: "https://github.com/username.keys"
```

---

## 4. Lệnh & Script

### Module `command` vs `shell` vs `raw`

| Module | Qua shell? | Pipe/Redirect? | Khi nào dùng |
|--------|-----------|----------------|-------------|
| `command` | Không | Không | Mặc định, an toàn nhất |
| `shell` | Có (`/bin/sh`) | Có | Cần pipe, redirect |
| `raw` | Không | Không | Server chưa có Python |

```yaml
# command — an toàn, không qua shell
- name: Kiểm tra phiên bản
  ansible.builtin.command: nginx -v
  register: nginx_version
  changed_when: false            # Đánh dấu không thay đổi

# shell — khi cần pipe
- name: Đếm số process nginx
  ansible.builtin.shell: "ps aux | grep nginx | wc -l"
  register: nginx_count
  changed_when: false

# raw — khi target chưa có Python (ví dụ: cài Python)
- name: Cài Python trên server mới
  ansible.builtin.raw: apt-get install -y python3
```

### Module `script` — Chạy script local trên server

```bash
# Ansible tự động copy script lên server và chạy
- name: Chạy script deploy
  ansible.builtin.script: scripts/deploy.sh
  args:
    chdir: /opt/app
```

---

## 5. Mạng & HTTP

### Module `uri` — Gọi HTTP/API

```yaml
# GET request
- name: Kiểm tra health endpoint
  ansible.builtin.uri:
    url: "http://localhost:80/"
    status_code: 200
  register: health

# POST request với body
- name: Gọi API
  ansible.builtin.uri:
    url: "https://api.example.com/deploy"
    method: POST
    body_format: json
    body:
      version: "1.0.0"
      env: "production"
    headers:
      Authorization: "Bearer {{ api_token }}"
    status_code: [200, 201]

# Tải file JSON
- name: Lấy cấu hình từ API
  ansible.builtin.uri:
    url: "https://config.example.com/app.json"
    return_content: yes
  register: config_response
```

### Module `get_url` — Tải file từ URL

```yaml
- name: Tải Node Exporter
  ansible.builtin.get_url:
    url: "https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz"
    dest: /tmp/node_exporter.tar.gz
    checksum: "sha256:abcdef1234..."  # Kiểm tra integrity
    mode: '0644'
```

### Module `wait_for` — Đợi điều kiện

```yaml
# Đợi port mở (service đã sẵn sàng)
- name: Đợi nginx khởi động
  ansible.builtin.wait_for:
    port: 80
    timeout: 30            # Đợi tối đa 30 giây

# Đợi file xuất hiện
- name: Đợi file log được tạo
  ansible.builtin.wait_for:
    path: /var/log/app/app.log
    state: present

# Đợi chuỗi xuất hiện trong file
- name: Đợi app sẵn sàng
  ansible.builtin.wait_for:
    path: /var/log/app/app.log
    search_regex: "Application started"
```

### Module `ufw` — Quản lý tường lửa (Ubuntu)

```yaml
# Cho phép SSH
- name: Mở port SSH
  community.general.ufw:
    rule: allow
    port: '22'
    proto: tcp

# Cho phép HTTP/HTTPS
- name: Mở port web
  community.general.ufw:
    rule: allow
    port: "{{ item }}"
    proto: tcp
  loop:
    - '80'
    - '443'

# Bật firewall
- name: Bật UFW
  community.general.ufw:
    state: enabled
    policy: deny             # Mặc định chặn tất cả
```

---

## 6. Docker Modules

> Yêu cầu: `ansible-galaxy collection install community.docker`

### Module `docker_container` — Quản lý container

```yaml
# Chạy container
- name: Chạy Redis
  community.docker.docker_container:
    name: redis
    image: redis:7-alpine
    state: started
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data
    restart_policy: always
    env:
      REDIS_ARGS: "--save 60 1000"

# Dừng container
- name: Dừng Redis
  community.docker.docker_container:
    name: redis
    state: stopped

# Xoá container
- name: Xoá Redis
  community.docker.docker_container:
    name: redis
    state: absent
```

### Module `docker_image` — Quản lý image

```yaml
# Pull image
- name: Tải image nginx
  community.docker.docker_image:
    name: nginx
    tag: latest
    source: pull

# Build image từ Dockerfile
- name: Build app image
  community.docker.docker_image:
    name: my-app
    tag: "{{ app_version }}"
    source: build
    build:
      path: /opt/app
      dockerfile: Dockerfile

# Xoá image
- name: Xoá image cũ
  community.docker.docker_image:
    name: my-app
    tag: old
    state: absent
```

### Module `docker_compose_v2` — Docker Compose

```yaml
# Deploy stack từ docker-compose.yml
- name: Copy docker-compose.yml
  ansible.builtin.copy:
    src: docker-compose.yml
    dest: /opt/app/docker-compose.yml

- name: Deploy stack
  community.docker.docker_compose_v2:
    project_src: /opt/app
    state: present

# Dừng stack
- name: Dừng stack
  community.docker.docker_compose_v2:
    project_src: /opt/app
    state: absent
```

### Module `docker_network` & `docker_volume`

```yaml
# Tạo network
- name: Tạo Docker network
  community.docker.docker_network:
    name: app-network
    driver: bridge

# Tạo volume
- name: Tạo Docker volume
  community.docker.docker_volume:
    name: app-data
```

---

## 7. Điều kiện & Luồng thực thi

### Module `assert` — Kiểm tra điều kiện

```yaml
- name: Kiểm tra RAM đủ
  ansible.builtin.assert:
    that:
      - ansible_memtotal_mb >= 1024
    fail_msg: "Server cần ít nhất 1GB RAM! Hiện tại: {{ ansible_memtotal_mb }}MB"
    success_msg: "RAM đủ: {{ ansible_memtotal_mb }}MB"
```

### Module `fail` — Dừng playbook với thông báo lỗi

```yaml
- name: Kiểm tra OS
  ansible.builtin.fail:
    msg: "Chỉ hỗ trợ Debian/Ubuntu! OS hiện tại: {{ ansible_distribution }}"
  when: ansible_distribution not in ['Debian', 'Ubuntu']
```

### Module `set_fact` — Tạo biến trong runtime

```yaml
- name: Tính toán port
  ansible.builtin.set_fact:
    app_url: "http://{{ inventory_hostname }}:{{ app_port | default(5000) }}"
    is_production: "{{ env == 'production' }}"

- name: Dùng biến vừa tạo
  ansible.builtin.debug:
    msg: "URL: {{ app_url }}, Production: {{ is_production }}"
```

### Module `pause` — Tạm dừng

```yaml
# Dừng để người dùng xác nhận
- name: Xác nhận trước khi deploy production
  ansible.builtin.pause:
    prompt: "Bạn có chắc muốn deploy lên PRODUCTION? (yes/no)"
  register: confirm
  when: env == 'production'

# Dừng chờ 30 giây
- name: Đợi service khởi động
  ansible.builtin.pause:
    seconds: 30
```

### `include_tasks` vs `import_tasks`

```yaml
# include_tasks — dynamic (xử lý lúc chạy, hỗ trợ loop & when)
- name: Cài đặt theo OS
  ansible.builtin.include_tasks: "install-{{ ansible_distribution | lower }}.yaml"

# import_tasks — static (xử lý lúc parse, nhanh hơn)
- name: Cài đặt chung
  ansible.builtin.import_tasks: common-setup.yaml
```

### `block / rescue / always` — Try/Catch/Finally

```yaml
- name: Deploy với xử lý lỗi
  block:
    - name: Deploy ứng dụng
      ansible.builtin.copy:
        src: app.tar.gz
        dest: /opt/app/

    - name: Khởi động ứng dụng
      ansible.builtin.service:
        name: my-app
        state: started

  rescue:                            # ← Chạy khi block bị lỗi
    - name: Rollback
      ansible.builtin.debug:
        msg: "Deploy thất bại! Đang rollback..."

    - name: Khôi phục bản cũ
      ansible.builtin.copy:
        src: app-backup.tar.gz
        dest: /opt/app/

  always:                            # ← Luôn chạy (dù thành công hay thất bại)
    - name: Gửi thông báo
      ansible.builtin.debug:
        msg: "Quá trình deploy đã hoàn tất (có thể thành công hoặc đã rollback)"
```

---

## 8. Thông tin hệ thống

### Module `stat` — Kiểm tra thông tin file

```yaml
- name: Kiểm tra file tồn tại
  ansible.builtin.stat:
    path: /etc/nginx/nginx.conf
  register: nginx_conf

- name: Thông báo kết quả
  ansible.builtin.debug:
    msg: "File tồn tại: {{ nginx_conf.stat.exists }}, Kích thước: {{ nginx_conf.stat.size | default(0) }} bytes"
```

### Module `find` — Tìm kiếm file

```yaml
# Tìm file log lớn hơn 100MB
- name: Tìm file log lớn
  ansible.builtin.find:
    paths: /var/log
    patterns: "*.log"
    size: "100m"
    recurse: yes
  register: large_logs

- name: Hiển thị kết quả
  ansible.builtin.debug:
    msg: "Tìm thấy {{ large_logs.files | length }} file log lớn"
```

### Module `hostname` — Đặt tên máy

```yaml
- name: Đặt hostname
  ansible.builtin.hostname:
    name: "web-{{ inventory_hostname }}"
```

---

## 9. Lập lịch

### Module `cron` — Quản lý cron jobs

```yaml
# Tạo cron job
- name: Backup database hàng ngày lúc 2 giờ sáng
  ansible.builtin.cron:
    name: "Database backup"         # Tên (dùng để nhận diện, phải unique)
    minute: "0"
    hour: "2"
    job: "/opt/scripts/backup.sh >> /var/log/backup.log 2>&1"
    user: root

# Cron chạy mỗi 5 phút
- name: Kiểm tra health mỗi 5 phút
  ansible.builtin.cron:
    name: "Health check"
    minute: "*/5"
    job: "curl -s http://localhost/health > /dev/null"

# Xoá cron job
- name: Xoá backup cũ
  ansible.builtin.cron:
    name: "Database backup"
    state: absent

# Tạo cron environment variable
- name: Đặt PATH cho cron
  ansible.builtin.cron:
    name: PATH
    env: yes
    value: "/usr/local/bin:/usr/bin:/bin"
```

---

## 10. Vòng lặp (Loops)

Ansible hỗ trợ vòng lặp để chạy cùng 1 task trên nhiều đối tượng:

```yaml
# Loop đơn giản
- name: Cài nhiều packages
  ansible.builtin.apt:
    name: "{{ item }}"
    state: present
  loop:
    - nginx
    - curl
    - vim
    - htop

# Loop với dictionary
- name: Tạo nhiều users
  ansible.builtin.user:
    name: "{{ item.name }}"
    shell: "{{ item.shell }}"
    groups: "{{ item.groups }}"
  loop:
    - { name: 'deploy', shell: '/bin/bash', groups: 'www-data' }
    - { name: 'monitor', shell: '/bin/sh', groups: 'docker' }

# Loop với index
- name: Tạo nhiều file
  ansible.builtin.copy:
    content: "Server {{ item }} - File {{ ansible_loop.index }}\n"
    dest: "/tmp/file-{{ ansible_loop.index }}.txt"
  loop:
    - alpha
    - beta
    - gamma

# Loop với when (lọc điều kiện)
- name: Cài package chỉ khi cần
  ansible.builtin.apt:
    name: "{{ item.name }}"
    state: present
  loop:
    - { name: 'nginx', install: true }
    - { name: 'apache2', install: false }
    - { name: 'curl', install: true }
  when: item.install
```

---

## Bảng tra cứu nhanh

| Muốn làm gì | Module | Ví dụ nhanh |
|-------------|--------|-------------|
| Cài phần mềm | `apt` | `apt: name=nginx state=present` |
| Sửa 1 dòng file | `lineinfile` | `lineinfile: path=/etc/conf regexp='^key' line='key=value'` |
| Thêm khối text | `blockinfile` | `blockinfile: path=/etc/conf block=...` |
| Copy file lên server | `copy` | `copy: src=local.txt dest=/remote.txt` |
| Render template | `template` | `template: src=app.conf.j2 dest=/etc/app.conf` |
| Tải file từ internet | `get_url` | `get_url: url=https://... dest=/tmp/file` |
| Giải nén | `unarchive` | `unarchive: src=/tmp/file.tar.gz dest=/opt/` |
| Tải file về máy mình | `fetch` | `fetch: src=/var/log/app.log dest=/tmp/` |
| Khởi động service | `service` | `service: name=nginx state=started` |
| Gọi HTTP API | `uri` | `uri: url=http://localhost/health status_code=200` |
| Đợi port mở | `wait_for` | `wait_for: port=80 timeout=30` |
| Chạy Docker container | `docker_container` | `docker_container: name=redis image=redis:7` |
| Kiểm tra file tồn tại | `stat` | `stat: path=/etc/nginx/nginx.conf` |
| Tạo cron job | `cron` | `cron: name=backup minute=0 hour=2 job=...` |
| Tạo user | `user` | `user: name=deploy shell=/bin/bash` |
| Dừng khi lỗi | `fail` | `fail: msg="Lỗi!" when: condition` |

**Trước đó:** [← Roles & Handlers](05-ansible-roles.md)
**Tiếp theo:** [Tích hợp Teleport + Ansible →](07-teleport-ansible-tich-hop.md)
