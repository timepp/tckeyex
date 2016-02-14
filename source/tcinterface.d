module tcinterface;

import std.file;
import std.path;
import std.stdio;
import std.string;
import std.conv;

int[string] GetCommandIdMap(string tcdir)
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
