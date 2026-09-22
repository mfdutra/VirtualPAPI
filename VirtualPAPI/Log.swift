//
//  Log.swift
//  VirtualPAPI
//

import os

/// Unified logging categories. Read them from a device with Console.app
/// (filter on subsystem `com.mfdutra.VirtualPAPI`) or with
/// `log stream --predicate 'subsystem == "com.mfdutra.VirtualPAPI"'`.
///
/// `.debug` messages cost almost nothing unless something is capturing them,
/// so per-update diagnostics belong there. Dynamic strings are redacted by
/// default, so values needed to diagnose a user report (errors, ports, paths)
/// are interpolated with `privacy: .public`.
///
/// `nonisolated` because the targets default to main-actor isolation and
/// these are used from the UDP receive threads and the database queue.
nonisolated extension Logger {
    private static let subsystem = "com.mfdutra.VirtualPAPI"

    /// Glide slope and target calculations (GenericLocation).
    static let guidance = Logger(subsystem: subsystem, category: "guidance")
    /// CoreLocation internal GPS.
    static let internalGPS = Logger(subsystem: subsystem, category: "internalGPS")
    /// X-Plane XGPS listener.
    static let xgps = Logger(subsystem: subsystem, category: "xgps")
    /// GDL90 listener and heartbeat broadcast.
    static let gdl90 = Logger(subsystem: subsystem, category: "gdl90")
    /// Raw UDP sockets and receive threads.
    static let udp = Logger(subsystem: subsystem, category: "udp")
    /// Aviation database: bundle copy, open, remote update.
    static let database = Logger(subsystem: subsystem, category: "database")
}
