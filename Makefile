APP_NAME := ScreenTouch Mapper
BUILD    := build
APP      := $(BUILD)/$(APP_NAME).app
VERSION  := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
SWIFT_RELEASE := swift build -c release --arch arm64 --arch x86_64

.PHONY: test icon app zip clean

test:
	swift test

icon:
	swift Resources/Icon/make-icon.swift

app:
	$(SWIFT_RELEASE)
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	cp Resources/Icon/AppIcon.icns "$(APP)/Contents/Resources/AppIcon.icns"
	cp "$$($(SWIFT_RELEASE) --show-bin-path)/ScreenTouchMapper" "$(APP)/Contents/MacOS/ScreenTouchMapper"
	codesign --force --sign - "$(APP)"

zip: app
	cd "$(BUILD)" && rm -f "ScreenTouchMapper-$(VERSION).zip" && \
		ditto -c -k --keepParent "$(APP_NAME).app" "ScreenTouchMapper-$(VERSION).zip"

clean:
	rm -rf .build "$(BUILD)"
