#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$OfficialDatPath,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [Parameter(Mandatory=$true)][string]$SelectedProfilePath
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$ExpectedOfficialHash='289B143A466FD08102BEB72210988BED37792E1762BB863F9B85916D8F7CE8D9'
$ReleaseVersion='26.20.15.07-261015a-205306C-AMD-Software-Adrenalin-Edition'
function Get-SHA256File([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()}
function Get-Sha256Bytes([byte[]]$Bytes){$s=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($s.ComputeHash($Bytes))).Replace('-','')}finally{$s.Dispose()}}
$helperSource = @'
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

public sealed class DatRecord2692
{
    public int Device;
    public int Revision;

    public DatRecord2692(int device, int revision)
    {
        Device = device;
        Revision = revision;
    }
}

public static class Amd2692DatClosure
{
    private const ulong K0 = 0xD6D018F5UL;
    private const ulong K1 = 0xA2AA033BUL;
    private const ulong K2 = 0x62992FC1UL;
    private const ulong K3 = 0x30BC5B29UL;

    private static ulong Ror(ulong value, int bits)
    {
        return (value >> bits) | (value << (64 - bits));
    }

    private static ulong U64(byte[] data, int offset)
    {
        return BitConverter.ToUInt64(data, offset);
    }

    private static uint U32(byte[] data, int offset)
    {
        return BitConverter.ToUInt32(data, offset);
    }

    private static ushort U16(byte[] data, int offset)
    {
        return BitConverter.ToUInt16(data, offset);
    }

    private static ulong MetroHash64(byte[] data)
    {
        unchecked
        {
            int length = data.Length;
            int offset = 0;
            ulong hash = K2 * K0;

            if (length >= 32)
            {
                ulong v0 = hash;
                ulong v1 = hash;
                ulong v2 = hash;
                ulong v3 = hash;
                int end = length - 32;

                while (offset <= end)
                {
                    v0 += U64(data, offset) * K0;
                    offset += 8;
                    v0 = Ror(v0, 29) + v2;

                    v1 += U64(data, offset) * K1;
                    offset += 8;
                    v1 = Ror(v1, 29) + v3;

                    v2 += U64(data, offset) * K2;
                    offset += 8;
                    v2 = Ror(v2, 29) + v0;

                    v3 += U64(data, offset) * K3;
                    offset += 8;
                    v3 = Ror(v3, 29) + v1;
                }

                v2 ^= Ror(((v0 + v3) * K0) + v1, 37) * K1;
                v3 ^= Ror(((v1 + v2) * K1) + v0, 37) * K0;
                v0 ^= Ror(((v0 + v2) * K0) + v3, 37) * K1;
                v1 ^= Ror(((v1 + v3) * K1) + v2, 37) * K0;

                hash += v0 ^ v1;
            }

            int remaining = length - offset;

            if (remaining >= 16)
            {
                ulong v0 = hash + (U64(data, offset) * K2);
                offset += 8;
                v0 = Ror(v0, 29) * K3;

                ulong v1 = hash + (U64(data, offset) * K2);
                offset += 8;
                v1 = Ror(v1, 29) * K3;

                v0 ^= Ror(v0 * K0, 21) + v1;
                v1 ^= Ror(v1 * K3, 21) + v0;
                hash += v1;

                remaining = length - offset;
            }

            if (remaining >= 8)
            {
                hash += U64(data, offset) * K3;
                offset += 8;
                hash ^= Ror(hash, 55) * K1;
                remaining = length - offset;
            }

            if (remaining >= 4)
            {
                hash += U32(data, offset) * K3;
                offset += 4;
                hash ^= Ror(hash, 26) * K1;
                remaining = length - offset;
            }

            if (remaining >= 2)
            {
                hash += U16(data, offset) * K3;
                offset += 2;
                hash ^= Ror(hash, 48) * K1;
                remaining = length - offset;
            }

            if (remaining >= 1)
            {
                hash += (ulong)data[offset] * K3;
                hash ^= Ror(hash, 37) * K1;
            }

            hash ^= Ror(hash, 28);
            hash *= K0;
            hash ^= Ror(hash, 29);

            return hash;
        }
    }

    private static byte[] HeaderFor(byte[] recordBytes, string releaseVersion)
    {
        byte[] versionBytes = Encoding.ASCII.GetBytes(releaseVersion);
        byte[] input = new byte[recordBytes.Length + versionBytes.Length];

        Buffer.BlockCopy(recordBytes, 0, input, 0, recordBytes.Length);
        Buffer.BlockCopy(versionBytes, 0, input, recordBytes.Length, versionBytes.Length);

        byte[] header = BitConverter.GetBytes(MetroHash64(input));
        if (BitConverter.IsLittleEndian)
            Array.Reverse(header);

        return header;
    }

    private static int Compare(DatRecord2692 a, DatRecord2692 b)
    {
        int d = a.Device.CompareTo(b.Device);
        if (d != 0)
            return d;

        return a.Revision.CompareTo(b.Revision);
    }

    public static List<DatRecord2692> Parse(byte[] source)
    {
        if (source == null)
            throw new ArgumentNullException("source");

        if (source.Length < 12)
            throw new InvalidOperationException("DAT is shorter than its header.");

        uint count = BitConverter.ToUInt32(source, 0);
        int expectedLength = checked(12 + (3 * (int)count));

        if (source.Length != expectedLength)
            throw new InvalidOperationException(
                "DAT shape mismatch. Count=" + count +
                " ExpectedLength=" + expectedLength +
                " ActualLength=" + source.Length);

        var rows = new List<DatRecord2692>((int)count);

        for (int i = 0; i < count; i++)
        {
            int position = 12 + (3 * i);
            ushort storedOffset = BitConverter.ToUInt16(source, position);
            int device = (int)storedOffset - position;
            int revision = source[position + 2];

            if (device < 0 || device > 0xFFFF)
                throw new InvalidOperationException("Invalid decoded device at index " + i + ".");

            rows.Add(new DatRecord2692(device, revision));
        }

        for (int i = 1; i < rows.Count; i++)
        {
            if (Compare(rows[i - 1], rows[i]) >= 0)
                throw new InvalidOperationException("Source DAT is not strictly ordered at index " + i + ".");
        }

        return rows;
    }

    public static bool Contains(List<DatRecord2692> rows, int device, int revision)
    {
        return rows.Any(r => r.Device == device && r.Revision == revision);
    }

    public static string VerifyOfficialHeader(byte[] source, string releaseVersion)
    {
        byte[] recordBytes = new byte[source.Length - 12];
        Buffer.BlockCopy(source, 12, recordBytes, 0, recordBytes.Length);

        byte[] computed = HeaderFor(recordBytes, releaseVersion);
        byte[] stored = new byte[8];
        Buffer.BlockCopy(source, 4, stored, 0, 8);

        string computedHex = BitConverter.ToString(computed).Replace("-", "");
        string storedHex = BitConverter.ToString(stored).Replace("-", "");

        if (!String.Equals(computedHex, storedHex, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException(
                "Release seed does not verify. Stored=" + storedHex + " Computed=" + computedHex);

        return storedHex;
    }

    public static byte[] Build(
        List<DatRecord2692> sourceRows,
        int firstDevice,
        int firstRevision,
        int secondDevice,
        int secondRevision,
        string releaseVersion)
    {
        if (Contains(sourceRows, firstDevice, firstRevision))
            throw new InvalidOperationException(
                String.Format("Source already contains DEV_{0:X4}/REV_{1:X2}.", firstDevice, firstRevision));

        if (Contains(sourceRows, secondDevice, secondRevision))
            throw new InvalidOperationException(
                String.Format("Source already contains DEV_{0:X4}/REV_{1:X2}.", secondDevice, secondRevision));

        var rows = sourceRows
            .Select(r => new DatRecord2692(r.Device, r.Revision))
            .ToList();

        rows.Add(new DatRecord2692(firstDevice, firstRevision));
        rows.Add(new DatRecord2692(secondDevice, secondRevision));
        rows.Sort(Compare);

        for (int i = 1; i < rows.Count; i++)
        {
            if (Compare(rows[i - 1], rows[i]) >= 0)
                throw new InvalidOperationException("Final DAT is not strictly ordered at index " + i + ".");
        }

        byte[] output = new byte[12 + (3 * rows.Count)];
        Buffer.BlockCopy(BitConverter.GetBytes((uint)rows.Count), 0, output, 0, 4);

        for (int i = 0; i < rows.Count; i++)
        {
            int position = 12 + (3 * i);
            int storedOffset = rows[i].Device + position;

            if (storedOffset < 0 || storedOffset > 0xFFFF)
                throw new InvalidOperationException("Stored-offset overflow at index " + i + ".");

            Buffer.BlockCopy(BitConverter.GetBytes((ushort)storedOffset), 0, output, position, 2);
            output[position + 2] = (byte)rows[i].Revision;
        }

        byte[] finalRecordBytes = new byte[output.Length - 12];
        Buffer.BlockCopy(output, 12, finalRecordBytes, 0, finalRecordBytes.Length);

        byte[] header = HeaderFor(finalRecordBytes, releaseVersion);
        Buffer.BlockCopy(header, 0, output, 4, 8);

        return output;
    }
}
'@

Add-Type -TypeDefinition $helperSource -Language CSharp
if(-not(Test-Path -LiteralPath $SelectedProfilePath -PathType Leaf)){throw "Selected profile is missing: $SelectedProfilePath"}
$Profile=Get-Content -LiteralPath $SelectedProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
if(-not [bool]$Profile.InstallCapable){throw "Selected profile is not install-capable: $([string]$Profile.Id)"}

$FirstDevice=0
$FirstRevision=0
$ExpectedDatDevice=''
$ExpectedDatRevision=''
$ExpectedFinalHash=''

switch([string]$Profile.Id){
    'LegionGo1' {
        $FirstDevice=0x15BF;$FirstRevision=0x04
        $ExpectedDatDevice='15BF';$ExpectedDatRevision='04'
        $ExpectedFinalHash='B928E5C32E85895A1C8EF20FBC90D3348C593AF88A1C6BF94E9A6B6E4A650E32'
    }
    'LegionGoS-Z1Extreme' {
        $FirstDevice=0x15BF;$FirstRevision=0x04
        $ExpectedDatDevice='15BF';$ExpectedDatRevision='04'
        $ExpectedFinalHash='B928E5C32E85895A1C8EF20FBC90D3348C593AF88A1C6BF94E9A6B6E4A650E32'
    }
    'LegionGo2-Z2Extreme' {
        $FirstDevice=0x150E;$FirstRevision=0xC5
        $ExpectedDatDevice='150E';$ExpectedDatRevision='C5'
        $ExpectedFinalHash='CDF57D74268F3CB763A996C16811CCB26F4055750743EEB68D03D8D686A2EC02'
    }
    default { throw "Unsupported selected profile for DAT build: $([string]$Profile.Id)" }
}

if(([string]$Profile.Dat.DeviceIdHex).ToUpperInvariant() -cne $ExpectedDatDevice){throw 'Profile DAT device changed.'}
if(([string]$Profile.Dat.RevisionHex).ToUpperInvariant() -cne $ExpectedDatRevision){throw 'Profile DAT revision changed.'}
if(([string]$Profile.Final.ExpectedDatSHA256).ToUpperInvariant() -cne $ExpectedFinalHash){throw 'Profile final DAT hash changed.'}
if((Get-SHA256File $OfficialDatPath) -cne $ExpectedOfficialHash){throw 'Official 26.10.1 DAT hash mismatch.'}

[byte[]]$Official=[IO.File]::ReadAllBytes($OfficialDatPath)
if($Official.Length -ne 693){throw "Official DAT length mismatch. Expected=693 Actual=$($Official.Length)"}
$Rows=[Amd2692DatClosure]::Parse($Official)
if($Rows.Count -ne 227){throw "Official DAT record-count mismatch. Expected=227 Actual=$($Rows.Count)"}
$Header=[Amd2692DatClosure]::VerifyOfficialHeader($Official,$ReleaseVersion)
if($Header -cne 'FA9EE7461186222C'){throw "Official DAT release seed/header mismatch: $Header"}

[byte[]]$Built=[Amd2692DatClosure]::Build($Rows,$FirstDevice,$FirstRevision,0x15C8,0xC9,$ReleaseVersion)
$Count=[BitConverter]::ToUInt32($Built,0)
$Hash=Get-Sha256Bytes $Built
if($Hash -cne $ExpectedFinalHash -or $Built.Length -ne 699 -or $Count -ne 229){throw "Final DAT mismatch. Hash=$Hash Length=$($Built.Length) Count=$Count"}

$Parent=Split-Path -Parent $OutputPath
if(-not(Test-Path -LiteralPath $Parent -PathType Container)){New-Item -ItemType Directory -Path $Parent -Force|Out-Null}
[IO.File]::WriteAllBytes($OutputPath,$Built)
if((Get-SHA256File $OutputPath) -cne $ExpectedFinalHash){throw 'Written final DAT hash changed.'}
Write-Host ("[PASS] Deterministic {0} AMD 26.10.1 DAT: {1}" -f [string]$Profile.Id,$ExpectedFinalHash)
