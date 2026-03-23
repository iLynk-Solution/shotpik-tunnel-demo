# Local File Server API

## Overview

Local File Server cho phép:

- Tìm folder
- Duyệt file
- Tạo folder export (tạo shortcut file)
- Public file thông qua tunnel
- Kiểm soát public bằng whitelist

---

## Base URL

```
https://tunnel-url
```

- **Private API prefix:** `/api/v1`
- **Content-Type:** `application/json`

---

# Authentication (RSA256)

Áp dụng cho tất cả API: `/api/v1/*`

Server sử dụng **RSA-SHA256 (RSA256)** để verify chữ ký.

## Required Headers

```
X-Signature: <base64_rsa_signature>
X-Algorithm: RSA-SHA256
```

---

## Signature Rule

Client sẽ ký **raw request body (payload)** bằng private key.

### Chuỗi được ký

```
raw_body
```

### Cách ký (Client)

```
signature = RSA_SHA256_SIGN(private_key, raw_body)
```

Sau đó encode base64 và gửi vào header `X-Signature`.

---

## Verify (Server)

Server dùng public key để verify:

```
RSA_SHA256_VERIFY(public_key, raw_body, base64_decode(signature))
```

Nếu verify fail:

```json
{
  "success": false,
  "error": "UNAUTHORIZED"
}
```

---

# API List

---

## 1. Search Folder 

Tìm folder theo tên (recursive).

### Endpoint

```
POST /api/v1/search
```

### Request

```json
{
  "path": "src"
}
```

### Response

```json
{
  "success": true,
  "data": [
    {
      "path": "src/components",
      "type": "folder"
    }
  ]
}
```

---

## 2. List Files

Lấy danh sách file và folder trong một thư mục (không recursive).

### Endpoint

```
POST /api/v1/files
```

### Request

```json
{
  "path": "src"
}
```

### Response

```json
{
  "success": true,
  "data": [
    {
      "name": "index.ts",
      "type": "file",
      "path": "src/index.ts",
      "size": 1200
    },
    {
      "name": "components",
      "type": "folder",
      "path": "src/components"
    }
  ]
}
```

---

## 3. Whitelist Folder

Khai báo các folder được phép public download.

### Endpoint

```
POST /api/v1/whitelist
```

### Request

```json
{
  "paths": [
    "public/uploads",
    "exports"
  ]
}
```

### Behavior

- Server lưu danh sách whitelist
- Chỉ folder trong whitelist mới được download public

### Response

```json
{
  "success": true,
  "whitelisted": [
    "public/uploads",
    "exports"
  ]
}
```

---

## 4. Create Export Folder (Shortcut)

Tạo folder và tạo shortcut (symlink) file vào folder đó. Không copy file thật.

### Endpoint

```
POST /api/v1/create-folder
```

### Request

```json
{
  "path": "exports/session-001",
  "files": [
    "public/uploads/a.pdf",
    "public/uploads/b.png"
  ]
}
```

### Server sẽ:

1. Tạo folder nếu chưa tồn tại
2. Kiểm tra file tồn tại
3. Tạo shortcut (symlink) vào folder

### Response

```json
{
  "success": true,
  "folder": "exports/session-001"
}
```

---

## 5. Public File Download

Public API — không cần signature.

### Endpoint

```
GET /file/{path}
```

Ví dụ:

```
GET /file/exports/session-001/a.pdf
```

### Rule

Server chỉ cho download nếu:

- File nằm trong folder whitelist
- File tồn tại
- Không phải folder

---

## 6. Healthcheck

### Endpoint

```
GET /healthcheck
```

### Response

```json
{
  "status": "ok"
}
```

---

# Error Codes

| HTTP | Meaning                |
|------|------------------------|
| 400  | Invalid request        |
| 401  | Invalid signature      |
| 403  | Access denied          |
| 404  | File or folder not found |
| 500  | Server error           |

---

# Summary

| Method | Endpoint              | Auth          |
|--------|-----------------------|---------------|
| POST   | `/api/v1/search`      | RSA Signature |
| POST   | `/api/v1/files`       | RSA Signature |
| POST   | `/api/v1/whitelist`   | RSA Signature |
| POST   | `/api/v1/create-folder` | RSA Signature |
| GET    | `/file/{path}`        | Public        |
| GET    | `/healthcheck`        | Public        |
