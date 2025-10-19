# daml-jsontests
## Hướng dẫn tạo repository và chạy kiểm thử

### 0. Tạo repository và chuẩn bị workspace
1. Trên GitHub, tạo một repository mới tên là `json-tests` (nếu bạn muốn một repo riêng để lưu test).
2. Mở workspace với Codespaces hoặc một terminal trên máy Linux để làm việc.

### 1. Lấy các script

1. Di chuyển lên thư mục cha nơi bạn muốn lưu bản clone (lưu ý: dùng `cd ../` nếu bạn đang ở trong một thư mục con):
	```bash
	cd ../
	```
2. Clone repository này (thay URL nếu repo của bạn ở nơi khác):
	```bash
	git clone https://github.com/longdoanz/daml-jsontests.git
	```

### 2. Chạy các script
Chạy lần lượt các script từ thư mục dự án (ví dụ `daml-jsontests` hoặc `json-tests` nếu bạn dùng tên đó khi clone):
```bash
cd daml-jsontests && bash ./quest3_setup.sh && bash ./quest3_run.sh
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