SHELL := /bin/sh
ARCH := $(shell uname -m)
SWIFTC := xcrun swiftc -O -swift-version 5 -target $(ARCH)-apple-macosx14.0 -module-cache-path build/cache
CORE := $(wildcard Sources/Core/*.swift)
MAC := $(wildcard Sources/Mac/*.swift)
UPSTREAM := build/vendor/whisper.cpp-1.7.5
WHISPER := build/whisper-$(ARCH)/libwhisper.a
SPEECH_FLAGS := -import-objc-header Sources/Speech/WhisperBridge.h -Xcc -I$(UPSTREAM)/include -Xcc -I$(UPSTREAM)/ggml/include
SPEECH_LIBS := $(WHISPER) -lc++ -framework Accelerate
APP := build/Bannerfall.app
BUNDLE := $(APP)/Contents

.PHONY: app run test audio-test
app: $(BUNDLE)/_CodeSignature/CodeResources

build/vendor/.source-ready: Scripts/prepare-voice.sh Scripts/complete-grammar.patch
	sh Scripts/prepare-voice.sh
	touch $@

$(WHISPER): build/vendor/.source-ready Scripts/whisper.mk Sources/Speech/WhisperBridge.h Sources/Speech/RadioGrammar.cpp
	$(MAKE) -j4 -f Scripts/whisper.mk library

$(BUNDLE)/_CodeSignature/CodeResources: $(CORE) $(MAC) Resources/Info.plist Resources/orders.json Resources/ThirdParty.txt $(WHISPER) Makefile
	mkdir -p $(BUNDLE)/MacOS $(BUNDLE)/Resources build/cache
	cp Resources/Info.plist $(BUNDLE)/Info.plist
	cp Resources/orders.json Resources/ThirdParty.txt build/vendor/ggml-base.en-q5_1.bin $(BUNDLE)/Resources/
	$(SWIFTC) -parse-as-library $(SPEECH_FLAGS) $(CORE) $(MAC) $(SPEECH_LIBS) -o $(BUNDLE)/MacOS/Bannerfall
	codesign --force --sign - $(APP)

run: app
	open $(APP)

test: build/core-tests
	./build/core-tests

build/core-tests: $(CORE) Tests/CoreTests.swift
	mkdir -p build/cache
	$(SWIFTC) -parse-as-library $(CORE) Tests/CoreTests.swift -o $@

audio-test: build/audio-test
	./build/audio-test

build/audio-test: $(WHISPER) $(CORE) Sources/Mac/LocalSpeech.swift Tests/AudioTests.swift Makefile
	mkdir -p build/cache
	$(SWIFTC) -parse-as-library $(SPEECH_FLAGS) $(CORE) Sources/Mac/LocalSpeech.swift Tests/AudioTests.swift $(SPEECH_LIBS) -o $@
