    //
//  ReTREEveApp.swift
//  ReTREEve
//
//  Created by Muhammad Rizki on 01/09/26.
//

import SwiftUI
import UIKit
import SwiftData

@main
struct ReTREEveApp: App {
    init() {
        NavigationTitleFonts.apply()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: ReadingInsight.self)
    }
}

private enum NavigationTitleFonts {
    static func apply() {
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: rounded(.largeTitle, bold: true)]
        bar.titleTextAttributes = [.font: rounded(.headline, bold: false)]
    }

    private static func rounded(_ style: UIFont.TextStyle, bold: Bool) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        var descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        if bold, let emphasized = descriptor.withSymbolicTraits(.traitBold) {
            descriptor = emphasized
        }
        return UIFont(descriptor: descriptor, size: base.pointSize)
    }
}
