/*****************************************************************************
 * DiscourseCatalogueFilterStore.swift
 * Rajneesh Discourse
 *****************************************************************************
 * Copyright (c) 2026 Sandalbar Enterprises, Inc. All rights reserved.
 *
 * This file is part of Rajneesh Discourse, a fork of VLC for iOS.
 * Rajneesh Discourse is free software under the GPLv2 (or later) and MPLv2,
 * like the upstream project it is derived from. See COPYING.
 *
 * Remembers the last language and sort filter of the catalogue so returning to
 * the Discourses tab keeps the user's selection. Unknown stored values (for
 * example a filter removed by a backend update) read as "no filter".
 *****************************************************************************/

import Foundation

final class DiscourseCatalogueFilterStore {
    enum Keys {
        static let language = "osho_api_catalogue_language"
        static let sort = "osho_api_catalogue_sort"
    }

    static let shared = DiscourseCatalogueFilterStore()

    private let settings: DiscourseSettings

    init(settings: DiscourseSettings = .shared) {
        self.settings = settings
    }

    var language: DiscourseLanguage? {
        get {
            guard let raw = settings.string(Keys.language) else {
                return nil
            }
            return DiscourseLanguage(rawValue: raw)
        }
        set {
            settings.set(newValue?.rawValue, forKey: Keys.language)
        }
    }

    var sort: DiscourseCatalogueSort? {
        get {
            guard let raw = settings.string(Keys.sort) else {
                return nil
            }
            return DiscourseCatalogueSort(rawValue: raw)
        }
        set {
            settings.set(newValue?.rawValue, forKey: Keys.sort)
        }
    }

    /// True when at least one filter is active.
    var hasActiveFilters: Bool {
        language != nil || sort != nil
    }

    func save(language: DiscourseLanguage?, sort: DiscourseCatalogueSort?) {
        self.language = language
        self.sort = sort
    }

    func reset() {
        settings.remove(Keys.language)
        settings.remove(Keys.sort)
    }
}
