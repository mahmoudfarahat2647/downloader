package com.example.downloader

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import androidx.annotation.RequiresApi
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException

object MediaStoreHelper {

    fun saveToDownloads(
        context: Context,
        tempPath: String,
        fileName: String,
        mimeType: String
    ): String {
        val mime = mimeType.ifBlank { mimeFromName(fileName) }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveViaMediaStore(context, tempPath, fileName, mime)
        } else {
            saveLegacy(tempPath, fileName)
        }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun saveViaMediaStore(
        context: Context,
        tempPath: String,
        fileName: String,
        mimeType: String
    ): String {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, fileName)
            put(MediaStore.Downloads.MIME_TYPE, mimeType)
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IOException("Failed to create MediaStore entry")
        try {
            val tempFile = File(tempPath)
            resolver.openOutputStream(uri)?.use { output ->
                FileInputStream(tempFile).use { input ->
                    input.copyTo(output, 8192)
                }
            } ?: throw IOException("Failed to open output stream")
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            try {
                tempFile.delete()
            } catch (_: Exception) {
            }
            return uri.toString()
        } catch (e: Exception) {
            try {
                resolver.delete(uri, null, null)
            } catch (_: Exception) {
            }
            if (e is IOException) throw e
            throw IOException("Failed to save to Downloads: ${e.message}", e)
        }
    }

    private fun saveLegacy(tempPath: String, fileName: String): String {
        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        if (!dir.exists()) {
            dir.mkdirs()
        }
        val target = resolveCollision(dir, fileName)
        try {
            FileInputStream(File(tempPath)).use { input ->
                FileOutputStream(target).use { output ->
                    input.copyTo(output, 8192)
                }
            }
            try {
                File(tempPath).delete()
            } catch (_: Exception) {
            }
            return target.absolutePath
        } catch (e: Exception) {
            try {
                if (target.exists() && target.length() == 0L) {
                    target.delete()
                }
            } catch (_: Exception) {
            }
            if (e is IOException) throw e
            throw IOException("Failed to save to Downloads: ${e.message}", e)
        }
    }

    private fun resolveCollision(dir: File, name: String): File {
        var candidate = File(dir, name)
        if (!candidate.exists()) return candidate
        val dotIndex = name.lastIndexOf('.')
        val base: String
        val ext: String
        if (dotIndex > 0) {
            base = name.substring(0, dotIndex)
            ext = name.substring(dotIndex)
        } else {
            base = name
            ext = ""
        }
        var i = 1
        while (true) {
            candidate = File(dir, "$base($i)$ext")
            if (!candidate.exists()) return candidate
            i++
        }
    }

    private fun mimeFromName(name: String): String {
        val dot = name.lastIndexOf('.')
        val ext = if (dot >= 0 && dot < name.length - 1) {
            name.substring(dot + 1).lowercase()
        } else {
            MimeTypeMap.getFileExtensionFromUrl(name)?.lowercase()
        }
        if (!ext.isNullOrEmpty()) {
            val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
            if (!mime.isNullOrEmpty()) return mime
        }
        return "application/octet-stream"
    }
}
