package com.jackwallner.headachelogger.data

import java.io.File

/** One small document on disk. Tests use `MemoryTextFile`. */
interface TextFile {
    fun read(): String?
    fun write(text: String)
}

/** Writes to a sibling temp file, then renames, so a crash never leaves half a file. */
class DiskTextFile(private val file: File) : TextFile {
    override fun read(): String? = runCatching { if (file.isFile) file.readText() else null }.getOrNull()

    override fun write(text: String) {
        file.parentFile?.mkdirs()
        val tmp = File(file.parentFile, "${file.name}.tmp")
        tmp.writeText(text)
        if (!tmp.renameTo(file)) {
            file.writeText(text)
            tmp.delete()
        }
    }
}

class MemoryTextFile(var text: String? = null) : TextFile {
    override fun read(): String? = text
    override fun write(text: String) { this.text = text }
}
