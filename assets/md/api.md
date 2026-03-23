# Tài liệu API Tunnel (shotpik-tunnel-demo)

Hệ thống API cung cấp các phương thức quản lý thư mục chia sẻ (album), tạo shortcut và cung cấp link tải file công khai thông qua Cloudflare Tunnel.

---

## 1. Cơ chế Bảo mật (RSA Signature)

Tất cả các API nằm trong tiền tố `/api/v1/` (**ngoại trừ API `/file/`**) đều yêu cầu xác thực bằng chữ ký RSA.

*   **Header bắt buộc:** `X-Signature: <base64_signature>`
*   **Cách tạo signature:** Ký lên toàn bộ nội dung của Request Body (chuỗi JSON) bằng mã khóa Private Key của App theo thuật toán **RSA-SHA256**. Nếu API là GET hoặc Body rỗng, ký lên một chuỗi rỗng `""`.

---

## 2. Quản lý Whitelist (Công khai)

Whitelist là danh sách các thư mục cho phép người dùng bên ngoài tải file mà không cần Token/Signature.

### GET /api/v1/whitelist/list
Lấy danh sách các thư mục đang được Whitelist.
*   **Phản hồi:** 
    ```json
    {
      "success": true,
      "data": [
        { "id": "...", "name": "...", "name_path": "Summer2024", "path": "...", "url": "..." }
      ]
    }
    ```

### POST /api/v1/whitelist
Thêm một thư mục vào Whitelist.
*   **Body:** `{"path": "FolderID_hoặc_NamePath_hoặc_LocalPath"}`
*   **Phản hồi:** Trả về thông tin thư mục và danh sách `whitelisted` mới nhất.

### DELETE /api/v1/whitelist/delete
Gỡ một thư mục khỏi Whitelist.
*   **Body:** `{"path": "..."}`

---

## 3. Quản lý Tunnel & Shortcut

### GET /api/v1/tunnel/list
Xem danh sách tất cả các thư mục (album) đang được chia sẻ trên App.
*   **Trường quan trọng:** `whitelisted: true/false` (biết thư mục đã được bảo vệ chưa).

### POST /api/v1/create-folder (Quan trọng)
Tạo shortcut (symlinks) từ một thư mục gốc vào một thư mục đích để chuẩn bị "xuất bản" (publish).
*   **Body:** 
    ```json
    {
      "location": "/Đường/dẫn/đích", 
      "path": "/Đường/dẫn/nguồn",
      "files": ["file1.jpg", "file2.pdf"] (Nếu rỗng sẽ lấy toàn bộ)
    }
    ```
*   **Điều kiện:** Thư mục `path` (nguồn) phải nằm trong Whitelist.
*   **Cơ chế tự động:** Thư mục `location` (đích) sẽ tự động được đăng ký vào App và tự động Whitelist sau khi tạo xong. Trả về `name_path` để dùng cho API tải file.

---

## 4. API Tải File Công khai (Public API)

Đây là API duy nhất không cần Signature, dùng để nhúng link ảnh/file vào website/app.

### GET /file/{name_path}/{relative_path}
*   **Ví dụ:** `GET /file/Summer2024_1/photo.jpg`
*   **Cơ chế hoạt động:**
    1.  Tìm thư mục có `name_path` là `Summer2024_1` trong Whitelist.
    2.  Kiểm tra file `photo.jpg` bên trong thư mục đó.
    3.  **Bắt buộc:** File phải là một **Shortcut (Symlink)** (được tạo qua lệnh `create-folder`).
*   **Phản hồi:** 
    ```json
    {
      "success": true, 
      "url": "https://<cloudflare_tunnel_id>.trycloudflare.com/photo.jpg" 
    }
    ```

---

## 5. Các biến chính và chức năng

| Biến | Chức năng | Ghi chú |
| :--- | :--- | :--- |
| `path` | Đường dẫn tuyệt đối hoặc định danh | Dùng trong Request để xác định thư mục nguồn/đích. |
| `location` | Thư mục chứa Shortcut | Nơi app sẽ tạo các Symlink để publish. |
| `name_path` | Slug định danh URL | Tên thư mục dùng trong link `/file/`. Ví dụ: `summer2024_1`. |
| `is_whitelisted`| Trạng thái bảo vệ | Boolean, xác định folder có được phép truy cập công khai không. |
| `tunnel_url` | Link Cloudflare | Địa chỉ internet để truy cập file từ xa. |
| `files` | Danh sách file | Lọc các file cụ thể muốn tạo shortcut. |

---

## 6. Luồng hoạt động tiêu chuẩn (Workflow)

1.  **Bước 1:** Thêm thư mục gốc (Album ảnh) vào App và bấm biểu tượng khiên (Whitelist).
2.  **Bước 2:** Gọi API `create-folder` để tạo các Shortcut vào một thư mục rỗng (ví dụ: `Export_Folder`).
3.  **Bước 3:** Hệ thống tự động Whitelist `Export_Folder` và trả về `name_path`.
4.  **Bước 4:** Sử dụng `domain:port/file/Export_Folder/ten_anh.jpg` để lấy link ảnh công khai cho web/app của bạn.
