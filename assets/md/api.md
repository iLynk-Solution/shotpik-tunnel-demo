# Tài liệu API Shotpik Tunnel

Tài liệu hướng dẫn các endpoint API để quản lý và truy cập file thông qua Shotpik Tunnel.

---

## 1. Cơ chế Bảo mật (RSA Signature)

Các API yêu cầu **RSA Signature** bắt buộc phải đính kèm Header:
`X-Signature: <base64_signature>`

- **Thuật toán:** RSA-SHA256.
- **Cách tạo signature:** Ký lên toàn bộ nội dung của Request Body (chuỗi JSON đã được minify - loại bỏ khoảng trắng và xuống dòng) bằng mã khóa Private Key của App. 
- **Lưu ý:** Nếu API không có Body hoặc Body rỗng, hãy ký phát hành chữ ký trên một chuỗi rỗng `""`.

---

## 2. Danh sách API (Theo thứ tự ưu tiên)

| Thứ tự | Phương thức | Endpoint | Yêu cầu Xác thực |
| :--- | :--- | :--- | :--- |
| 1 | POST | `/api/v1/search` | **RSA Signature** |
| 2 | POST | `/api/v1/files` | **RSA Signature** |
| 3 | POST | `/api/v1/whitelist` | **RSA Signature** |
| 4 | POST | `/api/v1/create-folder` | **RSA Signature** |
| 5 | GET | `/file/{path}` | Công khai (Public) |
| 6 | GET | `/healthcheck` | Công khai (Public) |

---

## 3. Chi tiết các Endpoint

### 1. Tìm kiếm thư mục (`POST /api/v1/search`)
Dùng để quét và tìm kiếm các thư mục trên máy tính local.
- **Xác thực:** RSA Signature.
- **Body mẫu:**
```json
{
  "path": "Wedding_Album", // Từ khóa tìm kiếm
  "base_path": "/Users/Documents" // Thư mục gốc để quét (Tùy chọn)
}
```

### 2. Danh sách Album/File (`POST /api/v1/files`)
Lấy danh sách các Album đã chia sẻ hoặc liệt kê file bên trong một Album.
- **Xác thực:** RSA Signature.
- **Body mẫu (Lấy danh sách Album):**
```json
{
  "path": "" 
}
```
- **Body mẫu (Liệt kê file trong Album):**
```json
{
  "path": "wedding_2024" // Tên định danh (slug) của Album
}
```
- **Lưu ý:** Đối với endpoint này, chỉ sử dụng duy nhất key `path` làm định danh ảo. Không sử dụng ID hệ thống hay đường dẫn vật lý.

### 3. Quản lý Whitelist (`/api/v1/whitelist/...`)
Cấp quyền hoặc thu hồi quyền truy cập công khai của Album. Tất cả các endpoint này yêu cầu **RSA Signature**.

- **Thêm vào Whitelist (POST `/api/v1/whitelist`):**
  - Body: `{"path": "slug_cua_album"}`
- **Danh sách Whitelist (GET `/api/v1/whitelist/list`):**
  - Trả về danh sách các Album đang được phép truy xuất công khai.
- **Xóa khỏi Whitelist (DELETE/POST `/api/v1/whitelist/delete`):**
  - Body: `{"path": "slug_cua_album"}`
- **Xóa toàn bộ Whitelist (DELETE/POST `/api/v1/whitelist/clear`):**
  - Dùng để dọn dẹp toàn bộ danh sách cho phép.


### 4. Tạo thư mục phím tắt (`POST /api/v1/create-folder`)
Tạo các phím tắt (symlink) từ một thư mục nguồn ngoài hệ thống vào một thư mục do app quản lý để chuẩn bị "xuất bản" (publish).
- **Xác thực:** RSA Signature.
- **Body mẫu:**
```json
{
  "location": "/path/to/export", // Thư mục đích (đã whitelist)
  "path": "/path/to/original",   // Thư mục ảnh gốc (nguồn)
  "files": ["img1.jpg", "img2.png"] // (Tùy chọn) Lọc file cụ thể
}
```

### 5. Truy cập/Tải File (`GET /file/{path}`)
Link trực tiếp dành cho phía Website hoặc App để hiển thị ảnh.
- **Xác thực:** Công khai (Public).
- **Định dạng URL:** `/file/{path}/{relative_sub_path}`
- **Ví dụ:** `/file/wedding_2024/beach/photo1.jpg`

### 6. Kiểm tra dịch vụ (`GET /healthcheck`)
Endpoint kiểm tra trạng thái hoạt động của server.
- **Xác thực:** Công khai (Public).
- **Phản hồi:** `{"status": "ok"}`
