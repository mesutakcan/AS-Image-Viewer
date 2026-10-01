; Trimmed version of https://github.com/buliasz/AHKv2-Gdip

#Requires AutoHotkey v2.0

Gdip_Startup()
{
	if (!DllCall("LoadLibrary", "str", "gdiplus", "UPtr")) {
		throw Error("Could not load GDI+ library")
	}

	si := Buffer(A_PtrSize = 4 ? 20 : 32, 0)
	NumPut("uint", 0x2, si)
	NumPut("uint", 0x4, si, A_PtrSize = 4 ? 16 : 24)
	DllCall("gdiplus\GdiplusStartup", "UPtr*", &pToken := 0, "Ptr", si, "UPtr", 0)
	if (!pToken) {
		throw Error("Gdiplus failed to start. Please ensure you have gdiplus on your system")
	}

	return pToken
}

Gdip_Shutdown(pToken)
{
	DllCall("gdiplus\GdiplusShutdown", "UPtr", pToken)
	hModule := DllCall("GetModuleHandle", "str", "gdiplus", "UPtr")
	if (!hModule) {
		throw Error("GDI+ library was unloaded before shutdown")
	}
	if (!DllCall("FreeLibrary", "UPtr", hModule)) {
		throw Error("Could not free GDI+ library")
	}

	return 0
}

Gdip_CreateBitmapFromFile(sFile)
{
	DllCall("gdiplus\GdipCreateBitmapFromFile", "UPtr", StrPtr(sFile), "UPtr*", &pBitmap := 0)
	return pBitmap
}

Gdip_GetImageWidth(pBitmap)
{
	DllCall("gdiplus\GdipGetImageWidth", "UPtr", pBitmap, "uint*", &Width := 0)
	return Width
}

Gdip_GetImageHeight(pBitmap)
{
	DllCall("gdiplus\GdipGetImageHeight", "UPtr", pBitmap, "uint*", &Height := 0)
	return Height
}

Gdip_CreateBitmap(Width, Height, Format := 0x26200A)
{
	DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", Width, "Int", Height, "Int", 0, "Int", Format, "UPtr", 0, "UPtr*", &pBitmap := 0)
	return pBitmap
}

Gdip_GraphicsFromImage(pBitmap)
{
	DllCall("gdiplus\GdipGetImageGraphicsContext", "UPtr", pBitmap, "UPtr*", &pGraphics := 0)
	return pGraphics
}

Gdip_GraphicsFromHDC(hdc)
{
	DllCall("gdiplus\GdipCreateFromHDC", "UPtr", hdc, "UPtr*", &pGraphics := 0)
	return pGraphics
}

Gdip_DrawImage(pGraphics, pBitmap, dx := "", dy := "", dw := "", dh := "", sx := "", sy := "", sw := "", sh := "", Matrix := 1)
{
	if !IsNumber(Matrix)
		ImageAttr := Gdip_SetImageAttributesColorMatrix(Matrix)
	else if (Matrix != 1)
		ImageAttr := Gdip_SetImageAttributesColorMatrix("1|0|0|0|0|0|1|0|0|0|0|0|1|0|0|0|0|0|" Matrix "|0|0|0|0|0|1")
	else
		ImageAttr := 0

	if (sx = "" && sy = "" && sw = "" && sh = "")
	{
		if (dx = "" && dy = "" && dw = "" && dh = "")
		{
			sx := dx := 0, sy := dy := 0
			sw := dw := Gdip_GetImageWidth(pBitmap)
			sh := dh := Gdip_GetImageHeight(pBitmap)
		}
		else
		{
			sx := sy := 0
			sw := Gdip_GetImageWidth(pBitmap)
			sh := Gdip_GetImageHeight(pBitmap)
		}
	}

	_E := DllCall("gdiplus\GdipDrawImageRectRect"
		, "UPtr", pGraphics
		, "UPtr", pBitmap
		, "Float", dx
		, "Float", dy
		, "Float", dw
		, "Float", dh
		, "Float", sx
		, "Float", sy
		, "Float", sw
		, "Float", sh
		, "Int", 2
		, "UPtr", ImageAttr
		, "UPtr", 0
		, "UPtr", 0)
	if ImageAttr
		Gdip_DisposeImageAttributes(ImageAttr)
	return _E
}

Gdip_SetImageAttributesColorMatrix(Matrix)
{
	ColourMatrix := Buffer(100, 0)
	Matrix := RegExReplace(RegExReplace(Matrix, "^[^\d-\.]+([\d\.])", "$1", , 1), "[^\d-\.]+", "|")
	Matrix := StrSplit(Matrix, "|")

	loop 25 {
		M := (Matrix[A_Index] != "") ? Matrix[A_Index] : Mod(A_Index - 1, 6) ? 0 : 1
		NumPut("Float", M, ColourMatrix, (A_Index - 1) * 4)
	}

	DllCall("gdiplus\GdipCreateImageAttributes", "UPtr*", &ImageAttr := 0)
	DllCall("gdiplus\GdipSetImageAttributesColorMatrix", "UPtr", ImageAttr, "Int", 1, "Int", 1, "UPtr", ColourMatrix.Ptr, "UPtr", 0, "Int", 0)

	return ImageAttr
}

Gdip_SetInterpolationMode(pGraphics, InterpolationMode)
{
	return DllCall("gdiplus\GdipSetInterpolationMode", "UPtr", pGraphics, "Int", InterpolationMode)
}

Gdip_DisposeImage(pBitmap)
{
	return DllCall("gdiplus\GdipDisposeImage", "UPtr", pBitmap)
}

Gdip_DeleteGraphics(pGraphics)
{
	return DllCall("gdiplus\GdipDeleteGraphics", "UPtr", pGraphics)
}

Gdip_DisposeImageAttributes(ImageAttr)
{
	return DllCall("gdiplus\GdipDisposeImageAttributes", "UPtr", ImageAttr)
}

Gdip_CreateBitmapFromHBITMAP(hBitmap, Palette := 0)
{
	DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "UPtr", hBitmap, "UPtr", Palette, "UPtr*", &pBitmap := 0)
	return pBitmap
}

Gdip_CreateHBITMAPFromBitmap(pBitmap, Background := 0xffffffff)
{
	DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "UPtr", pBitmap, "UPtr*", &hbm := 0, "Int", Background)
	return hbm
}

Gdip_CreateBitmapFromClipboard()
{
	if !DllCall("IsClipboardFormatAvailable", "UInt", 8) {
		return -2
	}

	if !DllCall("OpenClipboard", "UPtr", 0) {
		return -1
	}

	hBitmap := DllCall("GetClipboardData", "UInt", 2, "UPtr")

	if !hBitmap {
		DllCall("CloseClipboard")
		return -3
	}

	pBitmap := Gdip_CreateBitmapFromHBITMAP(hBitmap)
	if !DllCall("CloseClipboard") {
		if pBitmap
			Gdip_DisposeImage(pBitmap)
		return -5
	}

	if !pBitmap {
		return -4
	}

	return pBitmap
}

Gdip_SetBitmapToClipboard(pBitmap, hWnd := A_ScriptHwnd)
{
	off1 := A_PtrSize = 8 ? 52 : 44, off2 := A_PtrSize = 8 ? 32 : 24
	hBitmap := Gdip_CreateHBITMAPFromBitmap(pBitmap)
	if !hBitmap
		return false

	oi := Buffer(A_PtrSize = 8 ? 104 : 84, 0)
	if (DllCall("GetObject", "UPtr", hBitmap, "Int", oi.Size, "UPtr", oi.Ptr, "Int") != oi.Size) {
		DllCall("DeleteObject", "UPtr", hBitmap)
		return false
	}

	imageSize := NumGet(oi, off1, "UInt")
	pBits := NumGet(oi, off2 - A_PtrSize, "UPtr")
	if (!imageSize || !pBits) {
		DllCall("DeleteObject", "UPtr", hBitmap)
		return false
	}

	hDib := DllCall("GlobalAlloc", "UInt", 2, "UPtr", 40 + imageSize, "UPtr")
	if !hDib {
		DllCall("DeleteObject", "UPtr", hBitmap)
		return false
	}

	pDib := DllCall("GlobalLock", "UPtr", hDib, "UPtr")
	if !pDib {
		DllCall("GlobalFree", "UPtr", hDib)
		DllCall("DeleteObject", "UPtr", hBitmap)
		return false
	}

	DllCall("RtlMoveMemory", "UPtr", pDib, "UPtr", oi.Ptr + off2, "UPtr", 40)
	DllCall("RtlMoveMemory", "UPtr", pDib + 40, "UPtr", pBits, "UPtr", imageSize)
	DllCall("GlobalUnlock", "UPtr", hDib)
	DllCall("DeleteObject", "UPtr", hBitmap)

	if !DllCall("OpenClipboard", "UPtr", hWnd) {
		DllCall("GlobalFree", "UPtr", hDib)
		return false
	}
	if !DllCall("EmptyClipboard") {
		DllCall("CloseClipboard")
		DllCall("GlobalFree", "UPtr", hDib)
		return false
	}
	if !DllCall("SetClipboardData", "UInt", 8, "UPtr", hDib) {
		DllCall("CloseClipboard")
		DllCall("GlobalFree", "UPtr", hDib)
		return false
	}

	return !!DllCall("CloseClipboard")
}

DeleteObject(hObject)
{
	return DllCall("DeleteObject", "UPtr", hObject)
}
