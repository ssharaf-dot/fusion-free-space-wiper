//
//  POSIXHelpers.swift
//  Fusion Free Space Wiper
//
//  Thin, auditable wrappers over POSIX calls. We deliberately use supported
//  system calls (statfs, open/write/fsync, lstat) rather than parsing localized
//  `df` output or shelling out for anything destructive.
//

import Foundation

public struct FilesystemStats {
    public var blockSize: Int64
    public var totalBlocks: Int64
    public var freeBlocks: Int64            // f_bfree
    public var availableBlocks: Int64       // f_bavail (available to non-superuser)
    public var fsTypeName: String
    public var mountedOn: String

    /// Bytes available to an unprivileged process. This is the number we gate on.
    public var availableBytes: Int64 { availableBlocks * blockSize }
    public var totalBytes: Int64 { totalBlocks * blockSize }
    public var freeBytes: Int64 { freeBlocks * blockSize }
}

public enum POSIX {

    /// statfs for a path. Returns nil on failure.
    public static func statfsFor(path: String) -> FilesystemStats? {
        var st = statfs()
        let r = path.withCString { statfs($0, &st) }
        guard r == 0 else { return nil }

        // On Darwin, block counts (f_blocks/f_bfree/f_bavail) are expressed in
        // units of f_bsize.
        let bsize = Int64(st.f_bsize)
        let fsType = withUnsafePointer(to: st.f_fstypename) { ptr -> String in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) {
                String(cString: $0)
            }
        }
        let mnt = withUnsafePointer(to: st.f_mntonname) { ptr -> String in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
        return FilesystemStats(blockSize: bsize,
                               totalBlocks: Int64(bitPattern: UInt64(st.f_blocks)),
                               freeBlocks: Int64(bitPattern: UInt64(st.f_bfree)),
                               availableBlocks: Int64(bitPattern: UInt64(st.f_bavail)),
                               fsTypeName: fsType,
                               mountedOn: mnt)
    }

    /// Is a process alive? Uses kill(pid, 0). ESRCH => not alive.
    public static func isProcessAlive(_ pid: Int32) -> Bool {
        if pid <= 0 { return false }
        let r = kill(pid, 0)
        if r == 0 { return true }
        return errno == EPERM   // exists but owned by someone else
    }

    /// lstat wrapper. Returns nil if the path does not exist.
    public static func lstatFor(path: String) -> stat? {
        var s = stat()
        let r = path.withCString { lstat($0, &s) }
        return r == 0 ? s : nil
    }

    public static func isSymlink(path: String) -> Bool {
        guard let s = lstatFor(path: path) else { return false }
        return (s.st_mode & S_IFMT) == S_IFLNK
    }

    public static func isRegularFile(path: String) -> Bool {
        guard let s = lstatFor(path: path) else { return false }
        return (s.st_mode & S_IFMT) == S_IFREG
    }
}

/// A file opened for overwrite work. Uses O_NOFOLLOW on the final component and
/// 0600 permissions. Writes are chunked with full short-write / EINTR handling.
public final class OverwriteFile {
    private let fd: Int32
    public let path: String

    public init(createAt path: String) throws {
        self.path = path
        // O_NOFOLLOW: refuse to open through a symlink at the final component.
        let flags = O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW
        let opened = path.withCString { open($0, flags, 0o600) }
        if opened < 0 {
            throw WipeError.ioError("open(\(path)) failed: \(String(cString: strerror(errno)))")
        }
        self.fd = opened
    }

    public func seekToStart() throws {
        if lseek(fd, 0, SEEK_SET) < 0 {
            throw WipeError.ioError("lseek failed: \(String(cString: strerror(errno)))")
        }
    }

    /// Write exactly `count` bytes from `buffer`, handling partial writes and EINTR.
    /// Returns .success(bytesWritten) or throws. On ENOSPC returns a sentinel so the
    /// caller can stop gracefully rather than treat it as a hard failure.
    public enum WriteOutcome {
        case wroteAll(Int)
        case outOfSpace(Int)     // bytes written before ENOSPC
    }

    public func writeFully(_ buffer: UnsafeRawPointer, count: Int) throws -> WriteOutcome {
        var written = 0
        while written < count {
            let toWrite = count - written
            let n = write(fd, buffer.advanced(by: written), toWrite)
            if n > 0 {
                written += n
                continue
            }
            if n < 0 {
                let e = errno
                if e == EINTR { continue }               // interrupted, retry
                if e == ENOSPC { return .outOfSpace(written) }
                throw WipeError.ioError("write failed: \(String(cString: strerror(e)))")
            }
            // n == 0: nothing written, avoid spin
            if n == 0 { break }
        }
        return .wroteAll(written)
    }

    /// Best-effort durable flush. We call F_FULLFSYNC (stronger than fsync) but the
    /// README is explicit that this cannot guarantee particular physical SSD cells
    /// are overwritten. This only asks the drive to flush its buffers.
    public func flush() {
        if fcntl(fd, F_FULLFSYNC) == -1 {
            _ = fsync(fd)   // fall back
        }
    }

    public func close() {
        flush()
        _ = Foundation.close(fd)
    }

    deinit {
        _ = Foundation.close(fd)
    }
}
