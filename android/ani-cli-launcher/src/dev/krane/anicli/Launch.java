package dev.krane.anicli;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.widget.Toast;

/**
 * Runs ani-cli in a foreground Termux session through Termux's RUN_COMMAND intent, then
 * finishes. Needs Termux's allow-external-apps = true and this app's "Run commands in
 * Termux environment" permission, which is requested here when missing.
 */
abstract class Launch extends Activity {
    private static final String PERM = "com.termux.permission.RUN_COMMAND";
    private static final String HOME = "/data/data/com.termux/files/home";

    /** Arguments passed to ani-cli. */
    abstract String[] args();

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        if (checkSelfPermission(PERM) == PackageManager.PERMISSION_GRANTED) {
            run();
        } else {
            requestPermissions(new String[] {PERM}, 0);
        }
    }

    @Override
    public void onRequestPermissionsResult(int code, String[] perms, int[] results) {
        if (results.length > 0 && results[0] == PackageManager.PERMISSION_GRANTED) {
            run();
        } else {
            Toast.makeText(this,
                "Grant \"Run commands in Termux environment\" in the app settings",
                Toast.LENGTH_LONG).show();
            finish();
        }
    }

    private void run() {
        Intent i = new Intent("com.termux.RUN_COMMAND");
        i.setClassName("com.termux", "com.termux.app.RunCommandService");
        i.putExtra("com.termux.RUN_COMMAND_PATH",
            "/data/data/com.termux/files/usr/bin/ani-cli");
        i.putExtra("com.termux.RUN_COMMAND_ARGUMENTS", args());
        i.putExtra("com.termux.RUN_COMMAND_WORKDIR", HOME);
        i.putExtra("com.termux.RUN_COMMAND_BACKGROUND", false);
        // 0 = switch to the new session and open the Termux activity
        i.putExtra("com.termux.RUN_COMMAND_SESSION_ACTION", "0");
        try {
            startService(i);
        } catch (RuntimeException e) {
            Toast.makeText(this, "Termux RUN_COMMAND failed: " + e.getMessage(),
                Toast.LENGTH_LONG).show();
        }
        finish();
    }
}
