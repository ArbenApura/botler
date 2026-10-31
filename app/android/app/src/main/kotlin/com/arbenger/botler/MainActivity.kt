package com.arbenger.botler

import android.content.ClipboardManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.StatFs
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

// local_auth (fingerprint and face) needs a FragmentActivity
class MainActivity : FlutterFragmentActivity() {
    // -- APP UPDATE CHANNEL -- //
    // Everything the in-app update needs from Android: the installed build, the cache folder, a check of the downloaded file
    // (package, version and signing certificate against the installed app), and the system installer. Dart never touches a path
    // outside the update folder, and the installer is only opened from a tap.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        clipboardChannel(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.arbenger.botler/update")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "installedCode" -> result.success(installedCode())
                        "installedName" -> result.success(packageManager.getPackageInfo(packageName, 0).versionName ?: "")
                        "updateDir" -> result.success(updateDir().absolutePath)
                        "freeBytes" -> result.success(StatFs(cacheDir.absolutePath).availableBytes)
                        // The architectures of this phone, most preferred first: the server then offers only the matching build
                        "abis" -> result.success(Build.SUPPORTED_ABIS.toList())
                        "archiveCheck" -> {
                            // Reading the certificates hashes the whole file (tens of MB): off the main thread, so the screen never freezes
                            val path = call.argument<String>("path") ?: ""
                            val code = (call.argument<Number>("code") ?: 0).toLong()
                            Thread {
                                val verdict = try {
                                    archiveCheck(path, code)
                                } catch (e: Exception) {
                                    "unreadable"
                                }
                                runOnUiThread { result.success(verdict) }
                            }.start()
                        }
                        "canInstall" -> result.success(canInstall())
                        "openInstallSettings" -> {
                            // The per-app switch exists from Android 8; before that the installer asks by itself
                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                                result.success(false)
                                return@setMethodCallHandler
                            }
                            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        }
                        "install" -> result.success(install(call.argument<String>("path") ?: ""))
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    // The class name only: a message could hold a path
                    result.error("update", e.javaClass.simpleName, null)
                }
            }
    }

    // -- CLIPBOARD PICTURE CHANNEL -- //
    // A picture on the clipboard (a copied screenshot or image) is copied into the cache "paste" folder by this side, so the bytes never
    // cross the channel and Dart gets only a path. Nothing is read until the person taps Paste.
    private fun clipboardChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.arbenger.botler/clipboard")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "hasImage" -> result.success(clipboardImageUri() != null)
                        "saveImage" -> {
                            val uri = clipboardImageUri()
                            val max = (call.argument<Number>("maxBytes") ?: 0).toLong()
                            if (uri == null) {
                                result.success(null)
                                return@setMethodCallHandler
                            }
                            // Copying a large picture off the main thread
                            Thread {
                                val path = try {
                                    copyClipboardImage(uri, max)
                                } catch (e: Exception) {
                                    null
                                }
                                runOnUiThread { result.success(path) }
                            }.start()
                        }
                        "sweep" -> {
                            File(cacheDir, "paste").listFiles()?.forEach { it.delete() }
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    // The class name only: a message could hold a path
                    result.error("clipboard", e.javaClass.simpleName, null)
                }
            }
    }

    // The first image item on the clipboard, or null. Only the description and the item are read, not the picture itself.
    private fun clipboardImageUri(): Uri? {
        val manager = getSystemService(CLIPBOARD_SERVICE) as? ClipboardManager ?: return null
        if (!manager.hasPrimaryClip()) return null
        val description = manager.primaryClipDescription ?: return null
        if (!description.hasMimeType("image/*")) return null
        val clip = manager.primaryClip ?: return null
        for (i in 0 until clip.itemCount) {
            val uri = clip.getItemAt(i).uri ?: continue
            val type = contentResolver.getType(uri) ?: continue
            if (type.startsWith("image/")) return uri
        }
        return null
    }

    // Copies the picture to the cache "paste" folder; null when it is past maxBytes or cannot be read
    private fun copyClipboardImage(uri: Uri, maxBytes: Long): String? {
        val type = contentResolver.getType(uri) ?: return null
        val ext = when (type) {
            "image/png" -> ".png"
            "image/gif" -> ".gif"
            "image/webp" -> ".webp"
            else -> ".jpg"
        }
        val dir = File(cacheDir, "paste").also { it.mkdirs() }
        val out = File(dir, "paste_${System.currentTimeMillis()}$ext")
        var total = 0L
        val input = contentResolver.openInputStream(uri) ?: return null
        input.use { source ->
            out.outputStream().use { sink ->
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val n = source.read(buffer)
                    if (n < 0) break
                    total += n
                    if (maxBytes > 0 && total > maxBytes) {
                        out.delete()
                        return null
                    }
                    sink.write(buffer, 0, n)
                }
            }
        }
        return if (total > 0) out.absolutePath else { out.delete(); null }
    }

    // Android 7 (API 24 and 25) has no per-app install switch: its installer shows its own unknown sources prompt
    private fun canInstall(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()

    private fun updateDir(): File = File(cacheDir, "updates").also { it.mkdirs() }

    @Suppress("DEPRECATION")
    private fun installedCode(): Long {
        val info = packageManager.getPackageInfo(packageName, 0)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode else info.versionCode.toLong()
    }

    // The SHA-256 of every certificate that signs a package, as a sorted set of hex strings
    @Suppress("DEPRECATION")
    private fun certs(info: android.content.pm.PackageInfo?): Set<String> {
        if (info == null) return emptySet()
        // Some phones leave signingInfo empty for a file that is not installed: fall back to the older field
        val signatures = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners ?: info.signatures
        } else {
            info.signatures
        }) ?: return emptySet()
        return signatures.map { s ->
            MessageDigest.getInstance("SHA-256").digest(s.toByteArray()).joinToString("") { "%02x".format(it) }
        }.toSortedSet()
    }

    // Is the downloaded file the same app, newer, and signed by the same key as this one? Returns "ok" or the reason it is not.
    @Suppress("DEPRECATION")
    private fun archiveCheck(path: String, expectedCode: Long): String {
        val file = File(path)
        if (!isInUpdateDir(file) || !file.isFile) return "path"
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES or PackageManager.GET_SIGNATURES
        } else {
            PackageManager.GET_SIGNATURES
        }
        val archive = packageManager.getPackageArchiveInfo(file.absolutePath, flags) ?: return "unreadable"
        if (archive.packageName != packageName) return "package"
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) archive.longVersionCode else archive.versionCode.toLong()
        if (code != expectedCode || code <= installedCode()) return "version"
        val own = certs(packageManager.getPackageInfo(packageName, flags))
        val theirs = certs(archive)
        if (own.isEmpty() || own != theirs) return "signature"
        return "ok"
    }

    private fun isInUpdateDir(file: File): Boolean {
        val root = updateDir().canonicalPath + File.separator
        return file.canonicalPath.startsWith(root)
    }

    // Opens the system installer for a checked file. "needs_permission" when Android has not allowed installs from Botler yet.
    private fun install(path: String): String {
        val file = File(path)
        if (!isInUpdateDir(file) || !file.isFile) return "error"
        if (!canInstall()) return "needs_permission"
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
        return "ok"
    }
}
