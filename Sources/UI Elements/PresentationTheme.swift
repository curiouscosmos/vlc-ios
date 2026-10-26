/*****************************************************************************
 * PresentationTheme.swift
 * VLC for iOS
 *****************************************************************************
 * Copyright (c) 2018-2026 VideoLAN. All rights reserved.
 * $Id$
 *
 * Authors: Carola Nitz <caro # videolan.org>
 *
 * Refer to the COPYING file of the official project for license.
 *****************************************************************************/

import Foundation
import UIKit

extension Notification.Name {
    static let VLCThemeDidChangeNotification = Notification.Name("themeDidChangeNotfication")
}

@objcMembers class ColorPalette: NSObject {

    let isDark: Bool
    let name: String

#if !os(tvOS)
    let statusBarStyle: UIStatusBarStyle
#endif
    let navigationbarColor: UIColor
    let navigationbarTextColor: UIColor
    let background: UIColor
    let cellBackgroundA: UIColor
    let cellBackgroundB: UIColor
    let cellDetailTextColor: UIColor
    let cellTextColor: UIColor
    let cellSelectedTextColor: UIColor
    let lightTextColor: UIColor
    let sectionHeaderTextColor: UIColor
    let separatorColor: UIColor
    let mediaCategorySeparatorColor: UIColor
    let tabBarColor: UIColor
    let tabBarIconColor: UIColor
    let orangeUI: UIColor
    let orangeDarkAccent: UIColor
    let secondarySubtitleAccent: UIColor
    let selectionAccent: UIColor
    let overlayPrimaryTextColor: UIColor
    let overlaySecondaryTextColor: UIColor
    let overlayTertiaryTextColor: UIColor
    let overlayHairlineColor: UIColor
    let overlayControlFillColor: UIColor
#if !os(tvOS)
    let toolBarStyle: UIBarStyle
#endif
    let blurStyle: UIBlurEffect.Style
    let textfieldBorderColor: UIColor
    let textfieldPlaceholderColor: UIColor
    let thumbnailBackgroundColor: UIColor
    let transparentDarkBackgroundColor: UIColor
    let cardBackground: UIColor
    let accentTint: UIColor

#if os(tvOS)
    init(isDark: Bool,
         name: String,
         navigationbarColor: UIColor,
         navigationbarTextColor: UIColor,
         background: UIColor,
         cellBackgroundA: UIColor,
         cellBackgroundB: UIColor,
         cellDetailTextColor: UIColor,
         cellTextColor: UIColor,
         cellSelectedTextColor: UIColor,
         lightTextColor: UIColor,
         sectionHeaderTextColor: UIColor,
         separatorColor: UIColor,
         mediaCategorySeparatorColor: UIColor,
         tabBarColor: UIColor,
         tabBarIconColor: UIColor,
         orangeUI: UIColor,
         orangeDarkAccent: UIColor,
         secondarySubtitleAccent: UIColor,
         selectionAccent: UIColor,
         overlayPrimaryTextColor: UIColor,
         overlaySecondaryTextColor: UIColor,
         overlayTertiaryTextColor: UIColor,
         overlayHairlineColor: UIColor,
         overlayControlFillColor: UIColor,
         blurStyle: UIBlurEffect.Style,
         textfieldBorderColor: UIColor,
         textfieldPlaceholderColor: UIColor,
         thumbnailBackgroundColor: UIColor,
         transparentDarkBackgroundColor: UIColor,
         cardBackground: UIColor,
         accentTint: UIColor) {
        self.isDark = isDark
        self.name = name
        self.navigationbarColor = navigationbarColor
        self.navigationbarTextColor = navigationbarTextColor
        self.background = background
        self.cellBackgroundA = cellBackgroundA
        self.cellBackgroundB = cellBackgroundB
        self.cellDetailTextColor = cellDetailTextColor
        self.cellTextColor = cellTextColor
        self.cellSelectedTextColor = cellSelectedTextColor
        self.lightTextColor = lightTextColor
        self.sectionHeaderTextColor = sectionHeaderTextColor
        self.separatorColor = separatorColor
        self.mediaCategorySeparatorColor = mediaCategorySeparatorColor
        self.tabBarColor = tabBarColor
        self.tabBarIconColor = tabBarIconColor
        self.orangeUI = orangeUI
        self.orangeDarkAccent = orangeDarkAccent
        self.secondarySubtitleAccent = secondarySubtitleAccent
        self.selectionAccent = selectionAccent
        self.overlayPrimaryTextColor = overlayPrimaryTextColor
        self.overlaySecondaryTextColor = overlaySecondaryTextColor
        self.overlayTertiaryTextColor = overlayTertiaryTextColor
        self.overlayHairlineColor = overlayHairlineColor
        self.overlayControlFillColor = overlayControlFillColor
        self.blurStyle = blurStyle
        self.textfieldBorderColor = textfieldBorderColor
        self.textfieldPlaceholderColor = textfieldPlaceholderColor
        self.thumbnailBackgroundColor = thumbnailBackgroundColor
        self.transparentDarkBackgroundColor = transparentDarkBackgroundColor
        self.cardBackground = cardBackground
        self.accentTint = accentTint
    }
#else
    init(isDark: Bool,
         name: String,
         statusBarStyle: UIStatusBarStyle,
         navigationbarColor: UIColor,
         navigationbarTextColor: UIColor,
         background: UIColor,
         cellBackgroundA: UIColor,
         cellBackgroundB: UIColor,
         cellDetailTextColor: UIColor,
         cellTextColor: UIColor,
         cellSelectedTextColor: UIColor,
         lightTextColor: UIColor,
         sectionHeaderTextColor: UIColor,
         separatorColor: UIColor,
         mediaCategorySeparatorColor: UIColor,
         tabBarColor: UIColor,
         tabBarIconColor: UIColor,
         orangeUI: UIColor,
         orangeDarkAccent: UIColor,
         secondarySubtitleAccent: UIColor,
         selectionAccent: UIColor,
         overlayPrimaryTextColor: UIColor,
         overlaySecondaryTextColor: UIColor,
         overlayTertiaryTextColor: UIColor,
         overlayHairlineColor: UIColor,
         overlayControlFillColor: UIColor,
         toolBarStyle: UIBarStyle,
         blurStyle: UIBlurEffect.Style,
         textfieldBorderColor: UIColor,
         textfieldPlaceholderColor: UIColor,
         thumbnailBackgroundColor: UIColor,
         transparentDarkBackgroundColor: UIColor,
         cardBackground: UIColor,
         accentTint: UIColor) {
        self.isDark = isDark
        self.name = name
        self.statusBarStyle = statusBarStyle
        self.navigationbarColor = navigationbarColor
        self.navigationbarTextColor = navigationbarTextColor
        self.background = background
        self.cellBackgroundA = cellBackgroundA
        self.cellBackgroundB = cellBackgroundB
        self.cellDetailTextColor = cellDetailTextColor
        self.cellTextColor = cellTextColor
        self.cellSelectedTextColor = cellSelectedTextColor
        self.lightTextColor = lightTextColor
        self.sectionHeaderTextColor = sectionHeaderTextColor
        self.separatorColor = separatorColor
        self.mediaCategorySeparatorColor = mediaCategorySeparatorColor
        self.tabBarColor = tabBarColor
        self.tabBarIconColor = tabBarIconColor
        self.orangeUI = orangeUI
        self.orangeDarkAccent = orangeDarkAccent
        self.secondarySubtitleAccent = secondarySubtitleAccent
        self.selectionAccent = selectionAccent
        self.overlayPrimaryTextColor = overlayPrimaryTextColor
        self.overlaySecondaryTextColor = overlaySecondaryTextColor
        self.overlayTertiaryTextColor = overlayTertiaryTextColor
        self.overlayHairlineColor = overlayHairlineColor
        self.overlayControlFillColor = overlayControlFillColor
        self.toolBarStyle = toolBarStyle
        self.blurStyle = blurStyle
        self.textfieldBorderColor = textfieldBorderColor
        self.textfieldPlaceholderColor = textfieldPlaceholderColor
        self.thumbnailBackgroundColor = thumbnailBackgroundColor
        self.transparentDarkBackgroundColor = transparentDarkBackgroundColor
        self.cardBackground = cardBackground
        self.accentTint = accentTint
    }
#endif
}

// MARK: - Typography

@objcMembers class Typography: NSObject {

    let tableHeaderFont: UIFont

    init(tableHeaderFont: UIFont) {
        self.tableHeaderFont = tableHeaderFont
    }
}

// MARK: - PresentationThemeType

enum PresentationThemeType: Int {
    case bright = 0
    case dark
    case auto
}

// MARK: - PresentationTheme

@objcMembers class PresentationTheme: NSObject {

    static let brightTheme = PresentationTheme(colors: brightPalette)
    static let darkTheme = PresentationTheme(colors: darkPalette)
#if os(tvOS)
    static let blackTheme = PresentationTheme(colors: darkPalette)
#else
    static let blackTheme = PresentationTheme(colors: blackPalette)
#endif

    #if os(visionOS)
    static let visionTheme = PresentationTheme(colors: visionPalette)
    #endif

    var isDark: Bool {
        return colors.isDark
    }

    var webEquivalentTheme: PresentationTheme {
        #if os(visionOS)
        // Since visionOS uses semantic colors for many of these, there will not be equivalent
        // web hex colors. Fault back to the dark theme
        return .darkTheme
        #else
        return self
        #endif
    }

    var isBlack: Bool {
        return UserDefaults.standard.bool(forKey: kVLCSettingAppThemeBlack)
    }

    static var current: PresentationTheme = {
        let themeSettings = UserDefaults.standard.integer(forKey: kVLCSettingAppTheme)
        return PresentationTheme.respectiveTheme(for: PresentationThemeType(rawValue: themeSettings))
    }() {
        didSet {
#if !os(tvOS)
            AppearanceManager.setupAppearance(theme: self.current)
#endif
            NotificationCenter.default.post(name: .VLCThemeDidChangeNotification, object: self)
        }
    }

    static var currentExcludingWhite: PresentationTheme {
        if PresentationTheme.current.isBlack {
            return PresentationTheme.blackTheme
        } else {
            return PresentationTheme.darkTheme
        }
    }

    init(colors: ColorPalette) {
        self.colors = colors
        super.init()
    }

    @objc static func themeDidUpdate() {
        let themeSettings = UserDefaults.standard.integer(forKey: kVLCSettingAppTheme)
        PresentationTheme.current = PresentationTheme.respectiveTheme(for:
            PresentationThemeType(rawValue: themeSettings))
    }

    static func respectiveTheme(for theme: PresentationThemeType?, excludingBlackTheme: Bool = false, traitCollection: UITraitCollection? = nil) -> PresentationTheme {
#if os(visionOS)
        return .visionTheme
#else
        guard let theme = theme else {
            return PresentationTheme.brightTheme
        }

        var presentationTheme = PresentationTheme.brightTheme
        var darkTheme: PresentationTheme

        if UserDefaults.standard.bool(forKey: kVLCSettingAppThemeBlack) {
            darkTheme = PresentationTheme.blackTheme
        } else {
            darkTheme = PresentationTheme.darkTheme
        }

        if theme == .dark {
            presentationTheme = darkTheme
        } else if theme == .auto {
#if os(iOS) || os(tvOS)
            let traits = traitCollection ?? UITraitCollection.current
            let isSystemDarkTheme = traits.userInterfaceStyle == .dark
            presentationTheme = isSystemDarkTheme ? darkTheme : PresentationTheme.brightTheme
#else
            presentationTheme = darkTheme
#endif // os(iOS) || os(tvOS)
        }
        return presentationTheme
#endif // os(visionOS)
    }

    let colors: ColorPalette
    let font = defaultFont
}

// MARK: - UIColor

@objc extension UIColor {

    convenience init(_ rgbValue: UInt32, _ alpha: CGFloat = 1.0) {
        let r = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgbValue & 0xFF00) >> 8) / 255.0
        let b = CGFloat(rgbValue & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }

    func desaturated(_ scale: CGFloat) -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return self
        }
        return UIColor(hue: hue, saturation: saturation * scale, brightness: brightness, alpha: alpha)
    }

    private func toHex(alpha: Bool = false) -> String? {
        guard let components = cgColor.components, components.count >= 3 else {
            assertionFailure()
            return nil
        }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        var a = Float(1.0)

        if components.count == 4 {
            a = Float(components[3])
        }

        if alpha {
            return String(format: "#%02lX%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255), lroundf(a * 255))
        } else {
            return String(format: "#%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
        }
    }

    var toHex: String? {
        return toHex()
    }
}

// MARK: - Color Palettes

#if os(tvOS)

let brightPalette = ColorPalette(isDark: false,
                                 name: "Default",
                                 navigationbarColor: UIColor(0xFFFFFF),
                                 navigationbarTextColor: UIColor(0x000000),
                                 background: UIColor(0xFFFFFF),
                                 cellBackgroundA: UIColor(0xFFFFFF),
                                 cellBackgroundB: UIColor(0xE5E5E3),
                                 cellDetailTextColor: UIColor(0x919191),
                                 cellTextColor: UIColor(0x000000),
                                 cellSelectedTextColor: UIColor(0x474747),
                                 lightTextColor: UIColor(0x888888),
                                 sectionHeaderTextColor: UIColor(0x25292C),
                                 separatorColor: UIColor(0xF0F2F7),
                                 mediaCategorySeparatorColor: UIColor(0xECF2F6),
                                 tabBarColor: UIColor(0xFFFFFF),
                                 tabBarIconColor: UIColor(0x88949c),
                                 orangeUI: UIColor(0xFF8800),
                                 orangeDarkAccent: UIColor(0xFF8800),
                                 secondarySubtitleAccent: UIColor(0x32C8FF),
                                 selectionAccent: UIColor(0xFFB70D),
                                 overlayPrimaryTextColor: UIColor(0x000000),
                                 overlaySecondaryTextColor: UIColor(0x000000, 0.7),
                                 overlayTertiaryTextColor: UIColor(0x000000, 0.4),
                                 overlayHairlineColor: UIColor(0x000000, 0.18),
                                 overlayControlFillColor: UIColor(0x000000, 0.08),
                                 blurStyle: .extraLight,
                                 textfieldBorderColor: UIColor(0x84929C),
                                 textfieldPlaceholderColor: UIColor(0xB3B3B3),
                                 thumbnailBackgroundColor: UIColor(0xE6E6E6),
                                 transparentDarkBackgroundColor: UIColor(0x1E1E1E, 0.5),
                                 cardBackground: UIColor(0xFFFFFF),
                                 accentTint: UIColor(0xFF8800, 0.13))

let darkPalette = ColorPalette(isDark: true,
                               name: "Dark",
                               navigationbarColor: UIColor(0x1B1E21),
                               navigationbarTextColor: UIColor(0xFFFFFF),
                               background: UIColor(0x1B1E21),
                               cellBackgroundA: UIColor(0x1B1E21),
                               cellBackgroundB: UIColor(0x494B4D),
                               cellDetailTextColor: UIColor(0x919191),
                               cellTextColor: UIColor(0xFFFFFF),
                               cellSelectedTextColor: UIColor(0x474747),
                               lightTextColor: UIColor(0xB8B8B8),
                               sectionHeaderTextColor: UIColor(0x828282),
                               separatorColor: UIColor(0x25292C),
                               mediaCategorySeparatorColor: UIColor(0x25292C),
                               tabBarColor: UIColor(0x25292C),
                               tabBarIconColor: UIColor(0x88949c),
                               orangeUI: UIColor(0xFF8800),
                               orangeDarkAccent: UIColor(0xD57200),
                               secondarySubtitleAccent: UIColor(0x32C8FF),
                               selectionAccent: UIColor(0xFFB70D),
                               overlayPrimaryTextColor: UIColor(0xFFFFFF),
                               overlaySecondaryTextColor: UIColor(0xFFFFFF, 0.7),
                               overlayTertiaryTextColor: UIColor(0xFFFFFF, 0.4),
                               overlayHairlineColor: UIColor(0xFFFFFF, 0.18),
                               overlayControlFillColor: UIColor(0xFFFFFF, 0.08),
                               blurStyle: .dark,
                               textfieldBorderColor: UIColor(0x84929C),
                               textfieldPlaceholderColor: UIColor(0x737373),
                               thumbnailBackgroundColor: UIColor(0x26282B),
                               transparentDarkBackgroundColor: UIColor(0x1E1E1E, 0.5),
                               cardBackground: UIColor(0x1B1E21),
                               accentTint: UIColor(0xFF8800, 0.22))

#else // !os(tvOS)

let brightPalette = ColorPalette(isDark: false,
                                 name: "Default",
                                 statusBarStyle: .darkContent,
                                 navigationbarColor: UIColor(0xFFFFFF),
                                 navigationbarTextColor: UIColor(0x000000),
                                 background: UIColor(0xF6F6F8),
                                 cellBackgroundA: UIColor(0xF6F6F8),
                                 cellBackgroundB: UIColor(0xE5E5E3),
                                 cellDetailTextColor: UIColor(0x919191),
                                 cellTextColor: UIColor(0x000000),
                                 cellSelectedTextColor: UIColor(0x474747),
                                 lightTextColor: UIColor(0x888888),
                                 sectionHeaderTextColor: UIColor(0x25292C),
                                 separatorColor: UIColor(0xF0F2F7),
                                 mediaCategorySeparatorColor: UIColor(0xECF2F6),
                                 tabBarColor: UIColor(0xFFFFFF),
                                 tabBarIconColor: UIColor(0x88949c),
                                 orangeUI: UIColor(0xFF8800),
                                 orangeDarkAccent: UIColor(0xFF8800),
                                 secondarySubtitleAccent: UIColor(0x32C8FF),
                                 selectionAccent: UIColor(0xFFB70D),
                                 overlayPrimaryTextColor: UIColor(0x000000),
                                 overlaySecondaryTextColor: UIColor(0x000000, 0.7),
                                 overlayTertiaryTextColor: UIColor(0x000000, 0.4),
                                 overlayHairlineColor: UIColor(0x000000, 0.18),
                                 overlayControlFillColor: UIColor(0x000000, 0.08),
                                 toolBarStyle: UIBarStyle.default,
                                 blurStyle: .extraLight,
                                 textfieldBorderColor: UIColor(0x84929C),
                                 textfieldPlaceholderColor: UIColor(0xB3B3B3),
                                 thumbnailBackgroundColor: UIColor(0xE6E6E6),
                                 transparentDarkBackgroundColor: UIColor(0x1E1E1E, 0.5),
                                 cardBackground: UIColor(0xFFFFFF),
                                 accentTint: UIColor(0xFF8800, 0.13))

let darkPalette = ColorPalette(isDark: true,
                               name: "Dark",
                               statusBarStyle: .lightContent,
                               navigationbarColor: UIColor(0x1B1E21),
                               navigationbarTextColor: UIColor(0xFFFFFF),
                               background: UIColor(0x121417),
                               cellBackgroundA: UIColor(0x121417),
                               cellBackgroundB: UIColor(0x494B4D),
                               cellDetailTextColor: UIColor(0x919191),
                               cellTextColor: UIColor(0xFFFFFF),
                               cellSelectedTextColor: UIColor(0x474747),
                               lightTextColor: UIColor(0xB8B8B8),
                               sectionHeaderTextColor: UIColor(0x828282),
                               separatorColor: UIColor(0x25292C),
                               mediaCategorySeparatorColor: UIColor(0x25292C),
                               tabBarColor: UIColor(0x25292C),
                               tabBarIconColor: UIColor(0x88949c),
                               orangeUI: UIColor(0xFF8800),
                               orangeDarkAccent: UIColor(0xD57200),
                               secondarySubtitleAccent: UIColor(0x32C8FF),
                               selectionAccent: UIColor(0xFFB70D),
                               overlayPrimaryTextColor: UIColor(0xFFFFFF),
                               overlaySecondaryTextColor: UIColor(0xFFFFFF, 0.7),
                               overlayTertiaryTextColor: UIColor(0xFFFFFF, 0.4),
                               overlayHairlineColor: UIColor(0xFFFFFF, 0.18),
                               overlayControlFillColor: UIColor(0xFFFFFF, 0.08),
                               toolBarStyle: UIBarStyle.black,
                               blurStyle: .dark,
                               textfieldBorderColor: UIColor(0x84929C),
                               textfieldPlaceholderColor: UIColor(0x737373),
                               thumbnailBackgroundColor: UIColor(0x26282B),
                               transparentDarkBackgroundColor: UIColor(0x1E1E1E, 0.5),
                               cardBackground: UIColor(0x1B1E21),
                               accentTint: UIColor(0xFF8800, 0.22))

let blackPalette = ColorPalette(isDark: true,
                                name: "Dark",
                                statusBarStyle: .lightContent,
                                navigationbarColor: UIColor(0x000000),
                                navigationbarTextColor: UIColor(0xFFFFFF),
                                background: UIColor(0x000000),
                                cellBackgroundA: UIColor(0x000000),
                                cellBackgroundB: UIColor(0x494B4D),
                                cellDetailTextColor: UIColor(0x919191),
                                cellTextColor: UIColor(0xFFFFFF),
                                cellSelectedTextColor: UIColor(0x474747),
                                lightTextColor: UIColor(0xB8B8B8),
                                sectionHeaderTextColor: UIColor(0x828282),
                                separatorColor: UIColor(0x25292C),
                                mediaCategorySeparatorColor: UIColor(0x25292C),
                                tabBarColor: UIColor(0x000000),
                                tabBarIconColor: UIColor(0x88949c),
                                orangeUI: UIColor(0xFF8800),
                                orangeDarkAccent: UIColor(0xD57200),
                                secondarySubtitleAccent: UIColor(0x32C8FF),
                                selectionAccent: UIColor(0xFFB70D),
                                overlayPrimaryTextColor: UIColor(0xFFFFFF),
                                overlaySecondaryTextColor: UIColor(0xFFFFFF, 0.7),
                                overlayTertiaryTextColor: UIColor(0xFFFFFF, 0.4),
                                overlayHairlineColor: UIColor(0xFFFFFF, 0.18),
                                overlayControlFillColor: UIColor(0xFFFFFF, 0.08),
                                toolBarStyle: UIBarStyle.black,
                                blurStyle: .dark,
                                textfieldBorderColor: UIColor(0x84929C),
                                textfieldPlaceholderColor: UIColor(0x737373),
                                thumbnailBackgroundColor: UIColor(0x1C1E21),
                                transparentDarkBackgroundColor: UIColor(0x1E1E1E, 0.5),
                                cardBackground: UIColor(0x1B1E21),
                                accentTint: UIColor(0xFF8800, 0.22))

#if os(visionOS)
let visionPalette = ColorPalette(isDark: true,
                                 name: "visionOS",
                                 statusBarStyle: .lightContent,
                                 navigationbarColor: .clear,
                                 navigationbarTextColor: .label,
                                 background: .clear,
                                 cellBackgroundA: .clear,
                                 cellBackgroundB: UIColor(0x494B4D, 0.2),
                                 cellDetailTextColor: .tertiaryLabel,
                                 cellTextColor: .label,
                                 cellSelectedTextColor: UIColor(0x474747),
                                 lightTextColor: .secondaryLabel,
                                 sectionHeaderTextColor: .secondaryLabel,
                                 separatorColor: .tertiarySystemFill,
                                 mediaCategorySeparatorColor: .tertiarySystemFill,
                                 tabBarColor: .clear,
                                 tabBarIconColor: UIColor(0x88949c),
                                 orangeUI: UIColor(0xFF8800),
                                 orangeDarkAccent: UIColor(0xD57200),
                                 secondarySubtitleAccent: UIColor(0x32C8FF),
                                 selectionAccent: UIColor(0xFFB70D),
                                 overlayPrimaryTextColor: UIColor(0xFFFFFF),
                                 overlaySecondaryTextColor: UIColor(0xFFFFFF, 0.7),
                                 overlayTertiaryTextColor: UIColor(0xFFFFFF, 0.4),
                                 overlayHairlineColor: UIColor(0xFFFFFF, 0.18),
                                 overlayControlFillColor: UIColor(0xFFFFFF, 0.08),
                                 toolBarStyle: UIBarStyle.black,
                                 blurStyle: .dark,
                                 textfieldBorderColor: UIColor(0x84929C),
                                 textfieldPlaceholderColor: UIColor(0x737373),
                                 thumbnailBackgroundColor: UIColor(0x1C1E21),
                                 transparentDarkBackgroundColor: UIColor(0x1E1E1E, 0.5),
                                 cardBackground: UIColor(0x494B4D, 0.2),
                                 accentTint: UIColor(0xFF8800, 0.22))
#endif

#endif // !os(tvOS)

let defaultFont = Typography(tableHeaderFont: UIFont.systemFont(ofSize: 24, weight: .semibold))

// MARK: - Rajneesh Discourse palette

#if os(iOS)

/// Semantic colours for the fork-only discourse, audio-mixer and mini-player
/// screens.
///
/// The values are the design tokens from the product brief. They mirror the
/// Android reference (`res/values` and `res/values-night` colour resources) so
/// both apps look the same, and they are resolved from
/// `PresentationTheme.current` so light and dark switch with the existing theme
/// infrastructure and `.VLCThemeDidChangeNotification`.
///
/// Upstream screens keep using `ColorPalette`; only fork-only views use this.
struct DiscourseColors {

    struct Playlist {
        let screenSurface: UIColor
        let glowStart: UIColor
        let glowSecondary: UIColor
        let glowEnd: UIColor
        let rowStart: UIColor
        let rowEnd: UIColor
        let rowAccent: UIColor
        let coverStart: UIColor
        let coverEnd: UIColor
        let text: UIColor
        let textSecondary: UIColor
    }

    struct AudioMixer {
        let screenStart: UIColor
        let screenEnd: UIColor
        let card: UIColor
        let cardBorder: UIColor
        let rowStart: UIColor
        let rowEnd: UIColor
        let rowActiveStart: UIColor
        let rowActiveEnd: UIColor
        let bannerStart: UIColor
        let bannerEnd: UIColor
        let bannerIcon: UIColor
        let separator: UIColor
        let text: UIColor
        let textSecondary: UIColor
        let accent: UIColor
        let toggleBackgroundDefault: UIColor
        let toggleBackgroundSelected: UIColor
        let toggleForegroundDefault: UIColor
        let toggleForegroundSelected: UIColor
        let toggleDisabled: UIColor
        let sliderInactive: UIColor
    }

    struct MiniPlayer {
        let surfaceStart: UIColor
        let surfaceEnd: UIColor
        let border: UIColor
        let text: UIColor
        let textSecondary: UIColor
        let control: UIColor
        let accent: UIColor
        let progressInactive: UIColor
    }

    let isDark: Bool

    // Catalogue and track surfaces
    let accent: UIColor
    let appBackground: UIColor
    let catalogueBackgroundStart: UIColor
    let detailBackgroundStart: UIColor
    let detailBackgroundEnd: UIColor
    let surfaceStart: UIColor
    let surfaceEnd: UIColor
    let border: UIColor
    let primaryText: UIColor
    let secondaryText: UIColor
    let divider: UIColor
    let searchFieldBackground: UIColor
    let searchStroke: UIColor
    let trackSurface: UIColor
    let trackBorder: UIColor
    let trackText: UIColor
    let trackSecondaryText: UIColor
    let downloadedSurface: UIColor
    let downloadedBorder: UIColor

    // Liked/unliked hearts are brand constants, not theme dependent.
    let likedHeart = UIColor(0xFF5269)
    let unlikedHeart = UIColor(0xBEA8AA)
    // Downloaded tracks use the reference green in both themes.
    let downloaded = UIColor(0x50C8A3)

    let playlist: Playlist
    let audioMixer: AudioMixer
    let miniPlayer: MiniPlayer

    /// The palette for the theme currently in effect.
    static var current: DiscourseColors {
        return PresentationTheme.current.isDark ? .dark : .light
    }

    static let dark = DiscourseColors(
        isDark: true,
        accent: UIColor(0xFF484D),
        appBackground: UIColor(0x0D0D0D),
        catalogueBackgroundStart: UIColor(0x1C1110),
        detailBackgroundStart: UIColor(0x2D1017),
        detailBackgroundEnd: UIColor(0x09090B),
        surfaceStart: UIColor(0x321A19),
        surfaceEnd: UIColor(0x211312),
        border: UIColor(0x71302E),
        primaryText: UIColor(0xF5F3F3),
        secondaryText: UIColor(0xBBB8B8),
        divider: UIColor(0x302B2B),
        searchFieldBackground: UIColor(0x281515),
        searchStroke: UIColor(0x923330),
        trackSurface: UIColor(0x1B171B),
        trackBorder: UIColor(0x302329),
        trackText: UIColor(0xFFFFFF),
        trackSecondaryText: UIColor(0xBEA8AA),
        downloadedSurface: UIColor(0x29171D),
        downloadedBorder: UIColor(0x64303D),
        playlist: Playlist(screenSurface: UIColor(0x101010),
                           glowStart: UIColor(0x40201E),
                           glowSecondary: UIColor(0x351817),
                           glowEnd: UIColor(0x101010, 0.0),
                           rowStart: UIColor(0x462120),
                           rowEnd: UIColor(0x25201F),
                           rowAccent: UIColor(0xB83339),
                           coverStart: UIColor(0x592323),
                           coverEnd: UIColor(0x351B1C),
                           text: UIColor(0xFFFFFF),
                           textSecondary: UIColor(0xB7B4B4)),
        audioMixer: AudioMixer(screenStart: UIColor(0x19110F),
                               screenEnd: UIColor(0x000000),
                               card: UIColor(0x241A18),
                               cardBorder: UIColor(0x652520),
                               rowStart: UIColor(0x1B1918),
                               rowEnd: UIColor(0x211917),
                               rowActiveStart: UIColor(0x49201D),
                               rowActiveEnd: UIColor(0x351B19),
                               bannerStart: UIColor(0x601D17),
                               bannerEnd: UIColor(0x4C1111),
                               bannerIcon: UIColor(0xD6ABA4),
                               separator: UIColor(0x38302D),
                               text: UIColor(0xFFFFFF),
                               textSecondary: UIColor(0xBDBDBD),
                               accent: UIColor(0xEB3036),
                               toggleBackgroundDefault: UIColor(0x241A18),
                               toggleBackgroundSelected: UIColor(0xA82222),
                               toggleForegroundDefault: UIColor(0xEB3036),
                               toggleForegroundSelected: UIColor(0xFFFFFF),
                               toggleDisabled: UIColor(0x777777),
                               sliderInactive: UIColor(0x514B49)),
        miniPlayer: MiniPlayer(surfaceStart: UIColor(0x402020),
                               surfaceEnd: UIColor(0x241B1C),
                               border: UIColor(0x813034),
                               text: UIColor(0xFFFFFF),
                               textSecondary: UIColor(0xB7B4B4),
                               control: UIColor(0xFFFFFF),
                               accent: UIColor(0xEB3036),
                               progressInactive: UIColor(0x514747)))

    static let light = DiscourseColors(
        isDark: false,
        accent: UIColor(0xB3262D),
        appBackground: UIColor(0xFFFDFC),
        catalogueBackgroundStart: UIColor(0xFFFDFC),
        detailBackgroundStart: UIColor(0xFFF8F6),
        detailBackgroundEnd: UIColor(0xFFFDFC),
        surfaceStart: UIColor(0xFFF8F6),
        surfaceEnd: UIColor(0xF8EDEA),
        border: UIColor(0xE7C9C5),
        primaryText: UIColor(0x211A19),
        secondaryText: UIColor(0x685D5B),
        divider: UIColor(0xE5DAD8),
        searchFieldBackground: UIColor(0xFFFFFF),
        searchStroke: UIColor(0xD6B9B5),
        trackSurface: UIColor(0xFFFDFC),
        trackBorder: UIColor(0xE7DAD7),
        trackText: UIColor(0x211A19),
        trackSecondaryText: UIColor(0x685D5B),
        downloadedSurface: UIColor(0xF9EDEF),
        downloadedBorder: UIColor(0xE7C6CF),
        playlist: Playlist(screenSurface: UIColor(0xFAF7F5),
                           glowStart: UIColor(0xFFF0EC),
                           glowSecondary: UIColor(0xF8ECE8),
                           glowEnd: UIColor(0xFAF7F5, 0.0),
                           rowStart: UIColor(0xFFFDFC),
                           rowEnd: UIColor(0xF1E8E5),
                           rowAccent: UIColor(0xB3262D),
                           coverStart: UIColor(0xF4DCD6),
                           coverEnd: UIColor(0xEAD0CB),
                           text: UIColor(0x211A19),
                           textSecondary: UIColor(0x685D5B)),
        audioMixer: AudioMixer(screenStart: UIColor(0xFFF8F5),
                               screenEnd: UIColor(0xFAF7F5),
                               card: UIColor(0xFFFDFC),
                               cardBorder: UIColor(0xE7DAD7),
                               rowStart: UIColor(0xFFFDFC),
                               rowEnd: UIColor(0xF1E8E5),
                               rowActiveStart: UIColor(0xFFF0ED),
                               rowActiveEnd: UIColor(0xF8E2DE),
                               bannerStart: UIColor(0xFFF0ED),
                               bannerEnd: UIColor(0xF8E2DE),
                               bannerIcon: UIColor(0xB3262D),
                               separator: UIColor(0xE5DAD8),
                               text: UIColor(0x211A19),
                               textSecondary: UIColor(0x685D5B),
                               accent: UIColor(0xB3262D),
                               toggleBackgroundDefault: UIColor(0xF8EDEA),
                               toggleBackgroundSelected: UIColor(0xA82222),
                               toggleForegroundDefault: UIColor(0xB3262D),
                               toggleForegroundSelected: UIColor(0xFFFFFF),
                               toggleDisabled: UIColor(0x9B9290),
                               sliderInactive: UIColor(0xD6C9C6)),
        miniPlayer: MiniPlayer(surfaceStart: UIColor(0xFFFDFC),
                               surfaceEnd: UIColor(0xF3EAE7),
                               border: UIColor(0xE7DAD7),
                               text: UIColor(0x211A19),
                               textSecondary: UIColor(0x685D5B),
                               control: UIColor(0x211A19),
                               accent: UIColor(0xB3262D),
                               progressInactive: UIColor(0xD6C9C6)))
}

#endif // os(iOS)
