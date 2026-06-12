#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <notify.h>

@class ImageWindow;

// ============================================================================
// ImageWindow — Cửa sổ đặc biệt chứa ảnh Overlay
// Cho phép chạm xuyên qua (pass-through) các vùng không nằm trong ảnh
// ============================================================================
@interface ImageWindow : UIWindow
@property (nonatomic, weak) UIImageView *targetImageView;
@end

@implementation ImageWindow

// [Fix Bug #3] Dùng hitTest thay vì pointInside+convertPoint
// hitTest tự xử lý chính xác khi view có CGAffineTransform (scale/rotate)
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.targetImageView && self.targetImageView.superview) {
        // Convert point sang hệ tọa độ của superview của imageView
        CGPoint localPoint = [self.targetImageView.superview convertPoint:point fromView:self];
        // Kiểm tra xem point có nằm trong frame đã transform của imageView không
        if (CGRectContainsPoint(self.targetImageView.frame, localPoint)) {
            return self.targetImageView;
        }
    }
    return nil; // Pass through — trả nil = không xử lý event
}

@end

// ============================================================================
// OverlayWindow — Cửa sổ điều khiển (Menu) và quản lý Overlay
// ============================================================================
@interface OverlayWindow : UIWindow <PHPickerViewControllerDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIButton *floatingButton;
@property (nonatomic, strong) UIView *menuView;
@property (nonatomic, assign) BOOL isMenuExpanded;

// Cấu hình tính năng
@property (nonatomic, assign) BOOL isToggleClickEnabled;
@property (nonatomic, assign) NSInteger hideDelayValue; // ms
@property (nonatomic, assign) NSInteger showDelayValue; // ms

// Các thành phần của ảnh Overlay
@property (nonatomic, strong) ImageWindow *imageWindow;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIImage *selectedImage;
@property (nonatomic, assign) BOOL isImageVisible;
@property (nonatomic, assign) BOOL targetImageVisible;
@property (nonatomic, assign) CGRect originalFrame;
@property (nonatomic, assign) CGPoint originalCenter; // [Fix Bug #1] assign thay vì CGPoint

// UI Controls trong Menu
@property (nonatomic, strong) UISwitch *toggleSwitch;
@property (nonatomic, strong) UILabel *hideDelayLabel;
@property (nonatomic, strong) UISlider *hideDelaySlider;
@property (nonatomic, strong) UILabel *showDelayLabel;
@property (nonatomic, strong) UISlider *showDelaySlider;

- (void)displayImage:(UIImage *)image;
- (void)handleTouchDetectedNotification;
- (void)cleanupTool;
- (void)resetImagePosition;
@end

@implementation OverlayWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Cửa sổ menu điều khiển nằm trên cùng
        self.windowLevel = UIWindowLevelStatusBar + 100.0;
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        
        [self loadSettings];
        [self setupUI];
        
        // Đăng ký nhận sự kiện chạm toàn hệ thống thông qua Darwin Notification
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                       (__bridge const void *)(self),
                                       (CFNotificationCallback)touchCallback,
                                       CFSTR("com.vietanh.overlayiostool.touch_detected"),
                                       NULL,
                                       CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    return self;
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                       (__bridge const void *)(self),
                                       CFSTR("com.vietanh.overlayiostool.touch_detected"),
                                       NULL);
}

// Cử chỉ chạm xuyên qua đối với cửa sổ menu điều khiển
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.floatingButton && CGRectContainsPoint(self.floatingButton.frame, point)) {
        return YES;
    }
    if (self.isMenuExpanded && self.menuView && CGRectContainsPoint(self.menuView.frame, point)) {
        return YES;
    }
    return NO;
}

// [Fix Bug #6] Darwin notification callback — dispatch sang main thread
static void touchCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    OverlayWindow *window = (__bridge OverlayWindow *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [window handleTouchDetectedNotification];
    });
}

// Tải cấu hình đã lưu
- (void)loadSettings {
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Documents/overlayiostool_settings.plist"];
    if (settings) {
        self.isToggleClickEnabled = [settings[@"isToggleClickEnabled"] boolValue];
        self.hideDelayValue = [settings[@"hideDelayValue"] integerValue];
        self.showDelayValue = [settings[@"showDelayValue"] integerValue];
    } else {
        self.isToggleClickEnabled = NO;
        self.hideDelayValue = 300;
        self.showDelayValue = 300;
    }
}

// Lưu cấu hình
- (void)saveSettings {
    NSDictionary *settings = @{
        @"isToggleClickEnabled": @(self.isToggleClickEnabled),
        @"hideDelayValue": @(self.hideDelayValue),
        @"showDelayValue": @(self.showDelayValue)
    };
    [settings writeToFile:@"/var/mobile/Documents/overlayiostool_settings.plist" atomically:YES];
}

- (void)setupUI {
    self.isMenuExpanded = NO;
    self.isImageVisible = NO;
    self.targetImageVisible = NO;
    
    // 1. Tạo nút nổi tròn
    CGFloat btnSize = 60.0;
    self.floatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatingButton.frame = CGRectMake(20, 100, btnSize, btnSize);
    self.floatingButton.backgroundColor = [UIColor colorWithRed:0.12 green:0.56 blue:1.0 alpha:0.9];
    self.floatingButton.layer.cornerRadius = btnSize / 2.0;
    self.floatingButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.floatingButton.layer.shadowOffset = CGSizeMake(0, 4);
    self.floatingButton.layer.shadowOpacity = 0.3;
    self.floatingButton.layer.shadowRadius = 5.0;
    
    [self.floatingButton setTitle:@"⚙️" forState:UIControlStateNormal];
    self.floatingButton.titleLabel.font = [UIFont systemFontOfSize:30];
    
    [self.floatingButton addTarget:self action:@selector(floatingButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanGesture:)];
    [self.floatingButton addGestureRecognizer:pan];
    
    [self addSubview:self.floatingButton];
    
    // 2. Tạo bảng điều khiển Menu
    self.menuView = [[UIView alloc] initWithFrame:CGRectMake(20, 170, 280, 420)];
    self.menuView.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.08 alpha:0.96];
    self.menuView.layer.cornerRadius = 16.0;
    self.menuView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.15].CGColor;
    self.menuView.layer.borderWidth = 1.0;
    self.menuView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.menuView.layer.shadowOffset = CGSizeMake(0, 8);
    self.menuView.layer.shadowOpacity = 0.4;
    self.menuView.layer.shadowRadius = 10.0;
    self.menuView.alpha = 0.0;
    self.menuView.hidden = YES;
    
    // Title
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 16, 248, 24)];
    titleLabel.text = @"iOS Overlay Image Tool";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:18];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.menuView addSubview:titleLabel];
    
    // Button Chọn Ảnh
    UIButton *selectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    selectButton.frame = CGRectMake(16, 54, 248, 44);
    selectButton.backgroundColor = [UIColor colorWithRed:0.12 green:0.56 blue:1.0 alpha:0.9];
    [selectButton setTitle:@"📷 Chọn ảnh từ Thư viện" forState:UIControlStateNormal];
    [selectButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    selectButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    selectButton.layer.cornerRadius = 8.0;
    [selectButton addTarget:self action:@selector(selectImageButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:selectButton];
    
    // Button Khôi phục Vị trí
    UIButton *resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    resetButton.frame = CGRectMake(16, 108, 248, 44);
    resetButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    [resetButton setTitle:@"🔄 Khôi phục ảnh gốc" forState:UIControlStateNormal];
    [resetButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    resetButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    resetButton.layer.cornerRadius = 8.0;
    [resetButton addTarget:self action:@selector(resetImagePosition) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:resetButton];
    
    // Toggle Click Switch Label
    UILabel *toggleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 168, 180, 30)];
    toggleLabel.text = @"Ẩn/Hiện khi chạm màn hình";
    toggleLabel.textColor = [UIColor whiteColor];
    toggleLabel.font = [UIFont systemFontOfSize:14];
    [self.menuView addSubview:toggleLabel];
    
    // Toggle Switch
    self.toggleSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(214, 168, 50, 30)];
    self.toggleSwitch.onTintColor = [UIColor colorWithRed:0.12 green:0.56 blue:1.0 alpha:1.0];
    self.toggleSwitch.on = self.isToggleClickEnabled;
    [self.toggleSwitch addTarget:self action:@selector(toggleSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [self.menuView addSubview:self.toggleSwitch];
    
    // Trễ Ẩn (Hide Delay)
    self.hideDelayLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 214, 248, 20)];
    self.hideDelayLabel.text = [NSString stringWithFormat:@"Trễ ẩn: %ld ms", (long)self.hideDelayValue];
    self.hideDelayLabel.textColor = [UIColor lightGrayColor];
    self.hideDelayLabel.font = [UIFont systemFontOfSize:13];
    [self.menuView addSubview:self.hideDelayLabel];
    
    self.hideDelaySlider = [[UISlider alloc] initWithFrame:CGRectMake(16, 238, 248, 30)];
    self.hideDelaySlider.minimumValue = 0.0;
    self.hideDelaySlider.maximumValue = 2000.0;
    self.hideDelaySlider.value = self.hideDelayValue;
    [self.hideDelaySlider addTarget:self action:@selector(hideDelaySliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.menuView addSubview:self.hideDelaySlider];
    
    // Trễ Hiện (Show Delay)
    self.showDelayLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 278, 248, 20)];
    self.showDelayLabel.text = [NSString stringWithFormat:@"Trễ hiện: %ld ms", (long)self.showDelayValue];
    self.showDelayLabel.textColor = [UIColor lightGrayColor];
    self.showDelayLabel.font = [UIFont systemFontOfSize:13];
    [self.menuView addSubview:self.showDelayLabel];
    
    self.showDelaySlider = [[UISlider alloc] initWithFrame:CGRectMake(16, 302, 248, 30)];
    self.showDelaySlider.minimumValue = 0.0;
    self.showDelaySlider.maximumValue = 2000.0;
    self.showDelaySlider.value = self.showDelayValue;
    [self.showDelaySlider addTarget:self action:@selector(showDelaySliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.menuView addSubview:self.showDelaySlider];
    
    // Button Tắt Hoàn toàn / Giải phóng RAM
    UIButton *cleanupButton = [UIButton buttonWithType:UIButtonTypeSystem];
    cleanupButton.frame = CGRectMake(16, 342, 248, 30);
    [cleanupButton setTitle:@"🔴 Tắt hoàn toàn & Giải phóng RAM" forState:UIControlStateNormal];
    [cleanupButton setTitleColor:[UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0] forState:UIControlStateNormal];
    cleanupButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [cleanupButton addTarget:self action:@selector(cleanupTool) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:cleanupButton];
    
    // Button Đóng Menu
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.frame = CGRectMake(16, 380, 248, 30);
    [closeButton setTitle:@"Đóng Menu" forState:UIControlStateNormal];
    [closeButton setTitleColor:[UIColor lightGrayColor] forState:UIControlStateNormal];
    closeButton.titleLabel.font = [UIFont systemFontOfSize:13];
    [closeButton addTarget:self action:@selector(floatingButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:closeButton];
    
    [self addSubview:self.menuView];
}

// ============================================================================
// Bật/Tắt Menu điều khiển
// ============================================================================
- (void)floatingButtonTapped {
    self.isMenuExpanded = !self.isMenuExpanded;
    
    if (self.isMenuExpanded) {
        self.menuView.hidden = NO;
        CGRect btnFrame = self.floatingButton.frame;
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        
        CGFloat menuX = btnFrame.origin.x;
        CGFloat menuY = btnFrame.origin.y + btnFrame.size.height + 10;
        
        if (menuX + self.menuView.frame.size.width > screenBounds.size.width) {
            menuX = screenBounds.size.width - self.menuView.frame.size.width - 20;
        }
        if (menuX < 20) {
            menuX = 20;
        }
        if (menuY + self.menuView.frame.size.height > screenBounds.size.height) {
            menuY = btnFrame.origin.y - self.menuView.frame.size.height - 10;
        }
        
        self.menuView.frame = CGRectMake(menuX, menuY, self.menuView.frame.size.width, self.menuView.frame.size.height);
        
        [UIView animateWithDuration:0.3 animations:^{
            self.menuView.alpha = 1.0;
            self.floatingButton.transform = CGAffineTransformMakeRotation(M_PI_4);
        }];
    } else {
        [UIView animateWithDuration:0.3 animations:^{
            self.menuView.alpha = 0.0;
            self.floatingButton.transform = CGAffineTransformIdentity;
        } completion:^(BOOL finished) {
            if (finished) {
                self.menuView.hidden = YES;
            }
        }];
    }
}

// ============================================================================
// Di chuyển nút cấu hình
// ============================================================================
- (void)handlePanGesture:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self];
    CGPoint newCenter = CGPointMake(gesture.view.center.x + translation.x, gesture.view.center.y + translation.y);
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGFloat halfWidth = gesture.view.frame.size.width / 2.0;
    CGFloat halfHeight = gesture.view.frame.size.height / 2.0;
    
    CGFloat padding = 10.0;
    newCenter.x = MIN(MAX(newCenter.x, halfWidth + padding), screenBounds.size.width - halfWidth - padding);
    newCenter.y = MIN(MAX(newCenter.y, halfHeight + padding), screenBounds.size.height - halfHeight - padding);
    
    gesture.view.center = newCenter;
    [gesture setTranslation:CGPointZero inView:self];
    
    if (gesture.state == UIGestureRecognizerStateBegan && self.isMenuExpanded) {
        [self floatingButtonTapped];
    }
}

// ============================================================================
// Xử lý thay đổi cấu hình
// ============================================================================
- (void)toggleSwitchChanged:(UISwitch *)sender {
    self.isToggleClickEnabled = sender.isOn;
    [self saveSettings];
    
    if (!self.isToggleClickEnabled) {
        // Hủy bỏ các hiệu ứng trễ và hiển thị lại ảnh ngay lập tức
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(animateToTargetVisibility) object:nil];
        self.targetImageVisible = YES;
        self.isImageVisible = YES;
        if (self.imageWindow) {
            [UIView animateWithDuration:0.2 animations:^{
                self.imageWindow.alpha = 1.0;
            }];
        }
    } else {
        self.targetImageVisible = self.isImageVisible;
    }
}

- (void)hideDelaySliderChanged:(UISlider *)sender {
    self.hideDelayValue = (NSInteger)sender.value;
    self.hideDelayLabel.text = [NSString stringWithFormat:@"Trễ ẩn: %ld ms", (long)self.hideDelayValue];
    [self saveSettings];
}

- (void)showDelaySliderChanged:(UISlider *)sender {
    self.showDelayValue = (NSInteger)sender.value;
    self.showDelayLabel.text = [NSString stringWithFormat:@"Trễ hiện: %ld ms", (long)self.showDelayValue];
    [self saveSettings];
}

// ============================================================================
// Mở cửa sổ chọn ảnh
// ============================================================================
- (void)selectImageButtonTapped {
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
    config.filter = [PHPickerFilter imagesFilter];
    config.selectionLimit = 1;
    
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
    picker.delegate = self;
    
    // Ẩn tạm thời menu khi hiển thị picker
    if (self.isMenuExpanded) {
        [self floatingButtonTapped];
    }
    
    // Tìm rootViewController của OverlayWindow để present picker
    UIViewController *rootVC = self.rootViewController;
    if (rootVC) {
        // Nếu rootVC đang present gì đó, dismiss trước
        if (rootVC.presentedViewController) {
            [rootVC dismissViewControllerAnimated:NO completion:^{
                [rootVC presentViewController:picker animated:YES completion:nil];
            }];
        } else {
            [rootVC presentViewController:picker animated:YES completion:nil];
        }
    }
}

// ============================================================================
// Delegate của PHPickerViewController
// ============================================================================
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    
    if (results.count == 0) {
        return;
    }
    
    PHPickerResult *result = results.firstObject;
    NSItemProvider *provider = result.itemProvider;
    
    if ([provider canLoadObjectOfClass:[UIImage class]]) {
        [provider loadObjectOfClass:[UIImage class] completionHandler:^(id<NSItemProviderWriting>  _Nullable object, NSError * _Nullable error) {
            if (error) {
                return;
            }
            if ([object isKindOfClass:[UIImage class]]) {
                UIImage *image = (UIImage *)object;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self displayImage:image];
                });
            }
        }];
    }
}

// ============================================================================
// Hiển thị ảnh lớp phủ ở độ phân giải gốc và khôi phục về trạng thái căn giữa
// ============================================================================
- (void)displayImage:(UIImage *)image {
    // Giải phóng ảnh cũ hoàn toàn
    if (self.imageView) {
        // Gỡ gesture recognizers để tránh retain cycle
        for (UIGestureRecognizer *gr in self.imageView.gestureRecognizers.copy) {
            [self.imageView removeGestureRecognizer:gr];
        }
        [self.imageView removeFromSuperview];
        self.imageView = nil;
    }
    
    self.selectedImage = image;
    
    // Khởi tạo cửa sổ ảnh nếu chưa có
    if (!self.imageWindow) {
        self.imageWindow = [[ImageWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        self.imageWindow.backgroundColor = [UIColor clearColor];
        
        // Thấp hơn cửa sổ menu của tweak, nhưng cao hơn toàn bộ app khác
        self.imageWindow.windowLevel = UIWindowLevelStatusBar + 50.0;
        
        UIViewController *rootVC = [[UIViewController alloc] init];
        rootVC.view.backgroundColor = [UIColor clearColor];
        // [Fix Bug #4] PHẢI bật userInteractionEnabled để gesture trên imageView hoạt động
        rootVC.view.userInteractionEnabled = YES;
        self.imageWindow.rootViewController = rootVC;
        
        // [Fix Bug #5] KHÔNG gọi makeKeyAndVisible — chỉ hiện window
        // makeKeyAndVisible sẽ cướp key window khỏi app, hỏng keyboard/text input
        self.imageWindow.hidden = NO;
    }
    
    // Tạo UIImageView mới hiển thị ảnh (không bóng đổ, không viền)
    self.imageView = [[UIImageView alloc] initWithImage:image];
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.backgroundColor = [UIColor clearColor];
    self.imageView.userInteractionEnabled = YES;
    
    // Gán tham chiếu yếu trong ImageWindow để kiểm tra chạm xuyên qua
    self.imageWindow.targetImageView = self.imageView;
    
    // Tính toán kích thước ban đầu để nằm vừa vặn trong màn hình và giữ nguyên tỷ lệ
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGFloat imgWidth = image.size.width;
    CGFloat imgHeight = image.size.height;
    CGFloat scale = MIN(screenBounds.size.width / imgWidth, screenBounds.size.height / imgHeight);
    if (scale > 1.0) {
        scale = 1.0; // Không phóng to quá kích thước gốc
    }
    
    CGFloat targetWidth = imgWidth * scale;
    CGFloat targetHeight = imgHeight * scale;
    
    self.imageView.frame = CGRectMake(0, 0, targetWidth, targetHeight);
    self.imageView.center = CGPointMake(screenBounds.size.width / 2.0, screenBounds.size.height / 2.0);
    
    // Lưu lại vị trí và kích thước gốc để phục hồi khi cần
    self.originalFrame = self.imageView.frame;
    self.originalCenter = self.imageView.center;
    
    // Gắn gesture recognizer để di chuyển và phóng to thu nhỏ
    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleImagePan:)];
    panGesture.delegate = self;
    [self.imageView addGestureRecognizer:panGesture];
    
    UIPinchGestureRecognizer *pinchGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handleImagePinch:)];
    pinchGesture.delegate = self;
    [self.imageView addGestureRecognizer:pinchGesture];
    
    // [Fix Bug #8] Add vào rootViewController.view thay vì trực tiếp vào window
    [self.imageWindow.rootViewController.view addSubview:self.imageView];
    
    self.isImageVisible = YES;
    self.targetImageVisible = YES;
    self.imageWindow.alpha = 1.0;
}

// ============================================================================
// Xử lý di chuyển ảnh — không giới hạn vùng (cho phép kéo ra ngoài màn hình)
// ============================================================================
- (void)handleImagePan:(UIPanGestureRecognizer *)sender {
    UIView *view = sender.view;
    if (sender.state == UIGestureRecognizerStateBegan || sender.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [sender translationInView:view.superview];
        view.center = CGPointMake(view.center.x + translation.x, view.center.y + translation.y);
        [sender setTranslation:CGPointZero inView:view.superview];
    }
}

// ============================================================================
// Xử lý phóng to/thu nhỏ ảnh
// ============================================================================
- (void)handleImagePinch:(UIPinchGestureRecognizer *)sender {
    UIView *view = sender.view;
    if (sender.state == UIGestureRecognizerStateBegan || sender.state == UIGestureRecognizerStateChanged) {
        view.transform = CGAffineTransformScale(view.transform, sender.scale, sender.scale);
        sender.scale = 1.0;
    }
}

// Đồng ý cho nhiều cử chỉ chạy đồng thời (vừa zoom vừa kéo)
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

// ============================================================================
// Khôi phục ảnh về vị trí và độ phân giải gốc
// ============================================================================
- (void)resetImagePosition {
    if (self.imageView) {
        [UIView animateWithDuration:0.3 animations:^{
            self.imageView.transform = CGAffineTransformIdentity;
            self.imageView.frame = self.originalFrame;
            self.imageView.center = self.originalCenter;
        }];
    }
}

// ============================================================================
// Xử lý nhận sự kiện chạm màn hình để ẩn/hiện đan xen
// Hàm này được gọi trên main thread nhờ touchCallback dispatch_async
// ============================================================================
- (void)handleTouchDetectedNotification {
    if (!self.isToggleClickEnabled || !self.imageWindow || !self.imageView) {
        return;
    }
    
    // Đảo ngược trạng thái ẩn/hiện mục tiêu
    self.targetImageVisible = !self.targetImageVisible;
    
    // Hủy bỏ các yêu cầu ẩn/hiện trước đó đang xếp hàng chờ
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(animateToTargetVisibility) object:nil];
    
    // Lấy thời gian trễ tương ứng
    NSTimeInterval delay = 0.0;
    if (self.targetImageVisible) {
        delay = self.showDelayValue / 1000.0;
    } else {
        delay = self.hideDelayValue / 1000.0;
    }
    
    // Lên lịch thực hiện đổi trạng thái ẩn/hiện sau khi hết thời gian trễ
    [self performSelector:@selector(animateToTargetVisibility) withObject:nil afterDelay:delay];
}

- (void)animateToTargetVisibility {
    CGFloat targetAlpha = self.targetImageVisible ? 1.0 : 0.0;
    [UIView animateWithDuration:0.15 animations:^{
        self.imageWindow.alpha = targetAlpha;
    } completion:^(BOOL finished) {
        if (finished) {
            self.isImageVisible = self.targetImageVisible;
        }
    }];
}

// ============================================================================
// Tắt hoàn toàn và Giải phóng RAM
// ============================================================================
- (void)cleanupTool {
    // Hủy mọi pending selector (delay timers)
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    
    // Gỡ gesture recognizers
    if (self.imageView) {
        for (UIGestureRecognizer *gr in self.imageView.gestureRecognizers.copy) {
            [self.imageView removeGestureRecognizer:gr];
        }
        [self.imageView removeFromSuperview];
        self.imageView = nil;
    }
    
    // Huỷ cửa sổ ảnh
    if (self.imageWindow) {
        self.imageWindow.targetImageView = nil;
        self.imageWindow.rootViewController = nil;
        self.imageWindow.hidden = YES;
        self.imageWindow = nil;
    }
    
    // Giải phóng ảnh gốc
    self.selectedImage = nil;
    self.isImageVisible = NO;
    self.targetImageVisible = NO;
    
    // Reset toggle switch
    self.isToggleClickEnabled = NO;
    self.toggleSwitch.on = NO;
    [self saveSettings];
}

@end

// ============================================================================
// Hooks hệ thống — Chỉ chạy trong process SpringBoard
// ============================================================================
static OverlayWindow *overlayWindow = nil;

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!overlayWindow) {
            overlayWindow = [[OverlayWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
            
            UIViewController *rootVC = [[UIViewController alloc] init];
            rootVC.view.backgroundColor = [UIColor clearColor];
            overlayWindow.rootViewController = rootVC;
            
            // [Fix Bug #9] KHÔNG gọi makeKeyAndVisible trên OverlayWindow
            // Chỉ hiện window mà không cướp key status khỏi SpringBoard
            overlayWindow.hidden = NO;
        }
    });
}

%end

// ============================================================================
// Hook bắt sự kiện chạm — Chạy trong MỌI process có UIKit
// [Fix Bug #12] Guard: Bỏ qua nếu đang chạy trong SpringBoard process
// vì SpringBoard đã có observer nhận notification riêng
// ============================================================================
%hook UIApplication

- (void)sendEvent:(UIEvent *)event {
    %orig;
    
    // Chỉ gửi notification khi KHÔNG phải SpringBoard
    // Trong SpringBoard, touch trên home screen sẽ do observer tự xử lý
    // Nếu không guard, sẽ bị double-toggle (ẩn rồi hiện ngay)
    static NSString *bundleID = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bundleID = [[NSBundle mainBundle] bundleIdentifier];
    });
    
    if ([bundleID isEqualToString:@"com.apple.springboard"]) {
        return;
    }
    
    NSSet *allTouches = [event allTouches];
    for (UITouch *touch in allTouches) {
        if (touch.phase == UITouchPhaseBegan) {
            UIWindow *window = touch.window;
            if (window) {
                NSString *windowClass = NSStringFromClass([window class]);
                
                // Bỏ qua các sự kiện chạm xảy ra trong giao diện của chính Tool
                if ([windowClass isEqualToString:@"OverlayWindow"] || [windowClass isEqualToString:@"ImageWindow"]) {
                    return;
                }
            }
            
            // Gửi thông báo Darwin cho SpringBoard khi phát hiện chạm ở ngoài tool
            notify_post("com.vietanh.overlayiostool.touch_detected");
            break;
        }
    }
}

%end
