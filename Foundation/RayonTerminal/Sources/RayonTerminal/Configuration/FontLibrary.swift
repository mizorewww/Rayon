import CoreText
import Foundation

/// The fonts installed on this device, read once through CoreText so the same
/// code serves macOS and iOS.
@MainActor
enum FontLibrary {
    struct Face {
        let family: String
        let style: String
        let postScriptName: String
        let monospaced: Bool
    }

    struct Family: Identifiable, Hashable {
        var id: String { name }
        let name: String
        let monospaced: Bool
    }

    static let faces: [Face] = {
        let collection = CTFontCollectionCreateFromAvailableFonts(nil)
        let descriptors = CTFontCollectionCreateMatchingFontDescriptors(collection) as? [CTFontDescriptor] ?? []
        return descriptors.compactMap { descriptor in
            guard let family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String,
                  !family.hasPrefix("."),
                  let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String
            else { return nil }
            let style = CTFontDescriptorCopyAttribute(descriptor, kCTFontStyleNameAttribute) as? String ?? "Regular"
            let traits = CTFontDescriptorCopyAttribute(descriptor, kCTFontTraitsAttribute) as? [CFString: Any]
            let symbolic = (traits?[kCTFontSymbolicTrait] as? NSNumber)?.uint32Value ?? 0
            let monospaced = symbolic & CTFontSymbolicTraits.traitMonoSpace.rawValue != 0
            return Face(family: family, style: style, postScriptName: name, monospaced: monospaced)
        }
    }()

    static let families: [Family] = {
        var monospaced: [String: Bool] = [:]
        for face in faces { monospaced[face.family] = (monospaced[face.family] ?? false) || face.monospaced }
        return monospaced
            .map { Family(name: $0.key, monospaced: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }()

    static func isMonospaced(_ family: String) -> Bool {
        families.first { $0.name == family }?.monospaced ?? false
    }

    static func members(of family: String) -> [Face] {
        faces.filter { $0.family == family }
    }

    /// Style/feature/axis lookups are cached per family: editors ask for
    /// them on every render, and each miss creates a CTFont and copies its
    /// tables out of CoreText.
    private static var stylesCache: [String: [String]] = [:]
    private static var featuresCache: [String: [Feature]] = [:]
    private static var axesCache: [String: [Axis]] = [:]

    /// Style names offered when the family is Ghostty's built-in font.
    static let builtInStyles = ["Thin", "ExtraLight", "Light", "Regular", "Medium", "SemiBold", "Bold", "ExtraBold"]

    static func styles(of family: String) -> [String] {
        guard !family.isEmpty else { return builtInStyles }
        if let cached = stylesCache[family] { return cached }
        var seen = Set<String>()
        let result = members(of: family).map(\.style).filter { seen.insert($0).inserted }
        stylesCache[family] = result
        return result
    }

    /// The family's regular face, else its first.
    static func font(of family: String) -> CTFont? {
        let members = members(of: family)
        guard let face = members.first(where: { $0.style == "Regular" }) ?? members.first else { return nil }
        return CTFontCreateWithName(face.postScriptName as CFString, 12, nil)
    }

    struct Axis: Identifiable {
        var id: String { tag }
        let tag: String
        let name: String
        let minimum: Double
        let maximum: Double
        let defaultValue: Double
    }

    /// Variable-font axes (weight, width, slant…).
    static func axes(of family: String) -> [Axis] {
        if let cached = axesCache[family] { return cached }
        var result: [Axis] = []
        if let font = font(of: family),
           let raw = CTFontCopyVariationAxes(font) as? [[CFString: Any]]
        {
            result = raw.compactMap { axis in
                guard let identifier = axis[kCTFontVariationAxisIdentifierKey] as? NSNumber else { return nil }
                let value = identifier.uint32Value
                let tag = String(bytes: [24, 16, 8, 0].map { UInt8((value >> $0) & 0xFF) }, encoding: .ascii) ?? "\(value)"
                return Axis(
                    tag: tag,
                    name: axis[kCTFontVariationAxisNameKey] as? String ?? tag,
                    minimum: (axis[kCTFontVariationAxisMinimumValueKey] as? NSNumber)?.doubleValue ?? 0,
                    maximum: (axis[kCTFontVariationAxisMaximumValueKey] as? NSNumber)?.doubleValue ?? 0,
                    defaultValue: (axis[kCTFontVariationAxisDefaultValueKey] as? NSNumber)?.doubleValue ?? 0
                )
            }
        }
        axesCache[family] = result
        return result
    }

    struct Feature: Identifiable, Hashable {
        var id: String { tag }
        let tag: String
        let name: String
        let group: String
        let defaultOn: Bool
    }

    /// OpenType features the family's font actually has, named by the font.
    static func features(of family: String) -> [Feature] {
        guard !family.isEmpty else { return builtInFeatures }
        if let cached = featuresCache[family] { return cached }
        var result: [String: Feature] = [:]
        var order: [String] = []
        if let font = font(of: family), let types = CTFontCopyFeatures(font) as? [[CFString: Any]] {
            for type in types {
                let typeName = type[kCTFontFeatureTypeNameKey] as? String ?? "Other"
                for selector in type[kCTFontFeatureTypeSelectorsKey] as? [[CFString: Any]] ?? [] {
                    guard let tag = selector[kCTFontOpenTypeFeatureTag] as? String else { continue }
                    let value = (selector[kCTFontOpenTypeFeatureValue] as? NSNumber)?.intValue ?? 1
                    let isDefault = (selector[kCTFontFeatureSelectorDefaultKey] as? NSNumber)?.boolValue ?? false
                    let selectorName = selector[kCTFontFeatureSelectorNameKey] as? String ?? tag
                    // Character variants and stylistic sets arrive one feature type
                    // each, with selectors named just "On"/"Off": gather them into one
                    // group and name each by its type.
                    let generic = ["on", "off", "enabled", "disabled"].contains(selectorName.lowercased())
                    let name = generic ? typeName : selectorName
                    let group = featureGroup(tag: tag, fallback: typeName)
                    let existing = result[tag]
                    if existing == nil { order.append(tag) }
                    result[tag] = Feature(
                        tag: tag,
                        name: value != 0 ? name : existing?.name ?? name,
                        group: group,
                        defaultOn: isDefault ? value != 0 : existing?.defaultOn ?? false
                    )
                }
            }
        }
        let features = order.compactMap { result[$0] }
        featuresCache[family] = features
        return features
    }

    /// "cv01"–"cv99" and "ss01"–"ss99" get their own groups.
    private static func featureGroup(tag: String, fallback: String) -> String {
        guard tag.count == 4, tag.dropFirst(2).allSatisfy({ $0.isASCII && $0.isNumber }) else { return fallback }
        if tag.hasPrefix("cv") { return "Character Variants" }
        if tag.hasPrefix("ss") { return "Stylistic Sets" }
        return fallback
    }

    /// Ghostty's built-in JetBrains Mono is not installed, so its features are listed here.
    static let builtInFeatures: [Feature] = [
        Feature(tag: "calt", name: "Ligatures (contextual alternates)", group: "Ligatures", defaultOn: true),
        Feature(tag: "zero", name: "Slashed zero", group: "Characters", defaultOn: false),
    ] + (1 ... 20).map { index in
        Feature(tag: String(format: "ss%02d", index), name: "Stylistic set \(index)", group: "Stylistic Sets", defaultOn: false)
    } + (1 ... 20).map { index in
        Feature(tag: String(format: "cv%02d", index), name: "Character variant \(index)", group: "Character Variants", defaultOn: false)
    }
}
