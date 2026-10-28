/*****************************************************************************
 * VLC for iOS
 *****************************************************************************
 * Copyright (c) 2026 VideoLAN. All rights reserved.
 *
 * Authors: Felix Paul Kühne <fkuehne # videolan.org>
 *
 * Refer to the COPYING file of the official project for license.
 *****************************************************************************/

import UIKit

/// The branded app icon, drawn as a rounded square and kept full-colour.
/// `LaunchIcon` is the Osho artwork exported with rounded corners; it is
/// resized here so the bar button does not stretch the 480 px asset.
enum AppIconArtwork {
    static func rounded(pointSize: CGFloat) -> UIImage? {
        guard let icon = UIImage(named: "LaunchIcon") else {
            return nil
        }
        let rect = CGRect(x: 0, y: 0, width: pointSize, height: pointSize)
        let renderer = UIGraphicsImageRenderer(size: rect.size)
        let image = renderer.image { _ in
            UIBezierPath(roundedRect: rect, cornerRadius: pointSize * 0.2237).addClip()
            icon.draw(in: rect)
        }
        return image.withRenderingMode(.alwaysOriginal)
    }
}

@objc(VLCAppMenuBarButtonItem)
class AppMenuBarButtonItem: UIBarButtonItem {

    enum Style {
        /// The app icon plus the menu (the upstream bar-button shape).
        case appIcon
        /// A chevron that opens the same menu, used when the app icon is static.
        case dropdown
    }

    private weak var presenter: UIViewController?

    @objc convenience init(presenter: UIViewController) {
        self.init(presenter: presenter, style: .appIcon)
    }

    init(presenter: UIViewController, style: Style) {
        self.presenter = presenter
        super.init()

        switch style {
        case .appIcon:
            image = AppIconArtwork.rounded(pointSize: 26) ?? UIImage(named: "MenuCone")
            accessibilityLabel = NSLocalizedString("Settings", comment: "")
        case .dropdown:
            image = UIImage(systemName: "chevron.down")
            accessibilityLabel = NSLocalizedString("MENU", comment: "Opens the app menu")
        }
        accessibilityIdentifier = VLCAccessibilityIdentifier.settings

        menu = buildMenu()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildMenu() -> UIMenu {
        let about = UIAction(title: NSLocalizedString("SETTINGS_ABOUT", comment: ""),
                             image: AppIconArtwork.rounded(pointSize: 22) ?? UIImage(named: "MenuCone")) { [weak self] _ in
            self?.showAbout()
        }
        about.accessibilityIdentifier = VLCAccessibilityIdentifier.about

        let settings = UIAction(title: NSLocalizedString("Settings", comment: ""),
                                image: UIImage(systemName: "gearshape")) { [weak self] _ in
            self?.showSettings()
        }
        settings.accessibilityIdentifier = VLCAccessibilityIdentifier.openSettings

        let settingsSection = UIMenu(title: "", options: .displayInline, children: [settings])
        return UIMenu(title: "", children: [about, settingsSection])
    }

    private func showAbout() {
        let aboutController = AboutController()
        let aboutNavigationController = AboutNavigationController(rootViewController: aboutController)
        presenter?.present(aboutNavigationController, animated: true)
    }

    private func showSettings() {
        ParentalControlCoordinator.shared.authorizeIfParentalControlIsEnabled(action: { [weak self] in
            guard let presenter = self?.presenter else {
                return
            }

            let mediaLibraryService = VLCAppCoordinator.sharedInstance().mediaLibraryService
            let settingsController = SettingsController(mediaLibraryService: mediaLibraryService)
            let settingsNavigationController = UINavigationController(rootViewController: settingsController)
            presenter.present(settingsNavigationController, animated: true)
        })
    }
}

/// The static app-logo header item. It deliberately has no action: the header
/// menu lives on the right (`AppMenuBarButtonItem.Style.dropdown`).
@objc(VLCAppLogoBarButtonItem)
final class AppLogoBarButtonItem: UIBarButtonItem {

    override init() {
        super.init()

        let iconView = UIImageView(image: AppIconArtwork.rounded(pointSize: 26))
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.isUserInteractionEnabled = false

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isUserInteractionEnabled = false
        container.addSubview(iconView)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 26),
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 26),
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26),
            iconView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        customView = container

        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
