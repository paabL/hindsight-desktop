import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Metadata-only invalidation. ctime also detects edits that preserve size and mtime.
/// Content is still reread before an upload is approved.
struct FileVersion: Equatable {
    let values: [Int64]

    init(_ url: URL) throws {
        var info = stat()
        guard stat(url.path, &info) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        #if canImport(Darwin)
        let modified = info.st_mtimespec, changed = info.st_ctimespec
        #else
        let modified = info.st_mtim, changed = info.st_ctim
        #endif
        values = [Int64(info.st_dev), Int64(info.st_ino), info.st_size,
                  Int64(modified.tv_sec), Int64(modified.tv_nsec), Int64(changed.tv_sec), Int64(changed.tv_nsec)]
    }
}
