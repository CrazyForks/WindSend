package com.doraemon.wind_send

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class FileManagerHandler(private val activity: Activity) {
    companion object {
        private const val TAG = "FileManagerHandler"
        private const val EXTERNAL_STORAGE_AUTHORITY = "com.android.externalstorage.documents"
    }

    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openDirectory" -> {
                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) {
                    result.error("INVALID_ARGUMENT", "Directory path is empty", null)
                    return
                }
                result.success(openDirectory(path))
            }
            else -> result.notImplemented()
        }
    }

    private fun openDirectory(path: String): Boolean {
        return try {
            val directory = File(path)
            if (!directory.isDirectory) return false

            val initialUri = buildInitialUri(directory) ?: return false
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                putExtra(DocumentsContract.EXTRA_INITIAL_URI, initialUri)
            }
            if (intent.resolveActivity(activity.packageManager) == null) return false

            // Android has no portable "reveal in file manager" contract. The
            // Storage Access Framework is used because it is the system-owned,
            // provider-neutral navigator and supports a deterministic start folder.
            activity.startActivity(intent)
            true
        } catch (error: RuntimeException) {
            Log.e(TAG, "Unable to open directory: $path", error)
            false
        }
    }

    private fun buildInitialUri(directory: File): Uri? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null

        val storageRoot = Environment.getExternalStorageDirectory().canonicalFile
        val canonicalDirectory = directory.canonicalFile
        val rootPath = storageRoot.path
        val directoryPath = canonicalDirectory.path
        val isInPrimaryStorage = directoryPath == rootPath ||
            directoryPath.startsWith("$rootPath${File.separator}")
        if (!isInPrimaryStorage) return null

        val relativePath = directoryPath
            .removePrefix(rootPath)
            .trimStart(File.separatorChar)
            .replace(File.separatorChar, '/')
        val documentId = if (relativePath.isEmpty()) "primary:" else "primary:$relativePath"
        return DocumentsContract.buildDocumentUri(EXTERNAL_STORAGE_AUTHORITY, documentId)
    }
}
