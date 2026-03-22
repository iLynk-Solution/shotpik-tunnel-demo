**1. Quản lý Tunnel (Album chia sẻ)**

* **GET /api/v1/tunnel/list: **Xem danh sách tất cả các thư mục (album) đang được chia sẻ.
* **POST /api/v1/tunnel/create: **Tạo một link chia sẻ tunnel mới cho thư mục.
* **POST /api/v1/tunnel/refresh: **Làm mới (tạo lại) link tunnel cho một thư mục.
* **DELETE /api/v1/tunnel/delete: **Xóa link chia sẻ tunnel.


**2 . Quản lý File và Hệ thống**

* **POST /api/v1/start-service: **Kích hoạt khởi động lại dịch vụ Cloudflare chính.
* **POST /api/v1/files: **Liệt kê danh sách file/thư mục bên trong một album (bao gồm ngày sửa đổi, kích thước).
* **GET /api/v1/status: **Kiểm tra trạng thái Server, số lượng album đang share, danh sách whitelist.


**3. Quản lý Whitelist (Truy cập công khai)**

* **GET /api/v1/whitelist: **Xem danh sách các thư mục đang được cho phép truy cập file không cần Token.
* **POST /api/v1/whitelist/add: **Thêm một thư mục (theo ID) vào danh sách Whitelist.
* **DELETE /api/v1/whitelist/delete: **Gỡ bỏ một thư mục khỏi danh sách Whitelist.
* **DELETE /api/v1/whitelist/clear: **Xóa sạch toàn bộ danh sách Whitelist.
