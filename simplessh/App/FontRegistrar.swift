//
//  FontRegistrar.swift
//  simplessh
//
//  Registers fonts bundled with the app (e.g. MesloLGS NF, a Nerd Font that
//  carries the Powerline / prompt icons used by Oh My Zsh / Powerlevel themes)
//  so they can be referenced by `Font.custom` / `UIFont`.
//
//  Fonts are registered at runtime via Core Text rather than declared in
//  Info.plist's `UIAppFonts`, because this target uses a generated Info.plist
//  (GENERATE_INFOPLIST_FILE = YES) where adding an array key is awkward.
//

import CoreText
import Foundation

enum FontRegistrar {
    /// File names (without extension) of the bundled TrueType fonts.
    private static let bundledFontFileNames = [
        "MesloLGS-NF-Regular",
        "MesloLGS-NF-Bold",
    ]

    /// Registers all bundled fonts with the process font manager. Idempotent:
    /// re-registering an already-registered font is a no-op (the error is ignored).
    static func registerBundledFonts() {
        for name in bundledFontFileNames {
            // Resources are normally flattened to the bundle root; fall back to
            // the "Fonts" subdirectory in case it is copied as a folder reference.
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf")
                ?? Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
            else { continue }

            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
