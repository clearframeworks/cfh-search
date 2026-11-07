Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$source = @"
using System;
using System.Drawing;
using System.IO;
using System.Text;
using System.Diagnostics;
using System.Threading.Tasks;
using System.Windows.Forms;

public sealed class CfhSearchForm : Form {
    readonly TextBox folder = new TextBox(), query = new TextBox(), results = new TextBox();
    readonly Label status = new Label();
    readonly Button search = new Button(), cancel = new Button();
    readonly string executable;
    Process worker;
    readonly StringBuilder collected = new StringBuilder();
    readonly object gate = new object();
    bool truncated;

    public CfhSearchForm(string executablePath) {
        executable = executablePath;
        Text = "CFH Search"; Name = "CfhSearch"; StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(760, 570); MinimumSize = new Size(640, 500); Font = new Font("Segoe UI", 10);
        var title = new Label { Text="Find text in files", Font=new Font("Segoe UI", 16, FontStyle.Bold), AutoSize=true, Location=new Point(20,15) };
        var intro = new Label { Text="Search a folder for exact text. Files are read, not changed.", AutoSize=true, Location=new Point(22,50) };
        var folderLabel = new Label { Text="Folder", AutoSize=true, Location=new Point(22,85) };
        folder.SetBounds(25,110,580,28); folder.Anchor=AnchorStyles.Top|AnchorStyles.Left|AnchorStyles.Right; folder.AccessibleName="Folder";
        var browse = new Button { Text="Browse...", Location=new Point(615,106), Size=new Size(120,34), Anchor=AnchorStyles.Top|AnchorStyles.Right };
        browse.Click += (s,e) => { using (var dialog = new FolderBrowserDialog()) { if (dialog.ShowDialog(this)==DialogResult.OK) folder.Text=dialog.SelectedPath; } };
        var queryLabel = new Label { Text="Text to find", AutoSize=true, Location=new Point(22,150) };
        query.SetBounds(25,175,580,28); query.Anchor=AnchorStyles.Top|AnchorStyles.Left|AnchorStyles.Right; query.AccessibleName="Text to find";
        search.Text="Search"; search.SetBounds(615,171,120,34); search.Anchor=AnchorStyles.Top|AnchorStyles.Right; search.Click += StartSearch;
        cancel.Text="Stop"; cancel.SetBounds(615,213,120,34); cancel.Anchor=AnchorStyles.Top|AnchorStyles.Right; cancel.Enabled=false; cancel.Click += StopSearch;
        status.Text="Choose a folder and enter text."; status.SetBounds(25,218,575,30); status.Anchor=AnchorStyles.Top|AnchorStyles.Left|AnchorStyles.Right;
        results.SetBounds(25,255,710,290); results.Multiline=true; results.ReadOnly=true; results.ScrollBars=ScrollBars.Both; results.WordWrap=false; results.Anchor=AnchorStyles.Top|AnchorStyles.Bottom|AnchorStyles.Left|AnchorStyles.Right; results.AccessibleName="Search results";
        Controls.AddRange(new Control[]{title,intro,folderLabel,folder,browse,queryLabel,query,search,cancel,status,results});
        AcceptButton=search; FormClosing += (s,e) => { if (worker != null && !worker.HasExited) worker.Kill(); };
    }
    static string Quote(string value) {
        var b=new StringBuilder("\""); int slashes=0;
        foreach(char c in value) {
            if(c=='\\') { slashes++; continue; }
            if(c=='\"') { b.Append('\\', slashes*2+1); b.Append('\"'); slashes=0; continue; }
            b.Append('\\',slashes); slashes=0; b.Append(c);
        }
        b.Append('\\',slashes*2); b.Append('\"'); return b.ToString();
    }
    async Task Drain(StreamReader reader) {
        char[] buffer = new char[4096];
        int count;
        while ((count = await reader.ReadAsync(buffer, 0, buffer.Length)) > 0) {
            lock (gate) {
                int available = 1000000 - collected.Length;
                int take = Math.Min(available, count);
                if (take > 0) collected.Append(buffer, 0, take);
                if (take < count) truncated = true;
            }
        }
    }
    void StartSearch(object sender, EventArgs e) {
        if (!Directory.Exists(folder.Text)) { status.Text="Choose an existing folder."; return; }
        if (String.IsNullOrWhiteSpace(query.Text)) { status.Text="Enter text to find."; return; }
        if (!File.Exists(executable)) { status.Text="Search engine is missing. Reinstall CFH Search."; return; }
        lock(gate) { collected.Clear(); truncated=false; }
        results.Clear(); search.Enabled=false; cancel.Enabled=true; status.Text="Searching...";
        worker=new Process(); worker.StartInfo=new ProcessStartInfo { FileName=executable, Arguments="--line-number --fixed-strings --no-heading --color never -- " + Quote(query.Text) + " " + Quote(folder.Text), UseShellExecute=false, CreateNoWindow=true, RedirectStandardOutput=true, RedirectStandardError=true };
        try {
            worker.Start();
            Process running = worker;
            Task stdout = Drain(running.StandardOutput);
            Task stderr = Drain(running.StandardError);
            Task.Run(async () => {
                running.WaitForExit();
                await Task.WhenAll(stdout, stderr);
                int code = running.ExitCode;
                string output; bool cut;
                lock(gate) { output=collected.ToString(); cut=truncated; }
                if(IsDisposed || Disposing) return;
                try { BeginInvoke((Action)(() => { results.Text=output; search.Enabled=true; cancel.Enabled=false; status.Text=code==0 ? (cut ? "Search finished; results limited to 1 million characters." : "Search finished.") : code==1 ? "No matches found." : "Search stopped or could not finish. See details below."; })); }
                catch(InvalidOperationException) { }
            });
        }
        catch(Exception ex) { search.Enabled=true; cancel.Enabled=false; status.Text="Could not start search: "+ex.Message; }
    }
    void StopSearch(object sender, EventArgs e) { if(worker != null && !worker.HasExited) worker.Kill(); }
}
"@
Add-Type -TypeDefinition $source -ReferencedAssemblies System.Windows.Forms,System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run((New-Object CfhSearchForm (Join-Path $PSScriptRoot 'rg.exe')))