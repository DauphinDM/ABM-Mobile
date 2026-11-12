package io.github.dauphindm.abmmobile;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;
import java.io.*;
import java.security.MessageDigest;

/** A single private, read-only APK grant; never a generic file provider. */
public final class UpdateProvider extends ContentProvider {
    private static File apk(Context context) { return new File(context.getCacheDir(), "abm-update/ABM-Mobile.apk"); }
    public static String offerInstall(Context context, String source, String expected) {
        if (!expected.matches("[a-f0-9]{64}")) return "Invalid update digest.";
        File temporary=null;
        try {
            File input=new File(source).getCanonicalFile();
            if (!input.getPath().startsWith(context.getFilesDir().getCanonicalPath()+File.separator)) return "Update is outside private app storage.";
            if (!input.isFile() || input.length()<1 || input.length()>512L*1024*1024) return "Invalid APK size.";
            File target=apk(context);
            if (!target.getParentFile().isDirectory() && !target.getParentFile().mkdirs()) return "Cannot create installer staging folder.";
            temporary=File.createTempFile("download-", ".apk", target.getParentFile());
            MessageDigest digest=MessageDigest.getInstance("SHA-256");
            long total=0;
            try (InputStream in=new FileInputStream(input); FileOutputStream out=new FileOutputStream(temporary)) {
                byte[] buffer=new byte[65536]; int n;
                while ((n=in.read(buffer))!=-1) {
                    total+=n; if (total>512L*1024*1024) throw new IOException("APK too large");
                    digest.update(buffer,0,n); out.write(buffer,0,n);
                }
                out.getFD().sync();
            }
            StringBuilder actual=new StringBuilder();
            for (byte b:digest.digest()) actual.append(String.format(java.util.Locale.ROOT,"%02x",b&255));
            if (!actual.toString().equals(expected)) return "Update changed. Download it again.";
            PackageManager manager=context.getPackageManager();
            PackageInfo candidate=manager.getPackageArchiveInfo(temporary.getPath(),PackageManager.GET_SIGNING_CERTIFICATES);
            PackageInfo installed=manager.getPackageInfo(context.getPackageName(),PackageManager.GET_SIGNING_CERTIFICATES);
            if (candidate==null || !context.getPackageName().equals(candidate.packageName) || candidate.signingInfo==null || installed.signingInfo==null) return "APK does not match this application.";
            if (candidate.getLongVersionCode()<installed.getLongVersionCode()) return "APK is older than this installation.";
            Signature[] incoming=candidate.signingInfo.getApkContentsSigners(), current=installed.signingInfo.getApkContentsSigners();
            java.util.HashSet<String> a=new java.util.HashSet<>(), b=new java.util.HashSet<>();
            for(Signature s:incoming) a.add(s.toCharsString());
            for(Signature s:current) b.add(s.toCharsString());
            if(a.isEmpty() || !a.equals(b)) return "APK signing certificate differs. No installation or uninstall was attempted.";
            if (!temporary.renameTo(target)) return "Cannot stage APK for installation.";
            Uri uri=Uri.parse("content://"+context.getPackageName()+".abmupdates/apk");
            Intent intent=new Intent(Intent.ACTION_VIEW).setDataAndType(uri,"application/vnd.android.package-archive");
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_GRANT_READ_URI_PERMISSION);
            context.startActivity(intent);
            return "Android installer opened. Allow installation from ABM if prompted; the APK must have the same signing certificate.";
        } catch (Exception error) { return "Could not open Android installer. Check install-source permission and try again."; }
        finally { if (temporary!=null && temporary.exists()) temporary.delete(); }
    }
    private void check(Uri uri) {
        if (!"content".equals(uri.getScheme()) || !(getContext().getPackageName()+".abmupdates").equals(uri.getAuthority()) || !"/apk".equals(uri.getPath()) || uri.getQuery()!=null || uri.getFragment()!=null) throw new IllegalArgumentException("Unknown update URI");
    }
    @Override public boolean onCreate() { return true; }
    @Override public String getType(Uri uri) { check(uri); return "application/vnd.android.package-archive"; }
    @Override public Cursor query(Uri uri,String[] projection,String selection,String[] args,String sort) {
        check(uri); String[] columns=projection==null ? new String[]{OpenableColumns.DISPLAY_NAME,OpenableColumns.SIZE} : projection;
        MatrixCursor cursor=new MatrixCursor(columns); Object[] row=new Object[columns.length];
        for(int i=0;i<columns.length;i++) { if(columns[i].equals(OpenableColumns.DISPLAY_NAME)) row[i]="ABM-Mobile.apk"; else if(columns[i].equals(OpenableColumns.SIZE)) row[i]=apk(getContext()).length(); }
        cursor.addRow(row); return cursor;
    }
    @Override public ParcelFileDescriptor openFile(Uri uri,String mode) throws FileNotFoundException {
        check(uri); if(!"r".equals(mode)) throw new FileNotFoundException("Read only");
        return ParcelFileDescriptor.open(apk(getContext()),ParcelFileDescriptor.MODE_READ_ONLY);
    }
    @Override public Uri insert(Uri uri,ContentValues values) { throw new UnsupportedOperationException(); }
    @Override public int update(Uri uri,ContentValues values,String selection,String[] args) { throw new UnsupportedOperationException(); }
    @Override public int delete(Uri uri,String selection,String[] args) { throw new UnsupportedOperationException(); }
}
