# RSA API Authentication Guide

Hệ thống xác thực API của Agent sử dụng **RSA-SHA256** để đảm bảo tính toàn vẹn và bảo mật của dữ liệu.

## 1. Cơ chế xác thực (Signature Rule)

Tất cả các API nằm dưới đường dẫn `/api/v1/*` đều yêu cầu xác thực qua tiêu đề (Header):

- **Header name**: `X-Signature`
- **Data to sign**: Raw Request Body (JSON string)
- **Algorithm**: RSA-SHA256

### Luồng xử lý:
1. **Client**: Dùng **Private Key** ký vào `raw_body`. Kết quả encode **Base64** và gửi vào header `X-Signature`.
2. **Server (Agent)**: Dùng **Public Key** để verify nội dung body nhận được với chữ ký từ header.

---

## 2. Quản lý Keys (Không lưu vào mã nguồn)

Để tuân thủ quy tắc bảo mật, các Keys không được lưu trực tiếp trong file `.dart`.

### Cách chạy App với Keys tương ứng:
Bạn cần truyền Key qua cờ `--dart-define` khi chạy `flutter run` (Lưu ý: Bỏ qua header `-----BEGIN PUBLIC KEY-----` và các ký tự xuống dòng):

```bash
# Cách lấy chuỗi sạch để copy:
grep -v -- "-----" public_key.pem | tr -d '\n'

# Chạy App:
flutter run -d macos --dart-define=RSA_PUBLIC_KEY="CHUỖI_KEY_CỦA_BẠN"
```

---

## 3. Hướng dẫn Test API bằng Script

Sử dụng file `api_test.sh` trong thư mục gốc để thực hiện các cuộc gọi API có kèm chữ ký tự động.

### Bước 1: Chuẩn bị bộ khóa RSA (Chỉ làm 1 lần)
```bash
# Tạo Private Key
openssl genrsa -out private_key.pem 2048

# Trích xuất Public Key
openssl rsa -in private_key.pem -pubout -out public_key.pem
```

### Bước 2: Chạy Script Test
```bash
./api_test.sh
```

---

## 4. Danh sách các API Endpoint

| Method | Endpoint | Mô tả |
|---|---|---|
| POST | `/api/v1/status` | Kiểm tra trạng thái Agent |
| POST | `/api/v1/create-folder` | Chia sẻ folder mới (tạo Tunnel) |
| POST | `/api/v1/tunnel/list` | Danh sách Tunnel đang chạy |
| POST | `/api/v1/files` | Duyệt danh sách file trong tunnel |
| GET | `/api/v1/whitelist` | Danh sách folder được public |
| POST | `/api/v1/auth/sign` | (Mock) Dùng JWT để Agent ký hộ |

---

## 5. Xử lý lỗi thường gặp

- **Error 401 UNAUTHORIZED**: Chữ ký không đúng hoặc Public Key truyền vào khi chạy App (`--dart-define`) không khớp với Private Key dùng để ký.
- **Error 403**: Lỗi truy cập bị từ chối hoặc body không hợp lệ.
- **Could not open private_key.pem**: Đảm bảo file `private_key.pem` đang nằm cùng thư mục với script.
