using System;
using System.Runtime.InteropServices;
class Probe {
 [DllImport("d3d12.dll")] static extern int D3D12CreateDevice(IntPtr adapter, uint level, ref Guid iid, out IntPtr device);
 [DllImport("amd_fidelityfx_loader_dx12.dll", CallingConvention=CallingConvention.Cdecl)] static extern uint ffxQuery(IntPtr context, ref Versions desc);
 [DllImport("amd_fidelityfx_loader_dx12.dll", CallingConvention=CallingConvention.Cdecl)] static extern uint ffxCreateContext(out IntPtr context, ref Create desc, IntPtr callbacks);
 [DllImport("amd_fidelityfx_loader_dx12.dll", CallingConvention=CallingConvention.Cdecl)] static extern uint ffxDestroyContext(ref IntPtr context, IntPtr callbacks);
 [StructLayout(LayoutKind.Sequential)] struct Backend {public ulong type;public IntPtr next,device;}
 [StructLayout(LayoutKind.Sequential)] struct Override {public ulong type;public IntPtr next;public ulong id;}
 [StructLayout(LayoutKind.Sequential)] struct Create {public ulong type;public IntPtr next;public uint flags,rw,rh,ow,oh;public IntPtr message;}
 [StructLayout(LayoutKind.Sequential)] struct Versions {
  public ulong type; public IntPtr next; public ulong effect; public IntPtr device,count,ids,names;
 }
 static int Main() {
  IntPtr device=IntPtr.Zero, count=IntPtr.Zero, ids=IntPtr.Zero, names=IntPtr.Zero;
  try {
   Guid iid=new Guid("189819f1-1db6-4b57-be54-1821339b85f7");
   int hr=D3D12CreateDevice(IntPtr.Zero,0xc000,ref iid,out device);
   Console.WriteLine("D3D12CreateDevice HRESULT: 0x"+hr.ToString("X8"));
   if(hr<0) return 1;
   count=Marshal.AllocHGlobal(8); Marshal.WriteInt64(count,0);
   Versions q=new Versions{type=4,effect=0x10000,device=device,count=count};
   uint result=ffxQuery(IntPtr.Zero,ref q);
   long n=Marshal.ReadInt64(count);
   Console.WriteLine("FSR query result: "+result+"; provider count: "+n);
   if(result!=0 || n<1 || n>32) return 2;
   ids=Marshal.AllocHGlobal((int)n*8); names=Marshal.AllocHGlobal((int)n*8);q.ids=ids;q.names=names;
   result=ffxQuery(IntPtr.Zero,ref q);
   Console.WriteLine("FSR enumeration result: "+result);
   if(result!=0) return 3;
   ulong selectedId=0; string selectedName=null;
   for(int i=0;i<Marshal.ReadInt64(count);i++) {
    string name=Marshal.PtrToStringAnsi(Marshal.ReadIntPtr(names,i*8));
    ulong id=(ulong)Marshal.ReadInt64(ids,i*8);
    Console.WriteLine("Provider: "+name+"; id=0x"+id.ToString("X"));
    if(name=="4.1.2" || name=="4.1.2 *"){selectedId=id;selectedName=name;}
   }
   if(selectedName==null){Console.WriteLine("FSR 4.1.2 is NOT offered by these DLLs on this device. No fallback context will be created.");return 6;}
   Console.WriteLine("Selected exact provider: "+selectedName+"; id=0x"+selectedId.ToString("X"));
   IntPtr bp=Marshal.AllocHGlobal(Marshal.SizeOf(typeof(Backend))),op=Marshal.AllocHGlobal(Marshal.SizeOf(typeof(Override))),ctx=IntPtr.Zero;
   try {
    Marshal.StructureToPtr(new Backend{type=2,device=device},bp,false);
    Marshal.StructureToPtr(new Override{type=5,next=bp,id=selectedId},op,false);
    Create create=new Create{type=0x10000,next=op,flags=32,rw=640,rh=360,ow=960,oh=540};
    result=ffxCreateContext(out ctx,ref create,IntPtr.Zero);
    Console.WriteLine("Explicit FSR 4.1.2 context creation result: "+result+"; context valid: "+(ctx!=IntPtr.Zero));
    if(result!=0)return 5;
   } finally {if(ctx!=IntPtr.Zero)Console.WriteLine("Context destroy: "+ffxDestroyContext(ref ctx,IntPtr.Zero));Marshal.FreeHGlobal(op);Marshal.FreeHGlobal(bp);}
   return 0;
  } catch(Exception e){Console.WriteLine(e);return 4;}
  finally {if(names!=IntPtr.Zero)Marshal.FreeHGlobal(names);if(ids!=IntPtr.Zero)Marshal.FreeHGlobal(ids);if(count!=IntPtr.Zero)Marshal.FreeHGlobal(count);if(device!=IntPtr.Zero)Marshal.Release(device);}
 }
}

