# Teleport Căn bản

> **Tuần 1 — Ngày 02 đến 05**
> Mục tiêu: Hiểu kiến trúc Teleport, quản lý Users & Roles, SSH qua Teleport, và Audit.

---

## Phần 1: Kiến trúc Teleport (Ngày 02)

### Teleport là gì?

Teleport là một nền tảng **Zero Trust Access** — nó thay thế SSH truyền thống bằng một hệ thống truy cập có xác thực, phân quyền, và ghi nhật ký tập trung. Thay vì phải quản lý file SSH key trên từng server, Teleport tập trung mọi thứ vào một điểm duy nhất.

### 3 thành phần chính

```
                        Teleport Cluster
                        +-----------------+
                        |                 |
   +--------+           |  +-----------+  |
   | tsh    |---------->|  | Proxy     |  |  Port 3080 (WebUI)
   | (user) |  HTTPS    |  |           |  |  Port 3023 (SSH proxy)
   +--------+           |  +-----+-----+  |
                        |        |         |
                        |  +-----v-----+  |
                        |  | Auth      |  |  Port 3025 (nội bộ)
                        |  | Server    |  |
                        |  +-----+-----+  |
                        |        |         |
                        |  +-----v-----+  |
                        |  | Nodes     |  |  Port 3022 (SSH)
                        |  | node-01   |  |
                        |  | node-02   |  |
                        |  +-----------+  |
                        +-----------------+
```

| Thành phần | Vai trò | Tương đương |
|-----------|---------|-------------|
| **Auth Server** | Quản lý identity, certificate, RBAC | CA (Certificate Authority) |
| **Proxy** | Gateway — trung gian giữa user và nodes | SSH bastion host |
| **Node (Agent)** | SSH service trên target server | sshd |

### Luồng kết nối

```
User -> tsh login -> Proxy -> Auth (xác minh password/certificate)
User -> tsh ssh   -> Proxy -> Auth (kiểm tra quyền) -> Node
```

**Điểm quan trọng:** Node không mở port ra Internet. Node tự động tạo **reverse tunnel** (đường hầm ngược) về Proxy. Nhờ vậy, bạn có thể SSH vào server nằm sau firewall mà không cần mở port.

### Thực hành

**Bài 1: Khám phá cluster**

```bash
# Xem các nodes trong cluster
tctl --auth-server=localhost:3025 nodes ls

# Xem các auth servers
tctl --auth-server=localhost:3025 auth ls

# Xem các proxy servers
tctl --auth-server=localhost:3025 proxy ls

# Xem các tokens (lời mời join)
tctl --auth-server=localhost:3025 tokens ls
```

**Bài 2: Khám phá WebUI**

Mở trình duyệt: `https://localhost:3080`

- Đăng nhập với user admin
- Khám phá từng menu: Nodes, Sessions, Audit, Users, Roles

**Bài 3: Xem cấu hình Teleport**

```bash
# File cấu hình master
cat /etc/teleport/teleport.yaml
```

Phân tích từng section:
- `auth_service` + `tokens`: Ai được phép join cluster?
- `proxy_service`: Proxy lắng nghe ở đâu?
- `ssh_service`: Master cũng là một node SSH

**Bài 4: Xem log Teleport**

```bash
# Log của master
docker logs teleport-master --tail 20

# Log của node
docker logs node-01 --tail 20
```

Tìm kiếm trong log: "join", "auth", "certificate" — hiểu điều gì xảy ra khi node join.

### Bài tập
- [ ] Vẽ lại kiến trúc Teleport bằng tay (không copy)
- [ ] Giải thích bằng lời của bạn: tại sao không SSH trực tiếp mà cần Teleport?
- [ ] Tìm hiểu: Nếu Auth Server down, điều gì xảy ra?

---

## Phần 2: Users & Roles — RBAC (Ngày 03)

### RBAC là gì?

**RBAC (Role-Based Access Control)** — Kiểm soát truy cập dựa trên vai trò.

```
User (admin) -- có roles --> [editor, access, node-access]
                                     |
                              Role định nghĩa:
                              - logins: [root, admin]      -> Dùng user Linux nào
                              - node_labels: {env: prod}   -> Vào máy nào
                              - max_session_ttl: 8h         -> Tối đa bao lâu
```

### Phân biệt 3 loại "user"

| Loại | Ví dụ | Giải thích |
|------|-------|------------|
| Teleport user | `admin` | Tài khoản đăng nhập Teleport |
| Linux login | `root`, `admin` | Tài khoản trên server đích |
| Role | `editor`, `node-access` | Quyền trong Teleport |

**Ví dụ thực tế:** Teleport user `phuoc` có role `developer`. Role `developer` cho phép login bằng user Linux `deploy` vào các node có label `env: staging`. Nghĩa là `phuoc` chỉ SSH được vào staging server, với tài khoản Linux `deploy`, và session tối đa 4 giờ.

### Thực hành

**Bài 1: Xem user hiện tại**

```bash
# Thông tin user đang login
tsh status

# Chi tiết user
tctl --auth-server=localhost:3025 get user/admin

# Tất cả users
tctl --auth-server=localhost:3025 users ls
```

**Bài 2: Tạo user mới và quan sát**

```bash
# Tạo user "developer"
tctl --auth-server=localhost:3025 users add developer --roles=access
```

Mở link trong browser để set password cho developer.

**Bài 3: Tạo role hạn chế**

```bash
# Role chỉ được xem, không được chạy lệnh nguy hiểm
cat <<'EOF' | tctl --auth-server=localhost:3025 create -f
kind: role
version: v5
metadata:
  name: viewer
spec:
  allow:
    logins: [viewer]
    node_labels:
      "*": "*"
  options:
    max_session_ttl: 1h0m0s
    forward_agent: false
    ssh_file_copy: false
EOF
```

**Bài 4: Kiểm tra RBAC**

```bash
# Gán role viewer cho developer
tctl --auth-server=localhost:3025 users update developer --set-roles=access,viewer

# Login với developer
tsh logout
tsh login --proxy=localhost:3080 --user=developer

# Thử SSH
tsh ssh viewer@node-01 hostname

# Thử SSH với root (sẽ thất bại — viewer không có login root)
tsh ssh root@node-01 hostname
```

**Bài 5: Quay lại user admin**

```bash
tsh logout
tsh login --proxy=localhost:3080 --user=admin
```

### Bài tập
- [ ] Tạo 1 user `ops` chỉ được phép SSH vào node-01 (không vào được node-02)
- [ ] Giải thích: tại sao `tsh ssh root@node-01` thất bại với user developer?
- [ ] Tìm hiểu: `node_labels` là gì? Nó giúp gì trong môi trường thực tế?

---

## Phần 3: Teleport SSH & Audit (Ngày 04)

### SSH qua Teleport

Teleport cung cấp hai cách SSH:

| Cách | Lệnh | Khi nào dùng |
|------|-------|-------------|
| `tsh ssh` | `tsh ssh root@node-01` | Trực tiếp, nhanh gọn |
| SSH qua config | `ssh root@node-01` | Khi dùng với Ansible, scripts |

### Thực hành

**Bài 1: Các lệnh SSH**

```bash
# Chạy 1 lệnh
tsh ssh root@node-01 uptime
tsh ssh root@node-01 "cat /etc/os-release"
tsh ssh root@node-01 "free -h"

# Mở interactive shell
tsh ssh root@node-01
# (gõ 'exit' để thoát)

# SSH vào nhiều node cùng lúc
tsh ssh root@node-01 "hostname && uptime"
```

**Bài 2: Truyền file (SCP)**

```bash
# Tạo file test
echo "Hello from Teleport" > /tmp/test.txt

# Copy lên node (SCP)
tsh scp /tmp/test.txt root@node-01:/tmp/

# Kiểm tra
tsh ssh root@node-01 "cat /tmp/test.txt"

# Copy từ node về
tsh scp root@node-01:/tmp/test.txt /tmp/test-backup.txt
cat /tmp/test-backup.txt
```

**Bài 3: Ghi phiên SSH (Session recording)**

```bash
# Mở SSH session và chạy vài lệnh
tsh ssh root@node-01
# Trong session:
hostname
whoami
ls /tmp
exit

# Xem danh sách recordings
tsh recordings ls

# Replay một session (dùng recording ID từ lệnh trên)
# tsh play <session-id>
```

**Bài 4: Audit qua WebUI**

1. Mở `https://localhost:3080`
2. Vào menu **Sessions** — thấy danh sách SSH sessions
3. Vào menu **Audit** — thấy log mọi thao tác
4. Click vào một session để xem chi tiết

**Bài 5: Audit qua CLI**

```bash
# Xem audit events
tctl --auth-server=localhost:3025 audit query --query "event = session.start"

# Xem user login events
tctl --auth-server=localhost:3025 audit query --query "event = user.login"
```

### Bài tập
- [ ] SSH vào node-01, chạy vài lệnh, thoát. Tìm session recording đó.
- [ ] Upload 1 file Python lên node và chạy nó
- [ ] Giải thích: vì sao Teleport ghi lại được mọi session? Điều này có lợi ích gì trong production?

---

## Phần 4: Tổng hợp Tuần 1 (Ngày 05)

### Bài tập tổng hợp

**Challenge 1: Tạo môi trường multi-user**

```bash
# 1. Tạo 3 users:
#    - admin (toàn quyền)
#    - developer (chỉ đọc, 2h TTL)
#    - sre (SSH được, 8h TTL)

# 2. Tạo roles phù hợp cho từng user

# 3. Với mỗi user, thử:
#    - tsh login
#    - tsh ls (thấy nodes nào?)
#    - tsh ssh root@node-01 (được không?)
#    - tsh ssh viewer@node-01 (được không?)
```

**Challenge 2: Debug Teleport**

```bash
# Stop node-01
docker stop node-01

# Thử tsh ssh root@node-01
# Bạn thấy lỗi gì? Vì sao?

# Start lại
docker start node-01

# Đợi node join lại
tctl --auth-server=localhost:3025 nodes ls
```

**Challenge 3: Xoá và join lại node**

```bash
# Xoá node-01 khỏi cluster
tctl --auth-server=localhost:3025 rm node/<node-01-uuid>

# Xem node-01 còn trong danh sách không?
tctl --auth-server=localhost:3025 nodes ls

# Restart node-01 để join lại
docker restart node-01

# Kiểm tra lại
tctl --auth-server=localhost:3025 nodes ls
```

### Tự đánh giá

Sau tuần 1, bạn nên hiểu:
- [ ] SSH là gì, tại sao cần mã hoá
- [ ] Teleport kiến trúc: Auth, Proxy, Node
- [ ] User vs Role vs Linux login
- [ ] Cách tạo user, tạo role, gán role
- [ ] `tsh ssh`, `tsh scp`, `tsh recordings`
- [ ] Audit log — tại sao quan trọng

---

## Tóm tắt

| Khái niệm | Giải thích ngắn |
|-----------|----------------|
| Auth Server | Trung tâm xác thực, cấp certificate, quản lý quyền |
| Proxy | Cổng vào duy nhất, trung gian giữa user và nodes |
| Node Agent | Phần mềm cài trên mỗi server để nhận kết nối |
| RBAC | Phân quyền theo vai trò (Role → Login → Node Label) |
| Session Recording | Teleport ghi lại mọi phiên SSH để audit |
| Certificate | Chứng chỉ ngắn hạn thay thế SSH key truyền thống |

**Trước đó:** [← SSH căn bản](01-ssh-co-ban.md)
**Tiếp theo:** [Ansible căn bản →](03-ansible-co-ban.md)
