# daml-jsontests
## Hướng dẫn tạo repository và chạy kiểm thử

### 0. Tạo repository và chuẩn bị workspace
1. Trên GitHub, tạo một repository mới tên là `json-tests`.
2. Mở workspace với Codespaces để làm việc.

### 1. Tạo 2 script thiết lập và chạy kiểm thử

Tạo hai file script sau trong thư mục gốc repo:
- `quest3_setup.sh`: Script thiết lập môi trường
- `quest3_run.sh`: Script chạy kiểm thử tự động

Sau khi tạo xong, mở terminal và thực hiện các bước sau:
1. Cấp quyền thực thi cho 2 file:
	```bash
	chmod +x quest3_setup.sh quest3_run.sh
	```
2. Di chuyển 2 file script ra ngoài repo hiện tại (thư mục cha):
	```bash
	mv quest3_setup.sh quest3_run.sh ../
	```
3. Thay đổi thư mục làm việc sang thư mục cha:
	```bash
	cd ..
	```

### 2. Chạy các script
Chạy lần lượt các script:
```bash
./quest3_setup.sh
./quest3_run.sh
```
Các script sẽ tự động thiết lập môi trường và thực hiện kiểm thử.

## Hướng dẫn chạy Quest 3

Để thiết lập và chạy các bài kiểm tra Quest 3, hãy làm theo các bước sau:

### 1. Thiết lập môi trường
Chạy script thiết lập để cài đặt các công cụ cần thiết (Daml SDK, jq, Java...):

```bash
./quest3_setup.sh
```

Script này sẽ tự động cài đặt Daml SDK phiên bản phù hợp, thêm vào PATH, cài đặt jq và các phần mềm cần thiết.

### 2. Chạy kiểm tra tự động
Sau khi thiết lập xong, chạy script sau để khởi động môi trường kiểm thử và thực hiện các bước kiểm tra:

```bash
./quest3_run.sh
```

Script này sẽ:
- Dừng các tiến trình daml cũ
- Build lại project nếu cần
- Khởi động sandbox và JSON API
- Thiết lập các thông số cần thiết để kiểm thử

### Lưu ý
Nên chạy các script này trong môi trường Linux hoặc Codespaces để đảm bảo tương thích.
Nếu gặp lỗi về quyền thực thi, hãy cấp quyền cho file script:
```bash
chmod +x quest3_setup.sh quest3_run.sh
```