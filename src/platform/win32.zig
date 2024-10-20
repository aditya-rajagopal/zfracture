pub const PEEK_MESSAGE_REMOVE_TYPE = packed struct(u32) {
    REMOVE: u1 = 0,
    NOYIELD: u1 = 0,
    _2: u1 = 0,
    _3: u1 = 0,
    _4: u1 = 0,
    _5: u1 = 0,
    _6: u1 = 0,
    _7: u1 = 0,
    _8: u1 = 0,
    _9: u1 = 0,
    _10: u1 = 0,
    _11: u1 = 0,
    _12: u1 = 0,
    _13: u1 = 0,
    _14: u1 = 0,
    _15: u1 = 0,
    _16: u1 = 0,
    _17: u1 = 0,
    _18: u1 = 0,
    _19: u1 = 0,
    _20: u1 = 0,
    QS_PAINT: u1 = 0,
    QS_SENDMESSAGE: u1 = 0,
    _23: u1 = 0,
    _24: u1 = 0,
    _25: u1 = 0,
    _26: u1 = 0,
    _27: u1 = 0,
    _28: u1 = 0,
    _29: u1 = 0,
    _30: u1 = 0,
    _31: u1 = 0,
};

pub const SHOW_WINDOW_CMD = packed struct(u32) {
    SHOWNORMAL: u1 = 0,
    SHOWMINIMIZED: u1 = 0,
    SHOWNOACTIVATE: u1 = 0,
    SHOWNA: u1 = 0,
    SMOOTHSCROLL: u1 = 0,
    _5: u1 = 0,
    _6: u1 = 0,
    _7: u1 = 0,
    _8: u1 = 0,
    _9: u1 = 0,
    _10: u1 = 0,
    _11: u1 = 0,
    _12: u1 = 0,
    _13: u1 = 0,
    _14: u1 = 0,
    _15: u1 = 0,
    _16: u1 = 0,
    _17: u1 = 0,
    _18: u1 = 0,
    _19: u1 = 0,
    _20: u1 = 0,
    _21: u1 = 0,
    _22: u1 = 0,
    _23: u1 = 0,
    _24: u1 = 0,
    _25: u1 = 0,
    _26: u1 = 0,
    _27: u1 = 0,
    _28: u1 = 0,
    _29: u1 = 0,
    _30: u1 = 0,
    _31: u1 = 0,
    // NORMAL (bit index 0) conflicts with SHOWNORMAL
    // PARENTCLOSING (bit index 0) conflicts with SHOWNORMAL
    // OTHERZOOM (bit index 1) conflicts with SHOWMINIMIZED
    // OTHERUNZOOM (bit index 2) conflicts with SHOWNOACTIVATE
    // SCROLLCHILDREN (bit index 0) conflicts with SHOWNORMAL
    // INVALIDATE (bit index 1) conflicts with SHOWMINIMIZED
    // ERASE (bit index 2) conflicts with SHOWNOACTIVATE
};

pub const WINDOW_EX_STYLE = packed struct(u32) {
    DLGMODALFRAME: u1 = 0,
    _1: u1 = 0,
    NOPARENTNOTIFY: u1 = 0,
    TOPMOST: u1 = 0,
    ACCEPTFILES: u1 = 0,
    TRANSPARENT: u1 = 0,
    MDICHILD: u1 = 0,
    TOOLWINDOW: u1 = 0,
    WINDOWEDGE: u1 = 0,
    CLIENTEDGE: u1 = 0,
    CONTEXTHELP: u1 = 0,
    _11: u1 = 0,
    RIGHT: u1 = 0,
    RTLREADING: u1 = 0,
    LEFTSCROLLBAR: u1 = 0,
    _15: u1 = 0,
    CONTROLPARENT: u1 = 0,
    STATICEDGE: u1 = 0,
    APPWINDOW: u1 = 0,
    LAYERED: u1 = 0,
    NOINHERITLAYOUT: u1 = 0,
    NOREDIRECTIONBITMAP: u1 = 0,
    LAYOUTRTL: u1 = 0,
    _23: u1 = 0,
    _24: u1 = 0,
    COMPOSITED: u1 = 0,
    _26: u1 = 0,
    NOACTIVATE: u1 = 0,
    _28: u1 = 0,
    _29: u1 = 0,
    _30: u1 = 0,
    _31: u1 = 0,
};

pub const WINDOW_STYLE = packed struct(u32) {
    ACTIVECAPTION: u1 = 0,
    _1: u1 = 0,
    _2: u1 = 0,
    _3: u1 = 0,
    _4: u1 = 0,
    _5: u1 = 0,
    _6: u1 = 0,
    _7: u1 = 0,
    _8: u1 = 0,
    _9: u1 = 0,
    _10: u1 = 0,
    _11: u1 = 0,
    _12: u1 = 0,
    _13: u1 = 0,
    _14: u1 = 0,
    _15: u1 = 0,
    TABSTOP: u1 = 0,
    GROUP: u1 = 0,
    THICKFRAME: u1 = 0,
    SYSMENU: u1 = 0,
    HSCROLL: u1 = 0,
    VSCROLL: u1 = 0,
    DLGFRAME: u1 = 0,
    BORDER: u1 = 0,
    MAXIMIZE: u1 = 0,
    CLIPCHILDREN: u1 = 0,
    CLIPSIBLINGS: u1 = 0,
    DISABLED: u1 = 0,
    VISIBLE: u1 = 0,
    MINIMIZE: u1 = 0,
    CHILD: u1 = 0,
    POPUP: u1 = 0,
    // MINIMIZEBOX (bit index 17) conflicts with GROUP
    // MAXIMIZEBOX (bit index 16) conflicts with TABSTOP
    // ICONIC (bit index 29) conflicts with MINIMIZE
    // SIZEBOX (bit index 18) conflicts with THICKFRAME
    // CHILDWINDOW (bit index 30) conflicts with CHILD
};

pub const MESSAGEBOX_RESULT = enum(i32) {
    OK = 1,
    CANCEL = 2,
    ABORT = 3,
    RETRY = 4,
    IGNORE = 5,
    YES = 6,
    NO = 7,
    CLOSE = 8,
    HELP = 9,
    TRYAGAIN = 10,
    CONTINUE = 11,
    ASYNC = 32001,
    TIMEOUT = 32000,
};

pub const MESSAGEBOX_STYLE = packed struct(u32) {
    OKCANCEL: u1 = 0,
    ABORTRETRYIGNORE: u1 = 0,
    YESNO: u1 = 0,
    _3: u1 = 0,
    ICONHAND: u1 = 0,
    ICONQUESTION: u1 = 0,
    ICONASTERISK: u1 = 0,
    USERICON: u1 = 0,
    DEFBUTTON2: u1 = 0,
    DEFBUTTON3: u1 = 0,
    _10: u1 = 0,
    _11: u1 = 0,
    SYSTEMMODAL: u1 = 0,
    TASKMODAL: u1 = 0,
    HELP: u1 = 0,
    NOFOCUS: u1 = 0,
    SETFOREGROUND: u1 = 0,
    DEFAULT_DESKTOP_ONLY: u1 = 0,
    TOPMOST: u1 = 0,
    RIGHT: u1 = 0,
    RTLREADING: u1 = 0,
    SERVICE_NOTIFICATION: u1 = 0,
    _22: u1 = 0,
    _23: u1 = 0,
    _24: u1 = 0,
    _25: u1 = 0,
    _26: u1 = 0,
    _27: u1 = 0,
    _28: u1 = 0,
    _29: u1 = 0,
    _30: u1 = 0,
    _31: u1 = 0,
    // ICONERROR (bit index 4) conflicts with ICONHAND
    // ICONINFORMATION (bit index 6) conflicts with ICONASTERISK
    // ICONSTOP (bit index 4) conflicts with ICONHAND
    // SERVICE_NOTIFICATION_NT3X (bit index 18) conflicts with TOPMOST
};

pub const WNDCLASS_STYLES = packed struct(u32) {
    VREDRAW: u1 = 0,
    HREDRAW: u1 = 0,
    _2: u1 = 0,
    DBLCLKS: u1 = 0,
    _4: u1 = 0,
    OWNDC: u1 = 0,
    CLASSDC: u1 = 0,
    PARENTDC: u1 = 0,
    _8: u1 = 0,
    NOCLOSE: u1 = 0,
    _10: u1 = 0,
    SAVEBITS: u1 = 0,
    BYTEALIGNCLIENT: u1 = 0,
    BYTEALIGNWINDOW: u1 = 0,
    GLOBALCLASS: u1 = 0,
    _15: u1 = 0,
    IME: u1 = 0,
    DROPSHADOW: u1 = 0,
    _18: u1 = 0,
    _19: u1 = 0,
    _20: u1 = 0,
    _21: u1 = 0,
    _22: u1 = 0,
    _23: u1 = 0,
    _24: u1 = 0,
    _25: u1 = 0,
    _26: u1 = 0,
    _27: u1 = 0,
    _28: u1 = 0,
    _29: u1 = 0,
    _30: u1 = 0,
    _31: u1 = 0,
};

pub const CS_DBLCLKS = WNDCLASS_STYLES{ .DBLCLKS = 1 };

pub const WNDPROC = *const fn (
    param0: windows.HWND,
    param1: u32,
    param2: windows.WPARAM,
    param3: windows.LPARAM,
) callconv(windows.WINAPI) windows.LRESULT;

pub const WNDCLASSA = extern struct {
    style: WNDCLASS_STYLES,
    lpfnWndProc: ?WNDPROC,
    cbClsExtra: i32,
    cbWndExtra: i32,
    hInstance: ?windows.HINSTANCE,
    hIcon: ?windows.HICON,
    hCursor: ?windows.HCURSOR,
    hbrBackground: ?windows.HBRUSH,
    lpszMenuName: ?[*:0]const u8,
    lpszClassName: ?[*:0]const u8,
};

pub const MSG = extern struct {
    hwnd: ?windows.HWND,
    message: u32,
    wParam: windows.WPARAM,
    lParam: windows.LPARAM,
    time: u32,
    pt: windows.POINT,
};

// ----------------------------------------- CONSTANTS ---------------------------------------------/

pub const IDI_APPLICATION = typedConst([*:0]align(1) const u8, @as(u32, 32512));
pub const IDC_ARROW = typedConst([*:0]align(1) const u8, @as(i32, 32512));
pub const MB_ICONEXCLAMATION = MESSAGEBOX_STYLE{
    .ICONHAND = 1,
    .ICONQUESTION = 1,
};

pub const WS_OVERLAPPED: u32 = @bitCast(WINDOW_STYLE{});
pub const WS_SYSMENU: u32 = @bitCast(WINDOW_STYLE{ .SYSMENU = 1 });
pub const WS_CAPTION: u32 = @bitCast(WINDOW_STYLE{
    .DLGFRAME = 1,
    .BORDER = 1,
});
pub const WS_EX_APPWINDOW: u32 = @bitCast(WINDOW_EX_STYLE{ .APPWINDOW = 1 });
pub const WS_MINIMIZEBOX: u32 = @bitCast(WINDOW_STYLE{ .GROUP = 1 });
pub const WS_MAXIMIZEBOX: u32 = @bitCast(WINDOW_STYLE{ .TABSTOP = 1 });
pub const WS_THICKFRAME: u32 = @bitCast(WINDOW_STYLE{ .THICKFRAME = 1 });

pub const SW_SHOW: u32 = @bitCast(SHOW_WINDOW_CMD{
    .SHOWNORMAL = 1,
    .SHOWNOACTIVATE = 1,
});
pub const SW_SHOWNOACTIVATE: u32 = @bitCast(SHOW_WINDOW_CMD{ .SHOWNOACTIVATE = 1 });
pub const PM_REMOVE = PEEK_MESSAGE_REMOVE_TYPE{ .REMOVE = 1 };

pub const WM_NULL = @as(u32, 0);
pub const WM_CREATE = @as(u32, 1);
pub const WM_DESTROY = @as(u32, 2);
pub const WM_MOVE = @as(u32, 3);
pub const WM_SIZE = @as(u32, 5);
pub const WM_ACTIVATE = @as(u32, 6);
pub const WA_INACTIVE = @as(u32, 0);
pub const WA_ACTIVE = @as(u32, 1);
pub const WA_CLICKACTIVE = @as(u32, 2);
pub const WM_SETFOCUS = @as(u32, 7);
pub const WM_KILLFOCUS = @as(u32, 8);
pub const WM_ENABLE = @as(u32, 10);
pub const WM_SETREDRAW = @as(u32, 11);
pub const WM_SETTEXT = @as(u32, 12);
pub const WM_GETTEXT = @as(u32, 13);
pub const WM_GETTEXTLENGTH = @as(u32, 14);
pub const WM_PAINT = @as(u32, 15);
pub const WM_CLOSE = @as(u32, 16);
pub const WM_QUERYENDSESSION = @as(u32, 17);
pub const WM_QUERYOPEN = @as(u32, 19);
pub const WM_ENDSESSION = @as(u32, 22);
pub const WM_QUIT = @as(u32, 18);
pub const WM_ERASEBKGND = @as(u32, 20);
pub const WM_SYSCOLORCHANGE = @as(u32, 21);
pub const WM_SHOWWINDOW = @as(u32, 24);
pub const WM_WININICHANGE = @as(u32, 26);
pub const WM_SETTINGCHANGE = @as(u32, 26);
pub const WM_DEVMODECHANGE = @as(u32, 27);
pub const WM_ACTIVATEAPP = @as(u32, 28);
pub const WM_FONTCHANGE = @as(u32, 29);
pub const WM_TIMECHANGE = @as(u32, 30);
pub const WM_CANCELMODE = @as(u32, 31);
pub const WM_SETCURSOR = @as(u32, 32);
pub const WM_MOUSEACTIVATE = @as(u32, 33);
pub const WM_CHILDACTIVATE = @as(u32, 34);
pub const WM_QUEUESYNC = @as(u32, 35);
pub const WM_GETMINMAXINFO = @as(u32, 36);
pub const WM_PAINTICON = @as(u32, 38);
pub const WM_ICONERASEBKGND = @as(u32, 39);
pub const WM_NEXTDLGCTL = @as(u32, 40);
pub const WM_SPOOLERSTATUS = @as(u32, 42);
pub const WM_DRAWITEM = @as(u32, 43);
pub const WM_MEASUREITEM = @as(u32, 44);
pub const WM_DELETEITEM = @as(u32, 45);
pub const WM_VKEYTOITEM = @as(u32, 46);
pub const WM_CHARTOITEM = @as(u32, 47);
pub const WM_SETFONT = @as(u32, 48);
pub const WM_GETFONT = @as(u32, 49);
pub const WM_SETHOTKEY = @as(u32, 50);
pub const WM_GETHOTKEY = @as(u32, 51);
pub const WM_QUERYDRAGICON = @as(u32, 55);
pub const WM_COMPAREITEM = @as(u32, 57);
pub const WM_GETOBJECT = @as(u32, 61);
pub const WM_COMPACTING = @as(u32, 65);
pub const WM_COMMNOTIFY = @as(u32, 68);
pub const WM_WINDOWPOSCHANGING = @as(u32, 70);
pub const WM_WINDOWPOSCHANGED = @as(u32, 71);
pub const WM_POWER = @as(u32, 72);
pub const PWR_OK = @as(u32, 1);
pub const PWR_FAIL = @as(i32, -1);
pub const PWR_SUSPENDREQUEST = @as(u32, 1);
pub const PWR_SUSPENDRESUME = @as(u32, 2);
pub const PWR_CRITICALRESUME = @as(u32, 3);
pub const WM_COPYDATA = @as(u32, 74);
pub const WM_CANCELJOURNAL = @as(u32, 75);
pub const WM_INPUTLANGCHANGEREQUEST = @as(u32, 80);
pub const WM_INPUTLANGCHANGE = @as(u32, 81);
pub const WM_TCARD = @as(u32, 82);
pub const WM_HELP = @as(u32, 83);
pub const WM_USERCHANGED = @as(u32, 84);
pub const WM_NOTIFYFORMAT = @as(u32, 85);
pub const NFR_ANSI = @as(u32, 1);
pub const NFR_UNICODE = @as(u32, 2);
pub const NF_QUERY = @as(u32, 3);
pub const NF_REQUERY = @as(u32, 4);
pub const WM_STYLECHANGING = @as(u32, 124);
pub const WM_STYLECHANGED = @as(u32, 125);
pub const WM_DISPLAYCHANGE = @as(u32, 126);
pub const WM_GETICON = @as(u32, 127);
pub const WM_SETICON = @as(u32, 128);
pub const WM_NCCREATE = @as(u32, 129);
pub const WM_NCDESTROY = @as(u32, 130);
pub const WM_NCCALCSIZE = @as(u32, 131);
pub const WM_NCHITTEST = @as(u32, 132);
pub const WM_NCPAINT = @as(u32, 133);
pub const WM_NCACTIVATE = @as(u32, 134);
pub const WM_GETDLGCODE = @as(u32, 135);
pub const WM_SYNCPAINT = @as(u32, 136);
pub const WM_NCMOUSEMOVE = @as(u32, 160);
pub const WM_NCLBUTTONDOWN = @as(u32, 161);
pub const WM_NCLBUTTONUP = @as(u32, 162);
pub const WM_NCLBUTTONDBLCLK = @as(u32, 163);
pub const WM_NCRBUTTONDOWN = @as(u32, 164);
pub const WM_NCRBUTTONUP = @as(u32, 165);
pub const WM_NCRBUTTONDBLCLK = @as(u32, 166);
pub const WM_NCMBUTTONDOWN = @as(u32, 167);
pub const WM_NCMBUTTONUP = @as(u32, 168);
pub const WM_NCMBUTTONDBLCLK = @as(u32, 169);
pub const WM_NCXBUTTONDOWN = @as(u32, 171);
pub const WM_NCXBUTTONUP = @as(u32, 172);
pub const WM_NCXBUTTONDBLCLK = @as(u32, 173);
pub const WM_INPUT_DEVICE_CHANGE = @as(u32, 254);
pub const WM_INPUT = @as(u32, 255);
pub const WM_KEYFIRST = @as(u32, 256);
pub const WM_KEYDOWN = @as(u32, 256);
pub const WM_KEYUP = @as(u32, 257);
pub const WM_CHAR = @as(u32, 258);
pub const WM_DEADCHAR = @as(u32, 259);
pub const WM_SYSKEYDOWN = @as(u32, 260);
pub const WM_SYSKEYUP = @as(u32, 261);
pub const WM_SYSCHAR = @as(u32, 262);
pub const WM_SYSDEADCHAR = @as(u32, 263);
pub const WM_KEYLAST = @as(u32, 265);
pub const UNICODE_NOCHAR = @as(u32, 65535);
pub const WM_IME_STARTCOMPOSITION = @as(u32, 269);
pub const WM_IME_ENDCOMPOSITION = @as(u32, 270);
pub const WM_IME_COMPOSITION = @as(u32, 271);
pub const WM_IME_KEYLAST = @as(u32, 271);
pub const WM_INITDIALOG = @as(u32, 272);
pub const WM_COMMAND = @as(u32, 273);
pub const WM_SYSCOMMAND = @as(u32, 274);
pub const WM_TIMER = @as(u32, 275);
pub const WM_HSCROLL = @as(u32, 276);
pub const WM_VSCROLL = @as(u32, 277);
pub const WM_INITMENU = @as(u32, 278);
pub const WM_INITMENUPOPUP = @as(u32, 279);
pub const WM_GESTURE = @as(u32, 281);
pub const WM_GESTURENOTIFY = @as(u32, 282);
pub const WM_MENUSELECT = @as(u32, 287);
pub const WM_MENUCHAR = @as(u32, 288);
pub const WM_ENTERIDLE = @as(u32, 289);
pub const WM_MENURBUTTONUP = @as(u32, 290);
pub const WM_MENUDRAG = @as(u32, 291);
pub const WM_MENUGETOBJECT = @as(u32, 292);
pub const WM_UNINITMENUPOPUP = @as(u32, 293);
pub const WM_MENUCOMMAND = @as(u32, 294);
pub const WM_CHANGEUISTATE = @as(u32, 295);
pub const WM_UPDATEUISTATE = @as(u32, 296);
pub const WM_QUERYUISTATE = @as(u32, 297);
pub const UIS_SET = @as(u32, 1);
pub const UIS_CLEAR = @as(u32, 2);
pub const UIS_INITIALIZE = @as(u32, 3);
pub const UISF_HIDEFOCUS = @as(u32, 1);
pub const UISF_HIDEACCEL = @as(u32, 2);
pub const UISF_ACTIVE = @as(u32, 4);
pub const WM_CTLCOLORMSGBOX = @as(u32, 306);
pub const WM_CTLCOLOREDIT = @as(u32, 307);
pub const WM_CTLCOLORLISTBOX = @as(u32, 308);
pub const WM_CTLCOLORBTN = @as(u32, 309);
pub const WM_CTLCOLORDLG = @as(u32, 310);
pub const WM_CTLCOLORSCROLLBAR = @as(u32, 311);
pub const WM_CTLCOLORSTATIC = @as(u32, 312);
pub const MN_GETHMENU = @as(u32, 481);
pub const WM_MOUSEFIRST = @as(u32, 512);
pub const WM_MOUSEMOVE = @as(u32, 512);
pub const WM_LBUTTONDOWN = @as(u32, 513);
pub const WM_LBUTTONUP = @as(u32, 514);
pub const WM_LBUTTONDBLCLK = @as(u32, 515);
pub const WM_RBUTTONDOWN = @as(u32, 516);
pub const WM_RBUTTONUP = @as(u32, 517);
pub const WM_RBUTTONDBLCLK = @as(u32, 518);
pub const WM_MBUTTONDOWN = @as(u32, 519);
pub const WM_MBUTTONUP = @as(u32, 520);
pub const WM_MBUTTONDBLCLK = @as(u32, 521);
pub const WM_MOUSEWHEEL = @as(u32, 522);
pub const WM_XBUTTONDOWN = @as(u32, 523);
pub const WM_XBUTTONUP = @as(u32, 524);
pub const WM_XBUTTONDBLCLK = @as(u32, 525);
pub const WM_MOUSEHWHEEL = @as(u32, 526);
pub const WM_MOUSELAST = @as(u32, 526);
pub const WHEEL_DELTA = @as(u32, 120);
pub const WM_PARENTNOTIFY = @as(u32, 528);
pub const WM_ENTERMENULOOP = @as(u32, 529);
pub const WM_EXITMENULOOP = @as(u32, 530);
pub const WM_NEXTMENU = @as(u32, 531);
pub const WM_SIZING = @as(u32, 532);
pub const WM_CAPTURECHANGED = @as(u32, 533);
pub const WM_MOVING = @as(u32, 534);
pub const WM_POWERBROADCAST = @as(u32, 536);
pub const PBT_APMQUERYSUSPEND = @as(u32, 0);
pub const PBT_APMQUERYSTANDBY = @as(u32, 1);
pub const PBT_APMQUERYSUSPENDFAILED = @as(u32, 2);
pub const PBT_APMQUERYSTANDBYFAILED = @as(u32, 3);
pub const PBT_APMSUSPEND = @as(u32, 4);
pub const PBT_APMSTANDBY = @as(u32, 5);
pub const PBT_APMRESUMECRITICAL = @as(u32, 6);
pub const PBT_APMRESUMESUSPEND = @as(u32, 7);
pub const PBT_APMRESUMESTANDBY = @as(u32, 8);
pub const PBTF_APMRESUMEFROMFAILURE = @as(u32, 1);
pub const PBT_APMBATTERYLOW = @as(u32, 9);
pub const PBT_APMPOWERSTATUSCHANGE = @as(u32, 10);
pub const PBT_APMOEMEVENT = @as(u32, 11);
pub const PBT_APMRESUMEAUTOMATIC = @as(u32, 18);
pub const PBT_POWERSETTINGCHANGE = @as(u32, 32787);
pub const WM_MDICREATE = @as(u32, 544);
pub const WM_MDIDESTROY = @as(u32, 545);
pub const WM_MDIACTIVATE = @as(u32, 546);
pub const WM_MDIRESTORE = @as(u32, 547);
pub const WM_MDINEXT = @as(u32, 548);
pub const WM_MDIMAXIMIZE = @as(u32, 549);
pub const WM_MDITILE = @as(u32, 550);
pub const WM_MDICASCADE = @as(u32, 551);
pub const WM_MDIICONARRANGE = @as(u32, 552);
pub const WM_MDIGETACTIVE = @as(u32, 553);
pub const WM_MDISETMENU = @as(u32, 560);
pub const WM_ENTERSIZEMOVE = @as(u32, 561);
pub const WM_EXITSIZEMOVE = @as(u32, 562);
pub const WM_DROPFILES = @as(u32, 563);
pub const WM_MDIREFRESHMENU = @as(u32, 564);
pub const WM_POINTERDEVICECHANGE = @as(u32, 568);
pub const WM_POINTERDEVICEINRANGE = @as(u32, 569);
pub const WM_POINTERDEVICEOUTOFRANGE = @as(u32, 570);
pub const WM_TOUCH = @as(u32, 576);
pub const WM_NCPOINTERUPDATE = @as(u32, 577);
pub const WM_NCPOINTERDOWN = @as(u32, 578);
pub const WM_NCPOINTERUP = @as(u32, 579);
pub const WM_POINTERUPDATE = @as(u32, 581);
pub const WM_POINTERDOWN = @as(u32, 582);
pub const WM_POINTERUP = @as(u32, 583);
pub const WM_POINTERENTER = @as(u32, 585);
pub const WM_POINTERLEAVE = @as(u32, 586);
pub const WM_POINTERACTIVATE = @as(u32, 587);
pub const WM_POINTERCAPTURECHANGED = @as(u32, 588);
pub const WM_TOUCHHITTESTING = @as(u32, 589);
pub const WM_POINTERWHEEL = @as(u32, 590);
pub const WM_POINTERHWHEEL = @as(u32, 591);
pub const DM_POINTERHITTEST = @as(u32, 592);
pub const WM_POINTERROUTEDTO = @as(u32, 593);
pub const WM_POINTERROUTEDAWAY = @as(u32, 594);
pub const WM_POINTERROUTEDRELEASED = @as(u32, 595);
pub const WM_IME_SETCONTEXT = @as(u32, 641);
pub const WM_IME_NOTIFY = @as(u32, 642);
pub const WM_IME_CONTROL = @as(u32, 643);
pub const WM_IME_COMPOSITIONFULL = @as(u32, 644);
pub const WM_IME_SELECT = @as(u32, 645);
pub const WM_IME_CHAR = @as(u32, 646);
pub const WM_IME_REQUEST = @as(u32, 648);
pub const WM_IME_KEYDOWN = @as(u32, 656);
pub const WM_IME_KEYUP = @as(u32, 657);
pub const WM_NCMOUSEHOVER = @as(u32, 672);
pub const WM_NCMOUSELEAVE = @as(u32, 674);
pub const WM_WTSSESSION_CHANGE = @as(u32, 689);
pub const WM_TABLET_FIRST = @as(u32, 704);
pub const WM_TABLET_LAST = @as(u32, 735);
pub const WM_DPICHANGED = @as(u32, 736);
pub const WM_DPICHANGED_BEFOREPARENT = @as(u32, 738);
pub const WM_DPICHANGED_AFTERPARENT = @as(u32, 739);
pub const WM_GETDPISCALEDSIZE = @as(u32, 740);
pub const WM_CUT = @as(u32, 768);
pub const WM_COPY = @as(u32, 769);
pub const WM_PASTE = @as(u32, 770);
pub const WM_CLEAR = @as(u32, 771);
pub const WM_UNDO = @as(u32, 772);
pub const WM_RENDERFORMAT = @as(u32, 773);
pub const WM_RENDERALLFORMATS = @as(u32, 774);
pub const WM_DESTROYCLIPBOARD = @as(u32, 775);
pub const WM_DRAWCLIPBOARD = @as(u32, 776);
pub const WM_PAINTCLIPBOARD = @as(u32, 777);
pub const WM_VSCROLLCLIPBOARD = @as(u32, 778);
pub const WM_SIZECLIPBOARD = @as(u32, 779);
pub const WM_ASKCBFORMATNAME = @as(u32, 780);
pub const WM_CHANGECBCHAIN = @as(u32, 781);
pub const WM_HSCROLLCLIPBOARD = @as(u32, 782);
pub const WM_QUERYNEWPALETTE = @as(u32, 783);
pub const WM_PALETTEISCHANGING = @as(u32, 784);
pub const WM_PALETTECHANGED = @as(u32, 785);
pub const WM_HOTKEY = @as(u32, 786);
pub const WM_PRINT = @as(u32, 791);
pub const WM_APPCOMMAND = @as(u32, 793);
pub const WM_THEMECHANGED = @as(u32, 794);
pub const WM_CLIPBOARDUPDATE = @as(u32, 797);
pub const WM_DWMCOMPOSITIONCHANGED = @as(u32, 798);
pub const WM_DWMNCRENDERINGCHANGED = @as(u32, 799);
pub const WM_DWMCOLORIZATIONCOLORCHANGED = @as(u32, 800);
pub const WM_DWMWINDOWMAXIMIZEDCHANGE = @as(u32, 801);
pub const WM_DWMSENDICONICTHUMBNAIL = @as(u32, 803);
pub const WM_DWMSENDICONICLIVEPREVIEWBITMAP = @as(u32, 806);
pub const WM_GETTITLEBARINFOEX = @as(u32, 831);
pub const WM_HANDHELDFIRST = @as(u32, 856);
pub const WM_HANDHELDLAST = @as(u32, 863);
pub const WM_AFXFIRST = @as(u32, 864);
pub const WM_AFXLAST = @as(u32, 895);
pub const WM_PENWINFIRST = @as(u32, 896);
pub const WM_PENWINLAST = @as(u32, 911);
pub const WM_APP = @as(u32, 32768);
pub const WM_USER = @as(u32, 1024);

pub const MAPVK_VSC_TO_VK_EX = @as(u32, 3);
pub const MAPVK_VK_TO_VSC_EX = @as(u32, 4);
//------------------------------------------------ FUNCTIONS ------------------------------------------/

pub extern "kernel32" fn GetModuleHandleA(
    lpModuleName: ?[*:0]const u8,
) callconv(@import("std").os.windows.WINAPI) ?windows.HINSTANCE;

pub extern "user32" fn LoadIconA(
    proccess_handle: ?windows.HINSTANCE,
    lpIconName: ?[*:0]const u8,
) ?windows.HICON;

pub extern "user32" fn LoadCursorA(
    hInstance: ?windows.HINSTANCE,
    lpCursorName: ?[*:0]const u8,
) callconv(windows.WINAPI) ?windows.HCURSOR;

pub extern "user32" fn RegisterClassA(
    lpWndClass: ?*const WNDCLASSA,
) callconv(windows.WINAPI) u16;

pub extern "user32" fn MessageBoxA(
    hWnd: ?windows.HWND,
    lpText: ?[*:0]const u8,
    lpCaption: ?[*:0]const u8,
    uType: MESSAGEBOX_STYLE,
) callconv(windows.WINAPI) MESSAGEBOX_RESULT;

pub extern "user32" fn AdjustWindowRectEx(
    lpRect: ?*windows.RECT,
    dwStyle: WINDOW_STYLE,
    bMenu: windows.BOOL,
    dwExStyle: WINDOW_EX_STYLE,
) callconv(windows.WINAPI) windows.BOOL;

pub extern "user32" fn CreateWindowExA(
    dwExStyle: WINDOW_EX_STYLE,
    lpClassName: ?[*:0]const u8,
    lpWindowName: ?[*:0]const u8,
    dwStyle: WINDOW_STYLE,
    X: i32,
    Y: i32,
    nWidth: i32,
    nHeight: i32,
    hWndParent: ?windows.HWND,
    hMenu: ?windows.HMENU,
    hInstance: ?windows.HINSTANCE,
    lpParam: ?*anyopaque,
) callconv(windows.WINAPI) ?windows.HWND;

pub extern "user32" fn ShowWindow(
    hWnd: ?windows.HWND,
    nCmdShow: SHOW_WINDOW_CMD,
) callconv(windows.WINAPI) windows.BOOL;

pub extern "user32" fn DestroyWindow(
    hWnd: ?windows.HWND,
) callconv(windows.WINAPI) windows.BOOL;

pub extern "user32" fn PeekMessageA(
    lpMsg: ?*MSG,
    hWnd: ?windows.HWND,
    wMsgFilterMin: u32,
    wMsgFilterMax: u32,
    wRemoveMsg: PEEK_MESSAGE_REMOVE_TYPE,
) callconv(windows.WINAPI) windows.BOOL;

pub extern "user32" fn TranslateMessage(
    lpMsg: ?*const MSG,
) callconv(windows.WINAPI) windows.BOOL;

pub extern "user32" fn DispatchMessageA(
    lpMsg: ?*const MSG,
) callconv(windows.WINAPI) windows.LRESULT;

pub extern "user32" fn PostQuitMessage(
    nExitCode: i32,
) callconv(windows.WINAPI) void;

pub extern "user32" fn GetClientRect(
    hWnd: ?windows.HWND,
    lpRect: ?*windows.RECT,
) callconv(windows.WINAPI) windows.BOOL;

pub extern "user32" fn DefWindowProcA(
    hWnd: ?windows.HWND,
    Msg: u32,
    wParam: windows.WPARAM,
    lParam: windows.LPARAM,
) callconv(windows.WINAPI) windows.LRESULT;

pub extern "kernel32" fn CopyFileA(
    lpExistingFileName: ?[*:0]const u8,
    lpNewFileName: ?[*:0]const u8,
    bFailIfExists: windows.BOOL,
) callconv(windows.WINAPI) windows.BOOL;

pub extern "kernel32" fn LoadLibraryA(
    lpLibFileName: ?[*:0]const u8,
) callconv(windows.WINAPI) ?windows.HINSTANCE;

pub extern "kernel32" fn GetProcAddress(
    hModule: ?windows.HINSTANCE,
    lpProcName: ?[*:0]const u8,
) callconv(windows.WINAPI) ?windows.FARPROC;

pub extern "kernel32" fn FreeLibrary(
    hLibModule: ?windows.HINSTANCE,
) callconv(windows.WINAPI) windows.BOOL;

pub extern "user32" fn MapVirtualKeyA(
    uCode: u32,
    uMapType: u32,
) callconv(windows.WINAPI) u32;

pub fn typedConst(comptime T: type, comptime value: anytype) T {
    return typedConst2(T, T, value);
}

pub fn typedConst2(comptime ReturnType: type, comptime SwitchType: type, comptime value: anytype) ReturnType {
    const target_type_error = @as([]const u8, "typedConst cannot convert to " ++ @typeName(ReturnType));
    const value_type_error = @as([]const u8, "typedConst cannot convert " ++ @typeName(@TypeOf(value)) ++ " to " ++ @typeName(ReturnType));

    switch (@typeInfo(SwitchType)) {
        .int => |target_type_info| {
            if (value >= std.math.maxInt(SwitchType)) {
                if (target_type_info.signedness == .signed) {
                    const UnsignedT = @Type(std.builtin.Type{ .Int = .{ .signedness = .unsigned, .bits = target_type_info.bits } });
                    return @as(SwitchType, @bitCast(@as(UnsignedT, value)));
                }
            }
            return value;
        },
        .pointer => |target_type_info| switch (target_type_info.size) {
            .One, .Many, .C => {
                switch (@typeInfo(@TypeOf(value))) {
                    .comptime_int, .int => {
                        const usize_value = if (value >= 0) value else @as(usize, @bitCast(@as(isize, value)));
                        return @as(ReturnType, @ptrFromInt(usize_value));
                    },
                    else => @compileError(value_type_error),
                }
            },
            else => target_type_error,
        },
        .optional => |target_type_info| switch (@typeInfo(target_type_info.child)) {
            .pointer => return typedConst2(ReturnType, target_type_info.child, value),
            else => target_type_error,
        },
        .@"enum" => |_| switch (@typeInfo(@TypeOf(value))) {
            .int => return @as(ReturnType, @enumFromInt(value)),
            else => target_type_error,
        },
        else => @compileError(target_type_error),
    }
}

test "typedConst" {
    try testing.expectEqual(@as(usize, @bitCast(@as(isize, -1))), @intFromPtr(typedConst(?*opaque {}, -1)));
    try testing.expectEqual(@as(usize, @bitCast(@as(isize, -12))), @intFromPtr(typedConst(?*opaque {}, -12)));
    try testing.expectEqual(@as(u32, 0xffffffff), typedConst(u32, 0xffffffff));
    try testing.expectEqual(@as(i32, @bitCast(@as(u32, 0x80000000))), typedConst(i32, 0x80000000));
}

const std = @import("std");
const testing = std.testing;
const windows = std.os.windows;
