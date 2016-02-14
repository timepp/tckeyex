module app;

import std.stdio;
import core.sys.windows.windows;
import core.sys.windows.dll;

__gshared HINSTANCE g_inst;

extern (Windows)
BOOL DllMain(HINSTANCE inst, ULONG reason, LPVOID)
{
    switch (reason) {
    case DLL_PROCESS_ATTACH:
        g_inst = inst;
        dll_process_attach(inst, true);
        break;
    case DLL_PROCESS_DETACH:
        dll_process_detach(inst, true);
        break;
    case DLL_THREAD_ATTACH:
        dll_thread_attach(true, true);
        break;
    case DLL_THREAD_DETACH:
        dll_thread_detach(true, true);
        break;
    default:
    }
    return true;
}
