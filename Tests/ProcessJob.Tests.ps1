#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.1.0' }
# The capture stops its processes through a job object (tools\guide-capture\ProcessJob.ps1). Windows uses process ids again, so an older
# process can record the id of the app as its parent. A stop that follows parent ids then reaches a process that the capture did not start.
# The test starts processes of its own and opens no window.
#
# Windows cannot be told to use an id again. The stranger gets the same record in another way: it is created with the app process as its
# named parent while that process is not in the job yet. So the stranger records the id of the app as its parent and is not in the job.

BeforeAll {
    $script:ToolDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\guide-capture'
    . (Join-Path $script:ToolDir 'ProcessJob.ps1')
    if (-not ('CaptureTestStranger' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
public static class CaptureTestStranger
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct StartupInfo
    {
        public int cb; public string r1, r2, r3; public int x, y, xs, ys, xc, yc, fill, flags;
        public short show, cb2; public IntPtr r4, i, o, e;
    }
    [StructLayout(LayoutKind.Sequential)] struct StartupInfoEx { public StartupInfo Info; public IntPtr Attributes; }
    [StructLayout(LayoutKind.Sequential)] struct ProcessInformation { public IntPtr Process, Thread; public int ProcessId, ThreadId; }
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr OpenProcess(uint access, bool inherit, int id);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool InitializeProcThreadAttributeList(IntPtr list, int count, int flags, ref IntPtr size);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool UpdateProcThreadAttribute(IntPtr list, uint flags, IntPtr attribute, IntPtr value, IntPtr size, IntPtr previous, IntPtr returned);
    [DllImport("kernel32.dll")] static extern void DeleteProcThreadAttributeList(IntPtr list);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CreateProcess(string application, StringBuilder commandLine, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr environment, string directory, ref StartupInfoEx startup, out ProcessInformation information);

    public static Process Start(string commandLine, int parentId)
    {
        IntPtr parent = OpenProcess(0x80, false, parentId); // PROCESS_CREATE_PROCESS
        if (parent == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        IntPtr size = IntPtr.Zero;
        InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref size);
        IntPtr list = Marshal.AllocHGlobal(size);
        IntPtr value = Marshal.AllocHGlobal(IntPtr.Size);
        try
        {
            if (!InitializeProcThreadAttributeList(list, 1, 0, ref size)) throw new Win32Exception(Marshal.GetLastWin32Error());
            Marshal.WriteIntPtr(value, parent);
            // PROC_THREAD_ATTRIBUTE_PARENT_PROCESS
            if (!UpdateProcThreadAttribute(list, 0, new IntPtr(0x00020000), value, new IntPtr(IntPtr.Size), IntPtr.Zero, IntPtr.Zero)) throw new Win32Exception(Marshal.GetLastWin32Error());
            var startup = new StartupInfoEx();
            startup.Info.cb = Marshal.SizeOf(typeof(StartupInfoEx));
            startup.Attributes = list;
            ProcessInformation information;
            // EXTENDED_STARTUPINFO_PRESENT | CREATE_NO_WINDOW
            if (!CreateProcess(null, new StringBuilder(commandLine), IntPtr.Zero, IntPtr.Zero, false, 0x00080000 | 0x08000000, IntPtr.Zero, null, ref startup, out information))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            var process = Process.GetProcessById(information.ProcessId);
            IntPtr keep = process.Handle; // opened while the creation handle is open, so it is this process
            CloseHandle(information.Thread);
            CloseHandle(information.Process);
            DeleteProcThreadAttributeList(list);
            return process;
        }
        finally { Marshal.FreeHGlobal(list); Marshal.FreeHGlobal(value); CloseHandle(parent); }
    }
}
'@
    }
    # Start-App, Stop-App and Start-AppProcess of guilib.ps1, without the rest of the file: the rest loads UI Automation.
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:ToolDir 'guilib.ps1'), [ref]$null, [ref]$null)
    $functions = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in 'Register-RunProcess', 'Start-AppProcess', 'Stop-App' }, $true))
    . ([scriptblock]::Create(($functions.Extent.Text -join "`n")))
    $script:RealStart = ${function:Start-JobProcess}
}

Describe 'A stop of the app ends only the job of the app' {
    BeforeAll {
        $script:strangers = New-Object System.Collections.ArrayList
        Set-Variable -Name appDir -Value $TestDrive -Scope Script
        $script:RunLedger = Join-Path $TestDrive 'run.pids'
        $script:AppProcs = @{}
        $script:AppRuns = @{}
        $pidFile = Join-Path $TestDrive 'child.txt'
        # A stand-in for the app: it starts a child, as the app starts a browser for a report.
        Set-Content -LiteralPath (Join-Path $TestDrive 'app.ps1') -Encoding Ascii -Value @(
            '$c = Start-Process ping.exe -ArgumentList ''-n'', ''120'', ''127.0.0.1'' -PassThru -WindowStyle Hidden'
            ('Set-Content -LiteralPath ''{0}'' -Value $c.Id' -f $pidFile)
            'Start-Sleep -Seconds 120')
        $hook = [Action[int]] { param($id) $null = $script:strangers.Add([CaptureTestStranger]::Start('ping.exe -n 120 127.0.0.1', $id)) }
        function Start-JobProcess {
            param($FilePath, $ArgumentList)
            & $script:RealStart @PSBoundParameters -BeforeJoin $hook
        }
        Start-AppProcess 'app.ps1'
        $script:app = $script:AppRuns['app.ps1'].Process
        $end = (Get-Date).AddSeconds(90)
        while ((Get-Date) -lt $end -and -not ((Test-Path -LiteralPath $pidFile) -and (Get-Content -LiteralPath $pidFile -ErrorAction SilentlyContinue))) { Start-Sleep -Milliseconds 300 }
        # The object of the child is taken while the child runs, so it keeps naming that very process.
        $script:child = Get-Process -Id ([int](Get-Content -LiteralPath $pidFile))
        $null = $script:child.Handle
        $script:recordedParent = [int](Get-CimInstance Win32_Process -Filter ('ProcessId=' + $script:strangers[0].Id)).ParentProcessId
        Stop-App 'app.ps1'
    }
    AfterAll {
        if ($script:AppRuns -and $script:AppRuns['app.ps1']) { Stop-JobProcess -Run $script:AppRuns['app.ps1'] }
        foreach ($s in $script:strangers) { if (-not $s.HasExited) { $s.Kill() } }
    }

    It 'has a stranger that records the app as its parent' {
        $script:recordedParent | Should -Be $script:app.Id
    }
    It 'ends the app' {
        $script:app.WaitForExit(15000) | Should -BeTrue
    }
    It 'ends the process that the app started' {
        $script:child.WaitForExit(15000) | Should -BeTrue
    }
    It 'leaves the stranger alive' {
        $script:strangers[0].WaitForExit(3000) | Should -BeFalse
    }
    It 'can stop the app again' {
        { Stop-App 'app.ps1' } | Should -Not -Throw
    }
}
