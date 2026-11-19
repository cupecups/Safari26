export THEOS_PACKAGE_SCHEME = roothide
TARGET := iphone:clang:latest:16.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = MobileSafari

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Safari26
Safari26_FILES = Tweak.x
Safari26_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
