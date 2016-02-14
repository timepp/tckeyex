module plugin;

import core.sys.windows.windows;
import core.sys.windows.commctrl;
import core.stdc.string;
import core.stdc.wchar_;
import std.experimental.logger;
import std.string;
import std.utf;
import std.conv;
import std.path;
import std.stdio;
import wind.keyboard;
import wind.ui;
import wind.string;
import std.algorithm;
import tc = tcinterface;
import app;

class DbgoutputLogger : Logger
{
    this(LogLevel lv)
    {
        super(lv);
    }

    override void writeLogMsg(ref LogEntry payload)
    {
        WriteDbgOutput(payload.msg);
    }

    private:
    void WriteDbgOutput(string msg) @trusted
    {
        OutputDebugStringA(msg.toStringz());
    }
}

enum CommandType
    {
        TC,
        User,
        Extend,
    };

struct KeyMap
{
    KeySequence key;
    string action;
    
    CommandType cmdType;

    int tcid;
    int extid;
    string usercmd;
};

struct SplitInformation
{
    HWND splitter;
    RECT rcSplitter;

    HWND panel1;
    RECT rc1;

    HWND panel2;
    RECT rc2;

    Orientation ori;
};

__gshared HWND g_mainWindow;
__gshared DWORD g_mainThreadID;
__gshared string g_TCDIR;
__gshared string g_inifile;
__gshared HWND g_leftPanel;
__gshared HWND g_rightPanel;
__gshared HHOOK g_hookKeyboard;
__gshared int[string] g_tcCommandIdMap;
__gshared KeyMap[] g_keyMap;

extern(Windows) BOOL EnumWndProc(HWND hwnd, LPARAM lParam) nothrow
{
    if (CheckClassName(hwnd, "TTOTAL_CMD"w.ptr))
    {
        g_mainWindow = hwnd;
    }
    return TRUE;
}

bool CheckClassName(HWND hwnd, const(WCHAR)* name) nothrow
{
    WCHAR[100] clsname;
    GetClassNameW(hwnd, clsname.ptr, clsname.length);
    return wcscmp(clsname.ptr, name) == 0;
}

KeyMap[] parseKeyMap()
{
    KeyMap[] ret;
    string currentSection;
    auto f = File(g_inifile);
    foreach(line; f.byLine())
    {
        string s = cast(string)line.strip();
        if (s.length > 2 && s[0] == '[' && s[$-1] == ']')
            currentSection = s[1..$-1].idup;

        if (currentSection == "keysequence")
        {
            auto p = s.lastIndexOf('=');
            if (p >= 0)
            {
                string ks = s[0..p].strip();
                string cmd = s[p+1..$].strip();
                ret ~= KeyMap(ParseKeySequence(ks), cmd.idup);
            }
        }
    }
    
    f.close();
    return ret;
}

void Initialize()
{
    sharedLog = new DbgoutputLogger(LogLevel.all);
    g_mainThreadID = GetCurrentThreadId();
    EnumThreadWindows(g_mainThreadID, &EnumWndProc, 0);
    g_hookKeyboard = SetWindowsHookExW(WH_KEYBOARD, &KeyHook, NULL, g_mainThreadID);

    WCHAR[MAX_PATH] path;
    GetModuleFileNameW(NULL, path.ptr, path.length);
    g_TCDIR = dirName(stringFromCStringW(path.ptr));
    g_tcCommandIdMap = tc.GetCommandIdMap(g_TCDIR);

    GetModuleFileNameW(app.g_inst, path.ptr, path.length);
    g_inifile = dirName(stringFromCStringW(path.ptr)) ~ `\tckeyex.ini`;
    g_keyMap = parseKeyMap();

    log(g_inifile, g_keyMap);
    log("thread id:", g_mainThreadID, " main window:", g_mainWindow, " TCDIR:", g_TCDIR);
    log(g_tcCommandIdMap);
}

void RunTCCommand(int cmdid)
{
    logf("post message: hwnd=0x%X, msg=1075, wp=%d, lp=0", g_mainWindow, cmdid);
    PostMessageW(g_mainWindow, 1075, cmdid, 0);
}

void InitPanels()
{
    import std.algorithm: swap;
    
    if (!g_leftPanel || !g_rightPanel)
    {
        HWND panel1 = FindWindowExW(g_mainWindow, null, "TMyListBox"w.ptr, null);
        HWND panel2 = FindWindowExW(g_mainWindow, panel1, "TMyListBox"w.ptr, null);
        RECT rc1, rc2;
        GetWindowRect(panel1, &rc1);
        GetWindowRect(panel2, &rc2);
        if (rc1.left > rc2.left)
        {
            swap(panel1, panel2);
        }
        g_leftPanel = panel1;
        g_rightPanel = panel2;
        log("panel1:", panel1, " panel2:", panel2);
    }
}

HWND leftPanel()
{
    InitPanels();
    return g_leftPanel;
}

HWND rightPanel()
{
    InitPanels();
    return g_rightPanel;
}

enum Orientation
    {
        Vertical,
        Horizontal,
    };

SplitInformation GetSplitInformation()
{
    SplitInformation si;
    si.splitter = FindWindowExW(g_mainWindow, null, "TPanel"w.ptr, null);
    GetWindowRect(si.splitter, &si.rcSplitter);
    si.ori = (si.rcSplitter.right - si.rcSplitter.left > si.rcSplitter.bottom - si.rcSplitter.top)?
        Orientation.Horizontal :
        Orientation.Vertical;

    HWND hwnd;
    do {
        RECT rc;
        hwnd = FindWindowExW(g_mainWindow, hwnd, "TMyPanel"w.ptr, null);
        GetWindowRect(hwnd, &rc);
        if (si.ori == Orientation.Horizontal)
        {
            if (rc.left == si.rcSplitter.left && rc.right == si.rcSplitter.right)
            {
                if (rc.top <= si.rcSplitter.top) { si.panel1 = hwnd; si.rc1 = rc; }
                else { si.panel2 = hwnd; si.rc2 = rc; }
            }
        }
        else
        {
            if (rc.top == si.rcSplitter.top && rc.bottom == si.rcSplitter.bottom)
            {
                if (rc.left <= si.rcSplitter.left) { si.panel1 = hwnd; si.rc1 = rc; }
                else { si.panel2 = hwnd; si.rc2 = rc; }
            }
        }
    } while (hwnd != NULL);

    return si;
}

// void SimulateKeyPress(int[] keys)
// {
//     SimulateKeyPressInternal(keys);
// }

void KeyboardEvent(int[] keys)
{
    int k = keys[0];
    ubyte vk = cast(ubyte)k;
    ubyte scancode = cast(ubyte)MapVirtualKeyW(vk, MAPVK_VK_TO_VSC);
 
    keybd_event(vk, scancode, 0, 0);
    if (keys.length > 1)
        KeyboardEvent(keys[1..$]);
    keybd_event(vk, scancode, KEYEVENTF_KEYUP, 0);
}

// Simulate key press by directly send a WM_KEYDOWN message to list panel.
//
// We should clear the state of other unrelated modifiers before send message. Otherwise, consider
// that we map `ctrl+j` do `down arrow`, if we do not clear the keyboard state before send `down
// arrow`, TC will see `ctrl` is down so it will execute hotkey `ctrl+down` but not simple `down`.
void SimulateKeyPress(HWND hwnd, int vk, int[] modifiers)
{
    BYTE[0x100] oldKeyState;
    GetKeyboardState(oldKeyState.ptr);
    BYTE[] newKeyState = oldKeyState.dup;
    newKeyState[VK_CONTROL] = 0;
    newKeyState[VK_MENU] = 0;
    newKeyState[VK_LWIN] = 0;
    newKeyState[VK_SHIFT] = 0;
    foreach (k; modifiers)
    {
        newKeyState[k] = 0x80;
    }

    SetKeyboardState(newKeyState.ptr);
    
    int scancode = MapVirtualKeyW(vk, MAPVK_VK_TO_VSC);
    SendMessageW(hwnd, WM_KEYDOWN, vk, (scancode << 16) | 1);

    SetKeyboardState(oldKeyState.ptr);
}

// percentage: 0-100
void AdjustSplitPos(int percentage)
{
    SplitInformation si = GetSplitInformation();
    log(si);

    RECT rc1 = ScreenToClient(g_mainWindow, si.rc1);
    RECT rc2 = ScreenToClient(g_mainWindow, si.rc2);
    RECT rcSplitter = ScreenToClient(g_mainWindow, si.rcSplitter);

    if (si.ori == Orientation.Vertical)
    {
        LONG total = rc1.width + rc2.width;
        LONG w1 = total * percentage / 100;
        LONG w2 = total - w1;
        rc1.right = rcSplitter.left = rc1.left + w1;
        rc2.left = rcSplitter.right = rc2.right - w2;
    }
    else
    {
        LONG total = rc1.height + rc2.height;
        LONG w1 = total * percentage / 100;
        LONG w2 = total - w1;
        rc1.bottom = rcSplitter.top = rc1.top + w1;
        rc2.top = rcSplitter.bottom = rc2.bottom - w2;
    }
    
    MoveWindow(si.panel1, rc1.left, rc1.top, rc1.width, rc1.height, TRUE);
    MoveWindow(si.splitter, rcSplitter.left, rcSplitter.top, rcSplitter.width, rcSplitter.height, TRUE);
    MoveWindow(si.panel2, rc2.left, rc2.top, rc2.width, rc2.height, TRUE);
}

void MoveSplitPos(Orientation ori, int offset)
{
    SplitInformation si = GetSplitInformation();
    log(si);

    if (si.ori != ori) return;

    RECT rc1 = ScreenToClient(g_mainWindow, si.rc1);
    RECT rc2 = ScreenToClient(g_mainWindow, si.rc2);
    RECT rcSplitter = ScreenToClient(g_mainWindow, si.rcSplitter);

    if (si.ori == Orientation.Vertical)
    {
        LONG total = rc1.width + rc2.width;
        LONG w1 = clamp(rc1.width + offset, 0, total);
        LONG w2 = total - w1;
        rc1.right = rcSplitter.left = rc1.left + w1;
        rc2.left = rcSplitter.right = rc2.right - w2;
    }
    else
    {
        LONG total = rc1.height + rc2.height;
        LONG w1 = clamp(rc1.height + offset, 0, total);
        LONG w2 = total - w1;
        rc1.bottom = rcSplitter.top = rc1.top + w1;
        rc2.top = rcSplitter.bottom = rc2.bottom - w2;
    }
    
    MoveWindow(si.panel1, rc1.left, rc1.top, rc1.width, rc1.height, TRUE);
    MoveWindow(si.splitter, rcSplitter.left, rcSplitter.top, rcSplitter.width, rcSplitter.height, TRUE);
    MoveWindow(si.panel2, rc2.left, rc2.top, rc2.width, rc2.height, TRUE);
}

void DoExtendAction(string action)
{
    HWND hwnd = GetFocus();
    switch (action)
    {
    case "MoveCursorDown":
        SimulateKeyPress(hwnd, VK_DOWN, []);
        break;
    case "MoveCursorUp":
        SimulateKeyPress(hwnd, VK_UP, []);
        break;
    case "MoveCursorLeft":
        SimulateKeyPress(hwnd, VK_LEFT, []);
        break;
    case "MoveCursorRight":
        SimulateKeyPress(hwnd, VK_RIGHT, []);
        break;
    case "MoveCursorTop":
        SimulateKeyPress(hwnd, VK_HOME, []);
        break;
    case "MoveCursorBottom":
        SimulateKeyPress(hwnd, VK_END, []);
        break;
    case "SelectDown":
        SimulateKeyPress(hwnd, VK_DOWN, [VK_SHIFT]);
        break;
    case "SelectUp":
        SimulateKeyPress(hwnd, VK_UP, [VK_SHIFT]);
        break;
    case "SwitchToLeftPanel":
        SetFocus(leftPanel());
        break;
    case "SwitchToRightPanel":
        SetFocus(rightPanel());
        break;
    case "OpenSearch":
        SimulateKeyPress(hwnd, 'S', [VK_CONTROL]);
        break;
    case "SwitchTab":
        SimulateKeyPress(hwnd, VK_TAB, [VK_CONTROL]);
        break;
    case "DeleteFile":
        SimulateKeyPress(hwnd, VK_DELETE, []);
        break;
    case "Rename":
        SimulateKeyPress(hwnd, VK_F6, [VK_SHIFT]);
        break;
    case "SystemOpen":
        KeyboardEvent([VK_LWIN, VK_F2]);
        break;
    case "Split_0Percent":   AdjustSplitPos(0);   break;
    case "Split_10Percent":  AdjustSplitPos(10);  break;
    case "Split_20Percent":  AdjustSplitPos(20);  break;
    case "Split_30Percent":  AdjustSplitPos(30);  break;
    case "Split_40Percent":  AdjustSplitPos(40);  break;
    case "Split_50Percent":  AdjustSplitPos(50);  break;
    case "Split_60Percent":  AdjustSplitPos(60);  break;
    case "Split_70Percent":  AdjustSplitPos(70);  break;
    case "Split_80Percent":  AdjustSplitPos(80);  break;
    case "Split_90Percent":  AdjustSplitPos(90);  break;
    case "Split_100Percent": AdjustSplitPos(100); break;
    case "NewFileAndEdit":
        SimulateKeyPress(hwnd, VK_F4, [VK_SHIFT]);
        break;
    default:
        log("unknown action:", action);
        break;
    }
}

void DoAction(string action)
{
    log("do action: ", action);
    if (action.length > 4 && action[0..4] == "ecm_")
    {
        DoExtendAction(action[4..$]);
    }
    else if (action.length > 4 && action[0..4] == "cmn_")
    {
        RunTCCommand(to!int(action[4..$]));
    }
    else if (action.length > 3 && action[0..3] == "cm_")
    {
        int id = g_tcCommandIdMap[action[3..$]];
        RunTCCommand(id);
    }
}

size_t g_matchingPosition;
KeyMap[] g_matchingKeyMap;

bool MatchKeyPress(BYTE[] keyboardState, int vk, ref bool matchingInProgress, ref KeyMap matchedKeyMap)
{
    log("match: ", keyboardState);
    KeyMap[] effectiveMap = g_matchingKeyMap.length? g_matchingKeyMap : g_keyMap;
    if (g_matchingKeyMap.length == 0)
        g_matchingPosition = 0;
    g_matchingKeyMap.length = 0;
    foreach(km; effectiveMap)
    {
        KeyPress k = km.key[g_matchingPosition];
        log("matching: ", k);
        // compare k with {keyboardState, vk}
        if (k.key == vk)
        {
            bool match = all!(a => keyboardState[a] & 0x80)(k.modifiers);
            log("modifiers check result:", match);

            // the modifiers must be exactly match
            if (match)
            {
                int[] modifiers = [VK_SHIFT, VK_CONTROL, VK_MENU, VK_LWIN, VK_RWIN];
                auto len = count!(a => (keyboardState[a] & 0x80) > 0)(modifiers);
                match = (len == k.modifiers.length);
                log("modifiers count check result:", match, " ", len, " vs ", k.modifiers.length);
            }
            
            if (match)
            {
                if (km.key.length == g_matchingPosition + 1)
                {
                    g_matchingKeyMap.length = 0;
                    matchingInProgress = false;
                    matchedKeyMap = km;
                    return true;
                }
                else
                {
                    matchingInProgress = true;
                    g_matchingKeyMap ~= km;
                }
            }
        }
    }

    if (g_matchingKeyMap.length > 0)
    {
        g_matchingPosition++;
        return true;
    }
   
    return false;
}

extern(Windows)
LRESULT KeyHook(
    int    code,
    WPARAM wParam,
    LPARAM lParam
    ) nothrow
{
    try {
        bool handled = false;
        KeyHookInternal(code, wParam, lParam, handled);
        return handled? TRUE: CallNextHookEx(g_hookKeyboard, code, wParam, lParam);
    }
    catch (Exception)
    {
        return FALSE;
    }
}

// return TRUE if we proceeded the message and we shouldn't call next hook
// return FALSE if we do not proceed the message and we should call next hook
void KeyHookInternal(int code, WPARAM wParam, LPARAM lParam, ref bool handled)
{
    if (code < 0) return;

    // see MSDN
    if (lParam & 0x80000000) return;

    HWND hwnd = GetFocus();

    // currently we are only interested in the 2 file list panels
    if (!CheckClassName(hwnd, "TMyListBox"w.ptr)) return;

    // If there is menu popup, GetFocus() still get the panel but not the menu
    // so we should check any menu popup manually
    GUITHREADINFO threadInfo;
    threadInfo.cbSize = threadInfo.sizeof;
    if (GetGUIThreadInfo(g_mainThreadID, &threadInfo))
    {
        logf("menu flag: 0x%X", threadInfo.flags);
        if (threadInfo.flags & GUI_INMENUMODE) return;
    }
   
    uint scancode = (cast(uint)lParam >> 16) & 0xFF;
    logf("vk: 0x%X; scancode: 0x%X; wparam: 0x%X; hwnd: 0x%X", wParam, scancode, lParam, hwnd);

    BYTE[0x100] keyState;
    GetKeyboardState(keyState.ptr);
    string action;
    bool matchingInProgress;
    KeyMap km;
    
    if (!MatchKeyPress(keyState[], wParam, matchingInProgress, km)) return;
    
    if (!matchingInProgress)
    {
        log(km);
        DoAction(km.action);
    }

    handled = true;
}

// TODO: get global information and init key hook at first time
extern(Windows)
private int ContentGetSupportedField(int FieldIndex, char* FieldName, char* Units, int maxlen)
{
    if (!g_mainThreadID)
    {
        Initialize();
    }
    
    if (FieldIndex == 0)
    {
        immutable(char)[10] title = "tvmstart";
        FieldName[0..9] = title[0..9];
        return 1;
    }

    return 0;
}

extern(Windows) 
private int ContentGetValue(char* FileName, int FieldIndex, int UnitIndex, void* FieldValue, int maxlen, int flags)
{
    *cast(int*)FieldValue = 0;
    return 1;
}
