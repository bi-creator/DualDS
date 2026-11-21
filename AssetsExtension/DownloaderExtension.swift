// DualDS — Background Assets downloader extension for FoldPlay Originals (Apple-hosted asset packs).
// Copyright (C) 2026 DualDS contributors. GPL-3.0-or-later.
//
// Every FoldPlay Original is an on-demand asset pack, so the system downloads one only when the app
// asks for it, and the app asks only after StoreKit has verified the purchase (OriginalsInstaller).
// The default StoreKit implementation handles scheduling, updates and decompression.

import BackgroundAssets
import ExtensionFoundation
import StoreKit

@main
struct DownloaderExtension: StoreDownloaderExtension {
    func shouldDownload(_ assetPack: AssetPack) -> Bool { true }
}
