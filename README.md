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

## 4. Hướng dẫn chạy Quest 4 (quest4.sh)

Thêm hướng dẫn ngắn để chạy `quest4.sh` và kiểm tra file `Token.daml`.

1. Cài extension: tìm và cài "DAML" extension trong Visual Studio Code (hoặc Codespaces).

2. Chạy script `quest4.sh` từ thư mục gốc của project (cần quyền thực thi):

```bash
chmod +x quest4.sh || true
./quest4.sh
```

3. Mở file `intro1/daml/Token.daml` trong VS Code (hoặc Codespaces).

4. Trong giao diện VS Code, mở panel Test của DAML hoặc dùng các nút do extension cung cấp trong file `Token.daml`. Click vào `Test_1` và `Test_2` để chạy và xem kết quả kiểm thử.


## 5. Hướng dẫn chạy Quest 5 (PersonData)

1. Mở file `../persondata/PersonData.daml` (nằm trong thư mục chứa các bài kiểm thử của bạn).

2. Chạy `test_person_data` bằng nút ▶ (play) do DAML extension cung cấp trong file hoặc trong panel Test/Script.

3. Sau khi script chạy xong, chuyển sang tab "Script results". Bật tùy chọn "Show archived" để hiển thị các bản archived.

4. Bạn sẽ thấy 2 dòng kết quả:

- Dòng đầu (archived): chứa contact cũ.
- Dòng thứ hai (active): chứa contact mới.

Ghi chú: nếu bạn không thấy nút ▶ hoặc tab "Script results", đảm bảo đã cài và kích hoạt DAML extension và khởi động lại VS Code nếu cần.


## 6. Hướng dẫn chạy Quest 6

Quest 6 yêu cầu chạy `daml sandbox` trong một terminal và script `quest6.sh` trong terminal khác.

1. Mở 2 terminal (hoặc 2 tab terminal) trong môi trường của bạn.

2. Terminal 1: chạy sandbox

```sh
daml sandbox --json-api-port 7575
```

3. Terminal 2: chạy script

```sh
./quest6.sh
```

Lưu ý: khi sandbox đang chạy, script mới có thể upload DAR, allocate parties, issue IOU, thực hiện trade… và in ra kết quả cuối cùng. Nếu bạn chạy `./quest6.sh` khi sandbox chưa khởi động, script sẽ không thể kết nối tới JSON API và sẽ thất bại.

