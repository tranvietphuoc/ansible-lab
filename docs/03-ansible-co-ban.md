# Ansible Căn bản

> **Tuần 2 — Ngày 06 đến 07**
> Mục tiêu: Hiểu Ansible là gì, kiến trúc Agentless, chạy lệnh đầu tiên, và nắm vững các module cơ bản.

---

## Ansible là gì?

**Ansible** là công cụ tự động hoá: cấu hình server, deploy ứng dụng, chạy lệnh từ xa — tất cả mà **không cần cài bất kỳ phần mềm nào trên server đích**.

### So sánh các công cụ

| Công cụ | Cần cài gì trên target? | Cách kết nối | Ưu điểm |
|---------|------------------------|-------------|---------|
| Shell script + SSH | Chỉ cần SSH | Bạn phải viết mọi thứ | Đơn giản nhưng khó bảo trì |
| **Ansible** | Chỉ cần Python + SSH | Module sẵn, idempotent | Dễ học, không cần agent |
| Puppet/Chef | Cần agent chạy ngầm | Agent kết nối về server | Phức tạp, tốn tài nguyên |
| Terraform | Không cần trên target | API của cloud provider | Chuyên tạo hạ tầng, không quản lý OS |

### Kiến trúc Ansible

```
Control Node (teleport-master)        Target Nodes
+------------------+                  +------------------+
| Ansible          | --- SSH/3022 --> | node-01 (Python) |
| - playbooks      |                  +------------------+
| - inventory      | --- SSH/3022 --> | node-02 (Python) |
| - roles          |                  +------------------+
+------------------+
```

**Không cần agent trên target!** Ansible dùng SSH để kết nối, Python trên target để chạy module.

### Khái niệm Idempotent

**Idempotent** nghĩa là: *chạy nhiều lần cho cùng kết quả*. Đây là nguyên tắc cốt lõi của Ansible.

```
Lần 1: "Cài nginx" → nginx chưa có → CÀI → changed
Lần 2: "Cài nginx" → nginx đã có  → BỎ QUA → ok
Lần 3: "Cài nginx" → nginx đã có  → BỎ QUA → ok
```

Khác với shell script, nơi mà chạy `apt install nginx` lần thứ 2 vẫn tốn thời gian kiểm tra, Ansible kiểm tra trạng thái trước rồi mới quyết định có hành động hay không.

---

## Cấu hình Ansible trong Lab

### File `ansible.cfg`

```ini
[defaults]
inventory = ./inventory.ini       # Danh sách server
roles_path = ./roles               # Thư mục chứa roles
host_key_checking = False          # Tắt kiểm tra host key (lab only!)
remote_user = root                 # Đăng nhập server bằng user nào
stdout_callback = default          # Hiển thị output dạng gì

[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=30m  # Giữ kết nối SSH 30 phút
```

### File `inventory.ini`

```ini
[webservers]          # Nhóm web servers
node-01
node-02

[monitoring]          # Nhóm monitoring
teleport-master

[all:children]        # Nhóm "all" bao gồm 2 nhóm con
webservers
monitoring

[all:vars]            # Biến chung cho tất cả
ansible_python_interpreter=/usr/bin/python3
ansible_port=3022     # Teleport SSH port
```

---

## Thực hành cơ bản

```bash
cd /home/teleport/ansible
```

### Bài 1: Kiểm tra Ansible

```bash
# Phiên bản
ansible --version

# Inventory có những host nào?
ansible-inventory --list

# Ping tất cả
ansible all -m ping
```

### Bài 2: Ad-hoc commands (không cần playbook)

**Ad-hoc command** là cách chạy 1 lệnh nhanh mà không cần viết file YAML.

Cú pháp: `ansible <host-pattern> -m <module> -a "<tham số>"`

```bash
# Chạy lệnh đơn giản trên webservers
ansible webservers -m shell -a "hostname"
ansible webservers -m shell -a "uptime"
ansible webservers -m shell -a "free -h"
ansible webservers -m shell -a "df -h"

# Thu thập thông tin hệ thống (facts)
ansible node-01 -m setup | head -50
```

### Bài 3: Hiểu Inventory

```bash
cat inventory.ini
```

Phân tích:
- `[webservers]` — nhóm các web servers
- `[monitoring]` — nhóm monitoring servers
- `[all:children]` — nhóm tổng hợp từ các nhóm con
- `[all:vars]` — biến chung cho tất cả

```bash
# Liệt kê hosts trong group
ansible webservers --list-hosts
ansible monitoring --list-hosts
ansible all --list-hosts

# Chạy lệnh trên group cụ thể
ansible webservers -m shell -a "hostname"
ansible monitoring -m shell -a "hostname"
```

---

## Ansible Modules cơ bản (Ngày 07)

**Module** là đơn vị chức năng của Ansible. Mỗi module làm 1 việc cụ thể.

### Tổng quan các module cơ bản

| Module | Chức năng | Ví dụ |
|--------|-----------|-------|
| `ping` | Kiểm tra kết nối | `ansible all -m ping` |
| `shell` | Chạy lệnh shell | `-m shell -a "uptime"` |
| `command` | Chạy lệnh (không qua shell) | `-m command -a "ls /tmp"` |
| `apt` | Quản lý packages (Debian/Ubuntu) | `-m apt -a "name=nginx state=present"` |
| `copy` | Copy file từ control → target | `-m copy -a "src=x dest=y"` |
| `file` | Quản lý file/directory | `-m file -a "path=/tmp/test state=directory"` |
| `service` | Quản lý service | `-m service -a "name=nginx state=started"` |
| `user` | Tạo/xoá user | `-m user -a "name=deploy shell=/bin/bash"` |
| `debug` | In thông tin debug | `-m debug -a "msg='Hello'"` |
| `setup` | Thu thập thông tin hệ thống | `ansible node-01 -m setup` |

### Module `ping` — Kiểm tra kết nối

```bash
# Ping tất cả hosts
ansible all -m ping

# Ping một group
ansible webservers -m ping

# Ping một host cụ thể
ansible node-01 -m ping
```

> **Lưu ý:** Module `ping` của Ansible KHÔNG giống lệnh `ping` mạng. Nó kiểm tra xem Ansible có thể SSH vào server và chạy Python được không.

### Module `shell` vs `command`

```bash
# shell: chạy qua /bin/sh — hỗ trợ pipe, redirect
ansible webservers -m shell -a "cat /etc/hostname | tr 'a-z' 'A-Z'"

# command: chạy trực tiếp — KHÔNG hỗ trợ pipe, redirect (an toàn hơn)
ansible webservers -m command -a "ls /tmp"
```

| | `shell` | `command` |
|---|---------|-----------|
| Pipe (`\|`) | ✅ Có | ❌ Không |
| Redirect (`>`) | ✅ Có | ❌ Không |
| Biến môi trường | ✅ Có | ❌ Không |
| Độ an toàn | Thấp hơn | Cao hơn |
| Khi nào dùng | Cần pipe/redirect | Mặc định nên dùng |

### Module `apt` — Quản lý gói phần mềm

```bash
# Cài 1 package
ansible webservers -m apt -a "name=htop state=present update_cache=yes" --become

# Xem package đã cài chưa
ansible webservers -m shell -a "dpkg -l | grep htop"

# Gỡ package
ansible webservers -m apt -a "name=htop state=absent" --become

# Cài nhiều package cùng lúc
ansible webservers -m apt -a "name=vim,curl,wget state=present" --become
```

Các giá trị `state`:
| State | Ý nghĩa |
|-------|---------|
| `present` | Cài đặt nếu chưa có |
| `absent` | Gỡ bỏ nếu đang có |
| `latest` | Cài hoặc nâng cấp lên phiên bản mới nhất |

### Module `file` — Quản lý file và thư mục

```bash
# Tạo directory
ansible webservers -m file -a "path=/tmp/lab-test state=directory mode=0755" --become

# Tạo file rỗng
ansible webservers -m file -a "path=/tmp/lab-test/hello.txt state=touch" --become

# Tạo symlink
ansible webservers -m file -a "src=/tmp/lab-test dest=/tmp/lab-link state=link" --become

# Kiểm tra
ansible webservers -m shell -a "ls -la /tmp/lab-test/"

# Xoá directory (đệ quy)
ansible webservers -m file -a "path=/tmp/lab-test state=absent" --become
```

### Module `copy` — Copy file

```bash
# Tạo file local
echo "Hello from Ansible" > /tmp/hello.txt

# Copy lên nodes
ansible webservers -m copy -a "src=/tmp/hello.txt dest=/tmp/hello.txt" --become

# Copy với nội dung inline (không cần file local)
ansible webservers -m copy -a "content='Xin chào từ Ansible\n' dest=/tmp/greeting.txt" --become

# Kiểm tra
ansible webservers -m shell -a "cat /tmp/hello.txt"
```

### Module `user` — Quản lý người dùng

```bash
# Tạo user
ansible webservers -m user -a "name=deploy shell=/bin/bash" --become

# Kiểm tra
ansible webservers -m shell -a "id deploy"

# Tạo user với home directory và group
ansible webservers -m user -a "name=appuser shell=/bin/bash home=/opt/app groups=www-data" --become

# Xoá user
ansible webservers -m user -a "name=deploy state=absent remove=yes" --become
```

### Module `service` — Quản lý dịch vụ

```bash
# Khởi động service
ansible webservers -m service -a "name=nginx state=started" --become

# Dừng service
ansible webservers -m service -a "name=nginx state=stopped" --become

# Khởi động lại
ansible webservers -m service -a "name=nginx state=restarted" --become

# Reload (không downtime)
ansible webservers -m service -a "name=nginx state=reloaded" --become

# Bật tự khởi động khi boot
ansible webservers -m service -a "name=nginx enabled=yes" --become
```

### Module `setup` — Thu thập thông tin hệ thống

```bash
# Tất cả thông tin (rất dài)
ansible node-01 -m setup

# Chỉ lấy thông tin OS
ansible node-01 -m setup -a "filter=ansible_distribution*"

# Chỉ lấy thông tin network
ansible node-01 -m setup -a "filter=ansible_default_ipv4"

# Chỉ lấy thông tin memory
ansible node-01 -m setup -a "filter=ansible_mem*"
```

Các biến phổ biến từ `setup` (gọi là **facts**):

| Biến | Ý nghĩa | Ví dụ giá trị |
|------|---------|---------------|
| `ansible_hostname` | Tên máy | `node-01` |
| `ansible_distribution` | Hệ điều hành | `Debian` |
| `ansible_distribution_version` | Phiên bản OS | `12` |
| `ansible_default_ipv4.address` | Địa chỉ IP | `172.18.0.3` |
| `ansible_memtotal_mb` | Tổng RAM (MB) | `8192` |
| `ansible_processor_vcpus` | Số CPU | `4` |

---

## Bài tập

- [ ] Dùng ad-hoc commands để: cài `curl`, tạo user `appuser`, tạo directory `/opt/app`
- [ ] Chạy lại các lệnh trên nhiều lần. Có thấy gì không? (Idempotency)
- [ ] Chạy `ansible all -m setup` và tìm: IP address, OS version, RAM, CPU của mỗi node
- [ ] Tìm hiểu: tại sao Ansible cần Python trên target?

---

## Tóm tắt

| Khái niệm | Giải thích ngắn |
|-----------|----------------|
| Agentless | Không cần cài phần mềm trên server đích |
| Control Node | Máy chạy Ansible (laptop hoặc server điều khiển) |
| Target Node | Máy chủ đích mà Ansible quản lý |
| Inventory | Danh sách server và cách phân nhóm |
| Module | Đơn vị chức năng (apt, copy, file, service...) |
| Ad-hoc | Chạy 1 module nhanh không cần viết file |
| Facts | Thông tin hệ thống tự động thu thập bởi module `setup` |
| Idempotent | Chạy nhiều lần, kết quả giống nhau |
| `--become` | Chạy với quyền sudo/root |

**Trước đó:** [← Teleport căn bản](02-teleport-co-ban.md)
**Tiếp theo:** [Playbooks, Variables & Templates →](04-ansible-playbook.md)
