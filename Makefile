export THEOS_DEVICE_IP=192.168.1.14
TARGET = iphone:10.1:10.1
ARCHS = armv7 armv7s arm64
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

# export TARGET = iphone:10.1
# export ARCHS = armv7 armv7s arm64

TWEAK_NAME = XenInfo
XenInfo_FILES = Tweak/Tweak.xm Tweak/Internal/XIWidgetManager.m Tweak/System/XISystem.m Tweak/Music/XIMusic.m Tweak/Weather/XIWeather.m Tweak/Weather/XITWCWeather.m Tweak/Weather/XIWAWeather.m Tweak/Battery/XIInfoStats.m Tweak/Events/XIEvents.m Tweak/Reminders/XIReminders.m Tweak/Alarms/XIAlarms.m Tweak/Statusbar/XIStatusBar.m ThirdParty/Reachability/Reachability.m
XenInfo_LDFLAGS += -Wl,-segalign,4000
XenInfo_FRAMEWORKS = UIKit
XenInfo_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
