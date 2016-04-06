/**
 * A set of functions to manipulate Total Commander.
 */

module tcinterface;

import core.stdc.wchar_ : wcscmp;
import core.sys.windows.windows;
import std.experimental.logger;
import std.algorithm : clamp, filter;
import std.conv : to;
import std.stdio : File;
import std.string : indexOf;
import wind.string : splitHead, splitTail;
import wind.ui;

enum Orientation
{
    Vertical,
    Horizontal,
};

HWND mainWindow;
HWND splitter;
HWND panel1;
HWND path1;
HWND panel2;
HWND path2;
HWND commandEdit;

/******************************************
 * Fetch TC components if they are not fetched before.
 *
 * Note that this information is only need to fetch once during one TC session.
 */
private void ensureWindowInformation()
{
    if (mainWindow && splitter && panel1 && panel2 && commandEdit) return;
    
    mainWindow = getTCMainWindow();
    splitter = FindWindowExW(mainWindow, null, "TPanel"w.ptr, null);

    foreach (wnd; mainWindow.directChilds().filter!(a => a.getClassName() == "TMyPanel"))
    {
        RECT rc = wnd.rect;
        int r = rc.rectRelationShip(splitter.rect);
        if (r & RR.Align)
        {
            if (r & RR.Left || r & RR.Above) 
                panel1 = wnd; 

            if (r & RR.Right || r & RR.Below)
                panel2 = wnd;
        }

        if (!commandEdit)
        {
            auto combo = FindWindowExW(wnd, null, "TMyComboBox"w.ptr, null);
            if (combo)
            {
                commandEdit = FindWindowExW(combo, null, "Edit"w.ptr, null);
            }
        }
    }

    HWND tab1 = FindWindowExW(panel1, null, "TMyTabControl", null);
    path1 = FindWindowExW(tab1, null, "TPathPanel"w.ptr, null);
    HWND tab2 = FindWindowExW(panel2, null, "TMyTabControl", null);
    path2 = FindWindowExW(tab2, null, "TPathPanel"w.ptr, null);

    log("main window:", mainWindow, " splitter:", splitter
        , " panels:", panel1, ",", panel2
        , " paths:", path1, ",", path2
        , " edit:", commandEdit);
}

/******************************************
 * The most efficient way to check if a windows has specific class name.
 *
 * Returns:
 *     If the window class name is $(D, name), return true. otherwise return false.
 */
private bool checkClassName(HWND hwnd, const(WCHAR)* name) nothrow
{
    WCHAR[100] clsname;
    GetClassNameW(hwnd, clsname.ptr, clsname.length);
    return wcscmp(clsname.ptr, name) == 0;
}

HWND getCommandEdit()
{
    ensureWindowInformation();
    return commandEdit;
}

/******************************************
 * Get TC command ID map as an associative array.
 *
 * Params:
 *     tcdir = TC installed directory -- the directory where TOTALCMD.exe resides.
 * 
 * TC uses command ID internally and users command string in the configuration file for
 * readability. TC uses TOTALCMD.INC to help map command string to command ID.
 */
int[string] getCommandIdMap(string tcdir)
{
    int[string] ret;
    string incfile = tcdir ~ `\TOTALCMD.INC`;
    auto f = File(incfile);
    foreach(line; f.byLine())
    {
        if (line.length > 3 && line[0..3] == "cm_")
        {
            auto p1 = line.indexOf('=');
            auto p2 = line.indexOf(';');
            if (p1 != -1 && p2 != -1 && p2 > p1)
            {
                ret[line[3..p1].idup] = to!int(line[p1+1..p2]); 
            }
        }
    }
    f.close();
    return ret;
}

/// Run TC internal command by command ID
void runTCCommand(int cmdid, int param)
{
    ensureWindowInformation();
    PostMessageW(mainWindow, 1075, cmdid, param);
}

HWND getTCMainWindow()
{
    if (mainWindow == null)
    {
        mainWindow = FindWindowExW(null, null, "TTOTAL_CMD"w.ptr, null);
    }
    return mainWindow;
}

/******************************************
 * Resize TC left panel or right panel size. In other word, adjust the splitter positon.
 *
 * Params:
 *    args = left|right|top|bottom|first|second|focus [+|-]n[%]
 */
void resizePanel(string args)
{
    ensureWindowInformation();
    RECT rcs = splitter.rect;
    RECT rc1 = panel1.rect;
    RECT rc2 = panel2.rect;
    Orientation ori = rcs.width > rcs.height? Orientation.Horizontal : Orientation.Vertical;
    
    string panel = args.splitHead(' ');
    if (ori == Orientation.Vertical   && (panel == "top" || panel == "bottom") ||
        ori == Orientation.Horizontal && (panel == "left" || panel == "right"))
    {
        return;
    }
    
    HWND focusWnd = GetFocus();
    bool moveFirst =
        panel == "left" ||
        panel == "top" ||
        panel == "first" ||
        panel == "focus" && (focusWnd.rect.rectRelationShip(rcs) & (RR.Left | RR.Above));

    string amount = args.splitTail(' ', "");
    if (amount.length == 0)
    {
        return;
    }
    
    bool percentage = false;
    if (amount[$-1] == '%')
    {
        percentage = true;
        amount = amount[0..$-1];
    }
    bool relative = (amount[0] == '-' || amount[0] == '+');
    int value = to!int(amount);

    rc1 = toClientCoordinate(mainWindow, rc1);
    rc2 = toClientCoordinate(mainWindow, rc2);
    rcs = toClientCoordinate(mainWindow, rcs);

    if (ori == Orientation.Vertical)
    {
        LONG w1 = rc1.width;
        LONG w2 = rc2.width;
        LONG total = w1 + w2;
        LONG* pwa = moveFirst? &w1 : &w2;
        LONG* pwb = moveFirst? &w2 : &w1;
        if (percentage)
        {
            value = value * total / 100;
        }
        *pwa = relative? *pwa + value : value;
        *pwa = clamp(*pwa, 1, total-1);
        *pwb = total - *pwa;
        rc1.right = rcs.left = rc1.left + w1;
        rc2.left = rcs.right = rc2.right - w2;
    }
    else
    {
        LONG w1 = rc1.height;
        LONG w2 = rc2.height;
        LONG total = w1 + w2;
        LONG* pwa = moveFirst? &w1 : &w2;
        LONG* pwb = moveFirst? &w2 : &w1;
        if (percentage)
        {
            value = value * total / 100;
        }
        *pwa = relative? *pwa + value : value;
        *pwa = clamp(*pwa, 1, total-1);
        *pwb = total - *pwa;
        rc1.bottom = rcs.top = rc1.top + w1;
        rc2.top = rcs.bottom = rc2.bottom - w2;
    }
    
    MoveWindow(panel1,   rc1.left, rc1.top, rc1.width, rc1.height, TRUE);
    MoveWindow(splitter, rcs.left, rcs.top, rcs.width, rcs.height, TRUE);
    MoveWindow(panel2,   rc2.left, rc2.top, rc2.width, rc2.height, TRUE);
}

bool isFileList(HWND hwnd)
{
    return checkClassName(hwnd, "TMyListBox"w.ptr);
}

void switchCustomView(HWND hwnd, int view)
{
    ensureWindowInformation();
    if (hwnd.rect.rectRelationShip(splitter.rect) & (RR.Left | RR.Above))
    {
        runTCCommand(5510, view);
    }
    else
    {
        runTCCommand(5511, view);
    }
}

/******************************************
 * Open TC's splitter context menu.
 */
void openSplitMenu()
{
    ensureWindowInformation();
    RECT rc = splitter.rect;
    int lparam = ((rc.height() / 2) << 16) | (rc.width() / 2);
    SendMessageW(splitter, WM_RBUTTONUP, 0, lparam);
}

/******************************************
 * Open folder context menu
 */
void openDirectoryMenu(HWND hwnd)
{
    ensureWindowInformation();
    HWND path = (hwnd.rect.rectRelationShip(splitter.rect) & (RR.Left | RR.Above)) ? path1 : path2;
    RECT rc = path.rect;
    int lparam = ((rc.height() / 2) << 16);
    log("send", lparam, " to ", path);
    PostMessageW(path, WM_RBUTTONDOWN, 0, lparam);
    PostMessageW(path, WM_RBUTTONUP, 0, lparam);
}

