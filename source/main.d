import core.sys.windows.windows;
import std.algorithm : find;
import std.conv : to;
import std.experimental.logger;
import std.path : dirName;
import std.stdio : File;
import std.string;
import wind.keyboard;
import wind.string;
import wind.ui;

import tc = tcinterface;
import app;

/// The module version_ is generated by build script.
import version_ : appVersion;

pragma(lib, "user32.lib");

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
    string args;
    
    CommandType cmdType;

    int tcid;
    int extid;
    string usercmd;
};


__gshared DWORD g_mainThreadID;
__gshared string g_TCDIR;
__gshared string g_inifile;
__gshared HHOOK g_hookKeyboard;
__gshared int[string] g_tcCommandIdMap;
__gshared KeyMap[] g_keyMap;
__gshared bool g_visualSelect;

KeyMap[] parseKeyMap()
{
    KeyMap[] ret;
    string currentSection;
    auto f = File(g_inifile);
    foreach(line; f.byLine())
    {
        string s = cast(string)line.strip();

        // ignore any comments which starts with ';'
        if (s.length > 0 && s[0] == ';') continue;
        
        // extract section, if any
        if (s.length > 2 && s[0] == '[' && s[$-1] == ']')
        {
            currentSection = s[1..$-1].idup;
            continue;
        }

        if (currentSection == "keysequence")
        {
            auto p = s.lastIndexOf('=');
            if (p >= 0)
            {
                string ks = s[0..p].strip();
                string cmd = s[p+1..$].strip();
                string action = cmd.splitHead(' ');
                string args = cmd.splitTail(' ', "");
                ret ~= KeyMap(ParseKeySequence(ks), action.idup, args.idup);
            }
        }
    }
    
    f.close();
    return ret;
}

void Initialize()
{
    debug
    {
        sharedLog = new DbgoutputLogger(LogLevel.all);
    }
    else
    {
        sharedLog = new NullLogger();
    }
    
    g_mainThreadID = GetCurrentThreadId();
    g_hookKeyboard = SetWindowsHookExW(WH_KEYBOARD, &KeyHook, NULL, g_mainThreadID);

    WCHAR[MAX_PATH] path;
    GetModuleFileNameW(NULL, path.ptr, path.length);
    g_TCDIR = dirName(stringFromCStringW(path.ptr));
    g_tcCommandIdMap = tc.getCommandIdMap(g_TCDIR);

    GetModuleFileNameW(app.g_inst, path.ptr, path.length);
    g_inifile = dirName(stringFromCStringW(path.ptr)) ~ `\tckeyex.ini`;
    g_keyMap = parseKeyMap();

    log(g_inifile, g_keyMap);
    log("thread id:", g_mainThreadID, " TCDIR:", g_TCDIR);
    log("key hook handle:", g_hookKeyboard);
    log(g_tcCommandIdMap);
}

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

    // Limitation: send message will cause doing something here, if that thing is sensitive to the
    // keyboard state, our behavior may be wrong.  For example, if we simulate SHIFT+F4 which will
    // open a dialog waiting user input immediately, the inputs there will be all uppercase because
    // we havn't get the chance to restore the keyboard state at that time.
    SendMessageW(hwnd, WM_KEYDOWN, vk, (scancode << 16) | 1);

    SetKeyboardState(oldKeyState.ptr);
}

void sendKey(HWND hwnd, string args)
{
    KeySequence ks = ParseKeySequence(args);
    foreach (k; ks)
    {
        KeyboardEvent(k.modifiers ~ k.key);
    }
}

void DoExtendAction(string action, string args)
{
    HWND hwnd = GetFocus();
    switch (action)
    {
        case "MoveCursorDown":
            SimulateKeyPress(hwnd, VK_DOWN, g_visualSelect?[VK_SHIFT]:[]);
            break;
        case "MoveCursorUp":
            SimulateKeyPress(hwnd, VK_UP, g_visualSelect?[VK_SHIFT]:[]);
            break;
        case "MoveCursorLeft":
            SimulateKeyPress(hwnd, VK_LEFT, g_visualSelect?[VK_SHIFT]:[]);
            break;
        case "MoveCursorRight":
            SimulateKeyPress(hwnd, VK_RIGHT, g_visualSelect?[VK_SHIFT]:[]);
            break;
        case "MoveCursorTop":
            SimulateKeyPress(hwnd, VK_HOME, g_visualSelect?[VK_SHIFT]:[]);
            break;
        case "MoveCursorBottom":
            SimulateKeyPress(hwnd, VK_END, g_visualSelect?[VK_SHIFT]:[]);
            break;
        case "MoveCursorPagedown":
            SimulateKeyPress(hwnd, VK_NEXT, g_visualSelect?[VK_SHIFT]:[]);
            break;
        case "MoveCursorPageup":
            SimulateKeyPress(hwnd, VK_PRIOR, g_visualSelect?[VK_SHIFT]:[]);
            break;       
        case "SelectDown":
            SimulateKeyPress(hwnd, VK_DOWN, [VK_SHIFT]);
            break;
        case "SelectUp":
            SimulateKeyPress(hwnd, VK_UP, [VK_SHIFT]);
            break;
        case "PrepareForSelection":
            g_visualSelect = !g_visualSelect;
            break;
        case "ResizePanel":
            tc.resizePanel(args);
            break;
        case "SendKey":
            sendKey(hwnd, args);
            break;
        case "CustomView":
            tc.switchCustomView(hwnd, to!int(args));
            break;
        case "SplitMenu":
            tc.openSplitMenu();
            break;
        case "DirectoryMenu":
            tc.openDirectoryMenu(hwnd);
            break;
        default:
            log("unknown action:", action);
            break;
    }
}

void DoAction(string action, string args)
{
    log("do action: ", action);
    if (action.length > 4 && action[0..4] == "ecm_")
    {
        DoExtendAction(action[4..$], args);
    }
    else if (action.length > 4 && action[0..4] == "cmn_")
    {
        tc.runTCCommand(to!int(action[4..$]), args.length==0?0:to!int(args));
    }
    else if (action.length > 3 && action[0..3] == "cm_")
    {
        int id = g_tcCommandIdMap[action[3..$]];
        tc.runTCCommand(id, args.length==0?0:to!int(args));
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
            int[] modifiers = [VK_SHIFT, VK_CONTROL, VK_MENU, VK_LWIN, VK_RWIN];
            bool match = true;
            foreach (m; modifiers)
            {
                // check if exactly the same modifiers are pressed.
                // i.e. other modifiers must not be pressed. (one exception is that if the key
                // itself is a modifier, apprarently it's pressed, in such case we simly ignore it.)

                if (find(k.modifiers, m) != [])
                {
                    if (!(keyboardState[m] & 0x80)) match = false;
                }
                else
                {
                    if (vk != m && (keyboardState[m] & 0x80)) match = false;
                }
            }

            log("modifiers check result:", match);

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

    if (wParam == VK_RETURN)
    {
        if (hwnd == tc.getCommandEdit())
        {
            if (hwnd.title == ":tckeyex version")
            {
                SimulateKeyPress(hwnd, VK_ESCAPE, []);
                MessageBoxA(null, appVersion.ptr, "tckeyex".ptr, MB_OK|MB_ICONINFORMATION);
                handled = true;
            }
            return;
        }
    }

    // currently we are only interested in the 2 file list panels
    if (!tc.isFileList(hwnd)) return;

    // We shouldn't hijack the key if there is menu popup
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
    
    if (!MatchKeyPress(keyState[], cast(int)wParam, matchingInProgress, km)) 
    {
        // If no match, reset visual mode only when vk is not a modifier
        // otherwise key sequence like {SHIFT}+g won't work in visual mode
        int[] modifiers = [VK_SHIFT, VK_CONTROL, VK_MENU, VK_LWIN, VK_RWIN];
        if (modifiers.find(wParam) == [])
            g_visualSelect = false;
        return;
    }
   
    if (!matchingInProgress)
    {
        log(km);
        if (!km.action.startsWith("ecm_Move") && km.action != "ecm_PrepareForSelection")
        {
            g_visualSelect = false;
        }
        DoAction(km.action, km.args);
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
