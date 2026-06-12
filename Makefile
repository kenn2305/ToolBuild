TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = OverlayIOSTOOL

OverlayIOSTOOL_FILES = Tweak.x
OverlayIOSTOOL_CFLAGS = -fobjc-arc
OverlayIOSTOOL_FRAMEWORKS = UIKit PhotosUI Photos

include $(THEOS_MAKE_PATH)/tweak.mk
