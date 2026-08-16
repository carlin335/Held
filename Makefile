.PHONY: project open

project:
	xcodegen generate

open: project
	open CardSense.xcodeproj
