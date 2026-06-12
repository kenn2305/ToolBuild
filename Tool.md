# Hướng dẫn Phát triển & Biên dịch iOS Overlay Tweak (iOS 15+)

Dự án này là một iOS Jailbreak Tweak hoàn chỉnh chạy trên **iOS 15+** được xây dựng bằng **Theos** (Objective-C/Logos). Tweak cho phép người dùng chọn một ảnh từ thư viện, hiển thị lớp phủ (overlay) luôn nổi trên tất cả ứng dụng khác, hỗ trợ zoom/kéo thả mượt mà, chế độ ẩn/hiện đan xen trễ khi chạm màn hình và cơ chế giải phóng RAM hoàn toàn.

---

## 📂 Danh sách các file trong dự án

1. **[Tweak.x](file:///e:/OverlayIOSTOOL/Tweak.x):** Mã nguồn Logos chứa toàn bộ logic ứng dụng:
   - Hook `SpringBoard` để tạo giao diện menu điều khiển.
   - Hook `UIApplication` trong tất cả các ứng dụng để bắt sự kiện chạm màn hình toàn hệ thống.
   - Định nghĩa `ImageWindow` (chạm xuyên qua phần trống) và `OverlayWindow`.
2. **[Makefile](file:///e:/OverlayIOSTOOL/Makefile):** Cấu hình biên dịch Theos (liên kết các framework `UIKit`, `PhotosUI`, và `Photos`).
3. **[control](file:///e:/OverlayIOSTOOL/control):** Thông tin mô tả gói cài đặt `.deb`.
4. **[OverlayIOSTOOL.plist](file:///e:/OverlayIOSTOOL/OverlayIOSTOOL.plist):** Khai báo filter `com.apple.UIKit` để nạp tweak vào mọi ứng dụng nhằm theo dõi sự kiện chạm toàn màn hình.

---

## 🚀 Các tính năng chi tiết & Cơ chế lập trình

### 1. Chọn ảnh bằng `PHPickerViewController` (Không cần cấp quyền)
- Trên iOS 15+, `PHPickerViewController` là bộ chọn ảnh hiện đại chạy ngoài tiến trình (out-of-process).
- Không yêu cầu khai báo quyền truy cập ảnh trong file cấu hình SpringBoard (tránh bị crash hay lỗi bảo mật sandbox).
- Khi chọn ảnh mới: Tweak sẽ tự động giải phóng đối tượng ảnh cũ khỏi bộ nhớ RAM và thiết lập ảnh mới ở độ phân giải gốc của ảnh.

### 2. Lớp phủ ảnh gốc (Không nền, không bóng đổ)
- Lớp phủ sử dụng một đối tượng `UIImageView` đặt trong `ImageWindow` riêng biệt.
- Cửa sổ có mức độ ưu tiên hiển thị (`windowLevel`) rất cao để đè lên các ứng dụng khác, nhưng nằm dưới cửa sổ menu cấu hình.
- Nền và ảnh không có bất kỳ hiệu ứng bóng đổ hay viền nền nào, hiển thị đúng định dạng trong suốt (Alpha channel) của ảnh gốc (ví dụ: ảnh PNG).
- Gắn cử chỉ `UIPanGestureRecognizer` (kéo thả) và `UIPinchGestureRecognizer` (phóng to/thu nhỏ) cùng lúc nhờ cài đặt protocol `shouldRecognizeSimultaneouslyWithGestureRecognizer:`.

### 3. Khôi phục ảnh gốc (Recovery Mechanism)
- Khi lỡ kéo ảnh ra ngoài màn hình hoặc phóng quá nhỏ, người dùng chỉ cần nhấn **"🔄 Khôi phục ảnh gốc"** trong menu điều khiển hoặc chọn lại ảnh, tweak sẽ khôi phục ảnh về kích thước chuẩn và căn giữa màn hình ngay lập tức.

### 4. Chế độ ẩn/hiện tự động đan xen trễ (Delayed Toggle Click)
- Khi bật tính năng này, bất kỳ cú chạm nào bên ngoài vùng ảnh (ở bất kỳ app nào như Safari, Facebook, Game) sẽ làm ảnh tự động ẩn/hiện đan xen.
- **Cơ chế IPC qua Darwin Notification:** Khi người dùng chạm màn hình trong bất kỳ ứng dụng nào, hàm hook `-[UIApplication sendEvent:]` của app đó sẽ phát hiện và phát ra một thông báo hệ thống `com.vietanh.overlayiostool.touch_detected`. SpringBoard nhận thông báo này và xử lý logic ẩn/hiện.
- **Tránh tự động ẩn khi thao tác trên ảnh:** Nếu điểm chạm nằm trong vùng hitbox của ảnh (`ImageWindow` trả về `YES`), tweak sẽ chặn không phát thông báo, giúp người dùng thoải mái zoom/kéo ảnh mà không bị ẩn đi.
- **Thời gian trễ (Delay):** Tích hợp hai thanh trượt điều khiển thời gian trễ cho cả hành động Ẩn và Hiện (từ 0 đến 2000 ms). Tweak sử dụng `performSelector:withObject:afterDelay:` để hẹn giờ thực thi và tự động huỷ lịch cũ khi có thao tác mới nhằm tránh xung đột.

### 5. Tắt hoàn toàn & Giải phóng RAM
- Khi bấm nút **"🔴 Tắt hoàn toàn & Giải phóng RAM"**, tweak sẽ gỡ bỏ cửa sổ ảnh, huỷ các cử chỉ, xoá đối tượng ảnh khỏi bộ nhớ đệm và tắt chế độ trễ chạm để trả lại RAM sạch hoàn toàn cho hệ thống.

---

## ⚙️ Hướng dẫn Biên dịch & Cài đặt

Mở Terminal tại thư mục gốc của dự án (`e:\OverlayIOSTOOL`):

### 1. Biên dịch tweak
```bash
make package
```

### 2. Cài đặt lên điện thoại
Thiết lập địa chỉ IP của iPhone đã jailbreak (cùng mạng Wi-Fi và có cài `OpenSSH`):
```bash
export THEOS_DEVICE_IP=192.168.1.X
make install
```
Nhập mật khẩu SSH (mặc định là `alpine`), thiết bị sẽ tự động respring và tweak sẽ được kích hoạt.
