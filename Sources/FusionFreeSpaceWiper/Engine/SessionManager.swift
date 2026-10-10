//
//  SessionManager.swift
//  Fusion Free Space Wiper
//
//  Owns the creation, identification and safe removal of app-owned session
//  directories. A session directory carries a MARKER.json so that, on a later
//  launch, we can recognise ONLY our own stale sessions and never touch a
//  similarly named folder we did not create.
//

import Foundation

public struct SessionMarker: Codable {
    public var app: String            // fixed identifier string
    public var sessionID: String      // random UUID
    public var pid: Int32
    public var createdAt: Date
    public var volumeUUID: String?
    public var appVersion: String

    public static let appIdentifier = "com.local.fusionfreespacewiper.session.v1"
}

public struct StaleSession {
    public var directory: String
    public var marker: SessionMarker
    public var isOwnerProcessAlive: Bool
    public var fileCount: Int
    public var totalBytes: Int64
}

public final class SessionManager {

    public static let dirPrefix = ".FusionFreeSpaceWiper-"
    public static let markerName = "MARKER.json"

    public init() {}

    /// Choose a writable parent directory that physically lives on the target
    /// volume. For the startup volume we use the user's home directory (always
    /// writable and on the data volume). For any other mount we use the mount
    /// point itself if writable.
    public func writableParent(forMountPath mountPath: String) throws -> String {
        let fm = FileManager.default
        let home = NSHomeDirectory()

        // If the target volume is the one that contains the home directory, use home.
        if let homeStat = POSIX.statfsFor(path: home),
           let mountStat = POSIX.statfsFor(path: mountPath),
           homeStat.mountedOn == mountStat.mountedOn {
            return home
        }
        // Otherwise use the mount point directly, if writable.
        if fm.isWritableFile(atPath: mountPath) {
            return mountPath
        }
        // Last resort: a Shared folder on that volume.
        let shared = (mountPath as NSString).appendingPathComponent("Users/Shared")
        if fm.isWritableFile(atPath: shared) {
            return shared
        }
        throw WipeError.targetNotWritable(mountPath)
    }

    /// Create a fresh, uniquely named, 0700 session directory with a marker file.
    /// `kind` (e.g. "test" or "wipe") is embedded in the directory name so the
    /// session is clearly identifiable, while still carrying the common prefix so
    /// stale-session discovery finds it.
    public func createSession(parent: String, volumeUUID: String?, kind: String = "wipe") throws -> (dir: String, marker: SessionMarker) {
        let fm = FileManager.default
        let random = UUID().uuidString
        let safeKind = kind.filter { $0.isLetter || $0.isNumber }
        let dirName = SessionManager.dirPrefix + (safeKind.isEmpty ? "" : safeKind + "-") + random
        let dir = (parent as NSString).appendingPathComponent(dirName)

        // Refuse if something already exists at that path (astronomically unlikely).
        if fm.fileExists(atPath: dir) {
            throw WipeError.cannotCreateSession("path already exists: \(dir)")
        }
        do {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: false,
                                   attributes: [.posixPermissions: 0o700])
        } catch {
            throw WipeError.cannotCreateSession(error.localizedDescription)
        }

        let marker = SessionMarker(app: SessionMarker.appIdentifier,
                                   sessionID: random,
                                   pid: ProcessInfo.processInfo.processIdentifier,
                                   createdAt: Date(),
                                   volumeUUID: volumeUUID,
                                   appVersion: AppInfo.version)
        let markerPath = (dir as NSString).appendingPathComponent(SessionManager.markerName)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(marker)
        // Write marker with O_NOFOLLOW semantics via OverwriteFile.
        let mf = try OverwriteFile(createAt: markerPath)
        _ = try data.withUnsafeBytes { raw -> OverwriteFile.WriteOutcome in
            try mf.writeFully(raw.baseAddress!, count: data.count)
        }
        mf.close()
        return (dir, marker)
    }

    /// Discover stale, app-owned session directories under the given parent.
    /// Only directories carrying a valid MARKER.json with our app identifier are
    /// considered. Anything else is ignored.
    public func findStaleSessions(parents: [String]) -> [StaleSession] {
        let fm = FileManager.default
        var results: [StaleSession] = []
        var seen = Set<String>()

        for parent in parents where !seen.contains(parent) {
            seen.insert(parent)
            guard let entries = try? fm.contentsOfDirectory(atPath: parent) else { continue }
            for entry in entries where entry.hasPrefix(SessionManager.dirPrefix) {
                let dir = (parent as NSString).appendingPathComponent(entry)
                // Must be a real directory, not a symlink.
                guard POSIX.isRegularFile(path: dir) == false,
                      let s = POSIX.lstatFor(path: dir),
                      (s.st_mode & S_IFMT) == S_IFDIR else { continue }

                let markerPath = (dir as NSString).appendingPathComponent(SessionManager.markerName)
                guard let data = fm.contents(atPath: markerPath) else { continue }
                let dec = JSONDecoder()
                dec.dateDecodingStrategy = .iso8601
                guard let marker = try? dec.decode(SessionMarker.self, from: data),
                      marker.app == SessionMarker.appIdentifier else { continue }

                let (count, bytes) = tallyDirectory(dir)
                let alive = POSIX.isProcessAlive(marker.pid)
                results.append(StaleSession(directory: dir, marker: marker,
                                            isOwnerProcessAlive: alive,
                                            fileCount: count, totalBytes: bytes))
            }
        }
        return results
    }

    /// Safely remove an app-owned session directory. Verifies the marker again,
    /// then removes only regular files inside the directory (guarding against
    /// symlinks / path substitution), then the directory itself.
    /// Returns (success, leftoverPaths).
    @discardableResult
    public func removeSession(directory: String) -> (success: Bool, leftovers: [String]) {
        let fm = FileManager.default

        // Re-validate the marker right before deletion.
        let markerPath = (directory as NSString).appendingPathComponent(SessionManager.markerName)
        guard let data = fm.contents(atPath: markerPath),
              let marker = try? {
                  let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
                  return try d.decode(SessionMarker.self, from: data)
              }(),
              marker.app == SessionMarker.appIdentifier else {
            // No valid marker => refuse to delete anything.
            return (false, [directory])
        }

        // The directory itself must not be a symlink.
        if POSIX.isSymlink(path: directory) {
            return (false, [directory])
        }

        var leftovers: [String] = []
        guard let entries = try? fm.contentsOfDirectory(atPath: directory) else {
            return (false, [directory])
        }
        for entry in entries {
            let p = (directory as NSString).appendingPathComponent(entry)
            // Only remove regular files; never follow symlinks or descend into
            // unexpected subdirectories.
            if POSIX.isSymlink(path: p) {
                leftovers.append(p)   // do not touch symlinks
                continue
            }
            if POSIX.isRegularFile(path: p) {
                do { try fm.removeItem(atPath: p) }
                catch { leftovers.append(p) }
            } else {
                // Unexpected non-regular, non-symlink entry: leave it, report it.
                leftovers.append(p)
            }
        }

        if leftovers.isEmpty {
            do { try fm.removeItem(atPath: directory) }
            catch { return (false, [directory]) }
            return (true, [])
        }
        return (false, leftovers)
    }

    private func tallyDirectory(_ dir: String) -> (count: Int, bytes: Int64) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return (0, 0) }
        var count = 0
        var bytes: Int64 = 0
        for e in entries {
            let p = (dir as NSString).appendingPathComponent(e)
            if let s = POSIX.lstatFor(path: p), (s.st_mode & S_IFMT) == S_IFREG {
                count += 1
                bytes += Int64(s.st_size)
            }
        }
        return (count, bytes)
    }
}

/// Static app metadata, filled from the bundle when available.
public enum AppInfo {
    public static let name = "Fusion Free Space Wiper"
    public static let repositoryURL = "https://github.com/ssharaf-dot/fusion-free-space-wiper"
    public static var version: String {
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String { return v }
        return "1.1.0"
    }
}
