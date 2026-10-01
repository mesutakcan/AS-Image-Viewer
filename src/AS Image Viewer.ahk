/*
======================
AS Image Viewer
v1.9
01/10/2026
======================
AS Image Viewer is a minimalist image viewer application that uses GDI+ for rendering.
It supports multiple image formats and allows easy navigation and management through a simple GUI interface.
======================
Mesut Akcan
makcan@gmail.com
mesutakcan.blogspot.com
github.com/mesutakcan
youtube.com/mesutakcan
=======================
*/

;@Ahk2Exe-SetMainIcon app_icon.ico
;@Ahk2Exe-ExeName AS Image Viewer.exe
;@Ahk2Exe-SetName AS Image Viewer
;@Ahk2Exe-SetDescription A simple and fast image viewer
;@Ahk2Exe-SetFileVersion 1.9
;@Ahk2Exe-SetCompanyName akcanSoft
;@Ahk2Exe-SetCopyright ©2026 Mesut Akcan

#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon

#Include "gdip.ahk"
#Include "langSupport.ahk"

A_ScriptName := "AS Image Viewer v1.9"

appState := {
	settingsFile: A_ScriptDir "\settings.ini",
	savedLangCode: "",
	extensions: "*.jpg; *.jpeg; *.png; *.gif; *.bmp; *.tif; *.ico; *.webp; *.wmf",
	supportedExtensions: Map("jpg", true, "jpeg", true, "png", true, "gif", true, "bmp", true, "tif", true, "ico", true, "webp", true, "wmf", true),
	dropFile: "",
	DblClickTime: DllCall("GetDoubleClickTime", "UInt"),
	imageFiles: [],
	imgFile: "",
	currentFolder: "",
	lastIndex: 0,
	imgNo: 0,
	isClipboardImage: false,
	centerImage: true,
	windowX: 0,
	windowY: 0,
	windowPositionLoaded: false,
	windowPositionDirty: false,
	settingsAtLoad: Map(),
	titleBtnWidth: 32,
	titleBtnHeight: 30,
	mouseTracking: Map(),
	hMemDC: 0,
	hMemBitmap: 0,
	hOldBitmap: 0,
	cachedW: 0,
	cachedH: 0,
	bitmap: 0,
	originalWidth: 0,
	originalHeight: 0,
	imgWidth: 0,
	imgHeight: 0,
	zoomFactor: 1,
	zoomSteps: [1, 2, 5, 10, 15, 20, 30, 40, 50, 60, 80, 100, 125, 150, 175, 200, 300, 500, 700, 1000, 2000, 3000, 5000],
	maxDisplayPixels: 25000000,
	minDisplaySize: 100,
	pToken: 0
}
ui := {
	gui: { Hwnd: 0 },
	minButton: 0,
	closeButton: 0,
	rcMenu: 0,
	langMenu: 0,
	langCodeByName: Map(),
	mnuTxt: {}
}
appState.savedLangCode := IniRead(appState.settingsFile, "Settings", "Language", "")
LoadLanguage(appState.savedLangCode)

appState.pToken := Gdip_Startup()
if !appState.pToken {
	MsgBox(lang["File_load_failed"], , "Icon! 4096")
	ExitApp()
}

ui.gui := Gui("+OwnDialogs -Caption -Border +AlwaysOnTop -DPIScale +0x2000000")
ui.gui.OnEvent("Close", GuiClose)
ui.gui.OnEvent("DropFiles", Gui_DropFiles)
ui.gui.SetFont("s10 cWhite", "Segoe MDL2 Assets")
ui.minButton := ui.gui.AddText("w" appState.titleBtnWidth " h" appState.titleBtnHeight " Hidden Center +0x200 Background0078D7", Chr(0xE921))
ui.minButton.OnEvent("Click", MinimizeWindow)
ui.closeButton := ui.gui.AddText("w" appState.titleBtnWidth " h" appState.titleBtnHeight " Hidden Center +0x200 BackgroundC42B1C", Chr(0xE8BB))
ui.closeButton.OnEvent("Click", GuiClose)
OnMessage(0x0200, HandleCloseButtonMouseMove)
OnMessage(0x02A3, HandleCloseButtonMouseLeave)
OnMessage(0x0014, EraseBkgnd)
OnMessage(0x000F, PaintImage)

CreateMenu()
LoadSettings()
ApplyMenuCheckStates()
OpenFile()

#HotIf WinActive(ui.gui.Hwnd)
Home:: LoadImageByMode("first")
Browser_Back::
Left:: LoadImageByMode("prev")
Browser_Forward::
Right:: LoadImageByMode("next")
End:: LoadImageByMode("last")
NumpadAdd:: ZoomImage(1)
NumpadSub:: ZoomImage(-1)
Numpad0:: ZoomImage(0)
Numpad1:: ZoomImage(2)
Delete:: DeleteCurrentImage()

F1:: FileInfo()
F2:: FileProperties()
F3:: ShowFileInFolder()
F5:: ShowImage()
^o:: OpenFile()
^c:: CopyImageToClipboard()
^v:: PasteImageFromClipboard()
Esc:: ToolTip()

#HotIf mouseIsOver(ui.gui.Hwnd)
Down::
RButton:: ui.rcMenu.Show()
WheelUp:: ZoomImage(1)
WheelDown:: ZoomImage(-1)
XButton1:: LoadImageByMode("prev")
XButton2:: LoadImageByMode("next")
~MButton::
~LButton:: HandleMouseClick()
#HotIf

HandleMouseClick() {
	global appState
	if (A_ThisHotkey = A_PriorHotkey && A_TimeSincePriorHotkey < appState.DblClickTime) {
		switch A_ThisHotkey {
			case "~MButton":
				ZoomImage(2)
			case "~LButton":
				ZoomImage(0)
		}
		return
	}
	if (A_ThisHotkey = "~LButton") {
		MoveWindow()
	}
}

CreateMenu() {
	global ui

	imageres := A_WinDir "\system32\imageres.dll"
	shell32 := A_WinDir "\system32\shell32.dll"
	rcMenu := Menu()

	langMenu := Menu()
	langCodeByName := Map()
	languageNames := ""
	for code, name in GetAvailableLanguages() {
		langCodeByName[name] := code
		languageNames .= name "`n"
	}
	for name in StrSplit(Sort(RTrim(languageNames, "`n"), "D`n"), "`n") {
		langMenu.Add(name, LanguageMenuHandler)
	}

	mnuTxt := {
		open: lang["Menu_open"] . "`tCtrl+O",
		exit: lang["Menu_exit"] . "`tAlt+F4",
		first: lang["Menu_first"] . "`tHome",
		prev: lang["Menu_prev"] . "`tLeft",
		next: lang["Menu_next"] . "`tRight",
		last: lang["Menu_last"] . "`tEnd",
		delete: lang["Menu_delete"] . "`tDel",
		zoomin: lang["Menu_zoomin"] . "`tNumpad +",
		zoomout: lang["Menu_zoomout"] . "`tNumpad -",
		fit: lang["Menu_fit"] . "`tNumpad 1",
		osize: lang["Menu_osize"] . "`tNumpad 0",
		refresh: lang["Menu_refresh"] . "`tF5",
		copy: lang["Menu_copy"] . "`tCtrl+C",
		paste: lang["Menu_paste"] . "`tCtrl+V",
		fileinfo: lang["Menu_fileinfo"] . "`tF1",
		fileprop: lang["Menu_fileprop"] . "`tF2",
		fileinfolder: lang["Menu_fileinfolder"] . "`tF3",
		aot: lang["Menu_aot"],
		border: lang["Menu_border"],
		center: lang["Menu_center"],
		shortcuts: lang["Menu_shortcuts"],
		githubRepo: lang["Menu_github_repo"],
		about: lang["Menu_about"]
	}

	menuItems := [{ text: mnuTxt.open, iconFile: imageres, iconNo: 195 }, { text: mnuTxt.exit, iconFile: imageres, iconNo: 94 }, { separator: true }, { text: "Language", submenu: langMenu, iconFile: shell32, iconNo: 14 }, { separator: true }, { text: mnuTxt.first }, { text: mnuTxt.prev }, { text: mnuTxt.next, iconFile: shell32, iconNo: 298 }, { text: mnuTxt.last }, { separator: true }, { text: mnuTxt.delete, iconFile: shell32, iconNo: 63 }, { separator: true }, { text: mnuTxt.zoomin }, { text: mnuTxt.zoomout }, { text: mnuTxt.fit, iconFile: shell32, iconNo: 16 }, { text: mnuTxt.osize }, { separator: true }, { text: mnuTxt.refresh, iconFile: imageres, iconNo: 230 }, { text: mnuTxt.copy, iconFile: shell32, iconNo: 135 }, { text: mnuTxt.paste, iconFile: shell32, iconNo: 261 }, { separator: true }, { text: mnuTxt.fileinfo, iconFile: shell32, iconNo: 222 }, { text: mnuTxt.fileprop, iconFile: shell32, iconNo: 283 }, { text: mnuTxt.fileinfolder, iconFile: shell32, iconNo: 267 }, { separator: true }, { text: mnuTxt.aot }, { text: mnuTxt.border }, { text: mnuTxt.center }, { separator: true }, { text: mnuTxt.shortcuts, iconFile: shell32, iconNo: 30 }, { text: mnuTxt.githubRepo }, { text: mnuTxt.about, iconFile: shell32, iconNo: 155 }
	]

	for item in menuItems {
		if item.HasOwnProp("separator") {
			rcMenu.Add()
			continue
		}
		rcMenu.Add(item.text, item.HasOwnProp("submenu") ? item.submenu : menuHandler)
		if item.HasOwnProp("iconFile")
			rcMenu.SetIcon(item.text, item.iconFile, item.iconNo)
	}

	ui.rcMenu := rcMenu
	ui.langMenu := langMenu
	ui.langCodeByName := langCodeByName
	ui.mnuTxt := mnuTxt
}

LanguageMenuHandler(itemName, itemPos, menuObj) {
	global currentLangCode, ui
	if !ui.langCodeByName.Has(itemName)
		return
	selectedCode := ui.langCodeByName[itemName]
	if (selectedCode = currentLangCode)
		return
	SetLanguage(selectedCode)
}

SetLanguage(code) {
	global appState
	LoadLanguage(code)
	IniWrite(code, appState.settingsFile, "Settings", "Language")
	CreateMenu()
	ApplyMenuCheckStates()
}

ApplyMenuCheckStates() {
	global currentLangCode, appState, ui

	SetMenuCheck(ui.rcMenu, ui.mnuTxt.aot, IsAlwaysOnTop())
	SetMenuCheck(ui.rcMenu, ui.mnuTxt.border, HasBorder())
	SetMenuCheck(ui.rcMenu, ui.mnuTxt.center, appState.centerImage)
	for name, code in ui.langCodeByName
		SetMenuCheck(ui.langMenu, name, code = currentLangCode)
}

SetMenuCheck(menuObj, itemName, checked) {
	if checked
		menuObj.Check(itemName)
	else
		menuObj.Uncheck(itemName)
}

IsAlwaysOnTop() => (WinGetExStyle(ui.gui) & 0x8) != 0

HasBorder() => (WinGetStyle(ui.gui) & 0x800000) != 0

menuHandler(item, *) {
	global ui
	switch item {
		case ui.mnuTxt.open: OpenFile()
		case ui.mnuTxt.exit: GuiClose()
		case ui.mnuTxt.first: LoadImageByMode("first")
		case ui.mnuTxt.prev: LoadImageByMode("prev")
		case ui.mnuTxt.next: LoadImageByMode("next")
		case ui.mnuTxt.last: LoadImageByMode("last")
		case ui.mnuTxt.delete: DeleteCurrentImage()
		case ui.mnuTxt.zoomin: ZoomImage(1)
		case ui.mnuTxt.zoomout: ZoomImage(-1)
		case ui.mnuTxt.fit: ZoomImage(2)
		case ui.mnuTxt.osize: ZoomImage(0)
		case ui.mnuTxt.refresh: ShowImage()
		case ui.mnuTxt.copy: CopyImageToClipboard()
		case ui.mnuTxt.paste: PasteImageFromClipboard()
		case ui.mnuTxt.fileinfo: FileInfo()
		case ui.mnuTxt.fileprop: FileProperties()
		case ui.mnuTxt.fileinfolder: ShowFileInFolder()
		case ui.mnuTxt.aot: toggleAOT()
		case ui.mnuTxt.border: toggleBorder()
		case ui.mnuTxt.center: toggleCenterImage()
		case ui.mnuTxt.shortcuts: Shortcuts()
		case ui.mnuTxt.githubRepo: Run("https://github.com/mesutakcan/AS-Image-Viewer")
		case ui.mnuTxt.about: About()
	}
}

LoadSettings() {
	global appState, ui

	aotSetting := IniRead(appState.settingsFile, "Settings", "AlwaysOnTop", "1")
	if (aotSetting = "0")
		WinSetAlwaysOnTop(0, ui.gui)

	borderSetting := IniRead(appState.settingsFile, "Settings", "WindowBorder", "0")
	if (borderSetting = "1")
		WinSetStyle("+0x800000", ui.gui)
	else
		WinSetStyle("-0x800000", ui.gui)

	appState.centerImage := IniRead(appState.settingsFile, "Settings", "CenterImage", "1") != "0"

	savedWindowX := IniRead(appState.settingsFile, "Settings", "WindowX", "")
	savedWindowY := IniRead(appState.settingsFile, "Settings", "WindowY", "")
	if (RegExMatch(savedWindowX, "^-?\d+$") && RegExMatch(savedWindowY, "^-?\d+$")) {
		appState.windowX := Integer(savedWindowX)
		appState.windowY := Integer(savedWindowY)
		appState.windowPositionLoaded := true
	}

	appState.currentFolder := IniRead(appState.settingsFile, "Settings", "LastFolder", A_MyDocuments)
	if !DirExist(appState.currentFolder)
		appState.currentFolder := A_MyDocuments

	appState.settingsAtLoad := Map(
		"AlwaysOnTop", IsAlwaysOnTop() ? "1" : "0",
		"WindowBorder", HasBorder() ? "1" : "0",
		"CenterImage", appState.centerImage ? "1" : "0",
		"LastFolder", appState.currentFolder
	)
}

SaveSettings() {
	global appState, ui

	try {
		aotSetting := IsAlwaysOnTop() ? "1" : "0"
		borderSetting := HasBorder() ? "1" : "0"
	} catch {
		aotSetting := "1"
		borderSetting := "0"
	}
	current := Map(
		"AlwaysOnTop", aotSetting,
		"WindowBorder", borderSetting,
		"CenterImage", appState.centerImage ? "1" : "0"
	)
	if DirExist(appState.currentFolder)
		current["LastFolder"] := appState.currentFolder

	for key, value in current {
		if (value != appState.settingsAtLoad[key])
			IniWrite(value, appState.settingsFile, "Settings", key)
	}

	if appState.windowPositionDirty {
		try {
			WinGetPos(&x, &y, , , ui.gui)
			IniWrite(x, appState.settingsFile, "Settings", "WindowX")
			IniWrite(y, appState.settingsFile, "Settings", "WindowY")
		}
	}
}

OpenFile() {
	global appState
	iFile := GetImageFilePath()
	if !iFile {
		if !appState.bitmap {
			MsgBox(lang["File_nofile"], , "Icon! 4096")
			ExitApp()
		}
		return
	}

	SplitPath iFile, , , &ext
	if !ext || !appState.supportedExtensions.Has(StrLower(ext)) || !FileExist(iFile) {
		MsgBox(lang["File_invalid_file"] ":`n" iFile, , "Icon! 4096")
		return
	}
	LoadImageFromFile(iFile)
}

GetImageFilePath() {
	static argsUsed := false
	global appState, ui
	if !argsUsed && A_Args.Length > 0 {
		argsUsed := true
		return A_Args[1]
	}
	if appState.dropFile {
		dFile := appState.dropFile
		appState.dropFile := ""
		return dFile
	}
	ui.gui.Opt("+OwnDialogs")

	startFolder := (appState.currentFolder != "" && DirExist(appState.currentFolder)) ? appState.currentFolder : ""
	return FileSelect(, startFolder, lang["File_select_image_file"], "Images (" appState.extensions ")")
}

LoadImageFromFile(lFile) {
	global appState
	SplitPath lFile, , &folder
	files := appState.imageFiles
	index := (folder = appState.currentFolder) ? getArrayValueIndex(lFile, files) : 0
	if !index {
		files := GetImageFilesInFolder(folder)
		index := getArrayValueIndex(lFile, files)
	}

	if !index {
		MsgBox(lang["File_invalid_file"] ":`n" lFile, , "Icon! 4096")
		return false
	}

	return LoadImage(index, files, folder)
}

GetImageFilesInFolder(folder) {
	global appState
	list := ""
	Loop Files, folder "\*.*" {
		if appState.supportedExtensions.Has(StrLower(A_LoopFileExt))
			list .= A_LoopFileFullPath "`n"
	}
	if (list = "")
		return []
	return StrSplit(Sort(RTrim(list, "`n"), "D`n", (a, b, *) => StrCompare(a, b)), "`n")
}

LoadImage(index, imageFiles := "", folder := "") {
	global appState
	if !IsObject(imageFiles)
		imageFiles := appState.imageFiles

	if (index < 1 || index > imageFiles.Length) {
		MsgBox(lang["File_invalid_file"], , "Icon! 4096")
		return false
	}

	candidateFile := imageFiles[index]

	if (candidateFile = appState.imgFile && index = appState.lastIndex && !appState.isClipboardImage)
		return true

	newBitmap := CreateBitmapFromFileMemory(candidateFile)
	if !IsValidBitmap(newBitmap)
		newBitmap := Gdip_CreateBitmapFromFile(candidateFile)
	if !IsValidBitmap(newBitmap) {
		MsgBox(lang["Error_load_failed_msg"] " " candidateFile, , "Icon! 4096")
		if !appState.bitmap
			ExitApp()
		return false
	}

	cloned := CloneBitmap(newBitmap)
	if cloned {
		SafeDisposeBitmap(newBitmap)
		newBitmap := cloned
	}

	ClearRenderCache()
	SafeDisposeBitmap(appState.bitmap)
	appState.bitmap := newBitmap
	appState.imageFiles := imageFiles
	if (folder != "")
		appState.currentFolder := folder
	appState.imgFile := candidateFile
	appState.imgNo := index
	appState.lastIndex := index
	appState.isClipboardImage := false

	ShowLoadedImage()
	return true
}

ShowLoadedImage() {
	global appState
	appState.originalWidth := Gdip_GetImageWidth(appState.bitmap)
	appState.originalHeight := Gdip_GetImageHeight(appState.bitmap)

	if (appState.originalWidth > A_ScreenWidth || appState.originalHeight > A_ScreenHeight) {
		ZoomImage(2)
		return
	}
	appState.imgWidth := appState.originalWidth
	appState.imgHeight := appState.originalHeight
	appState.zoomFactor := 1
	ShowGui()
}

ReadFileToHGlobal(sFile) {
	hFile := DllCall("Kernel32\CreateFileW", "WStr", sFile, "UInt", 0x80000000, "UInt", 3, "Ptr", 0, "UInt", 3, "UInt", 0x80, "Ptr", 0, "Ptr")
	if (hFile = -1 || hFile = 0)
		return 0

	hMem := 0
	if (DllCall("Kernel32\GetFileSizeEx", "Ptr", hFile, "Int64*", &size := 0) && size > 0 && size <= 0xFFFFFFFF) {
		hMem := DllCall("GlobalAlloc", "UInt", 2, "Ptr", size, "Ptr")
		pData := hMem ? DllCall("GlobalLock", "Ptr", hMem, "Ptr") : 0
		ok := false
		if pData {
			ok := DllCall("Kernel32\ReadFile", "Ptr", hFile, "Ptr", pData, "UInt", size, "UInt*", &bytesRead := 0, "Ptr", 0) && bytesRead = size
			DllCall("GlobalUnlock", "Ptr", hMem)
		}
		if !ok {
			if hMem
				DllCall("GlobalFree", "Ptr", hMem)
			hMem := 0
		}
	}
	DllCall("Kernel32\CloseHandle", "Ptr", hFile)
	return hMem
}

CreateBitmapFromFileMemory(sFile) {
	hMem := ReadFileToHGlobal(sFile)
	if !hMem
		return 0

	if DllCall("Ole32.dll\CreateStreamOnHGlobal", "Ptr", hMem, "Int", 1, "Ptr*", &pStream := 0) {
		DllCall("GlobalFree", "Ptr", hMem)
		return 0
	}

	status := DllCall("gdiplus\GdipCreateBitmapFromStreamICM", "UPtr", pStream, "Ptr*", &pBitmap := 0)
	ObjRelease(pStream)

	return (status = 0 && pBitmap) ? pBitmap : 0
}

IsValidBitmap(pBitmap) {
	return pBitmap > 0 && Gdip_GetImageWidth(pBitmap) > 0 && Gdip_GetImageHeight(pBitmap) > 0
}

SafeDisposeBitmap(pBitmap) {
	if (pBitmap > 0)
		try Gdip_DisposeImage(pBitmap)
	return 0
}

CloneBitmap(pSrcBitmap) {
	w := Gdip_GetImageWidth(pSrcBitmap)
	h := Gdip_GetImageHeight(pSrcBitmap)

	pNew := Gdip_CreateBitmap(w, h)
	if !pNew
		return 0

	G := Gdip_GraphicsFromImage(pNew)
	if !G {
		Gdip_DisposeImage(pNew)
		return 0
	}

	Gdip_DrawImage(G, pSrcBitmap, 0, 0, w, h)
	Gdip_DeleteGraphics(G)

	return pNew
}

LoadImageByMode(mode) {
	global appState

	if !appState.imageFiles.Length
		return false

	candidateIndex := appState.imgNo
	if (candidateIndex < 1 || candidateIndex > appState.imageFiles.Length)
		candidateIndex := 1

	switch mode {
		case "first": candidateIndex := 1
		case "last": candidateIndex := appState.imageFiles.Length
		case "next":
			candidateIndex++
			if (candidateIndex > appState.imageFiles.Length)
				candidateIndex := 1
		case "prev":
			candidateIndex--
			if (candidateIndex < 1)
				candidateIndex := appState.imageFiles.Length
	}
	return LoadImage(candidateIndex)
}

ShowImage(*) {
	global ui
	ToolTip()
	UpdateRenderCache(true)
	DllCall("InvalidateRect", "Ptr", ui.gui.Hwnd, "Ptr", 0, "Int", false)
}

EraseBkgnd(*) => 1

PaintImage(wParam, lParam, msg, hwnd) {
	global appState, ui
	if (hwnd != ui.gui.Hwnd)
		return

	paintStruct := Buffer(A_PtrSize = 8 ? 72 : 64, 0)
	hdc := DllCall("BeginPaint", "Ptr", hwnd, "Ptr", paintStruct.Ptr, "Ptr")
	if !hdc
		return 0

	try {
		if appState.hMemDC {
			DllCall("BitBlt", "Ptr", hdc, "Int", 0, "Int", 0, "Int", appState.imgWidth, "Int", appState.imgHeight,
				"Ptr", appState.hMemDC, "Int", 0, "Int", 0, "UInt", 0x00CC0020)
		}
	} finally {
		DllCall("EndPaint", "Ptr", hwnd, "Ptr", paintStruct.Ptr)
	}
	return 0
}

UpdateRenderCache(force := false) {
	global appState
	if !appState.bitmap
		return
	if (!force && appState.hMemDC && appState.cachedW == appState.imgWidth && appState.cachedH == appState.imgHeight)
		return

	ClearRenderCache()

	hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
	appState.hMemDC := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
	appState.hMemBitmap := DllCall("CreateCompatibleBitmap", "Ptr", hdcScreen, "Int", appState.imgWidth, "Int", appState.imgHeight, "Ptr")
	appState.hOldBitmap := DllCall("SelectObject", "Ptr", appState.hMemDC, "Ptr", appState.hMemBitmap, "Ptr")
	DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)

	memGraphics := Gdip_GraphicsFromHDC(appState.hMemDC)
	if memGraphics {
		imgAttr := 0
		try {
			Gdip_SetInterpolationMode(memGraphics, 7)
			DllCall("gdiplus\GdipSetPixelOffsetMode", "UPtr", memGraphics, "Int", 4)
			DllCall("gdiplus\GdipCreateImageAttributes", "UPtr*", &imgAttr)
			DllCall("gdiplus\GdipSetImageAttributesWrapMode", "UPtr", imgAttr, "Int", 3, "UInt", 0, "Int", 0)
			DllCall("gdiplus\GdipDrawImageRectRectI", "UPtr", memGraphics, "UPtr", appState.bitmap
				, "Int", 0, "Int", 0, "Int", appState.imgWidth, "Int", appState.imgHeight
				, "Int", 0, "Int", 0, "Int", appState.originalWidth, "Int", appState.originalHeight
				, "Int", 2, "UPtr", imgAttr, "UPtr", 0, "UPtr", 0)
		} finally {
			if imgAttr
				Gdip_DisposeImageAttributes(imgAttr)
			Gdip_DeleteGraphics(memGraphics)
		}
	}
	appState.cachedW := appState.imgWidth
	appState.cachedH := appState.imgHeight
}

ClearRenderCache() {
	global appState
	if appState.hMemDC {
		if appState.hOldBitmap
			DllCall("SelectObject", "Ptr", appState.hMemDC, "Ptr", appState.hOldBitmap)
		if appState.hMemBitmap
			DllCall("DeleteObject", "Ptr", appState.hMemBitmap)
		DllCall("DeleteDC", "Ptr", appState.hMemDC)
		appState.hMemDC := 0
		appState.hMemBitmap := 0
		appState.hOldBitmap := 0
		appState.cachedW := 0
		appState.cachedH := 0
	}
}

ZoomImage(zoomMode) {
	global appState, ui
	if (appState.originalWidth < 1)
		return

	anchorCX := "", anchorCY := ""
	visible := DllCall("IsWindowVisible", "Ptr", ui.gui.Hwnd)
	if visible {
		WinGetPos(&wx, &wy, &ww, &wh, ui.gui)
		anchorCX := wx + ww / 2
		anchorCY := wy + wh / 2
	}

	minFactor := Min(1, appState.minDisplaySize / Max(appState.originalWidth, appState.originalHeight))
	maxFactor := Max(1, Min(appState.zoomSteps[appState.zoomSteps.Length] / 100, Sqrt(appState.maxDisplayPixels / (appState.originalWidth * appState.originalHeight))))
	switch zoomMode {
		case 0: appState.zoomFactor := 1
		case 1:
			if (appState.zoomFactor >= maxFactor)
				return
			appState.zoomFactor := Min(NextZoomStep(appState.zoomFactor * 100, 1) / 100, maxFactor)
		case -1:
			if (appState.zoomFactor <= minFactor)
				return
			appState.zoomFactor := Max(NextZoomStep(appState.zoomFactor * 100, -1) / 100, minFactor)
		case 2:
			GetWorkArea(&mLeft, &mTop, &mRight, &mBottom)
			availW := mRight - mLeft
			availH := mBottom - mTop
			if visible {
				WinGetClientPos(, , &cw, &ch, ui.gui)
				availW -= Max(0, ww - cw)
				availH -= Max(0, wh - ch)
			}
			appState.zoomFactor := Min(availW / appState.originalWidth, availH / appState.originalHeight, maxFactor)
	}

	appState.imgWidth := Max(1, Round(appState.originalWidth * appState.zoomFactor))
	appState.imgHeight := Max(1, Round(appState.originalHeight * appState.zoomFactor))
	ShowGui(anchorCX, anchorCY)
}

NextZoomStep(percent, direction) {
	global appState
	steps := appState.zoomSteps
	if (direction > 0) {
		for step in steps {
			if (step > percent + 0.01)
				return step
		}
		return steps[steps.Length]
	}
	Loop steps.Length {
		step := steps[steps.Length - A_Index + 1]
		if (step < percent - 0.01)
			return step
	}
	return 0
}

toggleAOT(*) {
	global ui
	WinSetAlwaysOnTop(-1, ui.gui)
	SetMenuCheck(ui.rcMenu, ui.mnuTxt.aot, IsAlwaysOnTop())
}

toggleBorder(*) {
	global appState, ui
	WinSetStyle(HasBorder() ? "-0x800000" : "+0x800000", ui.gui)
	SetMenuCheck(ui.rcMenu, ui.mnuTxt.border, HasBorder())
	DllCall("SetWindowPos", "Ptr", ui.gui.Hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x27)
	if (appState.imgWidth > 0 && appState.imgHeight > 0 && DllCall("IsWindowVisible", "Ptr", ui.gui.Hwnd)) {
		WinGetPos(&x, &y, , , ui.gui)
		ui.gui.Show("w" appState.imgWidth " h" appState.imgHeight " x" x " y" y)
		PositionTitleButtons(appState.imgWidth)
	}
	DllCall("RedrawWindow", "Ptr", ui.gui.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x485)
}

toggleCenterImage(*) {
	global appState, ui
	appState.centerImage := !appState.centerImage
	ui.rcMenu.ToggleCheck(ui.mnuTxt.center)
	if appState.centerImage
		ShowGui()
}

ShowGui(anchorCX := "", anchorCY := "") {
	global appState, ui
	UpdateRenderCache()

	getLong := DllCall.Bind(A_PtrSize = 8 ? "GetWindowLongPtr" : "GetWindowLong", "Ptr", ui.gui.Hwnd)
	rc := Buffer(16, 0)
	NumPut("Int", appState.imgWidth, "Int", appState.imgHeight, rc, 8)
	DllCall("AdjustWindowRectEx", "Ptr", rc, "UInt", getLong("Int", -16, "Ptr"), "Int", false, "UInt", getLong("Int", -20, "Ptr"))
	outerW := NumGet(rc, 8, "Int") - NumGet(rc, 0, "Int")
	outerH := NumGet(rc, 12, "Int") - NumGet(rc, 4, "Int")

	visible := DllCall("IsWindowVisible", "Ptr", ui.gui.Hwnd)
	if appState.centerImage {
		GetWorkArea(&mLeft, &mTop, &mRight, &mBottom)
		x := mLeft + Max(0, Round((mRight - mLeft - outerW) / 2))
		y := mTop + Max(0, Round((mBottom - mTop - outerH) / 2))
	} else if (anchorCX != "" && anchorCY != "") {
		x := Round(anchorCX - outerW / 2)
		y := Round(anchorCY - outerH / 2)
	} else if visible {
		WinGetPos(&x, &y, , , ui.gui)
	} else {
		x := appState.windowPositionLoaded ? appState.windowX : 0
		y := appState.windowPositionLoaded ? appState.windowY : 0
		if !IsWindowPositionOnScreen(x, y) {
			x := 0
			y := 0
		}
	}

	if visible {
		DllCall("SetWindowPos", "Ptr", ui.gui.Hwnd, "Ptr", 0, "Int", x, "Int", y, "Int", outerW, "Int", outerH, "UInt", 0x14)
		DllCall("RedrawWindow", "Ptr", ui.gui.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x501)
	} else {
		ui.gui.Show("w" appState.imgWidth " h" appState.imgHeight " x" x " y" y)
	}
	PositionTitleButtons(appState.imgWidth)
	UpdateTitleButtonsVisibility()
}

IsWindowPositionOnScreen(x, y) {
	try {
		Loop MonitorGetCount() {
			MonitorGet(A_Index, &left, &top, &right, &bottom)
			if (x >= left && x < right && y >= top && y < bottom)
				return true
		}
	} catch {
		return (x >= 0 && x < A_ScreenWidth && y >= 0 && y < A_ScreenHeight)
	}
	return false
}

GetWorkArea(&left, &top, &right, &bottom) {
	left := 0, top := 0, right := A_ScreenWidth, bottom := A_ScreenHeight
	try MonitorGetWorkArea(GetActiveMonitor(), &left, &top, &right, &bottom)
}

GetActiveMonitor() {
	global ui
	if !DllCall("IsWindowVisible", "Ptr", ui.gui.Hwnd)
		return 1
	WinGetPos(&wx, &wy, &ww, &wh, ui.gui)
	centerX := wx + ww / 2
	centerY := wy + wh / 2
	try {
		Loop MonitorGetCount() {
			MonitorGet(A_Index, &left, &top, &right, &bottom)
			if (centerX >= left && centerX < right && centerY >= top && centerY < bottom)
				return A_Index
		}
	}
	return 1
}

getArrayValueIndex(val, files) {
	for index, file in files {
		if (file = val)
			return index
	}
	return 0
}

mouseIsOver(windowIdentifier) {
	MouseGetPos(, , &winHwnd)
	return (winHwnd = windowIdentifier)
}

PositionTitleButtons(guiWidth := "") {
	global appState, ui
	if (guiWidth = "")
		WinGetClientPos(, , &guiWidth, , ui.gui)
	ui.closeButton.Move(Max(0, guiWidth - appState.titleBtnWidth), 0, appState.titleBtnWidth, appState.titleBtnHeight)
	ui.minButton.Move(Max(0, guiWidth - appState.titleBtnWidth * 2), 0, appState.titleBtnWidth, appState.titleBtnHeight)
}

HandleCloseButtonMouseMove(wParam, lParam, msg, hwnd) {
	global ui
	if (hwnd != ui.gui.Hwnd && hwnd != ui.closeButton.Hwnd && hwnd != ui.minButton.Hwnd)
		return

	TrackMouseLeave(hwnd)
	UpdateTitleButtonsVisibility()
}

HandleCloseButtonMouseLeave(wParam, lParam, msg, hwnd) {
	global appState, ui
	if appState.mouseTracking.Has(hwnd)
		appState.mouseTracking.Delete(hwnd)
	if (hwnd = ui.gui.Hwnd || hwnd = ui.closeButton.Hwnd || hwnd = ui.minButton.Hwnd)
		UpdateTitleButtonsVisibility()
}

TrackMouseLeave(hwnd) {
	global appState
	if appState.mouseTracking.Has(hwnd)
		return

	tracking := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
	NumPut("UInt", tracking.Size, tracking)
	NumPut("UInt", 0x2, tracking, 4)
	NumPut("Ptr", hwnd, tracking, 8)
	if DllCall("TrackMouseEvent", "Ptr", tracking.Ptr)
		appState.mouseTracking[hwnd] := true
}

UpdateTitleButtonsVisibility() {
	global appState, ui
	if !DllCall("IsWindowVisible", "Ptr", ui.gui.Hwnd, "Int") {
		ui.minButton.Visible := false
		ui.closeButton.Visible := false
		return
	}

	CoordMode("Mouse", "Screen")
	MouseGetPos(&mouseX, &mouseY)
	WinGetClientPos(&windowX, &windowY, &windowWidth, &windowHeight, ui.gui)
	nearCorner := (mouseX >= windowX + windowWidth - appState.titleBtnWidth * 2 - 24
		&& mouseX <= windowX + windowWidth
		&& mouseY >= windowY
		&& mouseY <= windowY + 48)
	if (nearCorner = ui.closeButton.Visible)
		return

	if nearCorner {
		ui.minButton.Visible := true
		ui.closeButton.Visible := true
		ui.minButton.Redraw()
		ui.closeButton.Redraw()
		return
	}

	ui.minButton.Visible := false
	ui.closeButton.Visible := false
	buttonX := Max(0, windowWidth - appState.titleBtnWidth * 2)
	buttonRect := Buffer(16, 0)
	NumPut("Int", buttonX, "Int", 0, "Int", buttonX + appState.titleBtnWidth * 2, "Int", appState.titleBtnHeight, buttonRect)
	DllCall("InvalidateRect", "Ptr", ui.gui.Hwnd, "Ptr", buttonRect.Ptr, "Int", false)
}

MinimizeWindow(*) {
	global ui
	ui.minButton.Visible := false
	ui.closeButton.Visible := false
	ui.gui.Minimize()
}

GuiClose(*) {
	global appState
	SaveSettings()
	ClearRenderCache()
	appState.bitmap := SafeDisposeBitmap(appState.bitmap)
	Gdip_Shutdown(appState.pToken)
	ExitApp()
}

ShowFileInFolder() {
	global appState

	if appState.isClipboardImage {
		MsgBox(lang["File_clipboard_image"], , "Icon! 4096")
		return
	}

	Run('explorer.exe /select,"' appState.imgFile '"')
	WinWait("ahk_class CabinetWClass")
	WinActivate("ahk_class CabinetWClass")
	WinSetAlwaysOnTop(, "A")
}

DeleteCurrentImage() {
	global appState, ui

	if appState.isClipboardImage {
		MsgBox(lang["File_clipboard_image"], , "Icon! 4096")
		return
	}

	result := MsgBox(lang["File_delete_confirm"] "`n`n" appState.imgFile,
		lang["File_delete_title"], "YesNo Icon! 4096")

	if (result != "Yes")
		return

	fileToDelete := appState.imgFile
	ui.minButton.Visible := false
	ui.closeButton.Visible := false
	ui.gui.Hide()
	ClearRenderCache()
	appState.bitmap := SafeDisposeBitmap(appState.bitmap)
	appState.lastIndex := 0
	Sleep(100)

	try {
		FileRecycle(fileToDelete)

		appState.imageFiles.RemoveAt(appState.imgNo)

		if (appState.imageFiles.Length > 0) {
			appState.imgNo := Min(appState.imgNo, appState.imageFiles.Length)
			LoadImage(appState.imgNo)
		} else {
			GuiClose()
		}
	} catch as err {
		errorMsg := lang["File_delete_error_msg"] "`n" fileToDelete "`n`n"
		errorMsg .= lang["File_delete_error_reasons"] "`n"
		errorMsg .= lang["File_delete_error_in_use"] "`n"
		errorMsg .= lang["File_delete_error_readonly"] "`n"
		errorMsg .= lang["File_delete_error_no_permission"] "`n`n"
		errorMsg .= lang["File_delete_error_label"] " " err.Message

		MsgBox(errorMsg, lang["File_delete_error_title"], "Icon! 16")

		LoadImage(appState.imgNo)
	}
}

FileInfo() {
	global appState, ui

	if appState.isClipboardImage {
		m := lang["FileInfo_source"] ": " lang["FileInfo_clipboard"] "`n"
		m .= lang["FileInfo_orig_size"] ": " appState.originalWidth "x" appState.originalHeight "`n"
		m .= lang["FileInfo_disp_size"] ": " appState.imgWidth "x" appState.imgHeight
	}
	else {
		SplitPath(appState.imgFile, &file, &dir)
		mfd := FileDT("M")
		cfd := FileDT("C")
		afd := FileDT("A")
		try {
			fsize := FileGetSize(appState.imgFile)
			fs := FormatByteSize(fsize) " (" RegExReplace(fsize, "(\d)(?=(\d{3})+(?!\d))", "$1.") " bytes)"
		} catch {
			fs := "N/A"
		}
		m := lang["FileInfo_folder"] ": " dir "`n"
		m .= lang["FileInfo_file"] ": " file "`n"
		m .= lang["FileInfo_mod_time"] ": " mfd "`n"
		m .= lang["FileInfo_create_time"] ": " cfd "`n"
		m .= lang["FileInfo_access_time"] ": " afd "`n"
		m .= lang["FileInfo_orig_size"] ": " appState.originalWidth "x" appState.originalHeight "`n"
		m .= lang["FileInfo_disp_size"] ": " appState.imgWidth "x" appState.imgHeight "`n"
		m .= lang["FileInfo_file_size"] ": " fs
	}

	zoomPercent := appState.zoomFactor * 100
	m .= "`n" lang["FileInfo_zoom"] ": " Round(zoomPercent, zoomPercent < 10 ? 1 : 0) "%"

	CoordMode("ToolTip", "Screen")
	WinGetPos(&x, &y, , , ui.gui)
	tX := Max(0, x)
	tY := Max(0, y)
	ToolTip(m, tX + 5, tY + 5)
}

FileDT(opt) {
	global appState
	try {
		return FormatTime(FileGetTime(appState.imgFile, opt), "d MMMM yyyy ddd HH:mm:ss")
	} catch {
		return "N/A"
	}
}

FileProperties() {
	global appState

	if appState.isClipboardImage {
		MsgBox(lang["File_clipboard_image"], , "Icon! 4096")
		return
	}

	Run('Properties "' appState.imgFile '"')
	WinWait("ahk_class #32770")
	WinSetAlwaysOnTop(, "A")
}

FormatByteSize(int, flags := 0x2) {
	size := VarSetStrCapacity(&buf, 0x0104)
	DllCall("shlwapi\StrFormatByteSizeEx", "int64", int, "int", flags, "str", buf, "uint", size)
	return buf
}

MoveWindow() {
	global appState
	CoordMode("Mouse")
	MouseGetPos &msX, &msY, &win
	WinGetPos(&startX, &startY, , , win)
	if !WinGetMinMax(win)
		SetTimer(WatchMouse, 10)

	WatchMouse() {
		global appState
		if !GetKeyState("LButton", "P") {
			SetTimer(, 0)
			WinGetPos(&endX, &endY, , , win)
			if (endX != startX || endY != startY)
				appState.windowPositionDirty := true
			ToolTip()
			return
		}
		CoordMode("Mouse")
		MouseGetPos(&mX, &mY)
		if (mX = msX && mY = msY)
			return
		WinGetPos(&wX, &wY, , , win)
		SetWinDelay(-1)
		WinMove(wX + mX - msX, wY + mY - msY, , , win)
		msX := mX
		msY := mY
		DllCall("UpdateWindow", "Ptr", win)
	}
}

Gui_DropFiles(GuiObj, GuiCtrlObj, FileArray, X, Y) {
	global appState
	appState.dropFile := FileArray[1]
	OpenFile()
}

PasteImageFromClipboard() {
	global appState

	pBitmap := Gdip_CreateBitmapFromClipboard()

	if !IsValidBitmap(pBitmap) {
		MsgBox(lang["File_no_clipboard_image"], , "Icon! 4096")
		return
	}

	ClearRenderCache()
	SafeDisposeBitmap(appState.bitmap)
	appState.bitmap := pBitmap
	appState.isClipboardImage := true
	appState.imgFile := lang["FileInfo_clipboard"]
	appState.lastIndex := 0

	ShowLoadedImage()
}

Shortcuts(*) {
	kbShortcuts := [
		lang["Shortcuts_keyboard"],
		"-------------------",
		lang["Shortcuts_kb_down"],
		lang["Shortcuts_kb_home"],
		lang["Shortcuts_kb_back"],
		lang["Shortcuts_kb_left"],
		lang["Shortcuts_kb_forward"],
		lang["Shortcuts_kb_right"],
		lang["Shortcuts_kb_end"],
		lang["Shortcuts_kb_delete"],
		lang["Shortcuts_kb_plus"],
		lang["Shortcuts_kb_minus"],
		lang["Shortcuts_kb_zero"],
		lang["Shortcuts_kb_one"],
		lang["Shortcuts_kb_f1"],
		lang["Shortcuts_kb_f2"],
		lang["Shortcuts_kb_f3"],
		lang["Shortcuts_kb_f5"],
		lang["Shortcuts_kb_ctrl_o"],
		lang["Shortcuts_kb_ctrl_c"],
		lang["Shortcuts_kb_ctrl_v"],
		lang["Shortcuts_kb_esc"],
		lang["Shortcuts_kb_alt_f4"]
	]

	mouseShortcuts := [
		lang["Shortcuts_mouse"],
		"------",
		lang["Shortcuts_mouse_right"],
		lang["Shortcuts_mouse_wheel_up"],
		lang["Shortcuts_mouse_wheel_down"],
		lang["Shortcuts_mouse_4"],
		lang["Shortcuts_mouse_5"],
		lang["Shortcuts_mouse_left_dbl"],
		lang["Shortcuts_mouse_middle_dbl"]
	]

	txt := ""
	for shortcut in kbShortcuts
		txt .= shortcut "`n"
	txt .= "`n"
	for shortcut in mouseShortcuts
		txt .= shortcut "`n"

	MsgBox(txt, lang["Shortcuts_title"], "Owner" ui.gui.Hwnd)
}

CopyImageToClipboard() {
	global appState, ui
	if !appState.bitmap {
		MsgBox(lang["File_nofile"], , "Icon! 4096")
		return
	}
	if !Gdip_SetBitmapToClipboard(appState.bitmap, ui.gui.Hwnd)
		MsgBox(lang["File_copy_failed"], , "Icon! 4096")
}

About(*) {
	txt := A_ScriptName "`n"
	txt .= "©2026`n"
	txt .= "Mesut Akcan`n"
	txt .= "makcan@gmail.com`n"
	txt .= "`n"
	txt .= "mesutakcan.blogspot.com`n"
	txt .= "github.com/mesutakcan`n"
	txt .= "youtube.com/mesutakcan"
	MsgBox(txt, lang["About_about"], "Owner" ui.gui.Hwnd)
}
