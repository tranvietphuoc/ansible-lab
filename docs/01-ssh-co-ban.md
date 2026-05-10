# SSH Căn bản

> **Tuần 1 — Ngày 01**
> Mục tiêu: Hiểu SSH là gì, tại sao cần, và cách hoạt động.

---

## SSH là gì?

**SSH (Secure Shell)** là giao thức truy cập máy tính từ xa có mã hoá. Khi bạn chạy `ssh root@server`, điều gì xảy ra?

```
Máy bạn (client)                Server
    |                              |
    |--- "Tôi muốn kết nối" ------>|  1. TCP handshake (port 22)
    |<--- "Đây là public key" -----|  2. Server gửi host key
    |--- "OK, đây là user key" --->|  3. Client gửi user key
    |<--- "Xác nhận thành công" ---|  4. Session mã hoá bắt đầu
    |--- lệnh/command ------------>|  5. Bạn có thể chạy lệnh
```

### Tại sao cần SSH?

- **Mã hoá**: Mọi dữ liệu truyền đi đều được mã hoá, không ai đọc lén được (khác với Telnet — gửi mật khẩu dạng văn bản thuần).
- **Xác thực**: Đảm bảo bạn đang kết nối đúng server, không bị giả mạo (man-in-the-middle).
- **Quản lý từ xa**: Cho phép bạn điều khiển server ở bất kỳ đâu trên thế giới qua Internet.

---

## 3 phương thức xác thực SSH

| Phương thức | Cách hoạt động | Độ an toàn |
|------------|----------------|------------|
| **Password** | Gõ mật khẩu khi kết nối | ⭐ Thấp — dễ bị brute-force |
| **Public Key** | Cặp key (private + public), private key giữ trên máy mình | ⭐⭐⭐ Cao — không truyền mật khẩu |
| **Certificate** | Giống Public Key nhưng có chữ ký từ CA (Certificate Authority) | ⭐⭐⭐⭐ Rất cao — Teleport dùng cách này |

### So sánh chi tiết

**Password authentication:**
```
Client: "Tôi là admin, mật khẩu là 123456"
Server: "OK, cho vào"
→ Vấn đề: Mật khẩu đi qua mạng (dù đã mã hoá), có thể bị đoán
```

**Public Key authentication:**
```
1. Bạn tạo cặp key: id_rsa (private, giữ trên máy) + id_rsa.pub (public, đặt lên server)
2. Khi kết nối, server thách thức (challenge) bằng public key
3. Client chứng minh mình có private key mà không cần gửi private key qua mạng
→ An toàn hơn vì private key không bao giờ rời khỏi máy bạn
```

**Certificate authentication (Teleport dùng cách này):**
```
1. Một CA (Certificate Authority) — trong trường hợp này là Teleport Auth Server — ký (sign) certificate cho bạn
2. Certificate có thời hạn (ví dụ: 12 giờ), tự hết hạn
3. Server tin tưởng CA, nên tin tưởng certificate do CA cấp
→ An toàn nhất vì không cần phân phát public key lên từng server
→ Certificate tự hết hạn, không cần thu hồi thủ công
```

---

## Thực hành

Mở terminal vào container master:

```bash
docker exec -it teleport-master bash
```

### Bài 1: Kiểm tra SSH client

```bash
# Xem SSH client có không
which ssh

# Xem SSH version
ssh -V

# Xem có SSH key chưa
ls -la ~/.ssh/
```

### Bài 2: Hiểu SSH config

```bash
# Xem SSH config hiện tại
cat ~/.ssh/config
```

Phân tích từng dòng:

```
Host node-01 node-02 teleport-master    # Áp dụng cho hosts nào
    IdentityFile .../admin              # Dùng private key nào
    CertificateFile .../cert.pub        # Dùng certificate nào
    Port 3022                           # Kết nối port nào
    ProxyCommand ... tsh proxy ssh ...  # Đi qua proxy nào
```

| Thuộc tính | Ý nghĩa |
|-----------|---------|
| `Host` | Danh sách hostname mà cấu hình này áp dụng |
| `IdentityFile` | Đường dẫn tới private key (do Teleport cấp) |
| `CertificateFile` | Đường dẫn tới SSH certificate (do Teleport CA ký) |
| `Port` | Port SSH trên server đích (Teleport dùng 3022, không phải 22) |
| `StrictHostKeyChecking` | Tắt kiểm tra host key (trong lab thì OK, production nên bật) |
| `ProxyCommand` | Lệnh tạo đường hầm (tunnel) qua Teleport Proxy |

### Bài 3: Thử kết nối SSH thường vs Teleport SSH

```bash
# SSH thường (sẽ thất bại vì không có sshd trên port 22)
ssh -p 22 root@node-01

# SSH qua Teleport (thành công)
tsh ssh root@node-01 hostname

# SSH qua config (Teleport proxy — cũng thành công)
ssh root@node-01 hostname
```

**Câu hỏi suy ngẫm**: Tại sao SSH thường thất bại nhưng `tsh ssh` thành công?

<details>
<summary>Đáp án</summary>

Node không chạy `sshd` (SSH daemon thường). Node chỉ chạy Teleport SSH trên port 3022. `tsh` biết cách nói chuyện với Teleport, còn SSH thường thì không (trừ khi có cấu hình `~/.ssh/config` với `ProxyCommand`).
</details>

### Bài 4: Xem verbose output

```bash
# Thêm -vvv để xem chi tiết quá trình kết nối SSH
ssh -vvv root@node-01 hostname
```

Quan sát output để hiểu:
- Bước nào nó đọc config file?
- Bước nào nó tải private key?
- Bước nào nó gọi ProxyCommand?
- Bước nào xác thực thành công?

---

## Bài tập

- [ ] Chạy `ssh -vvv root@node-01` và ghi chú các bước quan trọng trong quá trình handshake
- [ ] Ghi chú sự khác biệt giữa `tsh ssh` và `ssh` thường
- [ ] Thử tạo một cặp SSH key bằng lệnh `ssh-keygen -t ed25519` và quan sát 2 file được tạo ra (private key và public key)

---

## Tóm tắt

| Khái niệm | Giải thích ngắn |
|-----------|----------------|
| SSH | Giao thức truy cập máy chủ từ xa có mã hoá |
| Private Key | Chìa khoá bí mật — chỉ giữ trên máy mình, KHÔNG BAO GIỜ chia sẻ |
| Public Key | Ổ khoá — đặt lên server để server nhận diện mình |
| Certificate | Giấy chứng nhận có thời hạn — do CA (Teleport) cấp, tự hết hạn |
| SSH Config | File `~/.ssh/config` — cấu hình kết nối SSH cho từng host |

**Tiếp theo:** [Teleport căn bản →](02-teleport-co-ban.md)
