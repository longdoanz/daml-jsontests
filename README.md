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
### 3. Mở terminal mới, copy câu lệnh để chụp màn hình hoàn thành Quest
```bash
cd /workspaces/json-tests
ALICE_JWT='eyJhbGc...'
```
```bash
curl -s -H "Content-Type: application/json" -H "Authorization: Bearer $ALICE_JWT" -d @query.json -X POST localhost:7575/v1/query | jq
```
Các script sẽ tự động thiết lập môi trường.

### Lưu ý
Nên chạy các script này trong môi trường Linux hoặc Codespaces để đảm bảo tương thích.
Nếu gặp lỗi về quyền thực thi, hãy cấp quyền cho file script:
```bash
chmod +x quest3_setup.sh quest3_run.sh
```