using System;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Diagnostics;
using System.Windows.Forms;
internal static class Launcher {
 const string BundleHash="BUNDLE_HASH";
 static byte[] Bundle() {
  using(var s=Assembly.GetExecutingAssembly().GetManifestResourceStream("bundle.zip"))
  using(var m=new MemoryStream()) { s.CopyTo(m); byte[] b=m.ToArray();
   using(var h=SHA256.Create()) if(BitConverter.ToString(h.ComputeHash(b)).Replace("-","")!=BundleHash) throw new Exception("Embedded payload integrity check failed."); return b;
  }
 }
 static bool Admin() { return new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator); }
 static void CheckPath(string path) {
  string p=Path.GetFullPath(path);
  while(!String.IsNullOrEmpty(p)) {
   if((Directory.Exists(p)||File.Exists(p))&&(File.GetAttributes(p)&FileAttributes.ReparsePoint)!=0)throw new Exception("Reparse point rejected: "+p);
   p=Path.GetDirectoryName(p);
  }
 }
 static void Protect(string root) {
  CheckPath(root);
  if(Directory.Exists(root)) {
   var existing=Directory.GetAccessControl(root);
   string owner=existing.GetOwner(typeof(SecurityIdentifier)).Value;
   if(owner!="S-1-5-18"&&owner!="S-1-5-32-544")throw new Exception("Untrusted application directory owner.");
   foreach(FileSystemAccessRule r in existing.GetAccessRules(true,true,typeof(SecurityIdentifier))) {
    var mask=FileSystemRights.Write|FileSystemRights.Delete|FileSystemRights.ChangePermissions|FileSystemRights.TakeOwnership;
    if(r.AccessControlType==AccessControlType.Allow&&(r.FileSystemRights&mask)!=0&&r.IdentityReference.Value!="S-1-5-18"&&r.IdentityReference.Value!="S-1-5-32-544")throw new Exception("Untrusted application directory permissions.");
   }
  } else Directory.CreateDirectory(root);
  var acl=new DirectorySecurity(); acl.SetOwner(new SecurityIdentifier("S-1-5-32-544")); acl.SetAccessRuleProtection(true,false);
  foreach(string sid in new[]{"S-1-5-18","S-1-5-32-544"})acl.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(sid),FileSystemRights.FullControl,InheritanceFlags.ContainerInherit|InheritanceFlags.ObjectInherit,PropagationFlags.None,AccessControlType.Allow));
  acl.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier("S-1-5-32-545"),FileSystemRights.ReadAndExecute,InheritanceFlags.ContainerInherit|InheritanceFlags.ObjectInherit,PropagationFlags.None,AccessControlType.Allow));
  Directory.SetAccessControl(root,acl);
 }
 [STAThread] static int Main(string[] args) {
  try {
   byte[] bundle=Bundle();
   if(args.Length==1&&args[0]=="--self-test") { using(var z=new ZipArchive(new MemoryStream(bundle),ZipArchiveMode.Read)) { if(z.GetEntry("src/App.ps1")==null||z.GetEntry("config/release.json")==null)throw new Exception("Required embedded files missing."); Console.WriteLine("Go2FSR4 embedded bundle verified: "+BundleHash+"; files="+z.Entries.Count); } return 0; }
   if(args.Length!=0)throw new Exception("Unsupported launcher argument.");
   if(!Admin()) {
    var elevate=new ProcessStartInfo(Assembly.GetExecutingAssembly().Location); elevate.UseShellExecute=true; elevate.Verb="runas";
    using(var p=Process.Start(elevate)){p.WaitForExit();return p.ExitCode;}
   }
   string root=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"Go2FSR4"); Protect(root);
   string app=Path.Combine(root,BundleHash); CheckPath(app); Directory.CreateDirectory(app);
   using(var z=new ZipArchive(new MemoryStream(bundle),ZipArchiveMode.Read))foreach(var entry in z.Entries) {
    if(entry.FullName.Contains(":"))throw new Exception("Invalid archive entry.");
    string dest=Path.GetFullPath(Path.Combine(app,entry.FullName));
    if(!dest.StartsWith(app+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new Exception("Archive traversal rejected.");
    CheckPath(dest);
    if(entry.FullName.EndsWith("/")){Directory.CreateDirectory(dest);continue;}
    Directory.CreateDirectory(Path.GetDirectoryName(dest));
    using(var input=entry.Open())using(var output=new FileStream(dest,FileMode.Create,FileAccess.Write,FileShare.None))input.CopyTo(output);
   }
   string powershell=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),"System32/WindowsPowerShell/v1.0/powershell.exe");
   var launch=new ProcessStartInfo(powershell,"-NoProfile -ExecutionPolicy Bypass -STA -File \""+Path.Combine(app,"src/App.ps1")+"\"");
   launch.UseShellExecute=false; launch.CreateNoWindow=true; launch.WorkingDirectory=app;
   using(var p=Process.Start(launch)){p.WaitForExit();return p.ExitCode;}
  } catch(Exception e) { if(args.Length==1&&args[0]=="--self-test")Console.Error.WriteLine(e.Message);else MessageBox.Show(e.Message,"Go2FSR4 stopped",MessageBoxButtons.OK,MessageBoxIcon.Error);return 1; }
 }
}
