# Tài liệu API Shotpik Tunnel (Cập nhật 25/03/2026)

Tài liệu hướng dẫn các endpoint API để quản lý và truy cập file thông qua Shotpik Tunnel, sử dụng **Đường dẫn tuyệt đối (Absolute Path)** làm định danh duy nhất.

---

## 1. Cơ chế Bảo mật (RSA Signature)

Các API quản lý yêu cầu **RSA Signature** để xác thực quyền truy cập từ App Shotpik.

- **Header bắt buộc:** `X-Signature: <base64_signature>`
- **Thuật toán:** RSA-SHA256.
- **Cách tạo signature:** KÝ lên toàn bộ nội dung của Request Body (chuỗi JSON đã được minify - loại bỏ khoảng trắng và xuống dòng) bằng Private Key của App.
- **Lưu ý:** Nếu API không có Body (GET), hãy ký trên một chuỗi rỗng `""`.

---

## 2. Danh sách API

| Phương thức | Endpoint | Yêu cầu Xác thực | Mô tả |
| :--- | :--- | :--- | :--- |
| POST | `/api/v1/search` | **RSA Signature** | Quét tìm thư mục cục bộ (Search root) |
| POST | `/api/v1/files` | **RSA Signature** | Liệt kê file/thư mục (Dùng Absolute Path) |
| POST | `/api/v1/tunnel/create` | **RSA Signature** | Đăng ký chia sẻ một thư mục mới (Tạo Tunnel) |
| POST | `/api/v1/tunnel/list` | **RSA Signature** | Danh sách tất cả thư mục đang "Watch" |
| POST | `/api/v1/whitelist` | **RSA Signature** | Bật công khai (Whitelist) cho một thư mục |
| DELETE | `/api/v1/whitelist/delete` | **RSA Signature** | Hủy công khai (Gỡ Whitelist) |
| GET | `/api/v1/whitelist/list` | **RSA Signature** | Danh sách các thư mục đang công khai và URL |
| POST | `/api/v1/create-folder` | **RSA Signature** | Tạo shortcut (Symlink) từ danh sách file tuyệt đối |

---

## 3. Chi tiết các Endpoint quan trọng

### 1. Đăng ký Chia sẻ (`POST /api/v1/tunnel/create`)
Đưa một thư mục vào danh sách theo dõi của App để có thể truy cập từ xa.
- **Body:**
```json
{
  "path": "/Users/tuyen/Downloads/MyAlbum", // Đường dẫn tuyệt đối (Bắt buộc)
  "name": "Wedding 2024", // Tên hiển thị (Tùy chọn)
  "name_path": "wedding-2024" // Tên ảo/Slug cho URL (Tùy chọn)
}
```
- **Phản hồi:** Trả về thông tin Tunnel bao gồm `path` tuyệt đối và `url` riêng của Cloudflare.

### 2. Liệt kê File (`POST /api/v1/files`)
Lấy danh sách file bên trong thư mục. Trả về `public_url` nếu thư mục đã được Whitelist.
- **Body:** `{ "path": "/Users/tuyen/Downloads/MyAlbum" }`
- **Dữ liệu trả về:**
```json
{
  "name": "photo.jpg",
  "path": "/Users/tuyen/Downloads/MyAlbum/photo.jpg",
  "url": "https://chambers-....trycloudflare.com/Users/tuyen/...", // Link Tunnel
  "public_url": "https://gateway-domain.com/Users/tuyen/..." // Link Gateway (Nếu whitelisted)
}
```

### 3. Quản lý Whitelist (`/api/v1/whitelist`)
Dùng để bật/tắt quyền truy cập công khai mà không cần Signature cho các file bên trong.
- **POST/DELETE Body:** `{ "path": "/Users/tuyen/Downloads/MyAlbum" }`
- **Lưu ý:** Phải dùng đường dẫn tuyệt đối để định danh chính xác thư mục cần thao tác.

### 4. Danh sách Whitelist (`GET /api/v1/whitelist/list`)
Lấy tất cả các "Album" đang được công khai kèm theo link Gateway chính thức.
- **Phản hồi mẫu:**
```json
{
  "success": true,
  "data": [
    {
      "name": "Wedding 2024",
      "path": "/Users/tuyen/Downloads/MyAlbum",
      "url": "https://tunnel-domain.com/", 
      "public_url": "https://gateway-domain.com/Users/tuyen/Downloads/MyAlbum/",
      "status": "online"
    }
  ]
}
```

### 5. Tạo Shortcut hàng loạt (`POST /api/v1/create-folder`)
Hệ thống sẽ tạo các symlink (tương tự như tệp Shortcut) từ danh sách các tệp tin nguồn vào thư mục đích.
- **Body:**
```json
{
  "path": "/Users/tuyen/Desktop/Exports/Session-001", // Thư mục Đích (Shortcut sẽ nằm ở đây)
  "files": [
    "/Users/tuyen/Pictures/a.jpg", // Danh sách file nguồn (Đường dẫn tuyệt đối)
    "/Users/tuyen/Pictures/b.png"
  ]
}
```

---

## 4. Truy cập Công khai (Gateway Domain)

Khi một thư mục đã nằm trong **Whitelist**, toàn bộ nội dung bên trong có thể được truy cập trực tiếp thông qua Gateway Domain của hệ thống Shotpik mà không cần đính kèm Signature hay Token.

- **Cấu trúc URL:** `https://{GATEWAY_DOMAIN}/{ABSOLUTE_LOCAL_PATH}`
- **Ví dụ:** `https://lcd-caribbean-....trycloudflare.com/Users/tuyentb.it/Downloads/my_files/image.jpg`

---
*Tài liệu này được cập nhật tự động dựa trên phiên bản logic mới nhất của hệ thống Tunnel Desktop.*
